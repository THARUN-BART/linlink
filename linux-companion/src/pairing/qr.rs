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

    /// Print a high-contrast QR code to the terminal using TrueColor ANSI escape codes
    /// (pure white background + pure black blocks) with an ISO-compliant 4-module quiet zone.
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

        // 24-bit TrueColor ANSI escape codes:
        // Background: RGB(255, 255, 255) pure white
        // Foreground: RGB(0, 0, 0) pure pitch black
        let white_bg = "\x1b[48;2;255;255;255;38;2;0;0;0m";
        let reset = "\x1b[0m";

        // ISO/IEC 18004 specifies a quiet zone of at least 4 modules on all 4 sides.
        // Horizontally: 4 characters on left and 4 on right.
        // Vertically: 2 terminal lines top and bottom (each line represents 2 modules = 4 modules).
        let quiet_cols = 4;
        let border_len = width + (quiet_cols * 2);
        let border = format!("    {}{}{}", white_bg, " ".repeat(border_len), reset);

        // Top quiet zone (4 vertical modules = 2 terminal lines)
        println!("{}", border);
        println!("{}", border);

        let mut row = 0;
        while row < rows {
            let mut line = String::from("    ");
            line.push_str(white_bg);
            line.push_str(&" ".repeat(quiet_cols)); // left quiet zone
            for col in 0..width {
                let top = dark(col, row);
                let bot = dark(col, row + 1);
                let ch = match (top, bot) {
                    (true, true) => '█',
                    (true, false) => '▀',
                    (false, true) => '▄',
                    (false, false) => ' ',
                };
                line.push(ch);
            }
            line.push_str(&" ".repeat(quiet_cols)); // right quiet zone
            line.push_str(reset);
            println!("{}", line);
            row += 2;
        }

        // Bottom quiet zone (4 vertical modules = 2 terminal lines)
        println!("{}", border);
        println!("{}", border);

        Ok(())
    }
}
