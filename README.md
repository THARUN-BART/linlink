# LinLink 🔗📱💻

> **Seamless, Fast, and Secure Companion Bridge between Android and Linux.**

LinLink connects your Android smartphone and Linux computer over your local network (LAN / Wi-Fi) with zero cloud dependency. Pair in seconds using a terminal QR code, synchronize your clipboard in real-time both ways, transfer files seamlessly with the Android File Manager, browse Linux files from your phone, and explore your phone's storage through an interactive Linux terminal shell.

---

## 📑 Table of Contents

- [Overview & Architecture](#-overview--architecture)
- [📱 Flutter Screens Available](#-flutter-screens-available)
- [🔄 How Flutter Connects to Linux](#-how-flutter-connects-to-linux)
- [✨ Key Features Available](#-key-features-available)
  - [1. Real-Time Bidirectional Clipboard Sync](#1-real-time-bidirectional-clipboard-sync)
  - [2. Mobile to Linux File Upload](#2-mobile-to-linux-file-upload)
  - [3. Linux to Mobile Remote File Browser](#3-linux-to-mobile-remote-file-browser)
  - [4. Interactive Linux Shell (`linlink shell`)](#4-interactive-linux-shell-linlink-shell)
  - [5. Zero-Config QR Code Pairing](#5-zero-config-qr-code-pairing)
  - [6. Background Daemon & Session Management](#6-background-daemon--session-management)
- [🐧 Rust Linux Companion Reference](#-rust-linux-companion-reference)
- [Prerequisites](#-prerequisites)
- [Quickstart Guide](#-quickstart-guide)
- [CLI Reference Manual](#-cli-reference-manual)
- [Interactive Shell Command Reference](#-interactive-shell-command-reference)
- [File Storage Locations](#-file-storage-locations)
- [Project Directory Structure](#-project-directory-structure)

---

## 🏛 Overview & Architecture

LinLink consists of two synchronized components operating over high-performance local TCP:

```
┌────────────────────────────────────────────────────────┐
│                   Android Device                       │
│  • Flutter UI & Permissions Handler                    │
│  • AndroidFileAgent (HTTP/TCP Server on Port 7879)     │
│  • Native File Manager Picker (SAF) + Storage Fallback │
│  • Continuous Live Clipboard Service                   │
└────────────────────────▲───────────────────────────────┘
                         │
                    Local Wi-Fi / TCP
                         │
┌────────────────────────▼───────────────────────────────┐
│                   Linux Machine                        │
│  • Linux Companion CLI (`linlink`)                     │
│  • Background Daemon Server (Axum, Port 7878)          │
│  • Wayland / X11 System Clipboard Engine               │
│  • Interactive Terminal Shell Client                   │
└────────────────────────────────────────────────────────┘
```

---

## 📱 Flutter Screens Available

The Flutter application provides clean, responsive Material 3 screens designed for zero-latency device pairing, real-time sync, and remote file exploration:

### 1. `HomeScreen` ([`lib/features/home/home_screen.dart`](file:///home/bart-simpson/StudioProjects/linlink/lib/features/home/home_screen.dart))
The main central dashboard of the app. It dynamically shifts between **Unpaired State** and **Linked State**:

* **When Unpaired**:
  * **Pairing CTA**: Large primary button to open the QR camera scanner.
  * **Storage Permissions Card**: Checks and requests Android storage permissions (including Android 11+ All Files Access / Scoped Storage permissions).
  * **Onboarding Guide**: Step-by-step visual instructions explaining how to run `linlink pair` in Linux.
* **When Linked / Paired**:
  * **Active Device Status Card**: Displays the connected Linux machine name, base URL (`http://<host>:<port>`), ping response time, and an **Unlink** button.
  * **Shared Clipboard Card**:
    * **Live Sync Status Badge**: Displays `Live Sync ON` (pulsing green) or `Paused`.
    * **Continuous Auto-Sync Switch**: Interactive toggle to pause or resume real-time background sync without unlinking.
    * **Monospace Preview**: Live preview box showing the latest synchronized clipboard text.
    * **Manual Actions**: "Send to Linux" and "Get from Linux" buttons for immediate one-off transfers.
  * **Remote File Explorer Card**: Launches the `RemoteFileBrowserScreen` over TCP.
  * **Quick Actions**: "Send Note to Linux" button and "Storage Access" configuration.

### 2. `ScannerScreen` ([`lib/features/scanner/views/scanner_screen.dart`](file:///home/bart-simpson/StudioProjects/linlink/lib/features/scanner/views/scanner_screen.dart))
High-speed camera scanner using `mobile_scanner` and BLoC state management (`CameraBloc`):
* **Custom Scanner Overlay**: Animated corner-focused targeting reticle for fast QR capture.
* **Flash / Torch Toggle**: Allows scanning in low-light terminal setups.
* **Instant Handshake**: Parses the `linlink://pair?host=...&port=...&token=...` deep-link format, contacts the Linux pairing server, verifies tokens, and pops back to `HomeScreen` with a verified `PairedCompanion` model.

### 3. `RemoteFileBrowserScreen` ([`lib/features/storage/remote_file_browser_screen.dart`](file:///home/bart-simpson/StudioProjects/linlink/lib/features/storage/remote_file_browser_screen.dart))
Interactive remote filesystem explorer allowing Android to navigate and download files stored on Linux:
* **Current Path Breadcrumbs**: Displays current working path with a parent directory navigation button (`..`).
* **Directory Shortcuts**: Quick navigation chips to jump to `Home (~)` or `Transfers`.
* **File & Directory List**: Visual icons (folders, documents, media), formatted file sizes (B, KB, MB, GB), and modified dates.
* **One-Tap Download**: Tapping any remote file streams it from Linux directly into `/storage/emulated/0/Download/LinLink/`.
* **Floating Action Button ("Upload to Linux")**:
  * Directly launches the native Android Document Picker (`FilePicker.pickFiles`).
  * Supports picking single or multiple files (images, videos, documents, archives).
  * Streams picked files over TCP into the currently open Linux folder with real-time SnackBar progress.
* **In-App Device Storage Browser Modal (`_showLocalDeviceFilePicker`)**:
  * Automatically serves as an in-app fallback if the system document picker is unavailable.
  * Interactive modal bottom sheet allowing folder-by-folder navigation of phone storage (`/storage/emulated/0/Download`, `DCIM`, `Documents`, etc.) to select and upload any local file.
* **Text Note Creator Dialog (`_showCreateNoteDialog`)**:
  * Modal dialog accessible via the AppBar (`note_add_outlined`) to draft custom text notes and save them directly on Linux.

---

## 🔄 How Flutter Connects to Linux

The connection protocol operates completely over your local network using token-authenticated HTTP/TCP:

```
Android (Flutter)                                    Linux Host (`linlink`)
       │                                                       │
       │ 1. Scan ANSI QR Code (`linlink://pair?...`)           │
       │──────────────────────────────────────────────────────>│ (CLI renders QR)
       │                                                       │
       │ 2. POST /pair (token, device_name)                    │
       │──────────────────────────────────────────────────────>│ (Pairing Server: port 7878)
       │                                                       │
       │ 3. 200 OK (session_id, token, companion_info)         │
       │<──────────────────────────────────────────────────────│ (Spawns detached Daemon)
       │                                                       │
       │ 4. Start AndroidFileAgent (TCP Port 7879)             │
       │    (Listens on 0.0.0.0:7879)                          │
       │                                                       │
       │ 5. POST /api/device/register (token, agent_port:7879) │
       │──────────────────────────────────────────────────────>│ (Daemon records phone IP)
       │                                                       │
       │ 6. Start Live Clipboard Auto-Sync                     │
       │    • Android polls /clipboard & listens /fs/clipboard │
       │    • Linux monitors wl-paste/xclip & pushes changes   │
       │<─────────────────────────────────────────────────────>│
       │                                                       │
       │ 7. File Operations & Interactive Terminal Shell       │
       │    • Phone browses Linux: POST /api/fs/list           │
       │    • Phone uploads:       POST /api/fs/upload         │
       │    • Linux shell (`linlink shell`) queries Phone:     │
       │      GET/POST http://<phone_ip>:7879/fs/*             │
       │<─────────────────────────────────────────────────────>│
```

### Detailed Connection Phases:

1. **Discovery & Payload Parsing**:
   - The user runs `linlink pair` on Linux. The Rust companion discovers its local IPv4 address (e.g. `192.168.1.50`), generates a secure UUID token, and prints an ANSI QR code encoding:
     `linlink://pair?host=192.168.1.50&port=7878&token=UUID_V4`
   - In Flutter, `ScannerScreen` scans the QR code and parses the host, port, and token.

2. **Pairing Handshake**:
   - Flutter sends `POST http://192.168.1.50:7878/pair` containing the token and the Android device name.
   - The pairing server validates the token, stores the device in `devices.json`, and detaches the background daemon on port 7878.

3. **Android TCP File Agent Activation**:
   - Immediately upon pairing, Flutter starts [`AndroidFileAgent`](file:///home/bart-simpson/StudioProjects/linlink/lib/features/storage/file_agent.dart) (`HttpServer.bind(InternetAddress.anyIPv4, 7879)`).
   - Android then calls `POST http://192.168.1.50:7878/api/device/register` with `{"agent_port": 7879}`.
   - The Linux daemon detects the incoming socket connection, learns the Android device's IP, and records both IP and port.

4. **Continuous Live Clipboard Sync Activation**:
   - Flutter calls [`ClipboardService.startAutoSync()`](file:///home/bart-simpson/StudioProjects/linlink/lib/features/clipboard/clipboard_service.dart#L17).
   - **Linux to Android**: The Linux daemon's background task monitors `wl-paste` (Wayland) / `xclip` (X11). When new text is copied on Linux, it immediately makes an HTTP `POST http://<android_ip>:7879/fs/clipboard` to push text straight to Android's clipboard.
   - **Android to Linux**: A periodic 1.2-second check and `WidgetsBindingObserver` resume listener detect when the user copies text on Android, immediately posting to `POST http://<linux_ip>:7878/clipboard`.

5. **Bidirectional File Streaming**:
   - Android uploads files to Linux via `POST /api/fs/upload?dest_dir=...&filename=...`.
   - Android downloads files from Linux via `GET /api/fs/download?path=...`.
   - Linux reads or pulls files from Android via the `linlink shell` sending commands to `http://<android_ip>:7879/fs/list`, `/fs/download`, and `/fs/upload`.

6. **Termination / Unlink**:
   - Tapping **Unlink** in the app or running `linlink stop` on Linux calls `/pair/unlink`, terminates background tasks, stops `AndroidFileAgent`, cancels timers, and clears session files cleanly.

---

## ✨ Key Features Available

### 1. Real-Time Bidirectional Clipboard Sync
- **Continuous Background Synchronization**: While connected, copying text on Linux immediately pushes to Android's clipboard, and copying text on Android immediately updates Linux's system clipboard.
- **Wayland & X11 Native Integration**: Automatically detects and uses `wl-copy` / `wl-paste` on Wayland or `xclip` / `xsel` on X11.
- **No Echo Loops**: Intelligent deduplication ensures updates are only propagated when content genuinely changes.
- **App Lifecycle Awareness**: Automatically pulls the latest clipboard state when the Android app resumes from background.
- **Live Sync Controls**: Live indicator badge and toggle switch on `HomeScreen`.

### 2. Mobile to Linux File Upload
- **Native Android File Manager (SAF)**: Tap **"Upload to Linux"** to pick any file or multiple files via system document picker.
- **In-App Device Storage Browser Fallback**: Built-in fallback browser (`_showLocalDeviceFilePicker`) for direct `/storage/emulated/0` navigation.
- **Live Streaming Transfer**: Files are streamed directly into the destination directory on Linux over TCP with progress feedback.
- **Quick Text Notes**: Create `.txt` notes directly from Android into Linux.

### 3. Linux to Mobile Remote File Browser
- **Browse Linux Files from Phone**: Explore your Linux filesystem hierarchy directly from the Android app.
- **One-Tap Download**: Download remote files directly onto your Android device under `/storage/emulated/0/Download/LinLink/`.

### 4. Interactive Linux Shell (`linlink shell`)
Run `linlink shell` on Linux to launch an interactive terminal console directly connected to your Android phone's storage:
- `ls` / `dir`, `cd`, `pwd`, `cat` / `view`, `get`, `put`, `mkdir`, `rm`, `clip`.

### 5. Zero-Config QR Code Pairing
- Terminal ANSI QR code generated with dynamic LAN IP detection.
- Fast, secure pairing handshake in under a second.

### 6. Background Daemon & Session Management
- Detached background daemon process with graceful signal handling (`SIGINT`, `SIGTERM`), lockfile management, and automatic disconnect cleanup.

---

## 🐧 Rust Linux Companion Reference

For detailed documentation on all Rust modules, functions, background daemon internals, and CLI architecture, please consult the dedicated companion documentation:

👉 **[Read the Linux Companion Rust Documentation (`linux-companion/README.md`)](linux-companion/README.md)**

---

## 📋 Prerequisites

### Linux Host
1. **Rust Toolchain**: `cargo` and `rustc` (1.80+).
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```
2. **Clipboard Utility**:
   - For **Wayland**: `sudo apt install wl-clipboard` (or `dnf install wl-clipboard` / `pacman -S wl-clipboard`)
   - For **X11**: `sudo apt install xclip xsel`

### Android Device / Development
1. **Flutter SDK**: 3.24+ installed and on your `PATH`.
2. **Android Device**: Android 8.0+ connected to the same local Wi-Fi / LAN network.
3. **Permissions**: Camera (for QR scanner) and Storage (for file browsing).

---

## 🚀 Quickstart Guide

### A. Build & Run the Linux Companion

```bash
cd linux-companion
cargo build --release
sudo cp target/release/linlink /usr/local/bin/   # (Optional) install globally
linlink pair
```
*An ANSI QR code will appear in your terminal.*

### B. Run the Android App

```bash
flutter run
```

### C. Connect & Pair

1. Open **LinLink** on Android.
2. Tap **"Scan QR Code to Link"**.
3. Scan the QR code shown in your Linux terminal.
4. Once paired:
   - Copy text on either device $\rightarrow$ immediately paste on the other!
   - Tap **"Explore Linux Files"** to browse or upload files from mobile.
   - On Linux, type `linlink shell` to browse your phone.

---

## 🛠 CLI Reference Manual

| Command | Description | Example |
| :--- | :--- | :--- |
| `linlink pair` | Start pairing server and render QR code. | `linlink pair` |
| `linlink pair --foreground` | Keep running in foreground (for debugging). | `linlink pair -f` |
| `linlink pair --host <IP>` | Specify an explicit IP address for the QR code. | `linlink pair --host 192.168.1.50` |
| `linlink status` | Show active connection state, device name, IP, and port. | `linlink status` |
| `linlink shell` | Open the interactive terminal shell with Android. | `linlink shell` |
| `linlink clipboard [TEXT]` | View current shared clipboard or broadcast a new string. | `linlink clipboard "Hello from CLI"` |
| `linlink files` | List files received in the LinLink transfers folder. | `linlink files` |
| `linlink devices` | List active and past connected devices. | `linlink devices` |
| `linlink devices --remove <ID>` | Remove a device from paired devices history. | `linlink devices --remove "Pixel 8"` |
| `linlink logs -f` | Follow background daemon logs live (like `tail -f`). | `linlink logs -f` |
| `linlink stop` | Stop the active LinLink daemon session cleanly. | `linlink stop` |

---

## 💻 Interactive Shell Command Reference

Inside `linlink shell`:

| Shell Command | Parameters | Description | Example |
| :--- | :--- | :--- | :--- |
| `ls` / `dir` | `[path]` | List files and directories on Android. | `ls Download` |
| `cd` | `[directory]` | Change working directory on Android. | `cd DCIM/Camera` |
| `pwd` | None | Print current remote directory path. | `pwd` |
| `cat` / `view` | `<filename>` | Display text file contents in terminal. | `cat notes.txt` |
| `get` / `download` | `<remote_file> [local_dest]` | Download file from Android to Linux (`~/Downloads/LinLink/`). | `get photo.jpg` |
| `put` / `upload` | `<local_file> [remote_name]` | Upload file from Linux to Android folder. | `put ~/doc.pdf` |
| `mkdir` | `<folder_name>` | Create a new directory on Android. | `mkdir ProjectFiles` |
| `rm` / `del` | `<path>` | Delete a file or directory on Android. | `rm old_backup.zip` |
| `clip` | `[text]` | View or set shared clipboard from the shell. | `clip New link copied` |
| `exit` / `quit` / `q` | None | Exit the interactive terminal shell. | `exit` |

---

## 📁 File Storage Locations

| Platform | Purpose | Default Path |
| :--- | :--- | :--- |
| **Linux** | Incoming File Transfers | `~/Downloads/LinLink/` |
| **Linux** | Configuration & Sessions | `~/.config/linlink/session.json` |
| **Linux** | Paired Device Registry | `~/.config/linlink/devices.json` |
| **Linux** | Companion Daemon Logs | `~/.config/linlink/linlink.log` |
| **Android** | Downloaded Linux Files | `/storage/emulated/0/Download/LinLink/` |

---

## 📂 Project Directory Structure

```
linlink/
├── android/                         # Android native project & Gradle build configuration
├── lib/                             # Flutter frontend source code
│   ├── features/
│   │   ├── clipboard/
│   │   │   └── clipboard_service.dart   # Continuous live clipboard sync engine
│   │   ├── home/
│   │   │   └── home_screen.dart         # Main dashboard, live sync card & actions
│   │   ├── pairing/
│   │   │   └── pairing_service.dart     # QR verification & connection handshake
│   │   ├── scanner/
│   │   │   └── views/scanner_screen.dart# Mobile scanner for terminal QR codes
│   │   └── storage/
│   │       ├── file_agent.dart          # Android TCP file server & clipboard push endpoint
│   │       ├── remote_file_browser_screen.dart # Linux remote browser & file picker upload
│   │       └── storage_service.dart     # Storage permissions & file utilities
│   └── main.dart                    # Application entry point & plugin initialization
├── linux-companion/                 # Rust Linux Companion CLI & Daemon
│   ├── README.md                    # Dedicated Rust Companion documentation
│   ├── Cargo.toml                   # Rust dependencies
│   └── src/
│       ├── cli/                     # CLI args, command runner, interactive shell REPL
│       ├── daemon/                  # Background process management & Axum server
│       ├── device/                  # Device registry and session models
│       ├── pairing/                 # IP discovery, QR renderer & pairing server
│       └── storage.rs               # Persistence & filesystem paths
├── pubspec.yaml                     # Flutter dependencies
└── README.md                        # Primary project documentation
```

---

## 🔒 Security & Privacy

- **Local Network Only**: All communication occurs strictly over your local Wi-Fi / LAN. No telemetry, third-party relays, or external cloud servers are involved.
- **Tokenized Sessions**: Every pairing session generates a cryptographically random UUID token (`v4`). All subsequent API endpoints, file operations, and clipboard streams require token authentication.
- **Unlink Anytime**: Disconnecting from either the Android app or running `linlink stop` immediately terminates active daemon tasks and closes ports.

---

## 📄 License

This project is licensed under the MIT License.
