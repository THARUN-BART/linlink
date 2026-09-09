use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::device::DeviceManager;
use crate::storage::Storage;

pub async fn run_shell(_device_filter: Option<String>) {
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

    println!();
    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  💻 LinLink Interactive Terminal 📱                    │");
    println!("  └────────────────────────────────────────────────────────┘");
    println!("    Device:   {}", device_name);
    println!("    Endpoint: http://{}:{}", client_ip, agent_port);
    println!("    Session:  {}", dev.token);
    println!("    Type 'help' for commands, 'exit' or Ctrl+C to quit.\n");

    let client = reqwest_client();
    let base_url = format!("http://{}:{}", client_ip, agent_port);

    // Verify agent is reachable
    let ping_url = format!("{}/fs/ping?token={}", base_url, token);
    match client.get(&ping_url).send().await {
        Ok(res) if (200..300).contains(&res.status()) => {
            println!("  🟢 Connected to Android file agent successfully!\n");
        }
        _ => {
            println!(
                "  🟡 Warning: Android file agent at http://{}:{} is not responding.",
                client_ip, agent_port
            );
            println!("     Make sure the LinLink app is open on your Android phone.\n");
        }
    }

    let mut current_dir = "/storage/emulated/0".to_string();

    loop {
        // Display prompt
        print!(
            "  \x1b[1;36m📱 {}\x1b[0m \x1b[1;33m[{}]\x1b[0m > ",
            device_name, current_dir
        );
        let _ = io::stdout().flush();

        let mut input = String::new();
        if io::stdin().read_line(&mut input).is_err() {
            break;
        }

        let trimmed = input.trim();
        if trimmed.is_empty() {
            continue;
        }

        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        let cmd = parts[0].to_lowercase();
        let args = &parts[1..];

        match cmd.as_str() {
            "exit" | "quit" | "q" => {
                println!("\n  👋 Exiting LinLink shell.\n");
                break;
            }

            "help" | "?" => {
                print_shell_help();
            }

            "clear" | "cls" => {
                // Clear both the visible viewport and the scrollback buffer (\x1b[3J)
                // so the terminal does not push content up into hidden scrollback history.
                if std::process::Command::new("clear").status().is_err() {
                    print!("\x1b[H\x1b[2J\x1b[3J");
                }
                println!();
                println!("  📱 LinLink Shell \x1b[1;30m(connected to {})\x1b[0m", device_name);
                println!("  Type 'help' for commands, 'exit' to quit.\n");
                let _ = io::stdout().flush();
            }

            "pwd" => {
                println!("    {}", current_dir);
            }

            "ls" | "dir" => {
                let target_path = if !args.is_empty() {
                    resolve_path(&current_dir, args[0])
                } else {
                    current_dir.clone()
                };
                handle_ls(&client, &base_url, &token, &target_path).await;
            }

            "cd" => {
                if args.is_empty() {
                    current_dir = "/storage/emulated/0".to_string();
                } else {
                    let new_path = resolve_path(&current_dir, args[0]);
                    // Validate path exists on phone
                    if verify_dir(&client, &base_url, &token, &new_path).await {
                        current_dir = new_path;
                    } else {
                        println!("    ❌ Directory not found: {}", new_path);
                    }
                }
            }

            "get" | "download" | "pull" => {
                if args.is_empty() {
                    println!("    Usage: get <remote_filename> [local_destination]");
                } else {
                    let remote_file = resolve_path(&current_dir, args[0]);
                    let filename = Path::new(&remote_file)
                        .file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_else(|| "downloaded_file".into());

                    let local_dest = if args.len() > 1 {
                        PathBuf::from(args[1])
                    } else {
                        Storage::transfers_dir().join(&filename)
                    };

                    handle_get(&client, &base_url, &token, &remote_file, &local_dest).await;
                }
            }

            "put" | "upload" | "push" => {
                if args.is_empty() {
                    println!("    Usage: put <local_file_path> [remote_filename]");
                } else {
                    let local_path = PathBuf::from(args[0]);
                    if !local_path.exists() || !local_path.is_file() {
                        println!("    ❌ Local file does not exist: {}", local_path.display());
                        continue;
                    }

                    let remote_filename = if args.len() > 1 {
                        args[1].to_string()
                    } else {
                        local_path
                            .file_name()
                            .map(|n| n.to_string_lossy().to_string())
                            .unwrap_or_else(|| "uploaded_file".into())
                    };

                    handle_put(
                        &client,
                        &base_url,
                        &token,
                        &local_path,
                        &current_dir,
                        &remote_filename,
                    )
                    .await;
                }
            }

            "cat" | "view" => {
                if args.is_empty() {
                    println!("    Usage: cat <remote_filename>");
                } else {
                    let remote_file = resolve_path(&current_dir, args[0]);
                    handle_cat(&client, &base_url, &token, &remote_file).await;
                }
            }

            "mkdir" => {
                if args.is_empty() {
                    println!("    Usage: mkdir <folder_name>");
                } else {
                    let target = resolve_path(&current_dir, args[0]);
                    handle_mkdir(&client, &base_url, &token, &target).await;
                }
            }

            "rm" | "del" => {
                if args.is_empty() {
                    println!("    Usage: rm <filename>");
                } else {
                    let target = resolve_path(&current_dir, args[0]);
                    handle_rm(&client, &base_url, &token, &target).await;
                }
            }

            "clip" | "clipboard" => {
                if args.is_empty() {
                    match Storage::load_clipboard() {
                        Some(t) if !t.is_empty() => println!("    📋 Current clipboard: \"{}\"", t),
                        _ => println!("    📋 Shared clipboard is empty."),
                    }
                } else {
                    let text = args.join(" ");
                    Storage::save_clipboard(&text);
                    println!("    📋 Saved to shared clipboard: \"{}\"", text);
                }
            }

            other => {
                println!(
                    "    Unknown command: '{}'. Type 'help' for available commands.",
                    other
                );
            }
        }
    }
}

