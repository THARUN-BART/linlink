use crate::device::model::{CurrentDevice, PairedDevice};
use crate::storage::Storage;

pub struct DeviceManager;

impl DeviceManager {
    /// Returns the currently connected and active device, if any.
    /// If an active session exists in storage but its process is dead, it is pruned.
    pub fn get_current_device() -> Option<CurrentDevice> {
        let session = Storage::load_session()?;

        if !Storage::is_pid_alive(session.pid) {
            Storage::clear_session();
            return None;
        }

        // Must be in connected or pairing state with a device name or token
        let devices = Storage::load_devices();
        let matched = devices.iter().find(|d| {
            d.token == session.token
                || session
                    .device_name
                    .as_deref()
                    .map(|n| n.eq_ignore_ascii_case(&d.name))
                    .unwrap_or(false)
        });

        Some(CurrentDevice {
            name: session
                .device_name
                .clone()
                .or_else(|| matched.map(|d| d.name.clone()))
                .unwrap_or_else(|| "Unknown Device".to_string()),
            id: matched.map(|d| d.id.clone()),
            token: session.token.clone(),
            state: session.state.clone(),
            host: session.host.clone(),
            port: session.port,
            pid: session.pid,
            connected_at: session.started_at.clone(),
            client_ip: session
                .client_ip
                .or_else(|| matched.and_then(|d| d.ip.clone())),
            agent_port: session.agent_port,
        })
    }

    /// Returns all registered devices that are not currently active.
    pub fn get_past_devices() -> Vec<PairedDevice> {
        let current = Self::get_current_device();
        let devices = Storage::load_devices();

        match current {
            Some(curr) => devices
                .into_iter()
                .filter(|d| {
                    if let Some(ref curr_id) = curr.id {
                        d.id != *curr_id
                    } else {
                        d.token != curr.token && !d.name.eq_ignore_ascii_case(&curr.name)
                    }
                })
                .collect(),
            None => devices,
        }
    }

    /// Returns both current active device and past devices.
    pub fn get_all_devices() -> (Option<CurrentDevice>, Vec<PairedDevice>) {
        (Self::get_current_device(), Self::get_past_devices())
    }

    /// Find a device by case-insensitive name or ID.
    pub fn find_device(query: &str) -> Option<PairedDevice> {
        let devices = Storage::load_devices();
        devices
            .into_iter()
            .find(|d| d.id == query || d.name.eq_ignore_ascii_case(query))
    }
}
