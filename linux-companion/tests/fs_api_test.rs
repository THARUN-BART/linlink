use axum::{
    Router,
    body::Bytes,
    extract::{Query, State},
    http::{StatusCode, header},
    response::IntoResponse,
    routing::{get, post},
};
use serde::Deserialize;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

struct TestServerState {
    token: String,
}

#[derive(Deserialize)]
struct FsListRequest {
    token: String,
    path: Option<String>,
}

#[derive(Deserialize)]
struct FsDownloadQuery {
    token: String,
    path: String,
}

#[derive(Deserialize)]
struct FsUploadQuery {
    token: String,
    dest_dir: Option<String>,
    filename: String,
}

async fn handle_list(
    State(state): State<Arc<TestServerState>>,
    axum::Json(body): axum::Json<FsListRequest>,
) -> Result<axum::Json<serde_json::Value>, StatusCode> {
    if body.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let p = body.path.unwrap_or_else(|| ".".into());
    let mut entries = Vec::new();
    if let Ok(dir_entries) = std::fs::read_dir(&p) {
        for e in dir_entries.filter_map(|e| e.ok()) {
            entries.push(serde_json::json!({
                "name": e.file_name().to_string_lossy(),
                "is_dir": e.metadata().map(|m| m.is_dir()).unwrap_or(false),
            }));
        }
    }
    Ok(axum::Json(serde_json::json!({
        "status": "ok",
        "current_path": p,
        "entries": entries,
    })))
}

async fn handle_upload(
    State(state): State<Arc<TestServerState>>,
    Query(query): Query<FsUploadQuery>,
    body: Bytes,
) -> Result<axum::Json<serde_json::Value>, StatusCode> {
    if query.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let dir = query.dest_dir.unwrap_or_else(|| "/tmp".into());
    let dest = std::path::PathBuf::from(dir).join(&query.filename);
    tokio::fs::write(&dest, &body)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(axum::Json(
        serde_json::json!({ "status": "ok", "path": dest.to_string_lossy() }),
    ))
}

async fn handle_download(
    State(state): State<Arc<TestServerState>>,
    Query(query): Query<FsDownloadQuery>,
) -> Result<impl IntoResponse, StatusCode> {
    if query.token != state.token {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let bytes = tokio::fs::read(&query.path)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let headers = [(header::CONTENT_TYPE, "application/octet-stream".to_string())];
    Ok((headers, bytes))
}

#[tokio::test]
async fn test_tcp_fs_api_endpoints() {
    let port = 19888;
    let token = "test_fs_token_123";

    let state = Arc::new(TestServerState {
        token: token.to_string(),
    });

    let app = Router::new()
        .route("/api/fs/list", post(handle_list))
        .route("/api/fs/upload", post(handle_upload))
        .route("/api/fs/download", get(handle_download))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(format!("127.0.0.1:{}", port))
        .await
        .expect("bind failed");

    tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .unwrap();
    });

    tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

    // 1. Upload a file over TCP
    let file_content = b"Hello from LinLink TCP file test!";
    let upload_req = format!(
        "POST /api/fs/upload?token={}&dest_dir=/tmp&filename=linlink_test.txt HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        token,
        port,
        file_content.len()
    );

    let mut stream = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
    stream.write_all(upload_req.as_bytes()).await.unwrap();
    stream.write_all(file_content).await.unwrap();

    let mut resp = String::new();
    stream.read_to_string(&mut resp).await.unwrap();
    assert!(resp.starts_with("HTTP/1.1 200 OK"));
    assert!(resp.contains("\"status\":\"ok\""));

    // 2. Download the uploaded file over TCP
    let download_req = format!(
        "GET /api/fs/download?token={}&path=/tmp/linlink_test.txt HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\n\r\n",
        token, port
    );

    let mut stream = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
    stream.write_all(download_req.as_bytes()).await.unwrap();

    let mut resp = Vec::new();
    stream.read_to_end(&mut resp).await.unwrap();

    let resp_str = String::from_utf8_lossy(&resp);
    assert!(resp_str.starts_with("HTTP/1.1 200 OK"));
    assert!(resp_str.contains("Hello from LinLink TCP file test!"));

    // Clean up
    let _ = std::fs::remove_file("/tmp/linlink_test.txt");
}
