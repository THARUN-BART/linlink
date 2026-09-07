use linux_companion::daemon::{DaemonProcess, StopOutcome};
use linux_companion::device::{DeviceManager, PairedDevice};
use linux_companion::storage::{ActiveSession, Storage, current_timestamp};

static TEST_MUTEX: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[test]
fn test_device_manager_past_and_current() {
    let _lock = TEST_MUTEX.lock().unwrap();
    // Clean up any test state
    Storage::clear_session();

    // Setup past devices
    let dev1 = PairedDevice {
        id: "id-pixel".to_string(),
        name: "Google Pixel 8".to_string(),
        token: "tok12345".to_string(),
        paired_at: current_timestamp(),
        last_seen: Some(current_timestamp()),
        disconnected_at: Some(current_timestamp()),
        ip: Some("192.168.1.50".to_string()),
    };
    let dev2 = PairedDevice {
        id: "id-galaxy".to_string(),
        name: "Samsung Galaxy S24".to_string(),
        token: "tok67890".to_string(),
        paired_at: current_timestamp(),
        last_seen: Some(current_timestamp()),
        disconnected_at: None,
        ip: Some("192.168.1.60".to_string()),
    };

    Storage::save_device(dev1.clone());
    Storage::save_device(dev2.clone());

    // Case 1: No active session
    let (current, past) = DeviceManager::get_all_devices();
    assert!(current.is_none());
    assert!(past.iter().any(|d| d.id == "id-pixel"));
    assert!(past.iter().any(|d| d.id == "id-galaxy"));

    // Case 2: Active session for dev2 with current process PID
    let session = ActiveSession {
        pid: std::process::id(),
        host: "127.0.0.1".to_string(),
        port: 7878,
        token: "tok67890".to_string(),
        state: "connected".to_string(),
        device_name: Some("Samsung Galaxy S24".to_string()),
        client_ip: Some("192.168.1.60".to_string()),
        started_at: current_timestamp(),
    };
    Storage::save_session(&session);

    let (current, past) = DeviceManager::get_all_devices();
    assert!(current.is_some());
    let curr = current.unwrap();
    assert_eq!(curr.name, "Samsung Galaxy S24");
    assert_eq!(curr.pid, std::process::id());

    // dev2 should now NOT be in past devices, only dev1
    assert!(past.iter().any(|d| d.id == "id-pixel"));
    assert!(!past.iter().any(|d| d.id == "id-galaxy"));

    // Cleanup
    Storage::clear_session();
    Storage::remove_device("id-pixel");
    Storage::remove_device("id-galaxy");
}

#[test]
fn test_daemon_stop_device_matching() {
    let _lock = TEST_MUTEX.lock().unwrap();
    Storage::clear_session();

    // 1. When not running
    let res = DaemonProcess::stop(None);
    assert_eq!(res, StopOutcome::NotRunning);

    let res = DaemonProcess::stop(Some("UnknownPhone"));
    assert_eq!(
        res,
        StopOutcome::DeviceNotFound {
            requested_device: "UnknownPhone".to_string()
        }
    );

    // 2. Add a past device
    let past_dev = PairedDevice {
        id: "past-id".to_string(),
        name: "OnePlus 12".to_string(),
        token: "op123456".to_string(),
        paired_at: current_timestamp(),
        last_seen: Some(current_timestamp()),
        disconnected_at: Some("2026-09-07 10:00:00 UTC".to_string()),
        ip: None,
    };
    Storage::save_device(past_dev);

    let res = DaemonProcess::stop(Some("OnePlus"));
    assert!(matches!(res, StopOutcome::DeviceAlreadyDisconnected { .. }));

    // 3. Set an active session (using current PID)
    let session = ActiveSession {
        pid: std::process::id(),
        host: "127.0.0.1".to_string(),
        port: 7878,
        token: "active-tok".to_string(),
        state: "connected".to_string(),
        device_name: Some("Motorola Edge".to_string()),
        client_ip: None,
        started_at: current_timestamp(),
    };
    Storage::save_session(&session);

    // Stop with mismatching name
    let res = DaemonProcess::stop(Some("Pixel"));
    assert_eq!(
        res,
        StopOutcome::DeviceMismatch {
            active_device: "Motorola Edge".to_string(),
            requested_device: "Pixel".to_string(),
        }
    );

    // Cleanup session without killing our own test process
    Storage::clear_session();
    Storage::remove_device("past-id");
}
