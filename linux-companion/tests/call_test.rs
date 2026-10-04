use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use linux_companion::daemon::server::{CallStateInfo, DaemonServerState};

#[tokio::test]
async fn test_daemon_call_state() {
    let (shutdown_tx, _shutdown_rx) = mpsc::channel::<()>(1);
    let last_synced_clipboard = Arc::new(Mutex::new(String::new()));
    let client_ip = Arc::new(Mutex::new(Some("127.0.0.1".to_string())));
    let agent_port = Arc::new(Mutex::new(Some(7879)));
    let call_state = Arc::new(Mutex::new(CallStateInfo::default()));

    let state = Arc::new(DaemonServerState {
        session_id: "test_session".to_string(),
        host: "127.0.0.1".to_string(),
        port: 0,
        token: "testtoken123".to_string(),
        device_name: "Pixel 8".to_string(),
        shutdown_tx,
        last_synced_clipboard,
        client_ip,
        agent_port,
        call_state: Arc::clone(&call_state),
    });

    // Verify initial call status
    {
        let c = state.call_state.lock().await;
        assert_eq!(c.state, "idle");
        assert_eq!(c.mic_muted, false);
        assert_eq!(c.speaker_enabled, true);
    }

    // Simulate active call state
    {
        let mut c = state.call_state.lock().await;
        c.state = "in_call".to_string();
        c.caller = "Pixel 8".to_string();
        c.start_time = Some(100);
        c.mic_muted = false;
        c.speaker_enabled = true;
    }

    {
        let c = state.call_state.lock().await;
        assert_eq!(c.state, "in_call");
        assert_eq!(c.caller, "Pixel 8");
    }
}
