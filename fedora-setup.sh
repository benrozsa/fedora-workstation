#!/usr/bin/env bash
# Fedora Workstation (GNOME) post-install — minimal + battery-friendly
# Fedora 42+. Safe to rerun.

set -Eeuo pipefail

# ----------------- Logging -----------------
say(){ printf "\n\033[1m==> %s\033[0m\n" "$*"; }
green(){ printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red(){ printf "\033[31m%s\033[0m\n" "$*"; }
ok(){ green "✅ $*"; }
warn(){ yellow "⚠️  $*"; }
bad(){ red "❌ $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

trap 'bad "Script failed or interrupted (line $LINENO)"; exit 1' ERR INT TERM

# Simple retry helper: try once, then retry once on transient failure
retry_once(){
  local attempt=1
  local cmd=("$@")
  "${cmd[@]}" && return 0
  warn "Command failed, retrying once: ${cmd[*]}"
  sleep 2
  "${cmd[@]}"
}

# ----------------- Args & usage -----------------
usage(){
  cat <<EOF
Usage: $0 [--yes]

Post-install for Fedora Workstation 42+.
Performs system updates, enables RPM Fusion, installs codecs (full ffmpeg),
Mesa *freeworld* VAAPI/VDPAU drivers, VS Code, and TLP, and disables
conflicting services. Safe to re-run.

Options:
  -y, --yes, --assume-yes   Skip confirmation prompt
  -h, --help                Show this help and exit
EOF
}

AUTO_YES=0
for a in "$@"; do
  case "$a" in
    -y|--yes|--assume-yes) AUTO_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) ;;
  esac
done

# ----------------- OS guard -----------------
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  bad "/etc/os-release not found; unsupported system"
  exit 1
fi

if [ "${ID:-}" != "fedora" ]; then
  bad "This script supports Fedora only (found ID='${ID:-unknown}')"
  exit 1
fi

FEDORA_MAJOR=${VERSION_ID%%.*}
if ! printf '%s' "$FEDORA_MAJOR" | grep -Eq '^[0-9]+$'; then
  bad "Unrecognized Fedora VERSION_ID: '${VERSION_ID:-}'"
  exit 1
fi
if [ "$FEDORA_MAJOR" -lt 42 ]; then
  bad "Fedora 42+ required (found ${VERSION_ID})"
  exit 1
fi

# ----------------- Confirm changes -----------------
if [ "$AUTO_YES" -ne 1 ]; then
  say "About to configure this Fedora ${VERSION_ID} system with codecs, drivers, VS Code, and TLP."
  printf "Proceed with system-wide changes using sudo and DNF? [y/N] "
  read -r REPLY
  case "$REPLY" in
    [yY]|[yY][eE][sS]) ;;
    *) bad "Aborted by user"; exit 1 ;;
  esac
fi

# ----------------- Package manager -----------------
PKG=dnf
have dnf5 && PKG=dnf5
sudo -v

# ----------------- Base setup -----------------
say "System update"
if ! retry_once sudo "$PKG" -y upgrade --refresh; then
  bad "System upgrade failed twice. Check network/DNF and retry."
  exit 1
fi

say "Enable RPM Fusion (Free + Nonfree)"
if ! rpm -q rpmfusion-free-release >/dev/null 2>&1 || ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
  if ! retry_once sudo "$PKG" -y install \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; then
    bad "Failed to enable RPM Fusion repositories. Aborting."
    exit 1
  fi
else
  ok "RPM Fusion already enabled"
fi

# Verify RPM Fusion repos are actually enabled
if ! sudo "$PKG" repolist --enabled 2>/dev/null | grep -q "rpmfusion-free" || \
   ! sudo "$PKG" repolist --enabled 2>/dev/null | grep -q "rpmfusion-nonfree"; then
  bad "RPM Fusion repos not detected as enabled after setup. Aborting."
  exit 1
fi

say "Full FFmpeg (swap from ffmpeg-free if present)"
if rpm -q ffmpeg-free >/dev/null 2>&1; then
  if ! retry_once sudo "$PKG" -y swap ffmpeg-free ffmpeg --allowerasing; then
    warn "ffmpeg-free -> ffmpeg swap failed; continuing to attempt install."
  fi
fi
if ! retry_once sudo "$PKG" install -y --exclude='*.i686' \
  ffmpeg ffmpeg-libs libva-utils gstreamer1-plugin-openh264 mozilla-openh264; then
  bad "Failed to install FFmpeg/codecs. Aborting."
  exit 1
fi

say "Mesa drivers (Vulkan + VAAPI/VDPAU *freeworld*)"
if ! retry_once sudo "$PKG" install -y --exclude='*.i686' mesa-vulkan-drivers; then
  warn "Failed to install mesa-vulkan-drivers; Vulkan may be unavailable."
fi
if ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
  if ! retry_once sudo "$PKG" -y swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing; then
    warn "Failed to swap to mesa-va-drivers-freeworld; VAAPI may be limited."
  fi
else
  ok "mesa-va-drivers-freeworld already installed"
fi
if ! rpm -q mesa-vdpau-drivers-freeworld >/dev/null 2>&1; then
  if ! retry_once sudo "$PKG" -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing; then
    warn "Failed to swap to mesa-vdpau-drivers-freeworld; VDPAU may be limited."
  fi
else
  ok "mesa-vdpau-drivers-freeworld already installed"
fi

say "Editors & tools"
sudo "$PKG" -y install vim-enhanced vlc

