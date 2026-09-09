use crate::device::DeviceManager;
use crate::pairing::state::PairingState;
use crate::storage::Storage;

pub fn print_state_banner(state: PairingState) {
    println!();
    let label = state.to_string();
    let width = label.len() + 4;
    let bar = "─".repeat(width);
    println!("  ┌{}┐", bar);
    println!("  │  {}  │", label);
    println!("  └{}┘", bar);
}

pub fn print_status() {
    println!();
    if let Some(session) = Storage::load_session()
        && Storage::is_pid_alive(session.pid)
    {
        println!("  ┌────────────────────────────────────────────────────────┐");
        if session.state == "connected" {
            println!("  │  🟢 LinLink Companion: CONNECTED (Background Daemon)   │");
        } else {
            println!("  │  🟡 LinLink Companion: PAIRING (Waiting for Device)    │");
        }
        println!("  └────────────────────────────────────────────────────────┘");
        println!("    PID:           {}", session.pid);
        println!("    State:         {}", session.state.to_uppercase());
        println!(
            "    Server:        http://{}:{}",
            session.host, session.port
        );
        println!("    Started:       {}", session.started_at);
        if let Some(name) = &session.device_name {
            println!("    📱 Linked To:  {}", name);
        }
        if let Some(ip) = &session.client_ip {
            println!("    🌐 Device IP:  {}", ip);
        }
        println!("    📄 Daemon Log: {}", Storage::log_file().display());
        println!();
        return;
    }

    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  ⚪ LinLink Companion: NOT RUNNING                     │");
    println!("  └────────────────────────────────────────────────────────┘");
    println!("    No active bridge session is running.");
    println!("    Run `linlink pair` to pair and connect a device.\n");

    let devices = Storage::load_devices();
    if !devices.is_empty() {
        println!("    📱 Trusted Devices: {} registered.", devices.len());
        println!("    Run `linlink devices` to view current and past devices.\n");
    }
}

pub fn print_devices(current_only: bool, past_only: bool) {
    let (current, past) = DeviceManager::get_all_devices();

    println!();
    println!("  ================ LinLink Devices ================");
    println!();

    // 1. Current / Connected Device
    if !past_only {
        println!("  🟢 CURRENT CONNECTED DEVICE");
        println!("  ─────────────────────────────────────────────────");
        match current {
            Some(dev) => {
                println!("    Device:        {}", dev.name);
                if let Some(id) = dev.id {
                    println!("    Device ID:     {}", id);
                }
                println!("    Status:        {}", dev.state.to_uppercase());
                println!("    Connected:     {}", dev.connected_at);
                if let Some(ip) = dev.client_ip {
                    println!("    Device IP:     {}", ip);
                }
                println!("    Daemon PID:    {}", dev.pid);
                println!("    Server:        http://{}:{}", dev.host, dev.port);
                println!();
                println!(
                    "    👉 To disconnect this device, run: `linlink stop \"{}\"`",
                    dev.name
                );
            }
            None => {
                println!("    (No device is currently connected)");
                println!("    Run `linlink pair` to start pairing.");
            }
        }
        println!();
    }

    // 2. Past Devices
    if !current_only {
        println!("  🕒 PAST / REGISTERED DEVICES ({})", past.len());
        println!("  ─────────────────────────────────────────────────");
        if past.is_empty() {
            println!("    (No past devices found)");
        } else {
            for (idx, dev) in past.iter().enumerate() {
                println!("    {}. {}", idx + 1, dev.name);
                println!("       ID:           {}", dev.id);
                println!("       First Paired: {}", dev.paired_at);
                if let Some(ref seen) = dev.last_seen {
                    println!("       Last Seen:    {}", seen);
                }
                if let Some(ref disco) = dev.disconnected_at {
                    println!("       Disconnected: {}", disco);
                }
                if let Some(ref ip) = dev.ip {
                    println!("       Last IP:      {}", ip);
                }
                println!();
            }
        }
        println!();
    }

    println!("  =================================================");
    println!();
}
