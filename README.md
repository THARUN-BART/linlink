<p align="center">
  <img src="assets/icon.png" alt="LinLink Logo" width="120" />
</p>

# LinLink 🔗📱💻

> **Seamless, Fast, and Secure Companion Bridge between Android and Linux (and Phone-to-Phone).**

LinLink connects your Android smartphones and Linux computers over your local network (LAN / Wi-Fi / Hotspot) with **zero cloud dependency** and **zero internet usage**. Pair in seconds using a terminal QR code, synchronize your clipboard in real-time both ways, transfer files seamlessly with sender-first QR pairing, browse Linux files from your phone, and explore your phone's storage through an interactive Linux terminal shell.

---

## 📑 Table of Contents

- [🏛 Architecture Overview](#-architecture-overview) ([Full Document](ARCHITECTURE.md))
  - [📱 Mobile Architecture & Flutter Engine](#-mobile-architecture--flutter-engine)
  - [🐧 Linux Companion Architecture](#-linux-companion-architecture)
  - [🔄 How Mobile Connects to Linux & Peers](#-how-mobile-connects-to-linux--peers)
- [📥 Installation Guide](#-installation-guide) ([Full Document](INSTALL.md))
  - [🐧 Linux Installation (One-Liner / Script)](#-linux-installation)
  - [📱 Android Installation](#-android-installation)
  - [🛠 Building from Source](#-building-from-source)
- [✨ Key Features & Capabilities](#-key-features--capabilities)
- [🛠 CLI & Shell Reference Manual](#-cli--shell-reference-manual)
- [📁 File Storage Locations](#-file-storage-locations)
- [📂 Project Directory Structure](#-project-directory-structure)
- [🔒 Security & Privacy](#-security--privacy)
- [🤝 Contribution Guide](#-contribution-guide) ([Full Document](CONTRIBUTING.md))
- [📄 License](#-license)

---

## 🏛 Architecture Overview

LinLink consists of modular, zero-cloud components operating over high-performance local TCP:

```
┌────────────────────────────────────────────────────────┐
│                   Android Device                       │
│  • Flutter UI — Floating Glass Navigation Bar (M3)     │
│  • AndroidFileAgent (HTTP/TCP Server on Port 7879)     │
│  • Native SAF FilePicker + Storage Staging Pipeline    │
│  • Persistent Foreground Clipboard Sync Service        │
│  • Instant disconnect push (/fs/disconnect)            │
└────────────────────────▲───────────────────────────────┘
                         │
                    Local Wi-Fi / Hotspot LAN / TCP
                         │
┌────────────────────────▼───────────────────────────────┐
│                   Linux Machine                        │
│  • Linux Companion CLI (linlink) in Rust               │
│  • Background Axum Daemon (Port 7878)                  │
│  • Native Wayland / X11 System Clipboard Engine        │
│  • Interactive Terminal Shell Client (linlink shell)   │
│  • systemd User Service (auto-start on login)          │
└────────────────────────────────────────────────────────┘
```

---

### 📱 Mobile Architecture & Flutter Engine

The mobile client is built with Flutter and structured around decoupled, feature-driven modules:

- **Floating Glass UI Layer**:
  - `HomeScreen` ([`lib/features/home/home_screen.dart`](lib/features/home/home_screen.dart)) — Modern Material 3 dashboard with frosted glass floating navigation (`BackdropFilter` blur).
  - `PhoneSendDialog` ([`lib/features/pairing/views/phone_send_dialog.dart`](lib/features/pairing/views/phone_send_dialog.dart)) — Sender-first staging workflow: select files first, compute batch sizes, and render instant high-contrast QR codes.
  - `ScannerScreen` ([`lib/features/scanner/views/scanner_screen.dart`](lib/features/scanner/views/scanner_screen.dart)) — Dual-mode camera QR scanner using `mobile_scanner` + BLoC. Detects `mode=p2p` for batch file downloads or standard pairing payloads.
  - `RemoteFileBrowserScreen` ([`lib/features/storage/remote_file_browser_screen.dart`](lib/features/storage/remote_file_browser_screen.dart)) — Remote filesystem explorer with instant search and download streams.

- **Local Server Engine (`AndroidFileAgent`)**:
  - Embedded asynchronous HTTP/TCP server running on Android (Port `7879`).
  - Staged file queueing for sender-first P2P file downloads (`/p2p/files` & `/p2p/download`).
  - Automatic IP discovery prioritizing Wi-Fi (`wlan0`) and Mobile Hotspot (`ap0`) interfaces.
  - Strict Privacy Guard blocking remote folder inspection (`/fs/list`) with HTTP 403 Forbidden.

- **Background Services**:
  - Foreground notification service keeping clipboard synchronization active without battery-saver interruptions.

---

### 🐧 Linux Companion Architecture

The Linux host utility is written in high-performance, asynchronous Rust:

- **Axum Daemon Engine (`linux-companion/src/daemon/`)**:
  - Listens on TCP Port `7878` for device registration, file streaming, and health checks.
  - Token-authenticated session manager in `~/.config/linlink/session.json`.
- **System Clipboard Interop (`linux-companion/src/clipboard/`)**:
  - Zero-latency native bridge supporting Wayland (`wl-clipboard`) and X11 (`xclip`/`xsel`).
  - Loop prevention with SHA-256 state hashing.
- **Interactive Shell REPL (`linux-companion/src/cli/shell.rs`)**:
  - Interactive terminal environment to navigate, read (`cat`), upload (`put`), and download (`get`) Android files directly from the Linux terminal.

---

### 🔄 How Mobile Connects to Linux & Peers

```
Sender (Android / Linux)                        Receiver (Android / Linux)
       │                                                │
       │  1. Pick Files & Stage in Local Server         │
       │  2. Render QR (linlink://IP:Port?t=...&mode=..)│
       │                                                │
       │  3. Scan QR with Camera Scanner                │
       │<───────────────────────────────────────────────│
       │                                                │
       │  4. GET /p2p/files (List staged items)         │
       │<───────────────────────────────────────────────│
       │                                                │
       │  5. Stream Downloads (/p2p/download?index=N)  │
       │<───────────────────────────────────────────────│ All files transferred
       │                                                │ Saved in Downloads/LinLink
```

---

## 📥 Installation Guide

### 🐧 Linux Installation

#### Option 1: Quick Install via SourceForge Script (Recommended)

Run the following command in your Linux terminal:

```bash
curl -L -o install.sh "https://sourceforge.net/projects/linlink/files/install.sh/download"
chmod +x install.sh
./install.sh
```

*(Note: `chmod +x install.sh` or `chmod 777 install.sh` makes the installer executable).*

#### Option 2: Manual Binary Download

1. Download the latest Linux release tarball `linlink-linux-x86_64-v1.1.0.tar.gz` from [Releases](https://github.com/THARUN-BART/linlink/releases).
2. Extract and copy to your local bin:
   ```bash
   tar -xzf linlink-linux-x86_64-v1.1.0.tar.gz
   cd linlink-linux-x86_64
   mkdir -p ~/.local/bin
   cp linlink ~/.local/bin/
   ```
3. Ensure `~/.local/bin` is in your `PATH`.

---

### 📱 Android Installation

1. Download the latest `linlink-android-arm64-v8a-v1.1.0.apk` from [GitHub Releases](https://github.com/THARUN-BART/linlink/releases) or [SourceForge](https://sourceforge.net/projects/linlink/files/).
2. Open the `.apk` on your Android device to install.
3. Grant necessary permissions (Camera for QR scanning, Storage for file saving).

---

### 🛠 Building from Source

#### Prerequisites
- **Rust** 1.80+: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Flutter SDK** 3.24+
- **Clipboard utilities**:
  - Wayland: `sudo apt install wl-clipboard`
  - X11: `sudo apt install xclip xsel`

#### Build Linux Companion
```bash
git clone https://github.com/THARUN-BART/linlink.git
cd linlink/linux-companion
cargo build --release
cp target/release/linlink ~/.local/bin/
```

#### Build Android APK
```bash
cd linlink
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --split-per-abi
```

---

## ✨ Key Features & Capabilities

1. **📲 Sender-First Phone-to-Phone Direct Transfer**:
   - Pick files first on your phone → display QR code → receiver scans and downloads in batch.
   - 100% offline over Wi-Fi / Personal Hotspot with zero mobile data consumption.

2. **📋 Real-Time Bidirectional Clipboard Mirror**:
   - Copy on Linux → paste on Android. Copy on Android → paste on Linux.
   - Background service keeps synchronization alive with status notifications.

3. **💻 Interactive Linux Terminal Shell (`linlink shell`)**:
   - Terminal REPL connected directly to Android storage: `ls`, `cd`, `pwd`, `cat`, `get`, `put`, `mkdir`, `rm`, `clip`.

4. **🛡️ Strict Privacy Shield**:
   - Remote storage browsing is restricted by default during P2P transfers.

5. **⚙️ systemd User Service Integration**:
   - Enable auto-start daemon with `systemctl --user enable linlink`.

6. **🔌 Instant Disconnect Notification**:
   - `linlink stop` instantly notifies the Android app via `/fs/disconnect` to reset state immediately.

---

## 🛠 CLI & Shell Reference Manual

### Linux Host Commands

| Command | Description |
| :--- | :--- |
| `linlink pair` | Start pairing server and display QR code in terminal |
| `linlink pair --foreground` | Run pairing server in foreground for debugging |
| `linlink pair --host <IP>` | Specify custom LAN IP for the QR payload |
| `linlink status` | Show active connection, peer device name, IP, and port |
| `linlink shell` | Open interactive terminal shell with Android device |
| `linlink clipboard [TEXT]` | View or set shared system clipboard |
| `linlink files` | List files in the LinLink transfers directory |
| `linlink devices` | List active and previously paired devices |
| `linlink devices --remove <ID>` | Remove a device from paired history |
| `linlink logs -f` | Follow live daemon logs |
| `linlink stop` | Stop daemon and immediately notify Android to disconnect |

### Interactive Shell Commands (`linlink shell`)

| Command | Description |
| :--- | :--- |
| `ls [path]` | List files and folders on remote device |
| `cd [dir]` | Change remote working directory |
| `pwd` | Print current remote directory path |
| `cat <file>` | Print remote text file contents in terminal |
| `get <remote> [local]` | Download remote file to `~/Downloads/LinLink/` |
| `put <local> [name]` | Upload file from Linux to Android storage |
| `mkdir <folder>` | Create remote folder |
| `rm <path>` | Delete file or directory on remote storage |
| `clip [text]` | Read or update shared clipboard |
| `clear` / `cls` | Clear terminal screen |
| `exit` | Exit interactive shell |

---

## 📁 File Storage Locations

| Platform | Purpose | Path |
| :--- | :--- | :--- |
| Linux | Incoming transfers | `~/Downloads/LinLink/` |
| Linux | Session state | `~/.config/linlink/session.json` |
| Linux | Device registry | `~/.config/linlink/devices.json` |
| Linux | Daemon logs | `~/.config/linlink/linlink.log` |
| Linux | Shared clipboard cache | `~/.config/linlink/clipboard.txt` |
| Linux | systemd service | `~/.config/systemd/user/linlink.service` |
| Android | Downloaded files | `/storage/emulated/0/Download/LinLink/` |

---

## 📂 Project Directory Structure

```
linlink/
├── assets/
│   └── icon.png                          # App branding & UI icon
├── lib/
│   ├── features/
│   │   ├── clipboard/
│   │   │   ├── clipboard_service.dart    # Live clipboard sync engine
│   │   │   └── clipboard_view.dart       # Clipboard management UI
│   │   ├── home/
│   │   │   └── home_screen.dart          # M3 Dashboard + Glass Nav Bar
│   │   ├── pairing/
│   │   │   ├── pairing_service.dart      # TCP handshake & target parser
│   │   │   ├── pairing_success_screen.dart
│   │   │   └── views/phone_send_dialog.dart # Sender-first QR transfer dialog
│   │   ├── scanner/
│   │   │   └── views/scanner_screen.dart # QR scanner + P2P auto-downloader
│   │   ├── settings/settings_screen.dart
│   │   └── storage/
│   │       ├── file_agent.dart           # Local TCP HTTP server & P2P queues
│   │       ├── remote_file_browser_screen.dart
│   │       └── storage_service.dart
│   ├── theme/linlink_theme.dart          # Dark slate theme & tokens
│   └── main.dart
├── linux-companion/                      # Rust CLI & daemon engine
│   ├── Cargo.toml
│   ├── README.md
│   └── src/
│       ├── cli/                          # Shell REPL, args runner, UI formatting
│       ├── daemon/                       # Axum server, process manager
│       ├── device/                       # Device registry & models
│       ├── pairing/                      # QR generator, network IP detector
│       └── storage.rs
├── pubspec.yaml
└── README.md
```

---

## 🔒 Security & Privacy

- **100% Local-First Architecture** — No external servers, no cloud storage, and no tracking telemetry.
- **Dynamic Session Tokens** — Every transaction is authenticated with an ephemeral session token.
- **Privacy Shield by Default** — Remote filesystem listing is blocked during phone-to-phone transfers; only explicitly selected files can be downloaded.
- **Instant Unlink Handshake** — When shutting down, `linlink stop` dispatches an instant `/fs/disconnect` signal to clear state on all connected peers.

---

## 🤝 Contribution Guide

We welcome contributions from the community! Follow these steps to contribute to LinLink:

### 1. Fork & Clone the Repository
```bash
git clone https://github.com/THARUN-BART/linlink.git
cd linlink
```

### 2. Create a Feature Branch
```bash
git checkout -b feature/your-feature-name
```

### 3. Development Guidelines
- **Flutter**: Ensure code complies with analysis rules and tests pass:
  ```bash
  flutter pub get
  flutter analyze
  flutter test
  ```
- **Rust (Linux Companion)**: Format code, run clippy lints, and test:
  ```bash
  cd linux-companion
  cargo fmt --all -- --check
  cargo clippy --all-targets -- -D warnings
  cargo test
  ```

### 4. Commit Your Changes
Use concise conventional commit messages:
```bash
git commit -m "feat(module): add amazing feature description"
```

### 5. Push & Open a Pull Request
```bash
git push origin feature/your-feature-name
```
Open a Pull Request on GitHub with a clear summary of your changes.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
