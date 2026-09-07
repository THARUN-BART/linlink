use linux_companion::daemon::{DaemonProcess, StopOutcome};
use linux_companion::device::DeviceManager;
use linux_companion::storage::Storage;

#[test]
fn test_daemon_spawn_status_and_stop_lifecycle() {
    // 1. Spawn a mock daemon process
    let port = 19999;
    let token = "test_tok_999";
    let session_id = "test_sess_999";
    let device_name = "IntegrationTestDevice";

    let pid = DaemonProcess::spawn(
        "127.0.0.1",
        port,
        token,
        session_id,
        device_name,
        Some("127.0.0.1"),
    )
    .expect("failed to spawn daemon");

    assert!(Storage::is_pid_alive(pid));

    // Wait slightly for daemon to bind and write state
    std::thread::sleep(std::time::Duration::from_millis(150));

    // 2. Check DeviceManager
    let (current, past) = DeviceManager::get_all_devices();
    assert!(current.is_some(), "expected current device");
    let curr = current.unwrap();
    assert_eq!(curr.name, device_name);
    assert_eq!(curr.pid, pid);
    assert!(!past.iter().any(|d| d.name == device_name));

    // 3. Stop device by name
    let stop_res = DaemonProcess::stop(Some("IntegrationTestDevice"));
    assert_eq!(
        stop_res,
        StopOutcome::Stopped {
            device_name: device_name.to_string(),
            pid,
        }
    );

    // Wait slightly for process termination
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert!(!Storage::is_pid_alive(pid));

    // 4. Verify that after stop, the device moved to past devices
    let (current_after, past_after) = DeviceManager::get_all_devices();
    assert!(current_after.is_none());
    assert!(past_after.iter().any(|d| d.name == device_name));

    // Cleanup
    Storage::remove_device(device_name);
}
