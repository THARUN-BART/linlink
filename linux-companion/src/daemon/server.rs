use axum::{
    body::Bytes,
    extract::{ConnectInfo, Query, State},
    http::{header, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::signal::unix::{signal, SignalKind};
use tokio::sync::{mpsc, Mutex};
use tracing::info;

use crate::storage::{current_timestamp, ActiveSession, Storage};

pub struct DaemonServerState {
    pub session_id: String,
    pub host: String,
    pub port: u16,
    pub token: String,
    pub device_name: String,
    pub shutdown_tx: mpsc::Sender<()>,
    pub last_synced_clipboard: Arc<Mutex<String>>,
    pub client_ip: Arc<Mutex<Option<String>>>,
    pub agent_port: Arc<Mutex<Option<u16>>>,
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

#[derive(Deserialize)]
pub struct FsListRequest {
    pub token: String,
    pub path: Option<String>,
}

#[derive(Deserialize)]
pub struct FsDownloadQuery {
    pub token: String,
    pub path: String,
}

#[derive(Deserialize)]
pub struct FsUploadQuery {
    pub token: String,
    pub dest_dir: Option<String>,
    pub filename: String,
}

#[derive(Deserialize)]
pub struct DeviceRegisterRequest {
    pub token: String,
    pub agent_port: Option<u16>,
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

async fn handle_device_register(
    State(state): State<Arc<DaemonServerState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(body): Json<DeviceRegisterRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let detected_ip = addr.ip().to_string();
    *state.client_ip.lock().await = Some(detected_ip.clone());
    *state.agent_port.lock().await = body.agent_port;

    if let Some(mut session) = Storage::load_session() {
        session.agent_port = body.agent_port;
        session.client_ip = Some(detected_ip.clone());
        Storage::save_session(&session);
        info!(
            "Updated active session with Android agent_port: {:?} and IP: {}",
            body.agent_port, detected_ip
        );
    }

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": "Device agent registered",
    })))
}

async fn handle_get_clipboard(
    State(state): State<Arc<DaemonServerState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
) -> Json<serde_json::Value> {
    // Keep client IP fresh
    *state.client_ip.lock().await = Some(addr.ip().to_string());

    if let Some(sys_clip) = read_system_clipboard() {
        if !sys_clip.is_empty() {
            let mut last = state.last_synced_clipboard.lock().await;
            if *last != sys_clip {
                *last = sys_clip.clone();
                Storage::save_clipboard(&sys_clip);
            }
        }
    }

    let text = Storage::load_clipboard().unwrap_or_default();
    Json(serde_json::json!({
        "status": "ok",
        "text": text,
    }))
}

async fn handle_post_clipboard(
    State(state): State<Arc<DaemonServerState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(body): Json<ClipboardPayload>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // Keep client IP fresh
    *state.client_ip.lock().await = Some(addr.ip().to_string());

    info!(
        "Received clipboard update from '{}' ({} chars)",
        state.device_name,
        body.text.len()
    );
    *state.last_synced_clipboard.lock().await = body.text.clone();
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

/// Lists Linux files for the Android app to explore
async fn handle_fs_list(
    State(state): State<Arc<DaemonServerState>>,
    Json(body): Json<FsListRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    let requested_path = body.path.unwrap_or_else(|| home.clone());
    let path = std::path::PathBuf::from(&requested_path);

    if !path.exists() || !path.is_dir() {
        return Err(StatusCode::NOT_FOUND);
    }

    let parent_path = path.parent().map(|p| p.to_string_lossy().to_string());
    let mut entries = Vec::new();

    if let Ok(dir_entries) = std::fs::read_dir(&path) {
        for entry in dir_entries.filter_map(|e| e.ok()) {
            let file_name = entry.file_name().to_string_lossy().to_string();
            // Skip hidden files starting with '.' unless directly requested
            if file_name.starts_with('.') {
                continue;
            }

            if let Ok(meta) = entry.metadata() {
                let is_dir = meta.is_dir();
                let size = if is_dir { 0 } else { meta.len() };
                let modified = meta
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);

                entries.push(serde_json::json!({
                    "name": file_name,
                    "is_dir": is_dir,
                    "size": size,
                    "modified": modified,
                }));
            }
        }
    }

    // Sort: directories first, then alphabetical
    entries.sort_by(|a, b| {
        let a_dir = a["is_dir"].as_bool().unwrap_or(false);
        let b_dir = b["is_dir"].as_bool().unwrap_or(false);
        if a_dir != b_dir {
            b_dir.cmp(&a_dir)
        } else {
            a["name"].as_str().cmp(&b["name"].as_str())
        }
    });

    Ok(Json(serde_json::json!({
        "status": "ok",
        "current_path": path.to_string_lossy(),
        "parent_path": parent_path,
        "home_path": home,
        "transfers_path": Storage::transfers_dir().to_string_lossy(),
        "entries": entries,
    })))
}

