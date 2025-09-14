# fedora-workstation

Single-file post-install script for **Fedora Workstation 42+**.  
Enables full multimedia codecs, Mesa freeworld drivers, VS Code, and battery optimizations — all in one go.  
Idempotent: safe to re-run anytime.

---

## Usage

Clone or copy the script, then run:

    chmod +x ./fedora-setup.sh
    ./fedora-setup.sh

Non-interactive:

    ./fedora-setup.sh -y
    # or
    ./fedora-setup.sh --yes

No clone (download and run):

    # Prefer a tagged release (replace vX.Y.Z)
    curl -fsSLO https://raw.githubusercontent.com/benrozsa/fedora-workstation/v0.1.3/fedora-setup.sh
    # Or track main HEAD
    # curl -fsSLO https://raw.githubusercontent.com/benrozsa/fedora-workstation/HEAD/fedora-setup.sh
    chmod +x ./fedora-setup.sh
    ./fedora-setup.sh

Help:

    ./fedora-setup.sh --help

Flags:

- `-y`, `--yes`, `--assume-yes`: skip the confirmation prompt (non-interactive).
- `-h`, `--help`: show usage and exit.

Requirements:

- Fedora Workstation 42+ (the script enforces this).
- Sudo privileges for system-wide changes.
- Internet access for repositories and packages.

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

## Troubleshooting

- VA-API support: `vainfo | grep -E 'H\.264|H264|HEVC|AV1|VP9' || vainfo`
- TLP status: `systemctl status tlp --no-pager`
- Repositories: `dnf repolist --enabled | grep rpmfusion || dnf repolist --enabled`

---

## Notes & Scope

- Script is idempotent (safe to run multiple times).  
- Designed for **minimal + battery-friendly Fedora workstation**.  
- Extras like GNOME Tweaks, EasyEffects, or Flatpak apps are intentionally omitted — add them if you want a fuller setup.

See Releases for change history: https://github.com/benrozsa/fedora-workstation/releases

### Security & Repos

- Enables RPM Fusion Free + Nonfree by installing the `rpmfusion-*-release` packages.
- Adds Microsoft’s VS Code YUM/DNF repo file to `/etc/dnf/repos.d/` (or `/etc/yum.repos.d/`).
- Remove the VS Code repo later by deleting `vscode.repo` from that directory.

### NVIDIA note

- This script focuses on Mesa (AMD/Intel) with VAAPI/VDPAU. It does not install proprietary NVIDIA drivers. If needed: `sudo dnf install akmod-nvidia` (from RPM Fusion Nonfree) and reboot.

### Reverting Changes (optional)

- Switch FFmpeg back: `sudo dnf -y swap ffmpeg ffmpeg-free --allowerasing`
- Switch Mesa drivers back:
  - `sudo dnf -y swap mesa-va-drivers-freeworld mesa-va-drivers --allowerasing`
  - `sudo dnf -y swap mesa-vdpau-drivers-freeworld mesa-vdpau-drivers --allowerasing`
- Remove RPM Fusion (if you enabled it only for this): `sudo dnf remove rpmfusion-free-release rpmfusion-nonfree-release`

### Implementation details (robustness)

- Uses `set -Eeuo pipefail` and an `ERR` trap for clear failures.  
- Retries transient package operations once (network flakiness).  
- Verifies RPM Fusion repos after bootstrapping; aborts if missing.  
- Writes the VS Code repo file atomically and chooses the repo directory dynamically: prefers `/etc/dnf/repos.d` when present, falls back to `/etc/yum.repos.d`.
- Browser choice is left entirely to the user; the script does not configure Chromium.
- Works with both `dnf` and `dnf5` automatically.

---

## Contributing

- Run `shellcheck fedora-setup.sh` and fix warnings.
- Run `yamllint .github/workflows` to check workflow YAML.
- Keep changes minimal and focused; the script should remain single-file and idempotent.

---

## License

MIT
