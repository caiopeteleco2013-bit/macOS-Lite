# Installation & updates — macOS-Lite

User-facing guide for installing macOS-Lite and keeping it up to date.

---

## 1. Download & verify

Download the ISO matching your needs from the GitHub Releases page:

| ISO | Use when |
|-----|----------|
| `macos-lite-default-amd64-<date>.iso` | 100% DFSG-free; add non-free firmware manually if needed |
| `macos-lite-nonfree-firmware-amd64-<date>.iso` | Wi-Fi/GPU firmware included out of the box |

### Verify the signature

```bash
# 1. Import the project public key (once)
gpg --import macos-lite-release-pubkey.asc

# 2. Verify the checksums file
gpg --verify macos-lite-*.iso.sha256.sig macos-lite-*.iso.sha256

# 3. Verify the ISO against the checksums
sha256sum -c macos-lite-*.iso.sha256
```

If signature verification fails, do not boot the ISO — re-download.

---

## 2. Create bootable media

```bash
# Linux (replace /dev/sdX with your USB device — WARNING: data will be erased)
sudo dd if=macos-lite-*.iso of=/dev/sdX bs=4M status=progress conv=fsync

# Or use Etcher / Fedora Media Writer / Rufus (Windows/macOS)
```

The ISO is hybrid: it boots on both BIOS (MBR) and UEFI systems.

---

## 3. Boot & install

1. Insert the USB and boot from it (may require pressing a boot-menu key: F12, Esc, F2, etc.).
2. Choose **macOS-Lite (live)** from the GRUB menu.
3. The live desktop starts automatically (autologin). You'll see:
   - Top bar (system menu, indicators, clock)
   - Dock at the bottom
   - Wayfire compositor with animations
4. Open **System Settings** (gear icon) or launch **Calamares** from the app menu (Super+Space → "Install").
5. Follow the Calamares installer:
   - Keyboard, timezone, user account, password.
   - Disk partitioning (erase disk or manual).
   - Install bootloader (GRUB) to the EFI system partition or MBR.
6. Reboot and remove the USB.

### Advanced / text installer

For expert installs, choose **macOS-Lite (install to disk)** which launches the
Debian installer (debian-installer) in text mode.

---

## 4. First boot after install

- You are autologged in as the user you created.
- The top bar, dock, and notifications start automatically.
- Open **System Settings** to configure Wi-Fi, Bluetooth, dark mode, displays.
- Press **Super + Space** for Spotlight-like search (apps, files, settings).

---

## 5. Updates

macOS-Lite is based on Debian Stable. Updates are security and critical bug
fixes only — no feature churn.

```bash
# Update package lists and install updates
sudo apt-get update
sudo apt-get upgrade

# For a full upgrade (rarely needed on Stable)
sudo apt-get full-upgrade
```

Unattended upgrades are disabled by default to avoid background CPU/RAM
usage. To enable automatic security updates:

```bash
sudo apt-get install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Major version upgrades

Debian Stable releases a new version roughly every 2 years. When a new stable
(Bookworm → next) is available:

1. Back up your data.
2. Read the official Debian release notes.
3. Run `sudo apt-get update && sudo apt-get upgrade`
4. Follow Debian's `debUpgrade` / `dist-upgrade` procedure.

macOS-Lite does not force upgrades; you control when to move to the next
stable release.

---

## 6. Firmware (Wi-Fi / GPU)

The **default** ISO is 100% DFSG-free and does not include proprietary
firmware. If your Wi-Fi or GPU needs non-free firmware:

- Use the `nonfree-firmware` variant ISO, OR
- After install: `sudo apt-get install firmware-linux-nonfree` (adds
  `contrib non-free-firmware` to your sources), then reboot.

---

## 7. Troubleshooting

| Problem | Fix |
|---------|-----|
| No Wi-Fi on live/install | Use nonfree-firmware ISO, or tether via USB phone and install `firmware-iwlwifi` etc. |
| Black screen after boot | Boot with "macOS-Lite (live, safe graphics)" (nomodeset), then install proper GPU drivers. |
| Installer won't start | Calamares needs a working live session; ensure you booted the live ISO, not the installer-only menu. |
| Sound not working | Ensure `pipewire` and `wireplumber` are running: `systemctl --user status pipewire wireplumber` |

Support: file issues at https://github.com/<org>/macos-lite-distro/issues