/// Download a file from Linux to Android over TCP
async fn handle_fs_download(
    State(state): State<Arc<DaemonServerState>>,
    Query(query): Query<FsDownloadQuery>,
) -> Result<impl IntoResponse, StatusCode> {
    if query.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let path = std::path::PathBuf::from(&query.path);
    if !path.exists() || !path.is_file() {
        return Err(StatusCode::NOT_FOUND);
    }

    let file_bytes = tokio::fs::read(&path)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let filename = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "download".into());

    let headers = [
        (header::CONTENT_TYPE, "application/octet-stream".to_string()),
        (
            header::CONTENT_DISPOSITION,
            format!("attachment; filename=\"{}\"", filename),
        ),
    ];

    Ok((headers, file_bytes))
}

/// Upload a file from Android to a specific directory on Linux over TCP
async fn handle_fs_upload(
    State(state): State<Arc<DaemonServerState>>,
    Query(query): Query<FsUploadQuery>,
    body: Bytes,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if query.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let dest_dir = if let Some(ref d) = query.dest_dir {
        std::path::PathBuf::from(d)
    } else {
        Storage::transfers_dir()
    };

    let _ = std::fs::create_dir_all(&dest_dir);

    let safe_name = std::path::Path::new(&query.filename)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "uploaded_file".to_string());

    let dest_file = dest_dir.join(&safe_name);
    tokio::fs::write(&dest_file, &body)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    info!(
        "Saved uploaded file from device '{}' to: {}",
        state.device_name,
        dest_file.display()
    );

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": format!("File saved to {}", dest_file.display()),
        "path": dest_file.to_string_lossy(),
        "bytes_received": body.len(),
    })))
}

