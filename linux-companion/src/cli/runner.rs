use clap::Parser;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::process::Command as StdCommand;
use std::time::Duration;

use crate::cli::args::{Cli, Commands};
use crate::cli::ui;
use crate::daemon::{DaemonProcess, StopOutcome, run_daemon_server};
use crate::pairing::{
    network::detect_local_ip,
    qr::PairingQr,
    server::{self, PairingEvent},
    session::PairingSession,
    state::PairingState,
};
use crate::storage::{ActiveSession, Storage, current_timestamp};

pub fn run() {
    let cli = Cli::parse();

    let log_level = if cli.debug { "debug" } else { "info" };

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| log_level.into()),
        )
        .with_writer(std::io::stderr)
        .init();

    match cli.command {
        Commands::Pair {
            host,
            port,
            foreground,
        } => {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("failed to build tokio runtime")
                .block_on(run_pair(host, port, foreground));
        }

        Commands::Status => {
            ui::print_status();
        }

        Commands::Devices {
            current,
            past,
            remove,
        } => {
            if let Some(target) = remove {
                if Storage::remove_device(&target) {
                    println!("\n  ✅ Removed device '{}' from saved devices.\n", target);
                } else {
                    println!("\n  ❌ Device '{}' not found in saved devices.\n", target);
                }
            } else {
                ui::print_devices(current, past);
            }
        }

        Commands::Stop { device } => {
            run_stop(device.as_deref());
        }

        Commands::Shell { device } => {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("failed to build tokio runtime")
                .block_on(crate::cli::shell::run_shell(device));
        }

        Commands::Logs { lines, follow } => {
            run_logs(lines, follow);
        }

        Commands::Clipboard { text } => {
            if let Some(t) = text {
                Storage::save_clipboard(&t);
                println!("\n  📋 Saved to LinLink shared clipboard ({} chars):\n     \"{}\"\n", t.len(), t);
            } else {
                match Storage::load_clipboard() {
                    Some(content) if !content.is_empty() => {
                        println!("\n  📋 Current LinLink shared clipboard:\n     \"{}\"\n", content);
                    }
                    _ => {
                        println!("\n  📋 Shared clipboard is currently empty.\n     Run `linlink clipboard \"text\"` to set content.\n");
                    }
                }
            }
        }

        Commands::Files => {
            let dir = Storage::transfers_dir();
            println!("\n  📁 LinLink Transfers Directory: {}\n", dir.display());
            if let Ok(entries) = std::fs::read_dir(&dir) {
                let mut count = 0;
                for entry in entries.filter_map(|e| e.ok()) {
                    if let Ok(meta) = entry.metadata() {
                        if meta.is_file() {
                            count += 1;
                            println!("    • {} ({} bytes)", entry.file_name().to_string_lossy(), meta.len());
                        }
                    }
                }
                if count == 0 {
                    println!("    (No transferred files yet)");
                }
            }
            println!();
        }

        Commands::Daemon {
            host,
            port,
            token,
            session_id,
            device_name,
            client_ip,
        } => {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("failed to build tokio runtime")
                .block_on(run_daemon_server(
                    host,
                    port,
                    token,
                    session_id,
                    device_name,
                    client_ip,
                ));
        }
    }
}

