# LinLink Linux Companion 🐧💻

> **High-Performance Rust Daemon, CLI Suite, and Interactive Android Storage Shell.**

The **Linux Companion** (`linux-companion`) is the core backend of LinLink on the Linux host. Written in modern Rust (Edition 2024), it provides an asynchronous HTTP daemon (Axum), local network IP discovery, terminal ANSI QR code generation, native Wayland/X11 clipboard synchronization, and an interactive terminal shell to browse and transfer files with connected Android devices.

---

## 📑 Table of Contents

- [Architecture & Modules](#-architecture--modules)
- [Comprehensive Function & Module Reference](#-comprehensive-function--module-reference)
  - [1. CLI Engine (`src/cli/`)](#1-cli-engine-srccli)
  - [2. Interactive Shell REPL (`src/cli/shell.rs`)](#2-interactive-shell-repl-srcclishellrs)
  - [3. Background Daemon Server (`src/daemon/server.rs`)](#3-background-daemon-server-srcdaemonserverrs)
  - [4. Daemon Process Management (`src/daemon/process.rs`)](#4-daemon-process-management-srcdaemonprocessrs)
  - [5. Pairing & Network Engine (`src/pairing/`)](#5-pairing--network-engine-srcpairing)
  - [6. Storage & State Persistence (`src/storage.rs`)](#6-storage--state-persistence-srcstoragers)
  - [7. Device Management & Models (`src/device/`)](#7-device-management--models-srcdevice)
- [Daemon HTTP API Endpoint Reference](#-daemon-http-api-endpoint-reference)
- [Building & Installation](#-building--installation)
- [Configuration & File Locations](#-configuration--file-locations)

---

## 🏛 Architecture & Modules

```
linux-companion/src/
├── main.rs                 # CLI entry point, tracing & tokio initialization
├── lib.rs                  # Library crate root & module declarations
├── storage.rs              # File system persistence (JSON config, logs, transfers)
├── cli/
│   ├── mod.rs              # CLI module exports
│   ├── args.rs             # Clap CLI argument & command schemas
│   ├── runner.rs           # Subcommand execution router & dispatch
│   ├── shell.rs            # Interactive Android storage terminal shell
│   └── ui.rs               # Terminal UI, tables, banners & formatting
├── daemon/
│   ├── mod.rs              # Daemon module exports
│   ├── process.rs          # Background daemon process spawning & lifecycle
│   └── server.rs           # Axum HTTP/TCP daemon & live clipboard monitor
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

## 🔍 Comprehensive Function & Module Reference

### 1. CLI Engine (`src/cli/`)

#### [`src/cli/args.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/cli/args.rs)
Defines command-line parsing using `clap` (Derive API):
- `struct Cli`: Global CLI options including `--debug` / `-d` for verbose logging.
- `enum Commands`:
  - `Pair { host, port, foreground }`: Starts pairing server.
  - `Status`: Shows active link and device details.
  - `Devices { current, past, remove }`: Lists or deletes paired devices.
  - `Stop { device }`: Stops the running daemon.
  - `Shell { device }`: Opens interactive terminal shell with Android.
  - `Logs { lines, follow }`: Inspects companion background logs.
  - `Clipboard { text }`: Gets or sets shared clipboard.
  - `Files`: Lists transfers folder contents.
  - `Daemon { ... }`: Hidden command used by `process.rs` to spawn detached daemon.

#### [`src/cli/runner.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/cli/runner.rs)
Primary subcommand router and executor:
- `pub async fn run_cli(cli: Cli)`: Entry router matching subcommands.
- `async fn run_pair(host: String, port: u16, foreground: bool)`:
  - Resolves local LAN IP via `get_local_ip()`.
  - Generates secure session token and session ID (`uuid::Uuid::new_v4()`).
  - Launches ephemeral pairing server (`run_pairing_server`).
  - Upon device handshake, detaches background daemon process (unless `--foreground`).
- `async fn run_status()`: Queries running daemon `/status` endpoint or loads `session.json`, displaying uptime, device name, and socket addresses.
- `fn run_devices(current: bool, past: bool, remove: Option<String>)`: Loads `devices.json`, formats tabular device history, or removes records.
- `async fn run_stop(device: Option<String>)`: Sends `/pair/unlink` HTTP request to daemon; falls back to terminating background process PID.
- `fn run_logs(lines: usize, follow: bool)`: Reads `linlink.log`. If `follow` is set, dynamically tails new output.

#### [`src/cli/ui.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/cli/ui.rs)
Terminal formatting and visual indicators:
- `print_banner()`: Displays ASCII LinLink banner.
- `print_success(msg)`, `print_warning(msg)`, `print_error(msg)`, `print_info(msg)`: Colored status outputs.
- `format_table(...)`: Helper to align and print tabular data cleanly.

---

### 2. Interactive Shell REPL (`src/cli/shell.rs`)

Launches a terminal environment directly connected to the Android device's storage agent:

- `pub async fn run_shell(device_filter: Option<String>)`: Main REPL loop reading user commands, tracking `current_dir` (defaults to `/storage/emulated/0`), and maintaining command prompt `📱 <Device> [<Path>] >`.
- `async fn handle_ls(client, base_url, token, target_path)`: Requests `/fs/list` from Android, parsing JSON entries and formatting directories and files with size and modification date.
- `async fn verify_dir(client, base_url, token, path) -> bool`: Verifies directory exists on Android before updating shell working directory.
- `async fn handle_get(client, base_url, token, remote_path, local_dest)`: Streams file from Android (`/fs/download`) to Linux disk (`~/Downloads/LinLink/` or specified path).
- `async fn handle_put(client, base_url, token, local_path, remote_dir, remote_filename)`: Reads local file and streams bytes to Android (`/fs/upload`).
- `async fn handle_cat(client, base_url, token, remote_path)`: Fetches remote file (`/fs/download`) and prints UTF-8 lines directly in the Linux terminal.
- `async fn handle_mkdir(client, base_url, token, path)`: Sends directory creation request to Android (`/fs/mkdir`).
- `async fn handle_rm(client, base_url, token, path)`: Sends deletion request to Android (`/fs/delete`).
- `fn resolve_path(current, target) -> String`: Resolves relative paths (`..`, subfolders, `~`, `@`) into absolute Android storage paths.
- `fn normalize_path(path) -> String`: Cleans up redundant slashes and handles parent directory segments (`/../`).
- `fn format_bytes(bytes: u64) -> String`: Formats raw bytes into human-readable B, KB, MB, GB.
- `mod reqwest_compat`: Lightweight asynchronous HTTP 1.1 client implemented with raw `tokio::net::TcpStream` to avoid heavy external HTTP client dependencies.
  - `Client::get(url)`, `Client::post(url)`
  - `RequestBuilder::body(vec)`
  - `RequestBuilder::send()`: Handles TCP connect, HTTP headers, chunked transfer-encoding decoding, and timeouts.

---

### 3. Background Daemon Server (`src/daemon/server.rs`)

The background Axum server providing TCP endpoints for the Android mobile app:

#### Core Lifecycle & State
- `struct DaemonServerState`:
  - `session_id: String`: Active session UUID.
  - `host: String`, `port: u16`: Listening network parameters.
  - `token: String`: Authentication token.
  - `device_name: String`: Connected device friendly name.
  - `shutdown_tx: mpsc::Sender<()>`: Graceful shutdown signal channel.
  - `last_synced_clipboard: Arc<Mutex<String>>`: Tracks last synchronized clipboard text to prevent echo loops.
  - `client_ip: Arc<Mutex<Option<String>>>`: Android device IP address (dynamically updated from connection info).
  - `agent_port: Arc<Mutex<Option<u16>>>`: Android file agent TCP port (registered dynamically).
- `pub async fn run_daemon_server(...)`:
  - Binds TCP listener (`0.0.0.0:<port>`).
  - Sets up routes and max body limit (10 GB for large file uploads).
  - Spawns the asynchronous `clipboard_worker`.
  - Installs UNIX signal handlers for `SIGTERM` and `SIGINT`.
  - Cleans up `session.json` and records disconnect upon exit.

#### Clipboard Synchronization Engine
- `pub fn read_system_clipboard() -> Option<String>`:
  - **Wayland**: Executes `wl-paste -n` to capture text from the Wayland compositor.
  - **X11**: Falls back to `xclip -selection clipboard -o` or `xsel --clipboard --output`.
- `pub fn copy_to_system_clipboard(text: &str)`:
  - **Wayland**: Pipes text to `wl-copy` via standard input.
  - **X11**: Pipes text to `xclip -selection clipboard`.
- `pub async fn push_clipboard_to_android(ip, port, token, text) -> Result<(), String>`:
  - Opens direct TCP connection to the Android phone's `AndroidFileAgent` (`POST /fs/clipboard`).
  - Delivers new clipboard text immediately with timeout protection.
- `clipboard_worker`:
  - Runs in a background Tokio task ticking every 800ms.
  - Checks `read_system_clipboard()`. When new text is detected, updates `last_synced_clipboard`, persists to disk, and triggers `push_clipboard_to_android`.

#### HTTP Handler Functions
- `handle_status(State)`: Returns JSON `DaemonStatusResponse`.
- `handle_ping()`: Returns `{"status": "pong"}`.
- `handle_device_register(State, ConnectInfo, Json)`: Receives Android's `agent_port` and records client IP.
- `handle_get_clipboard(State, ConnectInfo)`: Serves Linux clipboard text to Android (syncs with fresh system clipboard).
- `handle_post_clipboard(State, ConnectInfo, Json)`: Receives clipboard text from Android, updates Linux system clipboard, and prevents loopback.
- `handle_list_files()`: Lists received files in `~/Downloads/LinLink/`.
- `handle_file_upload(State, Json)`: Saves single note or text upload.
- `handle_fs_list(State, Json)`: Lists Linux filesystem entries for Android remote file browser.
- `handle_fs_download(State, Query)`: Streams Linux file to Android over TCP with `Content-Disposition`.
- `handle_fs_upload(State, Query, Bytes)`: Receives streamed file upload from Android and writes to Linux directory.
- `handle_unlink(State, Json)`: Sends shutdown signal to daemon server.

---

### 4. Daemon Process Management (`src/daemon/process.rs`)

Handles detaching the daemon into an independent operating system background process:
- `pub fn spawn_daemon_process(host, port, token, session_id, device_name, client_ip) -> Result<u32, ...>`:
  - Spawns current executable with hidden `daemon` subcommand.
  - Redirects standard output and error to `~/.config/linlink/linlink.log`.
  - Detaches process so it outlives the pairing CLI command.
- `pub fn stop_daemon_process(pid: u32) -> bool`:
  - Sends `SIGTERM` (15) to PID; verifies termination using `/proc/<pid>`.

---

### 5. Pairing & Network Engine (`src/pairing/`)

- [`src/pairing/network.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/pairing/network.rs):
  - `pub fn get_local_ip() -> Option<String>`: Iterates local network interfaces using UDP socket discovery to find active LAN IPv4 address (e.g. `192.168.x.x`).
- [`src/pairing/qr.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/pairing/qr.rs):
  - `pub fn generate_qr_string(payload: &str) -> Result<String, ...>`: Encodes pairing URL payload (`linlink://pair?host=...&port=...&token=...`) into terminal ANSI block characters (`█`, `▀`, `▄`).
  - `pub fn print_qr_code(payload: &str)`: Renders formatted QR code in terminal with border and instructions.
- [`src/pairing/server.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/pairing/server.rs):
  - `pub async fn run_pairing_server(...)`: Runs ephemeral Axum HTTP server on port 7878 while user scans the QR code.
  - `handle_pair_request(...)`: Handles `POST /pair` from Android app, validates pairing token, and registers device name.

---

### 6. Storage & State Persistence (`src/storage.rs`)

Provides path resolution, JSON serialization, and filesystem persistence:

- `Storage::config_dir() -> PathBuf`: Resolves `~/.config/linlink` (or `$LINLINK_CONFIG_DIR`).
- `Storage::log_file() -> PathBuf`: Path to `linlink.log`.
- `Storage::devices_file() -> PathBuf`: Path to `devices.json`.
- `Storage::session_file() -> PathBuf`: Path to `session.json`.
- `Storage::clipboard_file() -> PathBuf`: Path to `clipboard.txt`.
- `Storage::transfers_dir() -> PathBuf`: Path to `~/Downloads/LinLink/`.
- `Storage::load_devices() -> Vec<PairedDevice>`: Reads paired devices list.
- `Storage::save_device(PairedDevice)`: Upserts device into registry.
- `Storage::record_device_connected(name, token, ip)`: Updates `last_seen` timestamp and IP.
- `Storage::record_device_disconnected(name_or_token)`: Updates `disconnected_at` timestamp.
- `Storage::remove_device(id_or_name) -> bool`: Deletes device from registry.
- `Storage::save_session(&ActiveSession)`, `load_session()`, `clear_session()`: Session persistence.
- `Storage::save_clipboard(text)`, `load_clipboard()`: Persists clipboard snapshot.
- `Storage::is_pid_alive(pid) -> bool`: Inspects `/proc/<pid>/status` ensuring process is not Zombie (`Z`) or Dead (`X`).
- `Storage::find_running_daemon_pids() -> Vec<u32>`: Scans `/proc` for existing `linlink daemon` processes.
- `pub fn current_timestamp() -> String`: UTC formatted timestamp string (`YYYY-MM-DD HH:MM:SS UTC`).

---

### 7. Device Management & Models (`src/device/`)

- [`src/device/model.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/device/model.rs):
  - `struct PairedDevice`: `{ id, name, token, paired_at, last_seen, disconnected_at, ip }`.
  - `struct ActiveSession`: `{ pid, host, port, token, state, device_name, client_ip, agent_port, started_at }`.
  - `struct ConnectedDeviceInfo`: DTO returned by `DeviceManager`.
- [`src/device/manager.rs`](file:///home/bart-simpson/StudioProjects/linlink/linux-companion/src/device/manager.rs):
  - `DeviceManager::get_current_device() -> Option<ConnectedDeviceInfo>`: Validates PID liveness and returns active linked device.
  - `DeviceManager::get_all_devices() -> Vec<ConnectedDeviceInfo>`: Combines active session with historical devices list.

---

## 🌐 Daemon HTTP API Endpoint Reference

All endpoints requiring authentication expect the token either in query parameters (`?token=...`), request body (`{"token": "..."}`), or `x-session-token` header.

| Endpoint | Method | Payload / Query | Description |
| :--- | :--- | :--- | :--- |
| `/status` | `GET` | None | Returns JSON server state, host, port, and connected device name. |
| `/ping` | `GET` | None | Health check returning `{"status": "pong"}`. |
| `/clipboard` | `GET` | None | Returns latest clipboard content from Linux system. |
| `/clipboard` | `POST` | `{"token": "...", "text": "..."}` | Sets Linux system clipboard (`wl-copy`/`xclip`). |
| `/api/device/register` | `POST` | `{"token": "...", "agent_port": 7879}` | Android registers its TCP file agent port. |
| `/api/fs/list` | `POST` | `{"token": "...", "path": "/home/user"}` | Lists directory contents on Linux for Android. |
| `/api/fs/download` | `GET` | `?token=...&path=/path/to/file` | Streams file from Linux to Android. |
| `/api/fs/upload` | `POST` | `?token=...&dest_dir=...&filename=...` | Streams uploaded bytes from Android to Linux disk. |
| `/files` | `GET` | None | Lists files in `~/Downloads/LinLink/`. |
| `/files/upload` | `POST` | `{"token": "...", "filename": "...", "content": "..."}` | Simple file/note upload. |
| `/pair/unlink` | `POST` | `{"token": "..."}` | Requests daemon shutdown and unlinks device. |

---

## 🔨 Building & Installation

```bash
# Debug build
cargo build

# Optimized release binary
cargo build --release

# Install globally
sudo cp target/release/linlink /usr/local/bin/
```

Verify installation:
```bash
linlink --version
linlink --help
```

---

## 📂 Configuration & File Locations

- **Log File**: `~/.config/linlink/linlink.log`
- **Active Session**: `~/.config/linlink/session.json`
- **Device Registry**: `~/.config/linlink/devices.json`
- **Shared Clipboard Cache**: `~/.config/linlink/clipboard.txt`
- **Received Transfers Folder**: `~/Downloads/LinLink/`
