use linux_companion::pairing::{
    network::detect_local_ip,
    qr::PairingQr,
    server::{self, PairingEvent},
    session::PairingSession,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

#[test]
fn test_pairing_session_creation() {
    let session = PairingSession::new("192.168.1.100".to_string(), 7878);
    assert_eq!(session.host, "192.168.1.100");
    assert_eq!(session.port, 7878);
    assert_eq!(session.token.len(), 8);
    assert!(!session.is_expired());
}

#[test]
fn test_pairing_qr_encoding() {
    let session = PairingSession::new("10.0.0.5".to_string(), 8080);
    let qr = PairingQr::from_session(&session);
    let expected = format!("linlink://10.0.0.5:8080?t={}", session.token);
    assert_eq!(qr.encode(), expected);
}

#[test]
fn test_local_ip_detection() {
    // If machine has network connectivity, it detects an IP; otherwise None.
    // Ensure it does not panic.
    let ip = detect_local_ip();
    if let Some(ref addr) = ip {
        assert!(!addr.is_empty());
        assert_ne!(addr, "0.0.0.0");
        assert_ne!(addr, "127.0.0.1");
    }
}

#[tokio::test]
async fn test_pairing_server_lifecycle() {
    let port = 19876;
    let session = PairingSession::new("127.0.0.1".to_string(), port);
    let token = session.token.clone();

    let (_handle, mut event_rx) =
        server::start("127.0.0.1", "127.0.0.1", port, session.id.clone(), token.clone()).await;

    // Small yield to let server bind
    tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

    // 1. Send Scan request with valid token
    let scan_body = format!("{{\"token\":\"{}\"}}", token);
    let scan_req = format!(
        "POST /pair/scan HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        port,
        scan_body.len(),
        scan_body
    );

    let mut stream = TcpStream::connect(("127.0.0.1", port)).await.expect("failed to connect");
    stream.write_all(scan_req.as_bytes()).await.unwrap();
    let mut resp = String::new();
    stream.read_to_string(&mut resp).await.unwrap();
    assert!(resp.starts_with("HTTP/1.1 200 OK"));

    // Check that event_rx received Scanned
    let event = event_rx.recv().await.expect("expected Scanned event");
    assert!(matches!(event, PairingEvent::Scanned));

    // 2. Send Handshake request
    let hs_body = format!("{{\"token\":\"{}\",\"device_name\":\"TestPhone\"}}", token);
    let hs_req = format!(
        "POST /pair/handshake HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        port,
        hs_body.len(),
        hs_body
    );

    let mut stream = TcpStream::connect(("127.0.0.1", port)).await.expect("failed to connect");
    stream.write_all(hs_req.as_bytes()).await.unwrap();
    let mut resp = String::new();
    stream.read_to_string(&mut resp).await.unwrap();
    assert!(resp.starts_with("HTTP/1.1 200 OK"));
    assert!(resp.contains("Welcome, TestPhone!"));

    // Check that event_rx received HandshakeSuccess
    let event = event_rx.recv().await.expect("expected Handshake event");
    if let PairingEvent::HandshakeSuccess { device_name, .. } = event {
        assert_eq!(device_name, "TestPhone");
    } else {
        panic!("unexpected event: {:?}", event);
    }

    // 3. Query /status
    let status_req = format!(
        "GET /status HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\n\r\n",
        port
    );
    let mut stream = TcpStream::connect(("127.0.0.1", port)).await.expect("failed to connect");
    stream.write_all(status_req.as_bytes()).await.unwrap();
    let mut resp = String::new();
    stream.read_to_string(&mut resp).await.unwrap();
    assert!(resp.starts_with("HTTP/1.1 200 OK"));
    assert!(resp.contains("\"connected\""));
    assert!(resp.contains("\"TestPhone\""));
}