async fn run_pair(host: String, port: u16, foreground: bool) {
    // Check if an existing session is running
    if let Some(existing) = Storage::load_session()
        && Storage::is_pid_alive(existing.pid)
    {
        eprintln!(
            "\n  ⚠️  An active LinLink session is already running (PID: {}).\n      Run `linlink stop` first or connect with `linlink shell`.\n",
            existing.pid
        );
        return;
    }

    // Check if an orphaned LinLink daemon is running
    let daemon_pids = Storage::find_running_daemon_pids();
    if !daemon_pids.is_empty() {
        eprintln!(
            "\n  ⚠️  An active LinLink daemon is already running in the background (PID: {}).\n      Run `linlink shell` to connect, or `linlink stop` to stop it.\n",
            daemon_pids[0]
        );
        return;
    }

    Storage::clear_session();

    let advertised_host = if host == "0.0.0.0" {
        detect_local_ip().unwrap_or_else(|| "127.0.0.1".into())
    } else {
        host.clone()
    };

    let session = PairingSession::new(advertised_host.clone(), port);
    let qr_data = PairingQr::from_session(&session);
    let token = session.token.clone();
    let session_id = session.id.clone();

    let (handle, mut event_rx) = match server::start(
        "0.0.0.0",
        &advertised_host,
        port,
        session_id.clone(),
        token.clone(),
    )
    .await
    {
        Ok(res) => res,
        Err(err) if err.kind() == std::io::ErrorKind::AddrInUse => {
            eprintln!(
                "\n  ❌ Cannot bind pairing server to port {}: Address already in use.\n      💡 Another process or a background LinLink daemon is using this port.\n         • Connect to current session:  linlink shell\n         • Stop the existing session:   linlink stop\n         • Or choose another port:      linlink pair --port {}\n",
                port,
                port + 2
            );
            return;
        }
        Err(err) => {
            eprintln!("\n  ❌ Failed to start pairing server: {}\n", err);
            return;
        }
    };

    let active_session = ActiveSession {
        pid: std::process::id(),
        host: advertised_host.clone(),
        port,
        token: session.token.clone(),
        state: "pairing".to_string(),
        device_name: None,
        client_ip: None,
        agent_port: None,
        started_at: current_timestamp(),
    };
    Storage::save_session(&active_session);

    ui::print_state_banner(PairingState::Pairing);

    println!("\n  Scan this QR code with your LinLink Android app:\n");
    if let Err(e) = qr_data.print_to_terminal() {
        eprintln!("Failed to render QR: {}", e);
    }
    println!(
        "\n  Session expires in 5 minutes.\n  Listening on http://{}:{}\n",
        advertised_host, port
    );

    let mut is_connected = false;

    loop {
        tokio::select! {
            Some(event) = event_rx.recv() => {
                match event {
                    PairingEvent::Scanned => {
                        ui::print_state_banner(PairingState::Waiting);
                        println!("\n  📱 Device scanned QR code! Completing handshake…\n");
                    }
                    PairingEvent::HandshakeSuccess { device_name, client_ip } => {
                        is_connected = true;
                        ui::print_state_banner(PairingState::Connected {
                            device_name: device_name.clone(),
                        });
                        println!("\n  ✅  Successfully paired with: {}", device_name);
                        if let Some(ref ip) = client_ip {
                            println!("  📱  Device IP: {}", ip);
                        }

                        if foreground {
                            println!("  🟢  LinLink Bridge is active in FOREGROUND mode.");
                            println!("  Press Ctrl+C or run `linlink stop \"{}\"` in another terminal to end.\n", device_name);
                        } else {
                            println!("  🚀  Transitioning connection to BACKGROUND daemon...");
                            // Drop server listener so daemon can rebind port
                            handle.abort();
                            tokio::time::sleep(Duration::from_millis(100)).await;

                            match DaemonProcess::spawn(
                                &advertised_host,
                                port,
                                &token,
                                &session_id,
                                &device_name,
                                client_ip.as_deref(),
                            ) {
                                Ok(pid) => {
                                    println!("  🟢  LinLink is now running in the background (PID: {}).", pid);
                                    println!("  📄  Log output: {}", Storage::log_file().display());
                                    println!("\n  Available commands:");
                                    println!("    • Interactive shell:  `linlink shell`");
                                    println!("    • View status:        `linlink status`");
                                    println!("    • View all devices:   `linlink devices`");
                                    println!("    • Shared clipboard:   `linlink clipboard`");
                                    println!("    • View live logs:     `linlink logs -f`");
                                    println!("    • Stop connection:    `linlink stop \"{}\"`\n", device_name);
                                    return;
                                }
                                Err(e) => {
                                    eprintln!("  ❌ Failed to spawn background daemon: {}", e);
                                    eprintln!("     Continuing in foreground mode...");
                                }
                            }
                        }
                    }
                    PairingEvent::Unlinked => {
                        ui::print_state_banner(PairingState::Stopped);
                        println!("\n  ℹ️  Device was unlinked.\n");
                        break;
                    }
                }
            }
            _ = tokio::signal::ctrl_c() => {
                println!("\n  🛑 Disconnecting LinLink session…\n");
                break;
            }
            _ = tokio::time::sleep(Duration::from_secs(300)) => {
                if !is_connected {
                    eprintln!("\n  ⏰ Session expired after 5 minutes. Run `linlink pair` to try again.\n");
                    break;
                }
            }
        }
    }

    Storage::clear_session();
}

fn run_stop(device_filter: Option<&str>) {
    println!();
    match DaemonProcess::stop(device_filter) {
        StopOutcome::Stopped { device_name, pid } => {
            println!("  🛑 Stopped LinLink session for device '{}' (PID: {}).", device_name, pid);
            println!("  ✅ LinLink connection closed cleanly.\n");
        }
        StopOutcome::DeviceMismatch {
            active_device,
            requested_device,
        } => {
            println!("  ⚠️  Active session is connected to '{}', not '{}'.", active_device, requested_device);
            println!("      To stop the active device, run: `linlink stop \"{}\"` or `linlink stop`.\n", active_device);
        }
        StopOutcome::DeviceAlreadyDisconnected {
            device_name,
            last_disconnected,
        } => {
            println!("  ℹ️  Device '{}' is not currently active.", device_name);
            if let Some(disco) = last_disconnected {
                println!("      Last disconnected at: {}", disco);
            }
            println!("      Run `linlink devices` to view all devices.\n");
        }
        StopOutcome::DeviceNotFound { requested_device } => {
            println!("  ❌ Device '{}' was not found in active or past devices.", requested_device);
            println!("      Run `linlink devices` to list known devices.\n");
        }
        StopOutcome::NotRunning => {
            let daemon_pids = Storage::find_running_daemon_pids();
            if !daemon_pids.is_empty() {
                for pid in &daemon_pids {
                    let _ = StdCommand::new("kill")
                        .arg("-TERM")
                        .arg(pid.to_string())
                        .status();
                }
                Storage::clear_session();
                println!("  🛑 Stopped {} orphaned LinLink background daemon(s).", daemon_pids.len());
                println!("  ✅ LinLink connection closed cleanly.\n");
            } else {
                println!("  ℹ️  LinLink is not currently running.");
                println!("      Run `linlink pair` to start a new pairing session.\n");
            }
        }
    }
}

fn run_logs(lines: usize, follow: bool) {
    let log_path = Storage::log_file();
    if !log_path.exists() {
        println!("\n  📄 No log file found at {}\n", log_path.display());
        return;
    }

    if follow {
        println!("  Streaming logs from {} (Ctrl+C to stop)...", log_path.display());
        let _ = StdCommand::new("tail")
            .arg("-f")
            .arg("-n")
            .arg(lines.to_string())
            .arg(&log_path)
            .status();
    } else if let Ok(file) = File::open(&log_path) {
        let reader = BufReader::new(file);
        let all_lines: Vec<String> = reader.lines().map_while(Result::ok).collect();
        let start = all_lines.len().saturating_sub(lines);

        println!("\n  📄 LinLink Log Output (last {} lines from {}):\n", lines, log_path.display());
        for line in &all_lines[start..] {
            println!("    {}", line);
        }
        println!();
    }
}
