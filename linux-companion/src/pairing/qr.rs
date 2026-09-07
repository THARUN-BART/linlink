use crate::pairing::session::PairingSession;
use qrcode::{EcLevel, QrCode};

pub struct PairingQr {
    pub host: String,
    pub port: u16,
    pub token: String,
}

impl PairingQr {
    pub fn from_session(session: &PairingSession) -> Self {
        Self {
            host: session.host.clone(),
            port: session.port,
            token: session.token.clone(),
        }
    }

    /// Compact URL payload — keeps the QR small and low-version.
    /// Format: `linlink://HOST:PORT?t=TOKEN`
    pub fn encode(&self) -> String {
        format!("linlink://{}:{}?t={}", self.host, self.port, self.token)
    }

    /// Print a high-contrast QR code to the terminal using ANSI escape codes
    /// (white background + black blocks) with a proper quiet zone.
    ///
    /// This ensures phone cameras and ML Kit can scan it reliably against dark or light terminals.
    pub fn print_to_terminal(&self) -> Result<(), Box<dyn std::error::Error>> {
        let payload = self.encode();
        // Use EcLevel::M for better scan tolerance against screen glare
        let code = QrCode::with_error_correction_level(payload.as_bytes(), EcLevel::M)?;

        let width = code.width();

        // Collect modules into a flat bool grid (true = dark).
        let dark = |col: usize, row: usize| -> bool {
            if col < width && row < width {
                code[(col, row)] == qrcode::Color::Dark
            } else {
                false // quiet zone is light
            }
        };

        // We need an even number of rows (pad with a light row if needed).
        let rows = if width % 2 == 0 { width } else { width + 1 };

        // ANSI escape codes: \x1b[47;30m = pure white background, black foreground.
        let white_bg = "\x1b[47;30m";
        let reset = "\x1b[0m";

        let border = format!("    {}{}{}", white_bg, " ".repeat(width + 4), reset);

        // Top quiet zone (2 vertical modules)
        println!("{}", border);

        let mut row = 0;
        while row < rows {
            let mut line = String::from("    ");
            line.push_str(white_bg);
            line.push_str("  "); // left quiet zone
            for col in 0..width {
                let top = dark(col, row);
                let bot = dark(col, row + 1);
                let ch = match (top, bot) {
                    (true,  true)  => '█',
                    (true,  false) => '▀',
                    (false, true)  => '▄',
                    (false, false) => ' ',
                };
                line.push(ch);
            }
            line.push_str("  "); // right quiet zone
            line.push_str(reset);
            println!("{}", line);
            row += 2;
        }

        // Bottom quiet zone
        println!("{}", border);

        Ok(())
    }
}
