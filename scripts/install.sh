#!/usr/bin/env bash
# =============================================================================
#  LinLink — Linux Integration Script
#  Installs the linlink binary, configures directories, and sets up systemd.
#
#  Usage:
#    chmod +x linux_integration.sh
#    ./linux_integration.sh            # install
#    ./linux_integration.sh --uninstall
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Configuration ─────────────────────────────────────────────────────────────

# SourceForge direct file download URL
DOWNLOAD_URL="https://sourceforge.net/projects/linlink/files/latest/download"

BINARY_NAME="linlink"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/linlink"
TRANSFERS_DIR="${HOME}/Downloads/LinLink"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_DIR}/linlink.service"
BINARY_PATH="${INSTALL_DIR}/${BINARY_NAME}"

# ─────────────────────────────────────────────────────────────────────────────

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ██╗     ██╗███╗   ██╗██╗     ██╗███╗   ██╗██╗  ██╗"
  echo "  ██║     ██║████╗  ██║██║     ██║████╗  ██║██║ ██╔╝"
  echo "  ██║     ██║██╔██╗ ██║██║     ██║██╔██╗ ██║█████╔╝ "
  echo "  ██║     ██║██║╚██╗██║██║     ██║██║╚██╗██║██╔═██╗ "
  echo "  ███████╗██║██║ ╚████║███████╗██║██║ ╚████║██║  ██╗"
  echo "  ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝"
  echo -e "${RESET}"
  echo -e "  ${BOLD}Android ↔ Linux Companion Bridge — Linux Integration Script${RESET}"
  echo ""
}

