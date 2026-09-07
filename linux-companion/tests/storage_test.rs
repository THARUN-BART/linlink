use linux_companion::storage::{current_timestamp, ActiveSession, PairedDevice, Storage};

#[test]
fn test_current_timestamp_format() {
    let ts = current_timestamp();
    assert!(ts.contains("UTC"));
    assert!(ts.len() >= 19);
}

#[test]
fn test_paired_device_serialization() {
    let dev = PairedDevice {
        id: "unique-uuid".to_string(),
        name: "Google Pixel 8".to_string(),
        token: "87654321".to_string(),
        paired_at: "2026-09-07 14:00:00 UTC".to_string(),
        last_seen: Some("2026-09-07 14:05:00 UTC".to_string()),
        disconnected_at: None,
        ip: Some("192.168.1.55".to_string()),
    };

    let json = serde_json::to_string(&dev).expect("serialization failed");
    let decoded: PairedDevice = serde_json::from_str(&json).expect("deserialization failed");

    assert_eq!(decoded.id, "unique-uuid");
    assert_eq!(decoded.name, "Google Pixel 8");
    assert_eq!(decoded.token, "87654321");
    assert_eq!(decoded.last_seen.as_deref(), Some("2026-09-07 14:05:00 UTC"));
    assert_eq!(decoded.disconnected_at, None);
    assert_eq!(decoded.ip.as_deref(), Some("192.168.1.55"));
}

#[test]
fn test_active_session_serialization() {
    let session = ActiveSession {
        pid: 12345,
        host: "192.168.1.50".to_string(),
        port: 7878,
        token: "abcdef12".to_string(),
        state: "connected".to_string(),
        device_name: Some("Android Phone".to_string()),
        client_ip: Some("192.168.1.88".to_string()),
        started_at: "2026-09-07 14:00:00 UTC".to_string(),
    };

    let json = serde_json::to_string(&session).expect("serialization failed");
    let decoded: ActiveSession = serde_json::from_str(&json).expect("deserialization failed");

    assert_eq!(decoded.pid, 12345);
    assert_eq!(decoded.host, "192.168.1.50");
    assert_eq!(decoded.port, 7878);
    assert_eq!(decoded.token, "abcdef12");
    assert_eq!(decoded.state, "connected");
    assert_eq!(decoded.device_name.as_deref(), Some("Android Phone"));
    assert_eq!(decoded.client_ip.as_deref(), Some("192.168.1.88"));
}

#[test]
fn test_storage_device_operations() {
    let device = PairedDevice {
        id: "test-device-id".to_string(),
        name: "Test Unit".to_string(),
        token: "testtoken".to_string(),
        paired_at: current_timestamp(),
        last_seen: Some(current_timestamp()),
        disconnected_at: None,
        ip: Some("10.0.0.99".to_string()),
    };

    Storage::save_device(device.clone());
    let devices = Storage::load_devices();
    assert!(devices.iter().any(|d| d.id == "test-device-id"));

    // Test record_device_disconnected
    Storage::record_device_disconnected("Test Unit");
    let devices = Storage::load_devices();
    let dev = devices.iter().find(|d| d.id == "test-device-id").unwrap();
    assert!(dev.disconnected_at.is_some());

    let removed = Storage::remove_device("test-device-id");
    assert!(removed);

    let devices_after = Storage::load_devices();
    assert!(!devices_after.iter().any(|d| d.id == "test-device-id"));
}