say "Visual Studio Code (Microsoft repo)"
# Pick repo directory dynamically (prefer existing file, then dnf, then yum)
REPO_DIR="/etc/yum.repos.d"
if [ -f /etc/dnf/repos.d/vscode.repo ]; then
  REPO_DIR="/etc/dnf/repos.d"
elif [ -f /etc/yum.repos.d/vscode.repo ]; then
  REPO_DIR="/etc/yum.repos.d"
elif [ -d /etc/dnf/repos.d ]; then
  REPO_DIR="/etc/dnf/repos.d"
else
  REPO_DIR="/etc/yum.repos.d"
fi

if [ ! -f "$REPO_DIR/vscode.repo" ]; then
  if ! retry_once sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; then
    warn "Failed to import Microsoft GPG key; relying on repo-provided gpgkey."
  fi
  TMP_REPO=$(mktemp) || { bad "mktemp failed creating temp repo file"; exit 1; }
  cat >"$TMP_REPO" <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
  if ! sudo install -m 0644 "$TMP_REPO" "$REPO_DIR/vscode.repo"; then
    rm -f "$TMP_REPO"
    bad "Failed to write $REPO_DIR/vscode.repo"
    exit 1
  fi
  rm -f "$TMP_REPO"
fi
if ! retry_once sudo "$PKG" -y install code; then
  warn "Failed to install Visual Studio Code; continuing."
fi

:

say "Battery optimization (TLP)"
sudo "$PKG" -y install tlp
sudo systemctl enable tlp --now

say "Disable power-profiles-daemon (let TLP manage power)"
if systemctl list-unit-files | grep -q '^power-profiles-daemon\.service'; then
  if ! sudo systemctl disable --now power-profiles-daemon; then
    warn "Failed to disable power-profiles-daemon"
  fi
else
  warn "power-profiles-daemon not present; skipping."
fi

say "Disable tuned (optional, avoids policy conflicts)"
if systemctl list-unit-files | grep -q '^tuned\.service'; then
  if ! sudo systemctl disable --now tuned; then
    warn "Failed to disable tuned"
  fi
else
  warn "tuned not present; skipping."
fi

# ----------------- Verification -----------------
say "Running post-install verification..."

say "1) GPU / VA-API support (vainfo)"
if have vainfo; then
  VA_OUT="$(vainfo 2>&1 | sed -n '1,200p')"
  if printf "%s" "$VA_OUT" | grep -qi "Driver version"; then
    ok "vainfo runs: $(printf "%s" "$VA_OUT" | grep -i 'Driver version' | head -1)"
  else
    warn "vainfo ran but no driver version found"
  fi
  printf "%s" "$VA_OUT" | grep -Eiq 'H\.264|H264|AVC' && ok "H.264/AVC decode present" || warn "H.264/AVC not listed"
  printf "%s" "$VA_OUT" | grep -Eiq 'HEVC|H\.265' && ok "HEVC/H.265 decode present" || warn "HEVC/H.265 not listed"
  printf "%s" "$VA_OUT" | grep -Eiq 'VP9' && ok "VP9 decode present" || warn "VP9 not listed"
  printf "%s" "$VA_OUT" | grep -Eiq 'AV1' && ok "AV1 decode present" || warn "AV1 not listed"
else
  bad "libva-utils (vainfo) missing"
fi

say "2) Mesa *freeworld* drivers"
rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1 && ok "mesa-va-drivers-freeworld installed" || bad "mesa-va-drivers-freeworld missing"
rpm -q mesa-vdpau-drivers-freeworld >/dev/null 2>&1 && ok "mesa-vdpau-drivers-freeworld installed" || bad "mesa-vdpau-drivers-freeworld missing"

say "3) FFmpeg build"
if have ffmpeg; then
  ok "ffmpeg package installed"
  CFG="$(ffmpeg -version 2>/dev/null | sed -n '1,12p')"
  printf "%s\n" "$CFG" | grep -q -- '--enable-libx264' && ok "FFmpeg has x264 enabled" || warn "x264 not shown"
  printf "%s\n" "$CFG" | grep -q -- '--enable-libx265' && ok "FFmpeg has x265 enabled" || warn "x265 not shown"
  printf "%s\n" "$CFG" | grep -q -- '--enable-libvpx'  && ok "FFmpeg has VP8/VP9 (libvpx)" || warn "libvpx not shown"
  printf "%s\n" "$CFG" | grep -q -- '--enable-libaom'  && ok "FFmpeg has AV1 (libaom)" || warn "libaom not shown"
else
  bad "ffmpeg not installed"
fi

say "4) OpenH264 bits"
for p in gstreamer1-plugin-openh264 mozilla-openh264; do
  rpm -q "$p" >/dev/null 2>&1 && ok "$p installed" || warn "$p missing"
done

say "5) Battery: TLP + conflicts"
if systemctl is-enabled tlp >/dev/null 2>&1 && systemctl is-active tlp >/dev/null 2>&1; then
  ok "TLP enabled & active"
else
  warn "TLP not fully active"
fi
systemctl is-active power-profiles-daemon >/dev/null 2>&1 \
  && warn "power-profiles-daemon active" || ok "power-profiles-daemon not active"
systemctl is-active tuned >/dev/null 2>&1 \
  && warn "tuned active" || ok "tuned not active"

:

echo
green "All checks complete."
echo "Tips:"
echo " - Reboot once after first install to refresh VA-API profiles."
echo " - Test 4K AV1/HEVC on YouTube to confirm HW decode."
