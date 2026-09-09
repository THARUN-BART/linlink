use std::fs;
use std::path::PathBuf;

pub use crate::device::model::{ActiveSession, PairedDevice};

pub struct Storage;

impl Storage {
    pub fn config_dir() -> PathBuf {
        if let Ok(dir) = std::env::var("LINLINK_CONFIG_DIR") {
            let path = PathBuf::from(dir);
            let _ = fs::create_dir_all(&path);
            return path;
        }
        let dir = if let Ok(home) = std::env::var("HOME") {
            PathBuf::from(home).join(".config").join("linlink")
        } else {
            PathBuf::from(".linlink")
        };
        let _ = fs::create_dir_all(&dir);
        dir
    }

    pub fn log_file() -> PathBuf {
        Self::config_dir().join("linlink.log")
    }

    pub fn devices_file() -> PathBuf {
        Self::config_dir().join("devices.json")
    }

    pub fn session_file() -> PathBuf {
        Self::config_dir().join("session.json")
    }

    pub fn load_devices() -> Vec<PairedDevice> {
        let path = Self::devices_file();
        if let Ok(content) = fs::read_to_string(path) {
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            Vec::new()
        }
    }

    pub fn save_device(device: PairedDevice) {
        let mut devices = Self::load_devices();
        // Replace existing device with same id or token if already present
        devices.retain(|d| d.id != device.id && d.token != device.token);
        devices.push(device);
        if let Ok(json) = serde_json::to_string_pretty(&devices) {
            let _ = fs::write(Self::devices_file(), json);
        }
    }

    pub fn record_device_connected(name: &str, token: &str, ip: Option<String>) {
        let mut devices = Self::load_devices();
        let now = current_timestamp();
        let mut found = false;

        for dev in devices.iter_mut() {
            if dev.token == token || dev.name.eq_ignore_ascii_case(name) {
                dev.name = name.to_string();
                dev.token = token.to_string();
                dev.last_seen = Some(now.clone());
                dev.disconnected_at = None;
                if ip.is_some() {
                    dev.ip = ip.clone();
                }
                found = true;
                break;
            }
        }

        if !found {
            devices.push(PairedDevice {
                id: uuid::Uuid::new_v4().to_string(),
                name: name.to_string(),
                token: token.to_string(),
                paired_at: now.clone(),
                last_seen: Some(now),
                disconnected_at: None,
                ip,
            });
        }

        if let Ok(json) = serde_json::to_string_pretty(&devices) {
            let _ = fs::write(Self::devices_file(), json);
        }
    }

    pub fn record_device_disconnected(name_or_token: &str) {
        let mut devices = Self::load_devices();
        let now = current_timestamp();
        let mut modified = false;

        for dev in devices.iter_mut() {
            if dev.token == name_or_token || dev.name.eq_ignore_ascii_case(name_or_token) {
                dev.disconnected_at = Some(now.clone());
                modified = true;
                break;
            }
        }

        if modified && let Ok(json) = serde_json::to_string_pretty(&devices) {
            let _ = fs::write(Self::devices_file(), json);
        }
    }

    pub fn remove_device(id_or_name: &str) -> bool {
        let mut devices = Self::load_devices();
        let initial_len = devices.len();
        devices.retain(|d| d.id != id_or_name && !d.name.eq_ignore_ascii_case(id_or_name));
        if devices.len() != initial_len {
            if let Ok(json) = serde_json::to_string_pretty(&devices) {
                let _ = fs::write(Self::devices_file(), json);
            }
            true
        } else {
            false
        }
    }

    pub fn clear_devices() {
        let _ = fs::remove_file(Self::devices_file());
    }

    pub fn save_session(session: &ActiveSession) {
        if let Ok(json) = serde_json::to_string_pretty(session) {
            let _ = fs::write(Self::session_file(), json);
        }
    }

    pub fn load_session() -> Option<ActiveSession> {
        let path = Self::session_file();
        if let Ok(content) = fs::read_to_string(path) {
            serde_json::from_str(&content).ok()
        } else {
            None
        }
    }

    pub fn clear_session() {
        let _ = fs::remove_file(Self::session_file());
    }

    pub fn clipboard_file() -> PathBuf {
        Self::config_dir().join("clipboard.txt")
    }

    pub fn save_clipboard(text: &str) {
        let _ = fs::write(Self::clipboard_file(), text);
    }

    pub fn load_clipboard() -> Option<String> {
        fs::read_to_string(Self::clipboard_file()).ok()
    }

    pub fn transfers_dir() -> PathBuf {
        let dir = if let Ok(home) = std::env::var("HOME") {
            PathBuf::from(home).join("Downloads").join("LinLink")
        } else {
            Self::config_dir().join("transfers")
        };
        let _ = fs::create_dir_all(&dir);
        dir
    }

    pub fn is_pid_alive(pid: u32) -> bool {
        let proc_path = format!("/proc/{}", pid);
        if !std::path::Path::new(&proc_path).exists() {
            return false;
        }
        if let Ok(status) = fs::read_to_string(format!("{}/status", proc_path)) {
            for line in status.lines() {
                if line.starts_with("State:") {
                    // Exclude Zombie (Z) and Dead (X) processes
                    return !line.contains('Z') && !line.contains('X');
                }
            }
        }
        true
    }

    pub fn find_running_daemon_pids() -> Vec<u32> {
        let mut pids = Vec::new();
        let my_pid = std::process::id();
        if let Ok(entries) = fs::read_dir("/proc") {
            for entry in entries.flatten() {
                if let Ok(file_name) = entry.file_name().into_string() {
                    if let Ok(pid) = file_name.parse::<u32>() {
                        if pid == my_pid {
                            continue;
                        }
                        if let Ok(cmdline) = fs::read_to_string(format!("/proc/{}/cmdline", pid)) {
                            if cmdline.contains("linlink") && cmdline.contains("daemon") {
                                pids.push(pid);
                            }
                        }
                    }
                }
            }
        }
        pids
    }
}

pub fn current_timestamp() -> String {
    let now = time::OffsetDateTime::now_utc();
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02} UTC",
        now.year(),
        u8::from(now.month()),
        now.day(),
        now.hour(),
        now.minute(),
        now.second()
    )
}
