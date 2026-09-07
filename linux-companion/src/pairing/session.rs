use std::time::{Duration, SystemTime};

#[derive(Debug, Clone)]
pub struct PairingSession {
    pub id: String,
    /// Short 8-char hex token (keeps the QR payload small).
    pub token: String,
    pub host: String,
    pub port: u16,
    pub created_at: SystemTime,
    pub expires_at: SystemTime,
}

impl PairingSession {
    pub fn new(host: String, port: u16) -> Self {
        // Use only the first 8 hex chars of a UUID for a compact token.
        let id = uuid::Uuid::new_v4().to_string();
        let token = uuid::Uuid::new_v4()
            .to_string()
            .replace('-', "")
            [..8]
            .to_string();

        let created_at = SystemTime::now();
        let expires_at = created_at + Duration::from_secs(300);

        Self {
            id,
            token,
            host,
            port,
            created_at,
            expires_at,
        }
    }

    pub fn is_expired(&self) -> bool {
        SystemTime::now() >= self.expires_at
    }
}
