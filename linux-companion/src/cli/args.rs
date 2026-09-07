use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(name = "linlink")]
#[command(about = "Android ↔ Linux Companion Bridge")]
#[command(version)]
pub struct Cli {
    /// Enable verbose debug logging
    #[arg(short, long, global = true)]
    pub debug: bool,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Start a pairing session (shows QR code; transitions to background once connected)
    Pair {
        /// IP address to advertise in the QR code (auto-detected if 0.0.0.0)
        #[arg(long, default_value = "0.0.0.0")]
        host: String,

        /// Port the pairing server should listen on
        #[arg(long, default_value_t = 7878)]
        port: u16,

        /// Keep running in foreground even after device is connected (for debugging)
        #[arg(short, long)]
        foreground: bool,
    },

    /// Show current connection and linked device status
    Status,

    /// Show current and past connected devices
    Devices {
        /// Show only the currently connected device
        #[arg(long)]
        current: bool,

        /// Show only past (disconnected) devices
        #[arg(long)]
        past: bool,

        /// Remove a device from registered devices by name or ID
        #[arg(long)]
        remove: Option<String>,
    },

    /// Stop the active session (optionally specify the device name to stop)
    Stop {
        /// Optional name or ID of the device to stop
        device: Option<String>,
    },

    /// View logs from the background daemon
    Logs {
        /// Number of lines to view
        #[arg(short = 'n', long, default_value_t = 50)]
        lines: usize,

        /// Follow log file output
        #[arg(short, long)]
        follow: bool,
    },

    /// View or set shared clipboard between Linux and Android
    Clipboard {
        /// Optional text to set onto the shared clipboard
        text: Option<String>,
    },

    /// List received files in the LinLink transfers folder
    Files,

    /// Internal command to run the background daemon server
    #[command(hide = true)]
    Daemon {
        #[arg(long)]
        host: String,
        #[arg(long)]
        port: u16,
        #[arg(long)]
        token: String,
        #[arg(long)]
        session_id: String,
        #[arg(long)]
        device_name: String,
        #[arg(long)]
        client_ip: Option<String>,
    },
}