log_info()    { echo -e "  ${BLUE}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "  ${GREEN}[  OK]${RESET}  $*"; }
log_warn()    { echo -e "  ${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "  ${RED}[FAIL]${RESET}  $*"; }
log_step()    { echo -e "\n  ${BOLD}${CYAN}▶ $*${RESET}"; }
log_done()    { echo -e "\n  ${GREEN}${BOLD}✅ $*${RESET}\n"; }

# ── Dependency check ──────────────────────────────────────────────────────────
check_dependencies() {
  log_step "Checking dependencies..."

  local missing=()

  for cmd in curl chmod mkdir systemctl tar; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    log_error "Please install them and re-run this script."
    exit 1
  fi

  log_ok "All required tools found."

  # Clipboard tool check (optional but recommended)
  if command -v wl-paste &>/dev/null; then
    log_ok "Clipboard: wl-clipboard (Wayland) detected."
  elif command -v xclip &>/dev/null; then
    log_ok "Clipboard: xclip (X11) detected."
  elif command -v xsel &>/dev/null; then
    log_ok "Clipboard: xsel (X11) detected."
  else
    log_warn "No clipboard utility found."
    log_warn "Install one for clipboard sync to work:"
    log_warn "  Wayland: sudo apt install wl-clipboard"
    log_warn "  X11:     sudo apt install xclip"
  fi
}

# ── Download binary ───────────────────────────────────────────────────────────
download_binary() {
  log_step "Downloading linlink binary from SourceForge..."

  local tmp_file
  tmp_file="$(mktemp /tmp/linlink.XXXXXX)"

  log_info "Fetching from: ${DOWNLOAD_URL}"

  if curl -fsSL -L --progress-bar "$DOWNLOAD_URL" -o "$tmp_file"; then
    chmod +x "$tmp_file"

    local file_type
    file_type="$(file "$tmp_file")"

    # Check if downloaded file is ELF binary or tar.gz archive
    if echo "$file_type" | grep -q "ELF"; then
      mv "$tmp_file" "${BINARY_PATH}"
      log_ok "Binary downloaded and installed to ${BINARY_PATH}"
    elif echo "$file_type" | grep -qE "gzip compressed|tar archive"; then
      log_info "Archive detected. Extracting binary..."
      local extract_dir
      extract_dir="$(mktemp -d /tmp/linlink_extract.XXXXXX)"
      tar -xzf "$tmp_file" -C "$extract_dir"
      
      # Find linlink executable inside archive
      local bin_found
      bin_found="$(find "$extract_dir" -type f -name "linlink" | head -n 1)"
      
      if [[ -n "$bin_found" && -f "$bin_found" ]]; then
        chmod +x "$bin_found"
        mv "$bin_found" "${BINARY_PATH}"
        log_ok "Binary extracted and installed to ${BINARY_PATH}"
      else
        log_error "Could not find 'linlink' binary inside downloaded archive."
        rm -rf "$extract_dir" "$tmp_file"
        exit 1
      fi
      rm -rf "$extract_dir" "$tmp_file"
    else
      log_error "Downloaded file is neither an ELF binary nor a tar.gz archive."
      log_error "File type detected: ${file_type}"
      log_error "Check that your SourceForge project has uploaded release files."
      rm -f "$tmp_file"
      exit 1
    fi
  else
    log_error "Download failed. Check your internet connection or the SourceForge URL."
    rm -f "$tmp_file"
    exit 1
  fi
}

# ── Create directories ────────────────────────────────────────────────────────
create_directories() {
  log_step "Creating required directories..."

  mkdir -p "$INSTALL_DIR"
  log_ok "Install dir:   ${INSTALL_DIR}"

  mkdir -p "$CONFIG_DIR"
  log_ok "Config dir:    ${CONFIG_DIR}"

  mkdir -p "$TRANSFERS_DIR"
  log_ok "Transfers dir: ${TRANSFERS_DIR}"

  mkdir -p "$SYSTEMD_DIR"
  log_ok "Systemd dir:   ${SYSTEMD_DIR}"
}

# ── PATH setup ────────────────────────────────────────────────────────────────
ensure_path() {
  log_step "Ensuring ${INSTALL_DIR} is in PATH..."

  local shell_rc=""
  if [[ "$SHELL" == *"zsh"* ]]; then
    shell_rc="${HOME}/.zshrc"
  elif [[ "$SHELL" == *"fish"* ]]; then
    shell_rc="${HOME}/.config/fish/config.fish"
  else
    shell_rc="${HOME}/.bashrc"
  fi

  if echo "$PATH" | grep -q "${INSTALL_DIR}"; then
    log_ok "${INSTALL_DIR} is already in PATH."
  else
    local export_line='export PATH="$HOME/.local/bin:$PATH"'
    echo "" >> "$shell_rc"
    echo "# Added by LinLink installer" >> "$shell_rc"
    echo "$export_line" >> "$shell_rc"
    log_ok "Added to ${shell_rc} — restart your terminal or run: source ${shell_rc}"
  fi
}

# ── systemd service ───────────────────────────────────────────────────────────
install_systemd_service() {
  log_step "Installing systemd user service..."

  cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=LinLink Android-Linux Companion Bridge
Documentation=https://github.com/THARUN-BART/linlink
After=network-online.target
Wants=network-online.target

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
SERVICE

  log_ok "Service file written to ${SERVICE_FILE}"

  systemctl --user daemon-reload
  log_ok "systemd user daemon reloaded."

  # Ask user if they want to enable auto-start
  echo ""
  read -rp "  Enable linlink to auto-start on login? [Y/n]: " answer
  answer="${answer:-Y}"
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    systemctl --user enable linlink.service
    log_ok "linlink.service enabled (will auto-start on login)."
  else
    log_info "Skipped auto-start. Enable later with: systemctl --user enable linlink"
  fi
}

# ── Verify installation ───────────────────────────────────────────────────────
verify_installation() {
  log_step "Verifying installation..."

  if [[ -x "$BINARY_PATH" ]]; then
    local version
    version="$("$BINARY_PATH" --version 2>/dev/null || echo 'unknown')"
    log_ok "Binary: ${BINARY_PATH}"
    log_ok "Version: ${version}"
  else
    log_error "Binary not found or not executable at ${BINARY_PATH}"
    exit 1
  fi

  if [[ -f "$SERVICE_FILE" ]]; then
    log_ok "Service file: ${SERVICE_FILE}"
  fi

  if systemctl --user is-enabled linlink.service &>/dev/null; then
    log_ok "Service status: enabled (auto-start on login)"
  else
    log_info "Service status: installed but not enabled"
  fi
}

# ── Print usage ───────────────────────────────────────────────────────────────
print_usage() {
  echo ""
  echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "  ${BOLD}  LinLink is ready!${RESET}"
  echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo -e "  ${CYAN}Quick start:${RESET}"
  echo -e "    ${BOLD}linlink pair${RESET}          — start pairing (scan QR from Android app)"
  echo -e "    ${BOLD}linlink status${RESET}        — check connection status"
  echo -e "    ${BOLD}linlink shell${RESET}         — browse Android storage in terminal"
  echo -e "    ${BOLD}linlink clipboard${RESET}     — view shared clipboard"
  echo -e "    ${BOLD}linlink logs -f${RESET}       — follow live daemon logs"
  echo -e "    ${BOLD}linlink stop${RESET}          — disconnect (notifies Android instantly)"
  echo ""
  echo -e "  ${CYAN}Service control:${RESET}"
  echo -e "    ${BOLD}systemctl --user start linlink${RESET}"
  echo -e "    ${BOLD}systemctl --user stop linlink${RESET}"
  echo -e "    ${BOLD}journalctl --user -u linlink -f${RESET}"
  echo ""
  echo -e "  ${CYAN}Config & logs:${RESET}"
  echo -e "    ${BOLD}${CONFIG_DIR}/${RESET}"
  echo -e "    ${BOLD}${TRANSFERS_DIR}/${RESET}"
  echo ""
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
uninstall() {
  banner
  echo -e "  ${RED}${BOLD}Uninstalling LinLink...${RESET}\n"

  if systemctl --user is-active linlink.service &>/dev/null; then
    systemctl --user stop linlink.service
    log_ok "Stopped linlink service."
  fi

  if systemctl --user is-enabled linlink.service &>/dev/null; then
    systemctl --user disable linlink.service
    log_ok "Disabled linlink service."
  fi

  [[ -f "$SERVICE_FILE" ]]  && rm -f "$SERVICE_FILE"  && log_ok "Removed: ${SERVICE_FILE}"
  [[ -x "$BINARY_PATH" ]]   && rm -f "$BINARY_PATH"   && log_ok "Removed: ${BINARY_PATH}"

  systemctl --user daemon-reload

  echo ""
  read -rp "  Also remove config & logs (~/.config/linlink)? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    log_ok "Removed: ${CONFIG_DIR}"
  else
    log_info "Config kept at ${CONFIG_DIR}"
  fi

  log_done "LinLink uninstalled successfully."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  banner

  if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
    exit 0
  fi

  echo -e "  ${BOLD}This script will:${RESET}"
  echo -e "  • Download the linlink binary from GitHub Releases"
  echo -e "  • Install it to ${INSTALL_DIR}"
  echo -e "  • Create config directories"
  echo -e "  • Set up a systemd user service"
  echo ""
  read -rp "  Continue? [Y/n]: " answer
  answer="${answer:-Y}"
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo -e "\n  Aborted.\n"
    exit 0
  fi

  check_dependencies
  create_directories
  download_binary
  ensure_path
  install_systemd_service
  verify_installation
  print_usage

  log_done "Installation complete! Open a new terminal and run: linlink pair"
}

main "$@"
