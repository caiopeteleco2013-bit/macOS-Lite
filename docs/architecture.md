# High-Level Architecture

This document captures the architecture decisions for macOS-Lite, the
justification for each trade-off, and the exact stack used to reproduce a
macOS-like experience without Apple trademarks or art assets.

---

## 1. Base distribution: Debian Stable (minimal)

**Recommendation:** Debian Stable (bookworm) minimal netinst, built with
`live-build` + `debootstrap`.

### Why Debian

| Criterion | Debian | Assessment |
|-----------|--------|------------|
| **Stability** | Stable receives only security & critical bug fixes; ABI/API stable across the release. | Excellent — ideal for a "just works" desktop OS. |
| **Size** | `debootstrap` minimal base is ~250–300 MB installed; live-build trims aggressively. | Excellent — small base, easy to keep ISO < 1.2 GB. |
| **Tooling** | `live-build` is the canonical, well-documented Debian live-image builder. `apt`/`apt-cache`/`aptitude` mature. | Best-in-class for reproducible, auditable ISO builds. |
| **Package universe** | ~60k packages, all with clear license metadata in `debian/copyright`. | Excellent for default-app selection and licensing audits. |
| **Reproducibility** | Debian Reproducible Builds effort; `SOURCE_DATE_EPOCH` supported by live-build/debootstrap. | Strong — aligns with CI reproducibility goal. |
| **Hardware support** | Wide driver/firmware coverage (non-free firmware available separately). | Good for out-of-the-box Wi-Fi/GPU. |

### Trade-offs considered

- **Ubuntu minimal:** Larger base, Snap mandatory for some stacks, Canonical CLA/telemetry concerns, less "minimal" purity. Rejected for a lightweight, clean design.
- **Arch base:** Rolling = less stability predictability; `archiso` is capable but the ecosystem is more DIY and less auditable for reproducible ISO signing. Rejected for a stability-first target.
- **Fedora minimal:** Excellent tooling (`lorax`, `koji`) but faster release cycle, stricter separation of free/non-free, and `dnf` metadata churn complicate reproducible caching. Rejected in favor of Debian's stability + `live-build` maturity.

**Decision:** Debian Stable minimal. Firmware (non-free) is offered as a separate opt-in netinst variant to keep the default image 100% DFSG-free.

---

## 2. Desktop stack

### Compositor: Wayfire (Wayland, wlroots-based)

**Recommendation:** Wayfire as the Wayland compositor.

| Requirement | How Wayfire satisfies it |
|-------------|--------------------------|
| Wayland (modern, tear-free, smooth) | Native Wayland compositor built on wlroots. |
| Lightweight | ~60–100 MB RAM; config-driven, no heavy DE services. |
| macOS-like animations | Built-in effects: fade, scale, zoom, wobbly, dim, inactive dim, fire/cube (disabled by default). Configurable duration/easing. |
| Window rules / tiling-ish | `workarounds`, `window-rules`, multiple workspaces, focus-follows-mouse, click-to-focus. |
| Extensible | `wayfire` config (INI-style) + plugins written in C++ or via `wf-shell`. |

**Not chosen:**
- **labwc:** Extremely light but fewer built-in animations; more manual to make "polished."
- **Hyprland:** Great animations but heavier config drift and NVIDIA-specific quirks; less conservative for a stable base.
- **X11 / Xfce / Openbox:** X11 lacks tear-free, modern HiDPI, and smooth animation story. Rejected for a "smooth, polished" goal.
- **GNOME / KDE Plasma / Pantheon:** Too heavy (800 MB–1.5 GB idle RAM), diverge from lightweight goal, and Pantheon is tightly coupled to elementary OS. Rejected.

### Shell / UI (custom, Qt-free, GTK4 + LayerShell)

To reproduce macOS UI pieces exactly, we write a small custom shell in **Python 3 + GTK4 + LayerShell** (or a minimal C/GTK4 variant). Wayfire does *window management*; our shell does *chrome* (dock, bar, control center, notification area, search).

| macOS feature | macOS-Lite implementation | Technology |
|---------------|---------------------------|------------|
| **Top bar** (Apple menu → Apple logo replaced) | Top-center app menu + right-side system indicators (Wi-Fi, sound, battery, time) | Custom GTK4 LayerShell panel (`mlite-bar`) |
| **Dock** | Persistent bottom dock, icon magnification on hover, app launchers + open-app indicators | `plank` (lightweight, GPL, macOS-like) OR custom GTK4 dock; default = plank + theme |
| **Control Center** | Grid of toggles (Wi-Fi, Bluetooth, sound, brightness, dark mode, display, users) | Custom GTK4 app (`mlite-control-center`) |
| **Notification Center** | Slide-out panel with notifications + calendar | `dunst` (lightweight, highly themeable, macOS-like bubbles) + custom panel |
| **Spotlight-like search** | Global hotkey (Cmd/Super + Space) fuzzy app + file + settings launcher | `wofi` (Wayland dmenu-like, fast, themeable) |
| **Window management** | Wayfire: workspaces, focus follows mouse, click-to-focus, snap edges, alt-tab | `wayfire` config + `wlr-randr` for displays |
| **Hot corners** | Corners trigger mission control / desktop / screensaver | Wayfire `workarounds` / custom helper |
| **Gestures** | 3/4-finger swipe between workspaces | Wayfire `gestures` plugin (libinput) |

