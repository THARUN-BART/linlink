use axum::{
    extract::{ConnectInfo, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};

use crate::pairing::state::PairingState;
use crate::storage::{current_timestamp, ActiveSession, PairedDevice, Storage};

#[derive(Debug, Clone)]
pub enum PairingEvent {
    Scanned,
    HandshakeSuccess {
        device_name: String,
        client_ip: Option<String>,
    },
    Unlinked,
}

/// Shared state handed into every Axum handler.
pub struct AppState {
    pub session_id: String,
    pub host: String,
    pub port: u16,
    pub pairing_state: Mutex<PairingState>,
    pub expected_token: String,
    pub event_tx: mpsc::UnboundedSender<PairingEvent>,
}

// ── Request / Response bodies ────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ScanRequest {
    pub token: String,
}

#[derive(Serialize)]
pub struct ScanResponse {
    pub status: String,
}

#[derive(Deserialize)]
pub struct HandshakeRequest {
    pub token: String,
    pub device_name: String,
}

#[derive(Serialize)]
pub struct HandshakeResponse {
    pub status: String,
    pub message: String,
}

#[derive(Deserialize)]
pub struct UnlinkRequest {
    pub token: String,
}

#[derive(Serialize)]
pub struct StatusResponse {
    pub status: String,
    pub state: String,
    pub device_name: Option<String>,
    pub host: String,
    pub port: u16,
}

// ── Handlers ─────────────────────────────────────────────────────────────────

/// Android scanned the QR → move state from PAIRING to WAITING.
async fn handle_scan(
    State(state): State<Arc<AppState>>,
    Json(body): Json<ScanRequest>,
) -> Result<Json<ScanResponse>, StatusCode> {
    if body.token != state.expected_token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let mut s = state.pairing_state.lock().await;
    *s = s.clone().qr_scanned();

    tracing::info!("QR scanned – state → {}", *s);

    // Update session store
    let session = ActiveSession {
        pid: std::process::id(),
        host: state.host.clone(),
        port: state.port,
        token: state.expected_token.clone(),
        state: "waiting".to_string(),
        device_name: None,
        client_ip: None,
        agent_port: None,
        started_at: current_timestamp(),
    };
    Storage::save_session(&session);

    let _ = state.event_tx.send(PairingEvent::Scanned);

    Ok(Json(ScanResponse {
        status: "ok".into(),
    }))
}

/// Android completed handshake → move state from WAITING to CONNECTED.
async fn handle_handshake(
    State(state): State<Arc<AppState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(body): Json<HandshakeRequest>,
) -> Result<Json<HandshakeResponse>, StatusCode> {
    if body.token != state.expected_token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let client_ip = Some(addr.ip().to_string());

    let mut s = state.pairing_state.lock().await;
    *s = s.clone().handshake_ok(body.device_name.clone());

    tracing::info!("Handshake OK – state → {}", *s);

    // Save device to trusted devices storage
    let paired_device = PairedDevice {
        id: uuid::Uuid::new_v4().to_string(),
        name: body.device_name.clone(),
        token: body.token.clone(),
        paired_at: current_timestamp(),
        last_seen: Some(current_timestamp()),
        disconnected_at: None,
        ip: client_ip.clone(),
    };
    Storage::save_device(paired_device);

    // Update active session file
    let session = ActiveSession {
        pid: std::process::id(),
        host: state.host.clone(),
        port: state.port,
        token: state.expected_token.clone(),
        state: "connected".to_string(),
        device_name: Some(body.device_name.clone()),
        client_ip: client_ip.clone(),
        agent_port: None,
        started_at: current_timestamp(),
    };
    Storage::save_session(&session);

    // Signal the CLI
    let _ = state.event_tx.send(PairingEvent::HandshakeSuccess {
        device_name: body.device_name.clone(),
        client_ip,
    });

    Ok(Json(HandshakeResponse {
        status: "ok".into(),
        message: format!("Welcome, {}!", body.device_name),
    }))
}

/// Status endpoint for clients or CLI to verify companion state
async fn handle_status(State(state): State<Arc<AppState>>) -> Json<StatusResponse> {
    let s = state.pairing_state.lock().await;
    let (state_str, device_name) = match &*s {
        PairingState::Pairing => ("pairing".to_string(), None),
        PairingState::Waiting => ("waiting".to_string(), None),
        PairingState::Connected { device_name } => {
            ("connected".to_string(), Some(device_name.clone()))
        }
        PairingState::Stopped => ("stopped".to_string(), None),
    };

    Json(StatusResponse {
        status: "ok".to_string(),
        state: state_str,
        device_name,
        host: state.host.clone(),
        port: state.port,
    })
}

/// Android or client unlinks
async fn handle_unlink(
    State(state): State<Arc<AppState>>,
    Json(body): Json<UnlinkRequest>,
) -> Result<Json<ScanResponse>, StatusCode> {
    if body.token != state.expected_token {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let mut s = state.pairing_state.lock().await;
    *s = s.clone().stop();

    tracing::info!("Device unlinked");

    let _ = state.event_tx.send(PairingEvent::Unlinked);

    Ok(Json(ScanResponse {
        status: "ok".into(),
    }))
}

// ── Server entry point ────────────────────────────────────────────────────────

pub async fn start(
    bind_host: &str,
    advertised_host: &str,
    port: u16,
    session_id: String,
    token: String,
) -> Result<
    (
        tokio::task::JoinHandle<()>,
        mpsc::UnboundedReceiver<PairingEvent>,
    ),
    std::io::Error,
> {
    let (event_tx, event_rx) = mpsc::unbounded_channel::<PairingEvent>();

    let shared = Arc::new(AppState {
        session_id,
        host: advertised_host.to_string(),
        port,
        pairing_state: Mutex::new(PairingState::Pairing),
        expected_token: token,
        event_tx,
    });

    let app = Router::new()
        .route("/pair/scan", post(handle_scan))
        .route("/pair/handshake", post(handle_handshake))
        .route("/pair/unlink", post(handle_unlink))
        .route("/status", get(handle_status))
        .with_state(shared);

    let addr = format!("{}:{}", bind_host, port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    tracing::info!("Pairing server listening on http://{}", addr);

    let handle = tokio::spawn(async move {
        let _ = axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await;
    });

    Ok((handle, event_rx))
}
