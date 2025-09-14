# fedora-workstation-postinstall

Single-file post-install script for **Fedora Workstation 42+**.  
It configures codecs, GPU drivers, editors, and battery optimization — all in one go.  
Safe to re-run anytime.

---

## Usage

Clone or copy the script, then run:

    chmod +x ./fedora-setup.sh
    ./fedora-setup.sh

Non-interactive:

    ./fedora-setup.sh --yes

Flags:

- `--yes` to skip the confirmation prompt (non-interactive).

Requirements:

- Fedora Workstation 42+ (the script enforces this).

After installation, reboot once to ensure GPU drivers and TLP are active.

---

## What It Does

- **System Updates**  
  Refreshes and upgrades Fedora packages.

- **RPM Fusion**  
  Enables Free + Nonfree repositories for full codec and driver support.

- **Codecs & Video Acceleration**  
  Swaps `ffmpeg-free` for full `ffmpeg` (x264, x265, VP9, AV1, etc.).  
  Installs `mesa-*freeworld` drivers for hardware H.264/HEVC/AV1 decode.  
  Adds OpenH264 (GStreamer + Mozilla).

- **Editors & Tools**  
  Installs `vim-enhanced`, `vlc`, and Visual Studio Code (via Microsoft repo).

- **Battery Optimization**  
  Installs and enables **TLP**.  
  Disables Fedora’s default `power-profiles-daemon` and `tuned` (to avoid conflicts).

- **Verification (built-in)**  
  Shows VA-API codec support (`vainfo`).  
  Prints FFmpeg build info.  
  Confirms TLP is running.

---

## Notes

- Script is idempotent (safe to run multiple times).  
- Designed for **minimal + battery-friendly Fedora workstation**.  
- Extras like GNOME Tweaks, EasyEffects, or Flatpak apps are intentionally omitted — add them if you want a fuller setup.

See Releases for change history: https://github.com/benrozsa/fedora-workstation/releases

### Implementation details (robustness)

- Uses `set -Eeuo pipefail` and an `ERR` trap for clear failures.  
- Retries transient package operations once (network flakiness).  
- Verifies RPM Fusion repos after bootstrapping; aborts if missing.  
- Writes the VS Code repo file atomically and chooses the repo directory dynamically: prefers `/etc/dnf/repos.d` when present, falls back to `/etc/yum.repos.d`.
- Browser choice is left entirely to the user; the script does not configure Chromium.

---

## License

MIT
