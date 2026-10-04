# Architecture (LinLink v1.1.1)

LinLink uses a decoupled, local-first architecture operating directly over high-performance local TCP (Wi-Fi or Mobile Hotspot) with **zero cloud or internet dependency**.

```
┌────────────────────────────────────────────────────────┐
│                   Android Device                       │
│  • Flutter UI — Floating Glass Navigation Bar (M3)     │
│  • Remote Call Engine (CallService & CallScreen)       │
│  • Native Telephony & MethodChannel Dialing Bridge     │
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
│  • Remote Calling Engine & PC Audio Bridge (linlink call)│
│  • Online Software Auto-Updater (linlink update)       │
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
  - Handles paired status, connection toggles, clipboard previews, quick actions, and calling widgets.
- **`CallScreen` & `CallCard` (`lib/features/call/views/`)**:
  - Modern calling UI with animated voice ripples, live equalizer meters, and remote phone dialer dialog.
  - Controls PC Mic mute and PC Speaker output toggles in real-time.
- **`PhoneSendDialog` (`lib/features/pairing/views/phone_send_dialog.dart`)**:
  - Sender-first P2P transfer interface: allows users to pick files first, calculates total payload size, starts the local server, and renders a dynamic QR code for the receiver.
- **`ScannerScreen` (`lib/features/scanner/views/scanner_screen.dart`)**:
  - High-speed camera scanner using `mobile_scanner` + BLoC state management.
  - Automatically identifies pairing vs `mode=p2p` QR codes to initiate direct batch file downloads.
- **`RemoteFileBrowserScreen` (`lib/features/storage/remote_file_browser_screen.dart`)**:
  - Remote Linux filesystem browser to explore directories and download files directly to mobile storage.
- **`SettingsScreen` (`lib/features/settings/settings_screen.dart`)**:
  - Permissions management, remote directory browsing toggle, and in-app online update checker.

### 2. Remote Calling & Telephony Bridge (`CallService`)
- Located in `lib/features/call/call_service.dart`.
- Manages the calling state machine: `idle` ➔ `ringing` ➔ `calling` ➔ `inCall` ➔ `ended`.
- **MethodChannel Telephony Bridge**:
  - Bridges calls to native Android Kotlin layer (`MainActivity.kt`) using `Intent.ACTION_CALL` and `Intent.ACTION_DIAL`.
  - Enables dialing contacts remotely from the Linux PC terminal.
- **Signaling Endpoints**:
  - Handles `/call/invite`, `/call/dial`, `/call/answer`, `/call/hangup`, `/call/status`, and `/call/control`.

### 3. Local File Server (`AndroidFileAgent`)
- Located in `lib/features/storage/file_agent.dart`.
- Runs an embedded asynchronous HTTP/TCP server on Android port **7879**.
- **Scoped Storage Compatibility**: Handles Android 11+ file permission restrictions gracefully, listing files and directories with sizes and timestamps without dropping entries.
- **P2P File Queueing**: Staged files are served via `/p2p/files` (listing) and `/p2p/download` (streamed binary download).
- **Network Interface Discovery**: Discovers local IPv4 addresses prioritizing Wi-Fi (`wlan0`) and Hotspot (`ap0`) interfaces.
- **Privacy Guard**: Blocks unauthorized remote folder inspection (`/fs/list`) with HTTP 403 Forbidden unless explicitly allowed.

### 4. Background Services & Custom Notification
- Integrates with Android Foreground Service (`LinLinkForegroundService.kt`) with a dedicated monochrome status bar vector silhouette (`ic_notification.xml`).
- Keeps clipboard synchronization and call signaling active without battery-saver interruptions.

### 5. In-App Online Updater (`UpdateService`)
- Located in `lib/features/update/update_service.dart`.
- Checks GitHub releases online, compares semver versions, and displays release notes and direct APK download links.

---

## 🐧 Linux Companion Architecture (Rust)

The Linux companion is written in asynchronous Rust (Tokio + Axum) under `linux-companion/`:

### 1. Axum Background Daemon (`linux-companion/src/daemon/`)
- Listens on TCP port **7878**.
- Endpoints for pairing handshakes (`/pair/handshake`), device registration (`/api/device/register`), clipboard sync (`/api/clipboard`), file streams (`/api/fs/upload`), and call state signaling (`/api/call/*`).
- Token-authenticated session manager persisted in `~/.config/linlink/session.json`.

### 2. Remote Calling & PC Audio Bridge (`linux-companion/src/cli/call.rs`)
- Full interactive terminal TUI for remote cellular calling and LinLink VoIP bridge:
  - Live call duration timer and VU meters for PC Mic input and PC Speaker output.
  - Keyboard shortcuts during calls (`[m]` mute, `[s]` speaker, `[q]`/`[h]` hang up).

### 3. Online Software Auto-Updater (`linux-companion/src/cli/update.rs`)
- Command: `linlink update` and in-shell `update`.
- Queries GitHub releases API for latest release assets and changelogs.
- Performs atomic self-replacement of the currently executing Linux binary using Unix file descriptor unlinking.
- Downloads Android APK updates (`--apk`) and can push them directly over TCP to the connected phone.

### 4. System Clipboard Integration (`linux-companion/src/clipboard/`)
- Native support for both **Wayland** (`wl-clipboard`) and **X11** (`xclip` / `xsel`).
- Automatic change detection with loop-prevention hashing.

### 5. Interactive Shell REPL (`linux-companion/src/cli/shell.rs`)
- Full interactive terminal environment connected to Android storage:
  - Commands: `ls`, `cd`, `pwd`, `cat`, `get`, `put`, `mkdir`, `rm`, `clip`, `call`, `dial`, `hangup`, `call-status`, `update`, `clear`, `exit`.

---

## 🔄 Protocol Flows

### 1. Remote Phone Calling & Audio Bridge Protocol

#### Outgoing Call Flow:
```
Linux Companion CLI                               Android Device (Agent)
        │                                                │
        │  1. linlink call +1234567890                   │
        │  POST /call/dial?number=+1234567890            │
        │───────────────────────────────────────────────>│
        │                                                │  2. Triggers ACTION_CALL intent
        │                                                │     Initiates phone dialer
        │  3. 200 OK (state: in_call, audio: bridge)     │
        │<───────────────────────────────────────────────│
        │                                                │
        │  4. Real-time PC Mic & Speaker Audio Streams   │
        │<══════════════════════════════════════════════>│
        │                                                │
        │  5. Hangup: POST /call/hangup                  │
        │───────────────────────────────────────────────>│  6. Terminates call session
```

#### Incoming Call & Laptop Answer Flow:
```
Linux Companion (Laptop)                          Android Phone (Cellular Network)
        │                                                │
        │                                                │  1. Incoming cellular call ringing
        │                                                │     PhoneCallReceiver catches event
        │  2. POST /api/call/incoming {caller, ringing}   │
        │<───────────────────────────────────────────────│
        │  Desktop notification shown on Laptop          │
        │                                                │
        │  3. User runs `linlink answer` / shell `a`     │
        │  POST /call/answer                             │
        │───────────────────────────────────────────────>│  4. TelecomManager.acceptRingingCall()
        │                                                │     Natively answers phone call
        │  5. Full-duplex PC Audio Bridge Connected      │
        │<══════════════════════════════════════════════>│  (PC Mic -> Phone, Phone -> PC Spk)
        │                                                │
        │  6. Hangup: POST /call/hangup                  │  7. TelecomManager.endCall()
        │───────────────────────────────────────────────>│     Natively ends call
```

---

### 2. P2P File Transfer Protocol Flow
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

---

### 3. Online Software Update Protocol Flow
```
LinLink (Linux CLI / Mobile App)                        GitHub Releases API
       │                                                │
       │  1. GET /repos/THARUN-BART/linlink/releases/latest
       │───────────────────────────────────────────────>│
       │                                                │
       │  2. 200 OK (version, changelog, assets)        │
       │<───────────────────────────────────────────────│
       │                                                │
       │  3. Compare semver (current vs latest)         │
       │  4. Download binary / APK asset with progress   │
       │  5. Atomic file replacement (chmod +x)         │
       │  6. Verification test (--version)               │
```
