use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum PairingState {
    /// QR code displayed, waiting for the Android device to scan it.
    Pairing,
    /// QR has been scanned; waiting for the final handshake to complete.
    Waiting,
    /// Handshake succeeded – device is connected.
    Connected { device_name: String },
    /// Session was stopped by the user or an error.
    Stopped,
}

impl fmt::Display for PairingState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PairingState::Pairing => write!(f, "PAIRING"),
            PairingState::Waiting => write!(f, "WAITING"),
            PairingState::Connected { device_name } => {
                write!(f, "CONNECTED ({})", device_name)
            }
            PairingState::Stopped => write!(f, "STOPPED"),
        }
    }
}

impl PairingState {
    /// Advance: QR was scanned by the phone.
    pub fn qr_scanned(self) -> Self {
        match self {
            PairingState::Pairing => PairingState::Waiting,
            other => other,
        }
    }

    /// Advance: handshake completed successfully.
    pub fn handshake_ok(self, device_name: String) -> Self {
        match self {
            PairingState::Waiting => PairingState::Connected { device_name },
            other => other,
        }
    }

    /// Advance: user or system requests a stop.
    pub fn stop(self) -> Self {
        PairingState::Stopped
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, PairingState::Stopped)
    }
}
