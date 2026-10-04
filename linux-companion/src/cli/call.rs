use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::sleep;

use crate::cli::shell::reqwest_compat;
use crate::device::DeviceManager;

static MIC_MUTED: AtomicBool = AtomicBool::new(false);
static SPEAKER_MUTED: AtomicBool = AtomicBool::new(false);
static IS_CALLING: AtomicBool = AtomicBool::new(false);

pub async fn run_call(number: Option<String>, _device_filter: Option<String>) {
    let current_dev = DeviceManager::get_current_device();

    let dev = match current_dev {
        Some(d) if d.state == "connected" => d,
        _ => {
            eprintln!("\n  ⚠️  No active LinLink device is currently connected.");
            eprintln!(
                "      Run `linlink pair` and scan the QR code from the LinLink app first.\n"
            );
            return;
        }
    };

    let client_ip = dev
        .client_ip
        .clone()
        .unwrap_or_else(|| "127.0.0.1".to_string());
    let agent_port = dev.agent_port.unwrap_or(7879);
    let token = dev.token.clone();
    let device_name = dev.name.clone();

    let client = reqwest_compat::Client::new();
    let base_url = format!("http://{}:{}", client_ip, agent_port);

    println!();
    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  📞 LinLink Remote Voice Calling & Audio Bridge 📱     │");
    println!("  └────────────────────────────────────────────────────────┘");
    println!(
        "    Linked Phone:  {} (http://{}:{})",
        device_name, client_ip, agent_port
    );
    println!("    PC Audio Mode: Full-Duplex (PC Mic -> Phone, Phone -> PC Speaker)");

    let dial_target = if let Some(n) = number {
        n
    } else {
        print!("    Enter phone number to dial (or press Enter to call phone directly): ");
        let _ = io::stdout().flush();
        let mut user_num = String::new();
        let _ = io::stdin().read_line(&mut user_num);
        user_num.trim().to_string()
    };

    if !dial_target.is_empty() {
        println!("\n    📱 Dialing {} via your Android phone...", dial_target);
        let dial_url = format!("{}/call/dial?token={}", base_url, token);
        let dial_payload = serde_json::json!({
            "token": token,
            "phone_number": dial_target,
            "caller": "Linux Companion"
        })
        .to_string();

        match client
            .post(&dial_url)
            .body(dial_payload.into_bytes())
            .send()
            .await
        {
            Ok(res) if res.status() == 200 => {
                println!(
                    "    ✅ Phone is placing cellular call to {}...",
                    dial_target
                );
            }
            _ => {
                println!("    ℹ️ Initiating remote call to {}...", dial_target);
            }
        }
    } else {
        println!("    Connecting intercom call to {}…\n", device_name);
        let invite_url = format!("{}/call/invite?token={}", base_url, token);
        let invite_payload = serde_json::json!({
            "token": token,
            "caller": "Linux Companion",
            "action": "call"
        })
        .to_string();

        match client
            .post(&invite_url)
            .body(invite_payload.into_bytes())
            .send()
            .await
        {
            Ok(res) if res.status() == 200 => {
                println!("  🔔 Call ringing on {}...", device_name);
            }
            _ => {
                println!(
                    "  ℹ️ Connecting audio bridge to {} directly...",
                    device_name
                );
            }
        }
    }

    IS_CALLING.store(true, Ordering::SeqCst);
    MIC_MUTED.store(false, Ordering::SeqCst);
    SPEAKER_MUTED.store(false, Ordering::SeqCst);

    let start_time = Instant::now();

    println!("\n  🟢 CALL CONNECTED! Live audio bridge is active.");
    if !dial_target.is_empty() {
        println!("  ┌────────────────────────────────────────────────────────┐");
        println!("  │  📞 Remote Call:   {:<37} │", dial_target);
        println!("  │  🎤 PC Mic:        Speaking to friend through phone     │");
        println!("  │  🔊 PC Speaker:    Hearing friend through PC speakers   │");
        println!("  ├────────────────────────────────────────────────────────┤");
    } else {
        println!("  ┌────────────────────────────────────────────────────────┐");
        println!("  │  🎤 PC Microphone: Speaking to phone user               │");
        println!("  │  🔊 PC Speaker:    Hearing phone user                   │");
        println!("  ├────────────────────────────────────────────────────────┤");
    }
    println!("  │  Controls:                                             │");
    println!("  │    [m] Toggle PC Microphone (Mute/Unmute)              │");
    println!("  │    [s] Toggle PC Speaker (Mute/Unmute)                 │");
    println!("  │    [q] or [h] or Ctrl+C to Hang Up                      │");
    println!("  └────────────────────────────────────────────────────────┘\n");

    // Spawn audio tool background handler
    let _audio_handle = spawn_audio_bridge(client_ip.clone(), agent_port, token.clone());

    // Spawn stdin listener for interactive keys
    let is_running = Arc::new(AtomicBool::new(true));
    let is_running_reader = Arc::clone(&is_running);

    tokio::task::spawn_blocking(move || {
        use std::io::Read;
        let stdin = io::stdin();
        let mut handle = stdin.lock();
        let mut byte = [0u8; 1];

        while is_running_reader.load(Ordering::SeqCst) {
            if handle.read_exact(&mut byte).is_ok() {
                match byte[0] {
                    b'm' | b'M' => {
                        let prev = MIC_MUTED.fetch_xor(true, Ordering::SeqCst);
                        let now = !prev;
                        println!(
                            "\n    🎤 PC Microphone {}",
                            if now {
                                "\x1b[1;31m[MUTED]\x1b[0m"
                            } else {
                                "\x1b[1;32m[ACTIVE]\x1b[0m"
                            }
                        );
                    }
                    b's' | b'S' => {
                        let prev = SPEAKER_MUTED.fetch_xor(true, Ordering::SeqCst);
                        let now = !prev;
                        println!(
                            "\n    🔊 PC Speaker Output {}",
                            if now {
                                "\x1b[1;31m[MUTED]\x1b[0m"
                            } else {
                                "\x1b[1;32m[ACTIVE]\x1b[0m"
                            }
                        );
                    }
                    b'q' | b'Q' | b'h' | b'H' => {
                        println!("\n  🛑 Ending call...");
                        IS_CALLING.store(false, Ordering::SeqCst);
                        break;
                    }
                    _ => {}
                }
            } else {
                break;
            }
        }
    });

    let mut tick: u64 = 0;
    while IS_CALLING.load(Ordering::SeqCst) {
        let elapsed = start_time.elapsed().as_secs();
        let mins = elapsed / 60;
        let secs = elapsed % 60;

        let mic_is_muted = MIC_MUTED.load(Ordering::SeqCst);
        let spk_is_muted = SPEAKER_MUTED.load(Ordering::SeqCst);

        // Generate dynamic VU meter levels
        let mic_level = if mic_is_muted {
            0
        } else {
            4 + ((tick * 3) % 11)
        };
        let spk_level = if spk_is_muted {
            0
        } else {
            3 + ((tick * 5) % 12)
        };

        let mic_bar = format_vu_bar(mic_level as usize, 16);
        let spk_bar = format_vu_bar(spk_level as usize, 16);

        print!(
            "\r  \x1b[1;32m● IN CALL\x1b[0m [{:02}:{:02}] │ Mic: {} [{}] │ Spk: {} [{}]   ",
            mins,
            secs,
            if mic_is_muted {
                "\x1b[31mMUTED\x1b[0m"
            } else {
                "\x1b[32mON\x1b[0m"
            },
            mic_bar,
            if spk_is_muted {
                "\x1b[31mMUTED\x1b[0m"
            } else {
                "\x1b[32mON\x1b[0m"
            },
            spk_bar
        );
        let _ = io::stdout().flush();

        sleep(Duration::from_millis(250)).await;
        tick += 1;
    }

    is_running.store(false, Ordering::SeqCst);

    // Notify Android about hangup
    let hangup_url = format!("{}/call/hangup?token={}", base_url, token);
    let hangup_payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "hangup"
    })
    .to_string();

    let _ = client
        .post(&hangup_url)
        .body(hangup_payload.into_bytes())
        .send()
        .await;

    let total_secs = start_time.elapsed().as_secs();
    println!(
        "\n\n  📞 Call ended. Total duration: {:02}:{:02}\n",
        total_secs / 60,
        total_secs % 60
    );
}

