use serde::{Deserialize, Serialize};

/// Represents a trusted or previously paired device.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PairedDevice {
    pub id: String,
    pub name: String,
    pub token: String,
    pub paired_at: String,
    #[serde(default)]
    pub last_seen: Option<String>,
    #[serde(default)]
    pub disconnected_at: Option<String>,
    pub ip: Option<String>,
}

/// Represents the currently active pairing or connected session on this machine.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ActiveSession {
    pub pid: u32,
    pub host: String,
    pub port: u16,
    pub token: String,
    pub state: String, // "pairing", "waiting", "connected"
    pub device_name: Option<String>,
    #[serde(default)]
    pub client_ip: Option<String>,
    pub started_at: String,
}

/// Details of a currently connected device verified with a live process.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CurrentDevice {
    pub name: String,
    pub id: Option<String>,
    pub token: String,
    pub state: String,
    pub host: String,
    pub port: u16,
    pub pid: u32,
    pub connected_at: String,
    pub client_ip: Option<String>,
}