#### Default theme (Apple-inspired, no Apple assets)

- Colors: SF Pro-like palette built from scratch (light #FFFFFF / #F2F2F7 chrome, dark #000000 / #1C1C1E), accent blue #0A84FF.
- Rounded corners: 8–12 px on panels/windows (CSS via GTK4).
- Fonts: **Inter** (SIL Open Font License) system UI; **JetBrains Mono** (SIL OFL) monospace. Neither is Apple's SF Pro, avoiding trademark/licensing issues.
- Icons: **Papirus** or **Papirus-Dark** (CC0/CC-BY) adapted; no Apple-logo-shaped icons.
- Wallpaper: abstract gradient/geometry, original, CC0.

All assets live in `assets/` with an accompanying `ASSET-LICENSES.md` report.

---

## 3. Default package selection

Tiered by install profile. Chroot package lists live in `config/package-lists/`.

**Core (always):**
`linux-image-amd64`, `firmware-linux-free`, `grub-pc`/`grub-efi-amd64`, `systemd`, `network-manager`, `wayfire`, `wayfire-plugins-extra`, `wofi`, `plank`, `dunst`, `pipewire`, `pipewire-pulse`, `seatd`, `dbus`, `udisks2`, `polkitd`, `sudo`, `bash`, `coreutils`, `util-linux`, `openssh-client`, `nano`.

**Desktop shell (GTK4):**
`gtk4`, `libgtk-4-dev` (build), `liblayershell0-dev`, `python3-gi`, `python3-cairo`, `gir1.2-gtk-4.0`, `gir1.2-glayer-shell-0.1`, `adwaita-icon-theme` (reference only, not default), `papirus-icon-theme`.

**Default apps:**
- Browser: `firefox-esr` (DFSG-free, lightweight-ish) — or `chromium` optional.
- Terminal: `foot` (Wayland-native, fast, lightweight).
- Editor: `nano` + `gedit` (lightweight GUI editor).
- File manager: `thunar` (lightweight, GTK3) or `pcmanfm-qt`; default = thunar.
- Image viewer: `viewnior`.
- PDF: `atril` or `evince-lite`.
- Settings: custom `mlite-control-center` + `mlite-bar` (built from `src/` in a later phase).

**Excluded (by design):** snapd, flatpak (opt-in), LibreOffice (optional install), printer stack (CUPS opt-in), bluetooth firmware non-free (opt-in).

Full lists: `config/package-lists/chroot.list`, `config/package-lists/binary.list`.

---

## 4. Minimal system requirements & performance goals

| Resource | Minimum | Recommended | Target |
|----------|---------|-------------|--------|
| RAM | 2 GB | 4 GB | Idle ≤ 600 MB |
| CPU | x86_64 dual-core 1.5 GHz | x86_64 quad-core 2.4 GHz | Idle < 5 % |
| Storage | 16 GB | 32 GB+ SSD | ISO < 1.2 GB |
| GPU | Any wlroots-compatible (Intel/AMD/NVIDIA via EGLStream) | Intel UHD 620+ / AMD / NVIDIA | 60 fps UI |

### Boot-time & service tuning

- `systemd` default target = graphical; disable bluetooth, cups, avahi-daemon, ModemManager, `rsyslog` (use journald with size cap), `unattended-upgrades` (manual/security-only).
- `network-manager-wait-online` masked (don't block boot on network).
- `journalctl` max size 50 MB, `SystemMaxUse=50M`.
- Disable getty on unused VTs.
- `wayfire` started via `systemd --user` + `seatd`, no display manager (autologin to shell) for fastest boot; optional `greetd` + `tuigreet` if a login screen is desired.

### Responsiveness tuning

- `vm.swappiness=10`, `vm.vfs_cache_pressure=50`.
- `zram` enabled by default (zram-generator) for compress in-RAM swap.
- `wayfire` vsync on, `damage` tracking, reduced effects on battery.
- Preload not used (minimizes RAM); instead `systemd-analyze` + `bootchartd` to audit boot.

---

## 5. Reproducible build notes

- `live-build` with `SOURCE_DATE_EPOCH` set.
- Packages pinned to Debian Stable (`bookworm`) + security only; no `testing`/`unstable`.
- `lb config` uses `--architectures amd64 --linux-flavours amd64 --mode debian`.
- SquashFS compression: `xz` with `-Xbcj x86 -b 1M` for reproducibility.
- ISO image built with `xorriso` + `grub-mkrescue` equivalents via live-build.
- Build occurs in a clean container (GitHub Actions) with a fixed base image (`debian:bookworm`).