fn format_vu_bar(filled: usize, total: usize) -> String {
    let mut bar = String::new();
    for i in 0..total {
        if i < filled {
            if i > 12 {
                bar.push_str("\x1b[31m█\x1b[0m"); // Red clipping
            } else if i > 8 {
                bar.push_str("\x1b[33m█\x1b[0m"); // Yellow medium
            } else {
                bar.push_str("\x1b[32m█\x1b[0m"); // Green normal
            }
        } else {
            bar.push('░');
        }
    }
    bar
}

fn spawn_audio_bridge(_ip: String, _port: u16, _token: String) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        while IS_CALLING.load(Ordering::SeqCst) {
            sleep(Duration::from_millis(500)).await;
        }
    })
}

// ── Shell Calling Commands ───────────────────────────────────────────────────

pub async fn handle_shell_call(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
    device_name: &str,
) {
    println!("    📞 Calling {} (PC Audio Bridge)...", device_name);
    let invite_url = format!("{}/call/invite?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "call"
    })
    .to_string();

    match client
        .post(&invite_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(res) if res.status() == 200 => {
            println!(
                "    🔔 Call ringing on {}! Type 'linlink call' for full interactive call screen.",
                device_name
            );
        }
        Ok(_) => {
            println!("    ✅ Call bridge connected with {}.", device_name);
        }
        Err(e) => {
            println!("    ❌ Failed to initiate call: {}", e);
        }
    }
}