// ── HTTP Helper routines ──────────────────────────────────────────────────────

fn reqwest_client() -> reqwest_compat::Client {
    reqwest_compat::Client::new()
}

fn resolve_path(current: &str, target: &str) -> String {
    if target.starts_with('/') {
        return normalize_path(target);
    }
    if target == "~" || target == "@" {
        return "/storage/emulated/0".to_string();
    }
    let combined = format!("{}/{}", current.trim_end_matches('/'), target);
    normalize_path(&combined)
}

fn normalize_path(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for seg in path.split('/') {
        if seg.is_empty() || seg == "." {
            continue;
        } else if seg == ".." {
            parts.pop();
        } else {
            parts.push(seg);
        }
    }
    format!("/{}", parts.join("/"))
}

async fn verify_dir(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
    path: &str,
) -> bool {
    let url = format!(
        "{}/fs/list?token={}&path={}",
        base_url,
        token,
        url_encode(path)
    );
    match client.get(&url).send().await {
        Ok(res) => res.status() == 200,
        Err(_) => false,
    }
}
fn wrap_str(s: &str, width: usize) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    chars
        .chunks(width)
        .map(|chunk| chunk.iter().collect())
        .collect()
}

async fn handle_ls(client: &reqwest_compat::Client, base_url: &str, token: &str, path: &str) {
    let url = format!(
        "{}/fs/list?token={}&path={}",
        base_url,
        token,
        url_encode(path)
    );
    match client.get(&url).send().await {
        Ok(res) if res.status() == 200 => match res.json::<serde_json::Value>().await {
            Ok(json) => {
                if let Some(err_msg) = json.get("message").and_then(|m| m.as_str()) {
                    if json.get("status").and_then(|s| s.as_str()) == Some("error") {
                        println!("    ❌ Android Message: {}", err_msg);
                        if json.get("permission_needed").and_then(|p| p.as_bool()) == Some(true) {
                            println!(
                                "    ⚠️  Please open the LinLink app on your phone and tap 'Grant All Files / Storage Access'.\n"
                            );
                        }
                        return;
                    }
                }

                if let Some(entries) = json.get("entries").and_then(|e| e.as_array()) {
                    if entries.is_empty() {
                        println!("    Listing: \x1b[1m{}\x1b[0m\n", path);
                        println!("    (Directory is empty)\n");
                        return;
                    }

                    println!(
                        "    Listing: \x1b[1m{}\x1b[0m ({} items)\n",
                        path,
                        entries.len()
                    );
                    println!(
                        "    {:<5} {:<32} {:>10}   {}",
                        "TYPE", "NAME", "SIZE", "MODIFIED"
                    );
                    println!(
                        "    ──────────────────────────────────────────────────────────────────"
                    );
                    for entry in entries {
                        let name = entry["name"].as_str().unwrap_or("");
                        let is_dir = entry["is_dir"].as_bool().unwrap_or(false);
                        let size = entry["size"].as_u64().unwrap_or(0);
                        let modified = entry["modified"].as_str().unwrap_or("-");

                        let name_lines = wrap_str(name, 32);

                        for (i, line) in name_lines.iter().enumerate() {
                            if i == 0 {
                                if is_dir {
                                    println!(
                                        "    \x1b[1;34m{:<5}\x1b[0m \x1b[1;36m{:<32}\x1b[0m {:>10}   {}",
                                        "DIR", line, "-", modified
                                    );
                                } else {
                                    println!(
                                        "    {:<5} {:<32} {:>10}   {}",
                                        "FILE",
                                        line,
                                        format_bytes(size),
                                        modified
                                    );
                                }
                            } else {
                                println!("    {:<5} {:<32}", "", line);
                            }
                        }
                    }
                    println!();
                    return;
                }
                println!("    (No entries found for {})", path);
            }
            Err(e) => {
                println!("    ❌ Failed to parse response from Android: {}", e);
            }
        },
        Ok(res) => {
            println!(
                "    ❌ Failed to list files (HTTP {}). Check permissions on Android.",
                res.status()
            );
        }
        Err(e) => {
            println!(
                "    ❌ Connection error: {}. Ensure LinLink app is running on phone.",
                e
            );
        }
    }
}

