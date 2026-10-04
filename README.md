<p align="center">
  <img src="assets/icon.png" alt="LinLink Logo" width="120" />
</p>

# LinLink v1.1.1 🔗📱💻

> **Seamless, Fast, and Secure Companion Bridge between Android and Linux (and Phone-to-Phone) with Zero Cloud Dependency.**

LinLink connects your Android smartphones and Linux computers over your local network (LAN / Wi-Fi / Hotspot) with **zero cloud dependency** and **zero internet usage**. Make remote phone calls using your PC's mic & speaker, download online updates automatically, pair in seconds with QR codes, synchronize your clipboard in real-time both ways, transfer files seamlessly with sender-first QR staging, browse Linux files from your phone, and explore your phone's storage through an interactive Linux terminal shell.

---

## 📑 Table of Contents

- [✨ What's New in v1.1.1](#-whats-new-in-v111)
- [🏛 Architecture Overview](#-architecture-overview) ([Full Architecture Document](ARCHITECTURE.md))
  - [📱 Mobile Architecture & Flutter Engine](#-mobile-architecture--flutter-engine)
  - [🐧 Linux Companion Architecture](#-linux-companion-architecture)
  - [🔄 How Mobile Connects to Linux & Peers](#-how-mobile-connects-to-linux--peers)
- [📥 Installation Guide](#-installation-guide) ([Full Install Guide](INSTALL.md))
  - [🐧 Linux Installation (One-Liner / Script)](#-linux-installation)
  - [📱 Android Installation](#-android-installation)
  - [🛠 Building from Source](#-building-from-source)
- [🚀 Supported Connections & Features Matrix](#-supported-connections--features-matrix)
- [🛠 CLI & Shell Reference Manual](#-cli--shell-reference-manual)
- [📁 File Storage Locations](#-file-storage-locations)
- [📂 Project Directory Structure](#-project-directory-structure)
- [🔒 Security & Privacy](#-security--privacy)
- [🤝 Contribution Guide](#-contribution-guide) ([Contributing Guide](CONTRIBUTING.md))
- [📄 License](#-license)

---

## ✨ What's New in v1.1.1

### 📞🎙️ Remote Calling & PC Audio Bridge (Call by Number)
Dial phone calls and speak directly through your Linux PC when your phone is across the room:
- **Dial by Number**: Trigger cellular phone calls on your Android phone straight from your Linux terminal (`linlink call <number>` or in-shell `dial <number>`) or mobile app.
- **PC Mic & Speaker Bridge**: Use your computer's microphone to talk and computer speakers/headphones to hear your calls with ultra-low latency.
- **Interactive Call TUI & Controls**: Live call duration timer, real-time VU audio meters for Mic and Speaker, and keyboard shortcuts (`[m]` mute, `[s]` speaker, `[q]`/`[h]` hang up).
- **In-App Call Interface**: Built `CallScreen` and `CallCard` UI with animated voice ripple waves and live equalizer meters.

### 🚀 Online Software Auto-Updater
Check for and download online updates directly from GitHub releases:
- **Linux Companion CLI**: Run `linlink update` or `update` inside `linlink shell` to automatically check versions, fetch release highlights, and perform atomic self-replacement of the binary.
- **Android APK Downloads**: Use `linlink update --apk` to download the latest Android package and auto-send it to your connected phone for instant installation.
- **In-App Mobile Checker**: Added an online update checker directly into the Android **Settings** screen under *About LinLink*.

### 📁 Enhanced Directory & Scoped Storage File Listing
- **Full File & Folder Visibility**: Resolved Android 11+ scoped storage permission scoping in `_handleList`. Both files and directories now display correctly with exact file sizes (`KB`, `MB`, `GB`), types, and modification timestamps.
- **Seamless Shell Navigation**: Fixed remote folder exploration via `ls`, `cd`, `get`, and `cat` in `linlink shell`.

### 🔔 Custom Status Bar Notification Symbol
- **Native Android Silhouette**: Replaced the default Flutter icon with a dedicated monochrome vector silhouette (`ic_notification.xml`) and `#6366F1` indigo accents adhering to Android status bar design guidelines.

---

## 🏛 Architecture Overview

LinLink consists of modular, zero-cloud components operating over high-performance local TCP:

```
┌────────────────────────────────────────────────────────┐
│                   Android Device                       │
│  • Flutter UI — Floating Glass Navigation Bar (M3)     │
│  • CallService & CallCard Voice Audio Bridge           │
│  • AndroidFileAgent (HTTP/TCP Server on Port 7879)     │
│  • Native SAF FilePicker + Storage Staging Pipeline    │
│  • Persistent Foreground Service with Custom Icon      │
│  • In-App Online Update Checker (UpdateService)        │
│  • Instant disconnect push (/fs/disconnect)            │
└────────────────────────▲───────────────────────────────┘
                         │
                    Local Wi-Fi / Hotspot LAN / TCP
                         │
┌────────────────────────▼───────────────────────────────┐
│                   Linux Machine                        │
│  • Linux Companion CLI (linlink) in Rust               │
│  • Background Axum Daemon (Port 7878)                  │
│  • Online Auto-Updater (linlink update)                │
│  • Remote Call Audio Bridge (linlink call <number>)    │
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
  - `CallScreen` & `CallCard` ([`lib/features/call/views/`](lib/features/call/views/)) — VoIP and cellular calling interface with live audio equalizer visualizers.
  - `PhoneSendDialog` ([`lib/features/pairing/views/phone_send_dialog.dart`](lib/features/pairing/views/phone_send_dialog.dart)) — Sender-first staging workflow: select files first, compute batch sizes, and render instant high-contrast QR codes.
  - `ScannerScreen` ([`lib/features/scanner/views/scanner_screen.dart`](lib/features/scanner/views/scanner_screen.dart)) — Dual-mode camera QR scanner using `mobile_scanner` + BLoC. Detects `mode=p2p` for batch file downloads or standard pairing payloads.
  - `RemoteFileBrowserScreen` ([`lib/features/storage/remote_file_browser_screen.dart`](lib/features/storage/remote_file_browser_screen.dart)) — Remote filesystem explorer with instant search and download streams.

- **Local Server Engine (`AndroidFileAgent`)**:
  - Embedded asynchronous HTTP/TCP server running on Android (Port `7879`).
  - Staged file queueing for sender-first P2P file downloads (`/p2p/files` & `/p2p/download`).
  - Automatic IP discovery prioritizing Wi-Fi (`wlan0`) and Mobile Hotspot (`ap0`) interfaces.
  - Scoped storage resilient file and folder listing with sizes and modified dates.
  - Strict Privacy Guard blocking remote folder inspection (`/fs/list`) with HTTP 403 Forbidden unless allowed.

- **Background Services & Calling Bridge**:
  - Native MethodChannel bridge for triggering Android telephony intents (`ACTION_CALL`/`ACTION_DIAL`).
  - Persistent foreground notification service with custom vector icon (`ic_notification.xml`) keeping clipboard synchronization active.

---

### 🐧 Linux Companion Architecture

The Linux host utility is written in high-performance, asynchronous Rust:

- **Axum Daemon Engine (`linux-companion/src/daemon/`)**:
  - Listens on TCP Port `7878` for device registration, file streaming, call signaling, and health checks.
  - Token-authenticated session manager in `~/.config/linlink/session.json`.
- **Calling & Audio Bridge Engine (`linux-companion/src/cli/call.rs`)**:
  - Interactive TUI with live VU meters and keyboard shortcuts for call management.
- **Online Auto-Updater (`linux-companion/src/cli/update.rs`)**:
  - GitHub release discovery, semver comparison, and atomic running binary self-replacement.
- **System Clipboard Interop (`linux-companion/src/clipboard/`)**:
  - Zero-latency native bridge supporting Wayland (`wl-clipboard`) and X11 (`xclip`/`xsel`).
  - Loop prevention with SHA-256 state hashing.
- **Interactive Shell REPL (`linux-companion/src/cli/shell.rs`)**:
  - Interactive terminal environment to navigate, read (`cat`), upload (`put`), download (`get`), call, and update directly from the Linux terminal.

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

## 🚀 Supported Connections & Features Matrix

| Feature / Connection | Support | Details |
| :--- | :---: | :--- |
| 📞 **Remote Phone Dialing** | ✅ | **New:** Dial phone numbers from Linux terminal & use PC Mic/Speaker |
| 🚀 **Online Auto-Updater** | ✅ | **New:** `linlink update` with binary self-replacement & APK download |
| 📁 **Remote File Browsing** | ✅ | **New:** Full file & folder listing with sizes and modified dates |
| 🔔 **Custom Notification Icon** | ✅ | **New:** Clean monochrome status bar vector icon |
| 📱 **Android → Android** | ✅ | Sender-first QR pick & auto-download |
| 💻 **Linux → Android** | ✅ | Browse phone filesystem, upload/download via TCP |
| 📱 **Android → Linux** | ✅ | Direct transfer via SAF File Picker or terminal |
| 📋 **Clipboard Sync** | ✅ | Real-time bi-directional (Wayland & X11) + Foreground service |
| 💻 **Interactive Shell** | ✅ | Full terminal shell (`linlink shell`, `call`, `get`, `put`, `update`) |
| 🛡️ **Privacy Shield** | ✅ | Blocks unauthorized storage inspection |
| ⚙️ **systemd Service** | ✅ | Background companion daemon with automatic startup |

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

*(Note: `chmod +x install.sh` makes the installer executable).*

#### Option 2: Manual Binary Download

1. Download the latest Linux release tarball `linlink-linux-x86_64-v1.1.1.tar.gz` from [GitHub Releases](https://github.com/THARUN-BART/linlink/releases).
2. Extract and copy to your local bin:
   ```bash
   tar -xzf linlink-linux-x86_64-v1.1.1.tar.gz
   cd linlink-linux-x86_64
   mkdir -p ~/.local/bin
   cp linlink ~/.local/bin/
   ```
3. Ensure `~/.local/bin` is in your `PATH`.

---

### 📱 Android Installation

1. Download the latest `linlink-android-arm64-v8a-v1.1.1.apk` from [GitHub Releases](https://github.com/THARUN-BART/linlink/releases) or [SourceForge](https://sourceforge.net/projects/linlink/files/).
2. Open the `.apk` on your Android device to install.
3. Grant necessary permissions (Camera for QR scanning, Storage for file saving, Microphone for calls).

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

## 🛠 CLI & Shell Reference Manual

### Linux Host Commands

| Command | Description |
| :--- | :--- |
| `linlink pair` | Start pairing server and display QR code in terminal |
| `linlink pair --foreground` | Run pairing server in foreground for debugging |
| `linlink pair --host <IP>` | Specify custom LAN IP for the QR payload |
| `linlink call [NUMBER]` | Start a remote voice call or dial a phone number with PC Mic & Speaker |
| `linlink update` | Check online repository and download/install latest software update |
| `linlink update --check` | Check if an online update is available without downloading |
| `linlink update --apk` | Download the latest Android APK update file |
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
| `ls [path]` | List files and folders on remote device with size and date |
| `cd [dir]` | Change remote working directory |
| `pwd` | Print current remote directory path |
| `get <remote> [local]` | Download remote file to `~/Downloads/LinLink/` |
| `put <local> [name]` | Upload file from Linux to Android storage |
| `cat <file>` | Print remote text file contents in terminal |
| `call [phone_number]` | Call phone or dial number (use PC mic to speak & speaker to hear) |
| `dial <phone_number>` | Dial a friend's phone number on phone remotely |
| `hangup` | Hang up active call |
| `call-status` | View active calling & audio bridge status |
| `update` | Check and download online updates |
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

## 🔒 Security & Privacy

- **100% Local-First Architecture** — No external servers, no cloud storage, and no tracking telemetry.
- **Dynamic Session Tokens** — Every transaction is authenticated with an ephemeral session token.
- **Privacy Shield by Default** — Remote filesystem listing is blocked during phone-to-phone transfers; only explicitly selected files can be downloaded.
- **Instant Unlink Handshake** — When shutting down, `linlink stop` dispatches an instant `/fs/disconnect` signal to clear state on all connected peers.

---

## 🤝 Contribution Guide

We welcome contributions from the community! Follow these steps to contribute to LinLink:

1. **Fork & Clone the Repository**:
   ```bash
   git clone https://github.com/THARUN-BART/linlink.git
   cd linlink
   ```
2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Run Tests**:
   ```bash
   # Flutter tests
   flutter test

   # Linux Companion tests
   cargo test --manifest-path linux-companion/Cargo.toml
   ```
4. **Commit & Push**:
   ```bash
   git commit -m "feat(module): description of changes"
   git push origin feature/your-feature-name
   ```

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