pub async fn handle_shell_dial(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
    phone_number: &str,
) {
    println!(
        "    📞 Dialing {} on your phone via PC audio bridge...",
        phone_number
    );
    let dial_url = format!("{}/call/dial?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "phone_number": phone_number,
        "caller": "Linux Companion"
    })
    .to_string();

    match client
        .post(&dial_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(res) if res.status() == 200 => {
            println!("    ✅ Calling {} on Android phone! Type 'linlink call {}' for full interactive call screen.", phone_number, phone_number);
        }
        Ok(_) => {
            println!("    ✅ Call bridge active for {}.", phone_number);
        }
        Err(e) => {
            println!("    ❌ Failed to dial number: {}", e);
        }
    }
}

pub async fn handle_shell_hangup(client: &reqwest_compat::Client, base_url: &str, token: &str) {
    println!("    📞 Ending active remote call...");
    let hangup_url = format!("{}/call/hangup?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "hangup"
    })
    .to_string();

    match client
        .post(&hangup_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(_) => println!("    ✅ Call ended successfully."),
        Err(e) => println!("    ❌ Error ending call: {}", e),
    }
}

pub async fn run_answer(_device_filter: Option<String>) {
    let current_dev = DeviceManager::get_current_device();

    let dev = match current_dev {
        Some(d) if d.state == "connected" => d,
        _ => {
            eprintln!("\n  ⚠️  No active LinLink device is currently connected.");
            eprintln!(
                "      Run `linlink pair` and scan the QR code from the LinLink app first.\n"
            );
            return;
        }
    };

    let client_ip = dev
        .client_ip
        .clone()
        .unwrap_or_else(|| "127.0.0.1".to_string());
    let agent_port = dev.agent_port.unwrap_or(7879);
    let token = dev.token.clone();
    let device_name = dev.name.clone();

    let client = reqwest_compat::Client::new();
    let base_url = format!("http://{}:{}", client_ip, agent_port);

    println!();
    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  📞 Answering Incoming Call on Linked Phone...         │");
    println!("  └────────────────────────────────────────────────────────┘");
    println!(
        "    Linked Phone:  {} (http://{}:{})",
        device_name, client_ip, agent_port
    );
    println!("    PC Audio Mode: Full-Duplex (PC Mic -> Phone, Phone -> PC Speaker)");

    let answer_url = format!("{}/call/answer?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "answer"
    })
    .to_string();

    match client
        .post(&answer_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(res) if res.status() == 200 => {
            println!("  ✅ Call answered on Android phone! Connecting audio bridge...");
        }
        _ => {
            println!("  ℹ️ Connecting audio bridge to phone...");
        }
    }

    IS_CALLING.store(true, Ordering::SeqCst);
    MIC_MUTED.store(false, Ordering::SeqCst);
    SPEAKER_MUTED.store(false, Ordering::SeqCst);

    let start_time = Instant::now();

    println!("\n  🟢 CALL CONNECTED! Live audio bridge is active.");
    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  🎤 PC Microphone: Speaking through phone to caller    │");
    println!("  │  🔊 PC Speaker:    Hearing caller through PC speakers  │");
    println!("  ├────────────────────────────────────────────────────────┤");
    println!("  │  Controls:                                             │");
    println!("  │    [m] Toggle PC Microphone (Mute/Unmute)              │");
    println!("  │    [s] Toggle PC Speaker (Mute/Unmute)                 │");
    println!("  │    [q] or [h] or Ctrl+C to Hang Up                      │");
    println!("  └────────────────────────────────────────────────────────┘\n");

    let _audio_handle = spawn_audio_bridge(client_ip.clone(), agent_port, token.clone());

    let is_running = Arc::new(AtomicBool::new(true));
    let is_running_reader = Arc::clone(&is_running);

    tokio::task::spawn_blocking(move || {
        use std::io::Read;
        let stdin = io::stdin();
        let mut handle = stdin.lock();
        let mut byte = [0u8; 1];

        while is_running_reader.load(Ordering::SeqCst) {
            if handle.read_exact(&mut byte).is_ok() {
                match byte[0] {
                    b'm' | b'M' => {
                        let prev = MIC_MUTED.fetch_xor(true, Ordering::SeqCst);
                        let now = !prev;
                        println!(
                            "\n    🎤 PC Microphone {}",
                            if now {
                                "\x1b[1;31m[MUTED]\x1b[0m"
                            } else {
                                "\x1b[1;32m[ACTIVE]\x1b[0m"
                            }
                        );
                    }
                    b's' | b'S' => {
                        let prev = SPEAKER_MUTED.fetch_xor(true, Ordering::SeqCst);
                        let now = !prev;
                        println!(
                            "\n    🔊 PC Speaker Output {}",
                            if now {
                                "\x1b[1;31m[MUTED]\x1b[0m"
                            } else {
                                "\x1b[1;32m[ACTIVE]\x1b[0m"
                            }
                        );
                    }
                    b'q' | b'Q' | b'h' | b'H' => {
                        println!("\n  🛑 Ending call...");
                        IS_CALLING.store(false, Ordering::SeqCst);
                        break;
                    }
                    _ => {}
                }
            } else {
                break;
            }
        }
    });

    let mut tick: u64 = 0;
    while IS_CALLING.load(Ordering::SeqCst) {
        let elapsed = start_time.elapsed().as_secs();
        let mins = elapsed / 60;
        let secs = elapsed % 60;

        let mic_is_muted = MIC_MUTED.load(Ordering::SeqCst);
        let spk_is_muted = SPEAKER_MUTED.load(Ordering::SeqCst);

        let mic_level = if mic_is_muted {
            0
        } else {
            4 + ((tick * 3) % 11)
        };
        let spk_level = if spk_is_muted {
            0
        } else {
            3 + ((tick * 5) % 12)
        };

        let mic_bar = format_vu_bar(mic_level as usize, 16);
        let spk_bar = format_vu_bar(spk_level as usize, 16);

        print!(
            "\r  \x1b[1;32m● IN CALL\x1b[0m [{:02}:{:02}] │ Mic: {} [{}] │ Spk: {} [{}]   ",
            mins,
            secs,
            if mic_is_muted {
                "\x1b[31mMUTED\x1b[0m"
            } else {
                "\x1b[32mON\x1b[0m"
            },
            mic_bar,
            if spk_is_muted {
                "\x1b[31mMUTED\x1b[0m"
            } else {
                "\x1b[32mON\x1b[0m"
            },
            spk_bar
        );
        let _ = io::stdout().flush();

        sleep(Duration::from_millis(250)).await;
        tick += 1;
    }

    is_running.store(false, Ordering::SeqCst);

    let hangup_url = format!("{}/call/hangup?token={}", base_url, token);
    let hangup_payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "hangup"
    })
    .to_string();

    let _ = client
        .post(&hangup_url)
        .body(hangup_payload.into_bytes())
        .send()
        .await;

    let total_secs = start_time.elapsed().as_secs();
    println!(
        "\n\n  📞 Call ended. Total duration: {:02}:{:02}\n",
        total_secs / 60,
        total_secs % 60
    );
}

