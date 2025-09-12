#!/usr/bin/env bash
# Fedora Workstation (GNOME) post-install — minimal + battery-friendly
# Fedora 42+. Safe to rerun.

set -euo pipefail

# ----------------- Logging -----------------
say(){ printf "\n\033[1m==> %s\033[0m\n" "$*"; }   # fixed: real newline, bold heading
green(){ printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red(){ printf "\033[31m%s\033[0m\n" "$*"; }
ok(){ green "✅ $*"; }
warn(){ yellow "⚠️  $*"; }
bad(){ red "❌ $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

trap 'bad "Script failed at line $LINENO"; exit 1' ERR

# ----------------- Package manager -----------------
PKG=dnf
have dnf5 && PKG=dnf5
sudo -v

# ----------------- Base setup -----------------
say "System update"
sudo "$PKG" -y upgrade --refresh || true

say "Enable RPM Fusion (Free + Nonfree)"
if ! ls /etc/yum.repos.d/rpmfusion-{free,nonfree}-release*.repo >/dev/null 2>&1; then
  sudo "$PKG" -y install \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true
else
  ok "RPM Fusion already enabled"
fi

say "Full FFmpeg (swap from ffmpeg-free if present)"
if rpm -q ffmpeg-free >/dev/null 2>&1; then
  sudo "$PKG" -y swap ffmpeg-free ffmpeg --allowerasing
fi
sudo "$PKG" -y install ffmpeg ffmpeg-libs libva-utils gstreamer1-plugin-openh264 mozilla-openh264 --exclude='*.i686'

say "Mesa drivers (Vulkan + VAAPI/VDPAU *freeworld*)"
sudo "$PKG" -y install mesa-vulkan-drivers --exclude='*.i686' || true
if ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
  sudo "$PKG" -y swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || true
else
  ok "mesa-va-drivers-freeworld already installed"
fi
if ! rpm -q mesa-vdpau-drivers-freeworld >/dev/null 2>&1; then
  sudo "$PKG" -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing || true
else
  ok "mesa-vdpau-drivers-freeworld already installed"
fi

say "Editors & tools"
sudo "$PKG" -y install vim-enhanced vlc

say "Visual Studio Code (Microsoft repo)"
if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc || true
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
fi
sudo "$PKG" -y install code

say "Chromium (optional) — install is commented out"
# sudo "$PKG" -y install chromium
if have chromium; then
  mkdir -p "$HOME/.config"
  FLAGS="$HOME/.config/chromium-flags.conf"
  grep -qxF "--use-gl=egl" "$FLAGS" 2>/dev/null || echo "--use-gl=egl" >> "$FLAGS"
  grep -qxF "--ignore-gpu-blocklist" "$FLAGS" 2>/dev/null || echo "--ignore-gpu-blocklist" >> "$FLAGS"
  grep -qxF "--enable-features=VaapiVideoDecoder,VaapiVideoEncodeLinuxGL" "$FLAGS" 2>/dev/null || echo "--enable-features=VaapiVideoDecoder,VaapiVideoEncodeLinuxGL" >> "$FLAGS"
fi

say "Battery optimization (TLP)"
sudo "$PKG" -y install tlp
sudo systemctl enable tlp --now

say "Disable power-profiles-daemon (let TLP manage power)"
if systemctl list-unit-files | grep -q '^power-profiles-daemon.service'; then
  sudo systemctl disable --now power-profiles-daemon || true
else
  warn "power-profiles-daemon not present; skipping."
fi

say "Disable tuned (optional, avoids policy conflicts)"
sudo systemctl disable --now tuned || true

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

say "6) Chromium flags (if Chromium installed)"
if have chromium; then
  FLAGS="$HOME/.config/chromium-flags.conf"
  for flag in "--use-gl=egl" "--ignore-gpu-blocklist" "--enable-features=VaapiVideoDecoder,VaapiVideoEncodeLinuxGL"; do
    grep -qxF "$flag" "$FLAGS" 2>/dev/null && ok "Chromium flag set: $flag" || warn "Missing Chromium flag: $flag"
  done
else
  yellow "ℹ️  Chromium not installed — skipping."
fi

echo
green "All checks complete."
echo "Tips:"
echo " - Reboot once after first install to refresh VA-API profiles."
echo " - Test 4K AV1/HEVC on YouTube to confirm HW decode."