pub fn copy_to_system_clipboard(text: &str) {
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

pub fn read_system_clipboard() -> Option<String> {
    use std::process::Command;

    // 1. Attempt wl-paste for Wayland
    if let Ok(output) = Command::new("wl-paste").arg("-n").output() {
        if output.status.success() {
            if let Ok(s) = String::from_utf8(output.stdout) {
                return Some(s);
            }
        }
    }

    // 2. Attempt xclip for X11
    if let Ok(output) = Command::new("xclip")
        .args(["-selection", "clipboard", "-o"])
        .output()
    {
        if output.status.success() {
            if let Ok(s) = String::from_utf8(output.stdout) {
                return Some(s);
            }
        }
    }

    // 3. Attempt xsel for X11
    if let Ok(output) = Command::new("xsel")
        .args(["--clipboard", "--output"])
        .output()
    {
        if output.status.success() {
            if let Ok(s) = String::from_utf8(output.stdout) {
                return Some(s);
            }
        }
    }

    None
}

pub async fn push_clipboard_to_android(
    ip: &str,
    port: u16,
    token: &str,
    text: &str,
) -> Result<(), String> {
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpStream;

    let payload = serde_json::json!({
        "token": token,
        "text": text,
    })
    .to_string();

    let addr = format!("{}:{}", ip, port);
    let mut stream = tokio::time::timeout(
        tokio::time::Duration::from_secs(2),
        TcpStream::connect(&addr),
    )
    .await
    .map_err(|_| "Connect timeout".to_string())?
    .map_err(|e| format!("Connect error: {}", e))?;

    let req = format!(
        "POST /fs/clipboard HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        addr,
        payload.len(),
        payload
    );

    stream
        .write_all(req.as_bytes())
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Notifies the Android agent that Linux is disconnecting so the app can
/// immediately clear its paired state without waiting for a timeout.
pub async fn push_disconnect_to_android(ip: &str, port: u16, token: &str) {
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpStream;

    let payload = serde_json::json!({ "token": token }).to_string();
    let addr = format!("{}:{}", ip, port);

    let Ok(Ok(mut stream)) = tokio::time::timeout(
        tokio::time::Duration::from_secs(2),
        TcpStream::connect(&addr),
    )
    .await
    else {
        tracing::debug!(
            "Could not reach Android agent at {} for disconnect notify",
            addr
        );
        return;
    };

    let req = format!(
        "POST /fs/disconnect HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        addr,
        payload.len(),
        payload
    );

    let _ = stream.write_all(req.as_bytes()).await;
    info!("Sent disconnect notification to Android agent at {}", addr);
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
    let (clip_stop_tx, mut clip_stop_rx) = mpsc::channel::<()>(1);

    let initial_clip = read_system_clipboard()
        .or_else(Storage::load_clipboard)
        .unwrap_or_default();
    let last_synced_clipboard = Arc::new(Mutex::new(initial_clip));
    let client_ip_shared = Arc::new(Mutex::new(client_ip.clone()));
    let agent_port_shared = Arc::new(Mutex::new(None));

    let state = Arc::new(DaemonServerState {
        session_id: session_id.clone(),
        host: host.clone(),
        port,
        token: token.clone(),
        device_name: device_name.clone(),
        shutdown_tx,
        last_synced_clipboard: Arc::clone(&last_synced_clipboard),
        client_ip: Arc::clone(&client_ip_shared),
        agent_port: Arc::clone(&agent_port_shared),
    });

    // Spawn live background clipboard sync worker
    let clipboard_worker = {
        let last_clipboard = Arc::clone(&last_synced_clipboard);
        let client_ip_shared = Arc::clone(&client_ip_shared);
        let agent_port_shared = Arc::clone(&agent_port_shared);
        let token = token.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(tokio::time::Duration::from_millis(800));
            loop {
                tokio::select! {
                    _ = interval.tick() => {
                        if let Some(current_clip) = read_system_clipboard() {
                            if !current_clip.is_empty() {
                                let mut last = last_clipboard.lock().await;
                                if *last != current_clip {
                                    *last = current_clip.clone();
                                    Storage::save_clipboard(&current_clip);
                                    info!(
                                        "📋 Linux clipboard changed ({} chars), syncing to Android...",
                                        current_clip.len()
                                    );

                                    let maybe_ip = client_ip_shared.lock().await.clone();
                                    let maybe_port = *agent_port_shared.lock().await;

                                    if let (Some(ip), Some(port)) = (maybe_ip, maybe_port) {
                                        let token = token.clone();
                                        let clip_text = current_clip.clone();
                                        tokio::spawn(async move {
                                            if let Err(e) = push_clipboard_to_android(&ip, port, &token, &clip_text).await {
                                                tracing::debug!("Could not push clipboard to Android ({}:{}): {}", ip, port, e);
                                            }
                                        });
                                    }
                                }
                            }
                        }
                    }
                    _ = clip_stop_rx.recv() => {
                        tracing::debug!("Clipboard sync worker stopped.");
                        break;
                    }
                }
            }
        })
    };

    let app = Router::new()
        .route("/status", get(handle_status))
        .route("/ping", get(handle_ping))
        .route(
            "/clipboard",
            get(handle_get_clipboard).post(handle_post_clipboard),
        )
        .route("/files", get(handle_list_files))
        .route("/files/upload", post(handle_file_upload))
        .route("/api/device/register", post(handle_device_register))
        .route("/api/fs/list", post(handle_fs_list))
        .route("/api/fs/download", get(handle_fs_download))
        .route("/api/fs/upload", post(handle_fs_upload))
        .route("/pair/unlink", post(handle_unlink))
        .layer(axum::extract::DefaultBodyLimit::max(
            10 * 1024 * 1024 * 1024,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{}", port);
    let listener = match tokio::net::TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            tracing::error!("Failed to bind daemon listener on {}: {}", addr, e);
            let _ = clip_stop_tx.send(()).await;
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
        agent_port: None,
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

    let _ = clip_stop_tx.send(()).await;
    let _ = clipboard_worker.await;

    // Notify Android immediately so it clears paired state without waiting for a timeout
    let maybe_ip = client_ip_shared.lock().await.clone();
    let maybe_agent_port = *agent_port_shared.lock().await;
    if let (Some(ip), Some(agent_port)) = (maybe_ip, maybe_agent_port) {
        info!(
            "Notifying Android agent at {}:{} about disconnect...",
            ip, agent_port
        );
        push_disconnect_to_android(&ip, agent_port, &token).await;
    }

    // Cleanup session and record disconnect
    Storage::record_device_disconnected(&device_name);
    Storage::clear_session();
    info!("LinLink daemon stopped cleanly.");
}