async fn handle_get(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
    remote_path: &str,
    local_dest: &Path,
) {
    println!("    ⬇️  Downloading '{}' over TCP...", remote_path);
    let url = format!(
        "{}/fs/download?token={}&path={}",
        base_url,
        token,
        url_encode(remote_path)
    );

    match client.get(&url).send().await {
        Ok(res) if res.status() == 200 => {
            if let Ok(bytes) = res.bytes().await {
                if let Some(parent) = local_dest.parent() {
                    let _ = std::fs::create_dir_all(parent);
                }
                match std::fs::write(local_dest, &bytes) {
                    Ok(_) => {
                        println!(
                            "    ✅ Successfully downloaded to \x1b[1m{}\x1b[0m ({})",
                            local_dest.display(),
                            format_bytes(bytes.len() as u64)
                        );
                    }
                    Err(e) => println!("    ❌ Error writing local file: {}", e),
                }
            } else {
                println!("    ❌ Failed to read data stream from Android.");
            }
        }
        Ok(res) => println!(
            "    ❌ Download failed (HTTP {}). File may not exist.",
            res.status()
        ),
        Err(e) => println!("    ❌ Network error: {}", e),
    }
}

async fn handle_put(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
    local_path: &Path,
    remote_dir: &str,
    remote_filename: &str,
) {
    let bytes = match std::fs::read(local_path) {
        Ok(b) => b,
        Err(e) => {
            println!("    ❌ Could not read local file: {}", e);
            return;
        }
    };

    println!(
        "    ⬆️  Uploading '{}' ({}) to Android [{}] over TCP...",
        local_path.file_name().unwrap_or_default().to_string_lossy(),
        format_bytes(bytes.len() as u64),
        remote_dir
    );

    let url = format!(
        "{}/fs/upload?token={}&path={}&filename={}",
        base_url,
        token,
        url_encode(remote_dir),
        url_encode(remote_filename)
    );

    match client.post(&url).body(bytes).send().await {
        Ok(res) if res.status() == 200 => {
            println!("    ✅ Upload complete: {}/{}", remote_dir, remote_filename);
        }
        Ok(res) => println!(
            "    ❌ Upload failed (HTTP {}). Check Android storage permissions.",
            res.status()
        ),
        Err(e) => println!("    ❌ Network error: {}", e),
    }
}