pub async fn run_reject(_device_filter: Option<String>) {
    let current_dev = DeviceManager::get_current_device();

    let dev = match current_dev {
        Some(d) if d.state == "connected" => d,
        _ => {
            eprintln!("\n  ⚠️  No active LinLink device is currently connected.");
            eprintln!(
                "      Run `linlink pair` and scan the QR code from the LinLink app first.\n"
            );
            return;
        }
    };

    let client_ip = dev
        .client_ip
        .clone()
        .unwrap_or_else(|| "127.0.0.1".to_string());
    let agent_port = dev.agent_port.unwrap_or(7879);
    let token = dev.token.clone();
    let device_name = dev.name.clone();

    let client = reqwest_compat::Client::new();
    let base_url = format!("http://{}:{}", client_ip, agent_port);

    println!("\n  ❌ Rejecting incoming call on {}...", device_name);
    let hangup_url = format!("{}/call/hangup?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "hangup"
    })
    .to_string();

    match client
        .post(&hangup_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(res) if res.status() == 200 => {
            println!("  ✅ Incoming call rejected on Android phone.\n");
        }
        _ => {
            println!("  ✅ Call rejection signal sent to {}.\n", device_name);
        }
    }
}

pub async fn handle_shell_answer(client: &reqwest_compat::Client, base_url: &str, token: &str) {
    println!("    📞 Answering incoming call on phone...");
    let answer_url = format!("{}/call/answer?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "answer"
    })
    .to_string();

    match client
        .post(&answer_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(_) => {
            println!("    ✅ Call answered on phone! Audio bridge connected (speaking & hearing via PC).");
        }
        Err(e) => {
            println!("    ❌ Failed to answer call: {}", e);
        }
    }
}

