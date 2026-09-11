# Architecture

LinLink uses a decoupled, local-first architecture operating directly over high-performance local TCP (Wi-Fi or Mobile Hotspot) with **zero cloud or internet dependency**.

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

## 📱 Mobile Architecture (Flutter)

The Android app is built using Flutter and structured into modular, feature-based packages under `lib/features/`:

### 1. UI Layer & Presentation
- **`HomeScreen` (`lib/features/home/home_screen.dart`)**:
  - Main dashboard with a floating frosted glass navigation bar (`BackdropFilter` blur + dark tint).
  - Handles paired status, connection toggles, clipboard previews, and quick actions.
- **`PhoneSendDialog` (`lib/features/pairing/views/phone_send_dialog.dart`)**:
  - Sender-first P2P transfer interface: allows users to pick files first, calculates total payload size, starts the local server, and renders a dynamic QR code for the receiver.
- **`ScannerScreen` (`lib/features/scanner/views/scanner_screen.dart`)**:
  - High-speed camera scanner using `mobile_scanner` + BLoC state management.
  - Automatically identifies pairing vs `mode=p2p` QR codes to initiate direct batch file downloads.
- **`RemoteFileBrowserScreen` (`lib/features/storage/remote_file_browser_screen.dart`)**:
  - Remote Linux filesystem browser to explore directories and download files directly to mobile storage.

### 2. Local File Server (`AndroidFileAgent`)
- Located in `lib/features/storage/file_agent.dart`.
- Runs an embedded asynchronous HTTP/TCP server on Android port **7879**.
- **P2P File Queueing**: Staged files are served via `/p2p/files` (listing) and `/p2p/download` (streamed binary download).
- **Network Interface Discovery**: Discovers local IPv4 addresses prioritizing Wi-Fi (`wlan0`) and Hotspot (`ap0`) interfaces.
- **Privacy Guard**: Blocks unauthorized remote folder inspection (`/fs/list`) with HTTP 403 Forbidden unless explicitly allowed.

### 3. Background Clipboard Engine
- Located in `lib/features/clipboard/clipboard_service.dart`.
- Integrates with Android Foreground Service to maintain continuous, bi-directional clipboard sync even when the app is in the background.

---

## 🐧 Linux Companion Architecture (Rust)

The Linux companion is written in asynchronous Rust (Tokio + Axum) under `linux-companion/`:

### 1. Axum Background Daemon (`linux-companion/src/daemon/`)
- Listens on TCP port **7878**.
- Endpoints for pairing handshakes (`/pair/handshake`), device registration (`/api/device/register`), clipboard sync (`/api/clipboard`), and file streams (`/api/fs/upload`).
- Token-authenticated session manager persisted in `~/.config/linlink/session.json`.

### 2. System Clipboard Integration (`linux-companion/src/clipboard/`)
- Native support for both **Wayland** (`wl-clipboard`) and **X11** (`xclip` / `xsel`).
- Automatic change detection with loop-prevention hashing.

### 3. Interactive Shell REPL (`linux-companion/src/cli/shell.rs`)
- Full interactive terminal environment connected to Android storage:
  - Commands: `ls`, `cd`, `pwd`, `cat`, `get`, `put`, `mkdir`, `rm`, `clip`, `clear`, `exit`.

---

## 🔄 P2P File Transfer Protocol Flow

```
Sender (Android Phone A)                        Receiver (Android Phone B)
       │                                                │
       │  1. Pick files via SAF                         │
       │  2. Start server & queue files in memory       │
       │  3. Display QR: linlink://IP:7879?t=..&mode=p2p│
       │                                                │
       │  4. Scan QR code                               │
       │<───────────────────────────────────────────────│
       │                                                │
       │  5. GET /p2p/files?t=TOKEN                     │
       │<───────────────────────────────────────────────│
       │  200 OK (file list JSON)                       │
       │───────────────────────────────────────────────>│
       │                                                │
       │  6. GET /p2p/download?t=TOKEN&index=0..N       │
       │<───────────────────────────────────────────────│
       │  Stream file binary data                       │
       │───────────────────────────────────────────────>│ Saved in Downloads/LinLink
```
