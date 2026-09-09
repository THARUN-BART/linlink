use std::fs::OpenOptions;
use std::process::{Command, Stdio};
use tracing::info;

use crate::device::model::ActiveSession;
use crate::storage::{Storage, current_timestamp};

#[derive(Debug, PartialEq, Eq)]
pub enum StopOutcome {
    /// The running session for the specified (or current) device was stopped.
    Stopped { device_name: String, pid: u32 },
    /// LinLink was running, but connected to a different device.
    DeviceMismatch {
        active_device: String,
        requested_device: String,
    },
    /// The specified device is not active, but found in past devices.
    DeviceAlreadyDisconnected {
        device_name: String,
        last_disconnected: Option<String>,
    },
    /// The specified device was never paired.
    DeviceNotFound { requested_device: String },
    /// No session is running.
    NotRunning,
}

pub struct DaemonProcess;

impl DaemonProcess {
    /// Determines the correct path to the linlink binary
    pub fn binary_path() -> std::path::PathBuf {
        let exe = std::env::current_exe().unwrap_or_else(|_| std::path::PathBuf::from("linlink"));
        if exe.to_string_lossy().contains("/deps/")
            && let Some(target_dir) = exe.parent().and_then(|p| p.parent())
        {
            let candidate = target_dir.join("linlink");
            if candidate.exists() {
                return candidate;
            }
        }
        exe
    }

    /// Spawns a background daemon running `linlink daemon` with stdout/stderr directed to the log file.
    pub fn spawn(
        host: &str,
        port: u16,
        token: &str,
        session_id: &str,
        device_name: &str,
        client_ip: Option<&str>,
    ) -> Result<u32, std::io::Error> {
        let bin_path = Self::binary_path();
        let log_path = Storage::log_file();

        let log_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)?;

        let log_err = log_file.try_clone()?;

        let mut cmd = Command::new(bin_path);
        cmd.arg("daemon")
            .arg("--host")
            .arg(host)
            .arg("--port")
            .arg(port.to_string())
            .arg("--token")
            .arg(token)
            .arg("--session-id")
            .arg(session_id)
            .arg("--device-name")
            .arg(device_name);

        if let Some(ip) = client_ip {
            cmd.arg("--client-ip").arg(ip);
        }

        cmd.stdin(Stdio::null())
            .stdout(Stdio::from(log_file))
            .stderr(Stdio::from(log_err));

        let child = cmd.spawn()?;
        let pid = child.id();

        // Immediately record session in storage
        let active = ActiveSession {
            pid,
            host: host.to_string(),
            port,
            token: token.to_string(),
            state: "connected".to_string(),
            device_name: Some(device_name.to_string()),
            client_ip: client_ip.map(|s| s.to_string()),
            agent_port: None,
            started_at: current_timestamp(),
        };
        Storage::save_session(&active);
        Storage::record_device_connected(device_name, token, client_ip.map(|s| s.to_string()));

        info!("Spawned background LinLink daemon with PID {}", pid);
        Ok(pid)
    }

    /// Stops the currently running session, optionally ensuring it matches `device_filter`.
    pub fn stop(device_filter: Option<&str>) -> StopOutcome {
        let session = match Storage::load_session() {
            Some(s) if Storage::is_pid_alive(s.pid) => Some(s),
            Some(_) => {
                // PID is dead, clear stale session
                Storage::clear_session();
                None
            }
            None => None,
        };

        if let Some(session) = session {
            let active_name = session
                .device_name
                .clone()
                .unwrap_or_else(|| "Unknown Device".to_string());

            // If a device filter was provided, verify it matches
            if let Some(filter) = device_filter {
                let filter_lower = filter.trim().to_lowercase();
                let active_lower = active_name.trim().to_lowercase();

                if !active_lower.contains(&filter_lower) && !filter_lower.contains(&active_lower) {
                    return StopOutcome::DeviceMismatch {
                        active_device: active_name,
                        requested_device: filter.to_string(),
                    };
                }
            }

            // Send SIGTERM to the daemon process
            let _ = Command::new("kill")
                .arg("-TERM")
                .arg(session.pid.to_string())
                .status();

            for _ in 0..20 {
                if !Storage::is_pid_alive(session.pid) {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }

            Storage::record_device_disconnected(&active_name);
            Storage::clear_session();

            return StopOutcome::Stopped {
                device_name: active_name,
                pid: session.pid,
            };
        }

        Self::handle_no_active_session(device_filter)
    }

    fn handle_no_active_session(device_filter: Option<&str>) -> StopOutcome {
        if let Some(filter) = device_filter {
            let devices = Storage::load_devices();
            let matched = devices.iter().find(|d| {
                d.name.to_lowercase().contains(&filter.to_lowercase())
                    || d.id.eq_ignore_ascii_case(filter)
            });

            if let Some(dev) = matched {
                StopOutcome::DeviceAlreadyDisconnected {
                    device_name: dev.name.clone(),
                    last_disconnected: dev.disconnected_at.clone(),
                }
            } else {
                StopOutcome::DeviceNotFound {
                    requested_device: filter.to_string(),
                }
            }
        } else {
            StopOutcome::NotRunning
        }
    }
}