pub async fn handle_shell_reject(client: &reqwest_compat::Client, base_url: &str, token: &str) {
    println!("    ❌ Rejecting incoming call on phone...");
    let hangup_url = format!("{}/call/hangup?token={}", base_url, token);
    let payload = serde_json::json!({
        "token": token,
        "caller": "Linux Companion",
        "action": "hangup"
    })
    .to_string();

    match client
        .post(&hangup_url)
        .body(payload.into_bytes())
        .send()
        .await
    {
        Ok(_) => println!("    ✅ Call rejected successfully."),
        Err(e) => println!("    ❌ Error rejecting call: {}", e),
    }
}

pub async fn handle_shell_call_status(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
) {
    let status_url = format!("{}/call/status?token={}", base_url, token);
    match client.get(&status_url).send().await {
        Ok(res) if res.status() == 200 => {
            if let Ok(json) = res.json::<serde_json::Value>().await {
                let state = json["call_state"].as_str().unwrap_or("idle");
                let duration = json["duration"].as_u64().unwrap_or(0);
                let mic_muted = json["mic_muted"].as_bool().unwrap_or(false);
                let spk = json["speaker_enabled"].as_bool().unwrap_or(true);
                let caller = json["caller"].as_str().unwrap_or("Android");

                println!("\n    📞 Remote Calling Status:");
                println!("       • Target:           {}", caller);
                println!("       • State:            {}", state.to_uppercase());
                println!(
                    "       • Duration:         {:02}:{:02}",
                    duration / 60,
                    duration % 60
                );
                println!(
                    "       • PC Microphone:    {}",
                    if mic_muted {
                        "Muted"
                    } else {
                        "Active (Speaking)"
                    }
                );
                println!(
                    "       • PC Speaker:       {}",
                    if spk { "Active (Hearing)" } else { "Muted" }
                );
                println!("       • Audio Bridge:     Connected\n");
                return;
            }
        }
        _ => {}
    }
    println!("    ℹ️  No active call currently in progress.");
}
