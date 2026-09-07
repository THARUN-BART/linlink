use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc;
use tracing::info;

use crate::storage::{ActiveSession, Storage, current_timestamp};

pub struct DaemonServerState {
    pub session_id: String,
    pub host: String,
    pub port: u16,
    pub token: String,
    pub device_name: String,
    pub shutdown_tx: mpsc::Sender<()>,
}

#[derive(Serialize)]
pub struct DaemonStatusResponse {
    pub status: String,
    pub state: String,
    pub device_name: String,
    pub host: String,
    pub port: u16,
}

#[derive(Deserialize)]
pub struct DaemonUnlinkRequest {
    pub token: String,
}

#[derive(Deserialize)]
pub struct ClipboardPayload {
    pub token: String,
    pub text: String,
}

#[derive(Deserialize)]
pub struct FileUploadPayload {
    pub token: String,
    pub filename: String,
    pub content: String,
}

async fn handle_status(State(state): State<Arc<DaemonServerState>>) -> Json<DaemonStatusResponse> {
    Json(DaemonStatusResponse {
        status: "ok".to_string(),
        state: "connected".to_string(),
        device_name: state.device_name.clone(),
        host: state.host.clone(),
        port: state.port,
    })
}

async fn handle_ping() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "pong" }))
}

async fn handle_get_clipboard() -> Json<serde_json::Value> {
    let text = Storage::load_clipboard().unwrap_or_default();
    Json(serde_json::json!({
        "status": "ok",
        "text": text,
    }))
}

async fn handle_post_clipboard(
    State(state): State<Arc<DaemonServerState>>,
    Json(body): Json<ClipboardPayload>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    info!(
        "Received clipboard update from '{}' ({} chars)",
        state.device_name,
        body.text.len()
    );
    Storage::save_clipboard(&body.text);
    copy_to_system_clipboard(&body.text);

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": "Clipboard updated on Linux Companion",
    })))
}

async fn handle_list_files() -> Json<serde_json::Value> {
    let transfers = Storage::transfers_dir();
    let mut files = Vec::new();

    if let Ok(entries) = std::fs::read_dir(&transfers) {
        for entry in entries.filter_map(|e| e.ok()) {
            if let Ok(meta) = entry.metadata() {
                if meta.is_file() {
                    files.push(serde_json::json!({
                        "name": entry.file_name().to_string_lossy(),
                        "size": meta.len(),
                    }));
                }
            }
        }
    }

    Json(serde_json::json!({
        "status": "ok",
        "directory": transfers.display().to_string(),
        "files": files,
    }))
}

async fn handle_file_upload(
    State(state): State<Arc<DaemonServerState>>,
    Json(body): Json<FileUploadPayload>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let safe_name = std::path::Path::new(&body.filename)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "uploaded_file.txt".to_string());

    let dest = Storage::transfers_dir().join(&safe_name);
    if std::fs::write(&dest, body.content.as_bytes()).is_ok() {
        info!(
            "File received from device '{}': {}",
            state.device_name,
            dest.display()
        );
        return Ok(Json(serde_json::json!({
            "status": "ok",
            "message": format!("Saved to {}", dest.display()),
            "path": dest.display().to_string(),
        })));
    }

    Err(StatusCode::INTERNAL_SERVER_ERROR)
}

fn copy_to_system_clipboard(text: &str) {
    use std::io::Write;
    use std::process::{Command, Stdio};

    // Attempt wl-copy for Wayland
    if let Ok(mut child) = Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(text.as_bytes());
        }
        let _ = child.wait();
        return;
    }

    // Attempt xclip for X11
    if let Ok(mut child) = Command::new("xclip")
        .arg("-selection")
        .arg("clipboard")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(text.as_bytes());
        }
        let _ = child.wait();
    }
}

async fn handle_unlink(
    State(state): State<Arc<DaemonServerState>>,
    Json(body): Json<DaemonUnlinkRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    info!("Unlink request received for device: {}", state.device_name);
    let _ = state.shutdown_tx.send(()).await;

    Ok(Json(serde_json::json!({ "status": "unlinked" })))
}

/// Runs the background daemon server until SIGTERM, SIGINT, or /pair/unlink.
pub async fn run_daemon_server(
    host: String,
    port: u16,
    token: String,
    session_id: String,
    device_name: String,
    client_ip: Option<String>,
) {
    info!(
        "Starting background daemon server for '{}' on port {}",
        device_name, port
    );

    let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);

    let state = Arc::new(DaemonServerState {
        session_id: session_id.clone(),
        host: host.clone(),
        port,
        token: token.clone(),
        device_name: device_name.clone(),
        shutdown_tx,
    });

    let app = Router::new()
        .route("/status", get(handle_status))
        .route("/ping", get(handle_ping))
        .route("/clipboard", get(handle_get_clipboard).post(handle_post_clipboard))
        .route("/files", get(handle_list_files))
        .route("/files/upload", post(handle_file_upload))
        .route("/pair/unlink", post(handle_unlink))
        .with_state(state);

    let addr = format!("0.0.0.0:{}", port);
    let listener = match tokio::net::TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            tracing::error!("Failed to bind daemon listener on {}: {}", addr, e);
            return;
        }
    };

    // Update session with current PID
    let session = ActiveSession {
        pid: std::process::id(),
        host: host.clone(),
        port,
        token: token.clone(),
        state: "connected".to_string(),
        device_name: Some(device_name.clone()),
        client_ip: client_ip.clone(),
        started_at: current_timestamp(),
    };
    Storage::save_session(&session);
    Storage::record_device_connected(&device_name, &token, client_ip);

    info!(
        "LinLink daemon active (PID: {}) listening on http://0.0.0.0:{}",
        std::process::id(),
        port
    );

    // Register UNIX signal listeners
    let mut sigterm = signal(SignalKind::terminate()).expect("failed to install SIGTERM handler");
    let mut sigint = signal(SignalKind::interrupt()).expect("failed to install SIGINT handler");

    let server = axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    );

    tokio::select! {
        res = server => {
            if let Err(e) = res {
                tracing::error!("Server error: {}", e);
            }
        }
        _ = sigterm.recv() => {
            info!("Received SIGTERM, shutting down daemon gracefully.");
        }
        _ = sigint.recv() => {
            info!("Received SIGINT, shutting down daemon gracefully.");
        }
        _ = shutdown_rx.recv() => {
            info!("Shutdown signal received via HTTP.");
        }
    }

    // Cleanup session and record disconnect
    Storage::record_device_disconnected(&device_name);
    Storage::clear_session();
    info!("LinLink daemon stopped cleanly.");
}