async fn handle_cat(
    client: &reqwest_compat::Client,
    base_url: &str,
    token: &str,
    remote_path: &str,
) {
    let url = format!(
        "{}/fs/download?token={}&path={}",
        base_url,
        token,
        url_encode(remote_path)
    );
    match client.get(&url).send().await {
        Ok(res) if res.status() == 200 => {
            if let Ok(bytes) = res.bytes().await {
                if let Ok(text) = std::str::from_utf8(&bytes) {
                    println!("\n    ─── Content of {} ───", remote_path);
                    for line in text.lines() {
                        println!("    {}", line);
                    }
                    println!("    ──────────────────────────────\n");
                } else {
                    println!(
                        "    ⚠️  File appears to be binary ({} bytes). Cannot print.",
                        bytes.len()
                    );
                }
            }
        }
        Ok(res) => println!("    ❌ Could not open file (HTTP {}).", res.status()),
        Err(e) => println!("    ❌ Network error: {}", e),
    }
}

async fn handle_mkdir(client: &reqwest_compat::Client, base_url: &str, token: &str, path: &str) {
    let url = format!(
        "{}/fs/mkdir?token={}&path={}",
        base_url,
        token,
        url_encode(path)
    );
    match client.post(&url).send().await {
        Ok(res) if res.status() == 200 => {
            println!("    ✅ Created directory: {}", path);
        }
        Ok(res) => println!("    ❌ Failed to create directory (HTTP {}).", res.status()),
        Err(e) => println!("    ❌ Network error: {}", e),
    }
}

async fn handle_rm(client: &reqwest_compat::Client, base_url: &str, token: &str, path: &str) {
    let url = format!(
        "{}/fs/delete?token={}&path={}",
        base_url,
        token,
        url_encode(path)
    );
    match client.post(&url).send().await {
        Ok(res) if res.status() == 200 => {
            println!("    ✅ Removed: {}", path);
        }
        Ok(res) => println!("    ❌ Failed to remove file (HTTP {}).", res.status()),
        Err(e) => println!("    ❌ Network error: {}", e),
    }
}

fn print_shell_help() {
    println!();
    println!("  Available Shell Commands:");
    println!("  ─────────────────────────────────────────────────────────────");
    println!("  ls [path]                     List files and folders on phone");
    println!("  cd <dir>                      Change current directory on phone");
    println!("  pwd                           Print current phone directory");
    println!("  get <remote_file> [local_dst] Download/pull file from phone to Linux");
    println!("  put <local_file> [remote_fn]  Upload/push file from Linux to phone");
    println!("  cat <remote_file>             Print text file contents");
    println!("  mkdir <folder_name>           Create directory on phone");
    println!("  rm <remote_file>              Delete file on phone");
    println!("  clip [text]                   View or set shared clipboard");
    println!("  clear                         Clear the terminal screen");
    println!("  exit, quit                    Exit interactive shell");
    println!();
}

fn format_bytes(bytes: u64) -> String {
    if bytes >= 1_000_000_000 {
        format!("{:.1} GB", bytes as f64 / 1_000_000_000.0)
    } else if bytes >= 1_000_000 {
        format!("{:.1} MB", bytes as f64 / 1_000_000.0)
    } else if bytes >= 1_000 {
        format!("{:.1} KB", bytes as f64 / 1_000.0)
    } else {
        format!("{} B", bytes)
    }
}

#[allow(dead_code)]
fn truncate_str(s: &str, max: usize) -> String {
    if s.len() > max {
        format!("{}…", &s[..max - 1])
    } else {
        s.to_string()
    }
}

fn url_encode(s: &str) -> String {
    let mut encoded = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric()
            || b == b'-'
            || b == b'_'
            || b == b'.'
            || b == b'~'
            || b == b'/'
        {
            encoded.push(b as char);
        } else {
            encoded.push_str(&format!("%{:02X}", b));
        }
    }
    encoded
}

// ── Minimal built-in HTTP client over TCP without extra dependencies ───────────
// Uses tokio::net::TcpStream or std to send HTTP 1.1 requests over pure TCP!

pub mod reqwest_compat {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpStream;

    #[derive(Clone)]
    pub struct Client;

    impl Client {
        pub fn new() -> Self {
            Client
        }

        pub fn get(&self, url: &str) -> RequestBuilder {
            RequestBuilder {
                method: "GET".to_string(),
                url: url.to_string(),
                body: Vec::new(),
            }
        }

        pub fn post(&self, url: &str) -> RequestBuilder {
            RequestBuilder {
                method: "POST".to_string(),
                url: url.to_string(),
                body: Vec::new(),
            }
        }
    }

