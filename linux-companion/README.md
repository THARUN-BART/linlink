# LinLink Linux Companion 🐧💻

> **High-Performance Rust Daemon, CLI Suite, and Interactive Android Storage Shell.**

The **Linux Companion** is the core backend of LinLink on the Linux host. Written in modern Rust (Edition 2024), it provides an asynchronous HTTP daemon (Axum), local network IP discovery, terminal ANSI QR code generation, native Wayland/X11 clipboard synchronization, an interactive terminal shell to browse Android storage, and **instant disconnect notification** pushed to the Android app on shutdown.

---

## 📑 Table of Contents

- [Architecture & Modules](#-architecture--modules)
- [Module Reference](#-module-reference)
  - [1. CLI Engine (`src/cli/`)](#1-cli-engine-srccli)
  - [2. Interactive Shell REPL (`src/cli/shell.rs`)](#2-interactive-shell-repl-srcclishellrs)
  - [3. Background Daemon Server (`src/daemon/server.rs`)](#3-background-daemon-server-srcdaemonserverrs)
  - [4. Daemon Process Management (`src/daemon/process.rs`)](#4-daemon-process-management-srcdaemonprocessrs)
  - [5. Pairing & Network Engine (`src/pairing/`)](#5-pairing--network-engine-srcpairing)
  - [6. Storage & State Persistence (`src/storage.rs`)](#6-storage--state-persistence-srcstoragers)
  - [7. Device Management & Models (`src/device/`)](#7-device-management--models-srcdevice)
- [Daemon HTTP API Endpoint Reference](#-daemon-http-api-endpoint-reference)
- [Android Agent HTTP API Reference](#-android-agent-http-api-reference)
- [Building & Installation](#-building--installation)
- [systemd Service Setup](#-systemd-service-setup)
- [Configuration & File Locations](#-configuration--file-locations)

---

## 🏛 Architecture & Modules

```
linux-companion/src/
├── main.rs                 # CLI entry point, tracing & tokio initialization
├── lib.rs                  # Library crate root & module declarations
├── storage.rs              # Filesystem persistence (JSON config, logs, transfers)
├── cli/
│   ├── mod.rs              # CLI module exports
│   ├── args.rs             # Clap CLI argument & command schemas
│   ├── runner.rs           # Subcommand execution router & dispatch
│   ├── shell.rs            # Interactive Android storage terminal shell REPL
│   └── ui.rs               # Terminal UI, tables, banners & formatting
├── daemon/
│   ├── mod.rs              # Daemon module exports
│   ├── process.rs          # Background daemon process spawning & lifecycle
│   └── server.rs           # Axum HTTP/TCP daemon, clipboard monitor,
│                           #   push_disconnect_to_android()
├── device/
│   ├── mod.rs              # Device module exports
│   ├── manager.rs          # Device registry queries & active session resolution
│   └── model.rs            # Data structures (PairedDevice, ActiveSession)
└── pairing/
    ├── mod.rs              # Pairing module exports
    ├── network.rs          # LAN IP interface discovery (wlan0, eth0, etc.)
    ├── qr.rs               # ANSI terminal QR code generator
    ├── server.rs           # Ephemeral pairing handshake HTTP server
    ├── session.rs          # Session generation & token hashing
    └── state.rs            # Pairing state transitions
```

---

## 🔍 Module Reference

### 1. CLI Engine (`src/cli/`)

#### `src/cli/args.rs`
Defines command-line parsing using `clap` (Derive API):
- `struct Cli`: Global options including `--debug` / `-d` for verbose logging.
- `enum Commands`:
  - `Pair { host, port, foreground }`: Starts pairing server.
  - `Status`: Shows active link and device details.
  - `Devices { current, past, remove }`: Lists or removes paired devices.
  - `Stop { device }`: Stops the running daemon and notifies Android.
  - `Shell { device }`: Opens interactive terminal shell with Android.
  - `Logs { lines, follow }`: Inspects companion background logs.
  - `Clipboard { text }`: Gets or sets shared clipboard.
  - `Files`: Lists transfers folder contents.
  - `Daemon { ... }`: Hidden command used by `process.rs` to spawn the detached daemon.

#### `src/cli/runner.rs`
Primary subcommand router and executor:
- `async fn run_pair(host, port, foreground)`: Resolves LAN IP, generates session token, launches ephemeral pairing server, on handshake spawns background daemon.
- `async fn run_status()`: Queries daemon `/status` or loads `session.json`.
- `fn run_devices(current, past, remove)`: Formats tabular device history.
- `fn run_stop(device_filter)`: Sends SIGTERM to daemon PID (daemon then pushes `/fs/disconnect` to Android before exiting).
- `fn run_logs(lines, follow)`: Reads/tails `linlink.log`.

#### `src/cli/ui.rs`
Terminal formatting:
- `print_banner()`: ASCII LinLink banner.
- `print_success/warning/error/info(msg)`: Colored outputs.
- `format_table(...)`: Aligned tabular data.

---

### 2. Interactive Shell REPL (`src/cli/shell.rs`)

Terminal environment directly connected to the Android device's storage agent:

- `pub async fn run_shell(device_filter)`: Main REPL loop. Prompt: `📱 <Device> [<Path>] >`.
- `handle_ls(...)`: Requests `/fs/list` from Android, formats directory listing.
- `verify_dir(...)`: Validates directory exists before `cd`.
- `handle_get(...)`: Streams file from Android `/fs/download` to `~/Downloads/LinLink/`.
- `handle_put(...)`: Streams local file to Android via `/fs/upload`.
- `handle_cat(...)`: Fetches and prints remote text file in terminal.
- `handle_mkdir(...)`: Creates directory on Android via `/fs/mkdir`.
- `handle_rm(...)`: Deletes file or directory via `/fs/delete`.
- `resolve_path(current, target)`: Resolves relative paths (`..`, `~`, `@`) to absolute Android paths.
- `format_bytes(u64)`: Human-readable B / KB / MB / GB.
- `mod reqwest_compat`: Lightweight async HTTP client over raw `TcpStream` (no heavy dependencies).

---

### 3. Background Daemon Server (`src/daemon/server.rs`)

The background Axum HTTP server providing all TCP endpoints for the Android app.

#### Core State — `DaemonServerState`
| Field | Type | Purpose |
| :--- | :--- | :--- |
| `session_id` | `String` | Active session UUID |
| `host` / `port` | `String` / `u16` | Listening address |
| `token` | `String` | Auth token for all requests |
| `device_name` | `String` | Connected Android device name |
| `shutdown_tx` | `mpsc::Sender<()>` | Graceful shutdown channel |
| `last_synced_clipboard` | `Arc<Mutex<String>>` | Dedup clipboard state |
| `client_ip` | `Arc<Mutex<Option<String>>>` | Android IP (updated dynamically) |
| `agent_port` | `Arc<Mutex<Option<u16>>>` | Android file agent port |

#### Clipboard Synchronization Engine
- `read_system_clipboard()`: Wayland → `wl-paste -n`; X11 → `xclip` / `xsel`.
- `copy_to_system_clipboard(text)`: Wayland → `wl-copy`; X11 → `xclip`.
- `push_clipboard_to_android(ip, port, token, text)`: TCP `POST /fs/clipboard` to Android agent with 2s timeout.
- `clipboard_worker`: Background Tokio task polling every 800ms. Pushes changes to Android automatically.

#### Instant Disconnect — `push_disconnect_to_android()` *(new)*
- Called **before** every shutdown path (SIGTERM, SIGINT, HTTP unlink).
- Sends `POST /fs/disconnect` to the Android agent (2s timeout).
- Android receives it and immediately clears its paired state, stops sync, and returns to the connect screen — no polling required.

#### HTTP Handler Functions
| Handler | Route | Description |
| :--- | :--- | :--- |
| `handle_status` | `GET /status` | Returns JSON daemon state |
| `handle_ping` | `GET /ping` | Health check → `{"status":"pong"}` |
| `handle_device_register` | `POST /api/device/register` | Android registers its agent port |
| `handle_get_clipboard` | `GET /clipboard` | Serves current Linux clipboard |
| `handle_post_clipboard` | `POST /clipboard` | Receives clipboard from Android, updates Linux |
| `handle_list_files` | `GET /files` | Lists `~/Downloads/LinLink/` |
| `handle_file_upload` | `POST /files/upload` | Saves text/note upload |
| `handle_fs_list` | `POST /api/fs/list` | Lists Linux directory for Android browser |
| `handle_fs_download` | `GET /api/fs/download` | Streams Linux file to Android |
| `handle_fs_upload` | `POST /api/fs/upload` | Receives file from Android |
| `handle_unlink` | `POST /pair/unlink` | Sends shutdown signal + pushes disconnect to Android |

---

### 4. Daemon Process Management (`src/daemon/process.rs`)

- `DaemonProcess::spawn(host, port, token, session_id, device_name, client_ip)`:
  - Spawns current executable with hidden `daemon` subcommand.
  - Redirects stdout/stderr to `~/.config/linlink/linlink.log`.
  - Detaches process (outlives the pairing CLI command).
- `DaemonProcess::stop(device_filter) -> StopOutcome`:
  - Loads `session.json`, verifies PID liveness.
  - Sends `SIGTERM` to daemon PID → daemon's shutdown path then calls `push_disconnect_to_android`.
  - Returns `Stopped`, `DeviceMismatch`, `DeviceAlreadyDisconnected`, `DeviceNotFound`, or `NotRunning`.

---

### 5. Pairing & Network Engine (`src/pairing/`)

- `network.rs` — `get_local_ip()`: UDP socket trick to discover active LAN IPv4 address.
- `qr.rs` — `generate_qr_string(payload)`: Encodes `linlink://pair?host=...&port=...&token=...` into ANSI block characters (`█`, `▀`, `▄`).
- `server.rs` — `run_pairing_server(...)`: Ephemeral Axum server on port 7878 while user scans QR. Handles `POST /pair/scan` and `POST /pair/handshake`.
- `session.rs` — Session token generation and UUID v4 session IDs.
- `state.rs` — Pairing state transitions (`Pairing → Waiting → Connected → Stopped`).

---

### 6. Storage & State Persistence (`src/storage.rs`)

| Function | Description |
| :--- | :--- |
| `Storage::config_dir()` | `~/.config/linlink` (or `$LINLINK_CONFIG_DIR`) |
| `Storage::log_file()` | `linlink.log` path |
| `Storage::devices_file()` | `devices.json` path |
| `Storage::session_file()` | `session.json` path |
| `Storage::clipboard_file()` | `clipboard.txt` path |
| `Storage::transfers_dir()` | `~/Downloads/LinLink/` |
| `Storage::load/save_devices()` | Paired device registry CRUD |
| `Storage::record_device_connected/disconnected()` | Timestamp tracking |
| `Storage::save/load/clear_session()` | Active session persistence |
| `Storage::save/load_clipboard()` | Clipboard snapshot persistence |
| `Storage::is_pid_alive(pid)` | `/proc/<pid>/status` liveness check |
| `Storage::find_running_daemon_pids()` | Scans `/proc` for orphaned daemons |
| `current_timestamp()` | `YYYY-MM-DD HH:MM:SS UTC` string |

---

### 7. Device Management & Models (`src/device/`)

- `model.rs`:
  - `PairedDevice`: `{ id, name, token, paired_at, last_seen, disconnected_at, ip }`
  - `ActiveSession`: `{ pid, host, port, token, state, device_name, client_ip, agent_port, started_at }`
  - `ConnectedDeviceInfo`: DTO returned by `DeviceManager`
- `manager.rs`:
  - `DeviceManager::get_current_device()`: Validates PID liveness and returns active device.
  - `DeviceManager::get_all_devices()`: Combines active session + device history.

---

## 🌐 Daemon HTTP API Endpoint Reference

All authenticated endpoints accept the token in `?token=...`, request body `{"token":"..."}`, or `x-session-token` header.

| Endpoint | Method | Auth | Description |
| :--- | :--- | :--- | :--- |
| `/status` | GET | No | JSON daemon state, host, port, device name |
| `/ping` | GET | No | `{"status":"pong"}` |
| `/clipboard` | GET | No | Current Linux clipboard text |
| `/clipboard` | POST | Yes | Set Linux clipboard from Android |
| `/api/device/register` | POST | Yes | Android registers agent port |
| `/api/fs/list` | POST | Yes | List Linux directory for Android |
| `/api/fs/download` | GET | Yes | Stream Linux file to Android |
| `/api/fs/upload` | POST | Yes | Receive file from Android |
| `/files` | GET | No | List `~/Downloads/LinLink/` |
| `/files/upload` | POST | Yes | Text / note file upload |
| `/pair/unlink` | POST | Yes | Shutdown daemon + push `/fs/disconnect` to Android |

---

## 📱 Android Agent HTTP API Reference

The Android app runs `AndroidFileAgent` on port 7879. The Linux shell and daemon connect directly to these endpoints:

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/fs/ping` | GET | Android health check |
| `/pair/scan` | POST | QR scan acknowledgement |
| `/pair/handshake` | POST | Phone-to-phone pairing handshake |
| `/fs/disconnect` | POST | **Instant disconnect from Linux** — clears Android paired state immediately *(new)* |
| `/fs/list` | POST | List Android directory (Privacy Mode must be enabled) |
| `/fs/download` | GET | Download file from Android (Privacy Mode must be enabled) |
| `/fs/upload` | POST | Receive file upload from Linux |
| `/fs/clipboard` | POST | Receive clipboard push from Linux |
| `/fs/mkdir` | POST | Create directory on Android |
| `/fs/delete` | POST | Delete file or directory on Android |

---

## 🔨 Building & Installation

```bash
# Debug build
cargo build

# Optimized release binary
cargo build --release

# Install to user PATH (no sudo required)
cp target/release/linlink ~/.local/bin/

# Or install system-wide
sudo cp target/release/linlink /usr/local/bin/
```

Verify:
```bash
linlink --version
linlink --help
```

---

## 🖥 systemd Service Setup

A `systemd` user service allows `linlink` to auto-start on login without root:

```ini
# ~/.config/systemd/user/linlink.service
[Unit]
Description=LinLink Android-Linux Companion Bridge
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/linlink daemon
Restart=on-failure
RestartSec=5s
StandardOutput=append:%h/.config/linlink/linlink.log
StandardError=append:%h/.config/linlink/linlink.log
Environment=RUST_LOG=info

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable linlink
systemctl --user start linlink

# Service control
systemctl --user status linlink
systemctl --user stop linlink
journalctl --user -u linlink -f
```

---

## 📂 Configuration & File Locations

| Path | Purpose |
| :--- | :--- |
| `~/.config/linlink/linlink.log` | Daemon log output |
| `~/.config/linlink/session.json` | Active session state |
| `~/.config/linlink/devices.json` | Paired device registry |
| `~/.config/linlink/clipboard.txt` | Last synced clipboard snapshot |
| `~/Downloads/LinLink/` | Received file transfers |
| `~/.config/systemd/user/linlink.service` | systemd user service unit |
| `~/.local/bin/linlink` | Installed binary |
