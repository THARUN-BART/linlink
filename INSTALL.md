# Installation Guide

This guide covers installing LinLink on **Linux** and **Android**, as well as building from source.

---

## 🐧 Linux Installation

### Method 1: Automated Script via SourceForge (Recommended)

Run the following commands in your Linux terminal:

```bash
curl -L -o install.sh "https://sourceforge.net/projects/linlink/files/install.sh/download"
chmod +x install.sh
./install.sh
```

*(You can also use `chmod 777 install.sh` if needed).*

---

### Method 2: Manual Binary Installation

1. Download the release archive `linlink-linux-x86_64-v1.1.0.tar.gz` from [GitHub Releases](https://github.com/THARUN-BART/linlink/releases) or [SourceForge](https://sourceforge.net/projects/linlink/files/).
2. Extract the archive and copy the binary to your local bin directory:
   ```bash
   tar -xzf linlink-linux-x86_64-v1.1.0.tar.gz
   cd linlink-linux-x86_64
   mkdir -p ~/.local/bin
   cp linlink ~/.local/bin/
   ```
3. Make sure `~/.local/bin` is added to your system `PATH`:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

---

### Method 3: Enable Background systemd Service (Optional)

To have the LinLink companion daemon start automatically when you log in:

```bash
systemctl --user enable linlink
systemctl --user start linlink
```

---

## 📱 Android Installation

1. Download the latest Android APK (`linlink-android-arm64-v8a-v1.1.0.apk`) from [GitHub Releases](https://github.com/THARUN-BART/linlink/releases) or [SourceForge](https://sourceforge.net/projects/linlink/files/).
2. Transfer and open the APK file on your phone to install.
3. Grant permissions for:
   - **Camera**: For scanning pairing and transfer QR codes.
   - **Storage / Media**: For saving downloaded and transferred files to `Downloads/LinLink`.

---

## 🛠 Building from Source

### Prerequisites
- **Rust** 1.80+:
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```
- **Flutter SDK** 3.24+
- **Clipboard packages**:
  - Wayland: `sudo apt install wl-clipboard`
  - X11: `sudo apt install xclip xsel`

### 1. Build Linux Companion
```bash
git clone https://github.com/THARUN-BART/linlink.git
cd linlink/linux-companion
cargo build --release
cp target/release/linlink ~/.local/bin/
```

### 2. Build Android App
```bash
cd linlink
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --split-per-abi
```
The resulting APK will be located at:
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