    pub struct RequestBuilder {
        method: String,
        url: String,
        body: Vec<u8>,
    }

    impl RequestBuilder {
        pub fn body(mut self, data: Vec<u8>) -> Self {
            self.body = data;
            self
        }

        pub async fn send(self) -> Result<Response, String> {
            let uri = self.url.strip_prefix("http://").unwrap_or(&self.url);
            let slash_idx = uri.find('/').unwrap_or(uri.len());
            let host_port = &uri[..slash_idx];
            let path_query = if slash_idx < uri.len() {
                &uri[slash_idx..]
            } else {
                "/"
            };

            let addr = if host_port.contains(':') {
                host_port.to_string()
            } else {
                format!("{}:80", host_port)
            };

            let mut stream =
                tokio::time::timeout(Duration::from_secs(5), TcpStream::connect(&addr))
                    .await
                    .map_err(|_| "Connection timed out".to_string())?
                    .map_err(|e| format!("Failed to connect to {}: {}", addr, e))?;

            let header = format!(
                "{} {} HTTP/1.1\r\nHost: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                self.method,
                path_query,
                host_port,
                self.body.len()
            );

            stream
                .write_all(header.as_bytes())
                .await
                .map_err(|e| e.to_string())?;

            if !self.body.is_empty() {
                stream
                    .write_all(&self.body)
                    .await
                    .map_err(|e| e.to_string())?;
            }

            let mut resp_data = Vec::new();
            stream
                .read_to_end(&mut resp_data)
                .await
                .map_err(|e| e.to_string())?;

            parse_http_response(resp_data)
        }
    }

    pub struct Response {
        status_code: u16,
        body: Vec<u8>,
    }

    impl Response {
        pub fn status(&self) -> u16 {
            self.status_code
        }

        pub async fn bytes(self) -> Result<Vec<u8>, String> {
            Ok(self.body)
        }

        pub async fn json<T: serde::de::DeserializeOwned>(self) -> Result<T, String> {
            serde_json::from_slice(&self.body).map_err(|e| e.to_string())
        }
    }

    fn parse_http_response(raw: Vec<u8>) -> Result<Response, String> {
        let double_crlf = b"\r\n\r\n";
        let sep_pos = raw
            .windows(4)
            .position(|w| w == double_crlf)
            .ok_or_else(|| "Invalid HTTP response".to_string())?;

        let header_bytes = &raw[..sep_pos];
        let body_bytes = raw[sep_pos + 4..].to_vec();

        let header_str = String::from_utf8_lossy(header_bytes);
        let first_line = header_str
            .lines()
            .next()
            .ok_or_else(|| "Empty status line".to_string())?;

        let parts: Vec<&str> = first_line.split_whitespace().collect();
        let status_code = if parts.len() >= 2 {
            parts[1].parse::<u16>().unwrap_or(500)
        } else {
            500
        };

        let is_chunked = header_str
            .to_lowercase()
            .contains("transfer-encoding: chunked");
        let decoded_body = if is_chunked {
            decode_chunked_body(&body_bytes)
        } else {
            body_bytes
        };

        Ok(Response {
            status_code,
            body: decoded_body,
        })
    }

    fn decode_chunked_body(mut body: &[u8]) -> Vec<u8> {
        let mut decoded = Vec::new();
        while !body.is_empty() {
            let Some(crlf_pos) = body.windows(2).position(|w| w == b"\r\n") else {
                decoded.extend_from_slice(body);
                break;
            };

            let size_str = String::from_utf8_lossy(&body[..crlf_pos]);
            // Remove any chunk extensions (after ';')
            let clean_size_str = size_str.split(';').next().unwrap_or("").trim();
            let Ok(size) = usize::from_str_radix(clean_size_str, 16) else {
                decoded.extend_from_slice(body);
                break;
            };

            if size == 0 {
                break;
            }

            let start = crlf_pos + 2;
            if start + size > body.len() {
                decoded.extend_from_slice(&body[start..]);
                break;
            }

            decoded.extend_from_slice(&body[start..start + size]);
            body = &body[start + size..];
            if body.starts_with(b"\r\n") {
                body = &body[2..];
            }
        }
        decoded
    }
}
