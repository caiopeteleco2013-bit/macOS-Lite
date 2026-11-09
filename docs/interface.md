# macOS-Lite Interface Specification

Complete, working interface reproducing macOS interactions using only Free
Software (GTK4, LayerShell, Wayfire, wlroots). No Apple code, fonts, icons, or
artwork is used.

## Shell components (source in `src/`)

| Component | File | Trigger | macOS equivalent |
|-----------|------|---------|------------------|
| Top bar | `src/mlite-bar/mlite-bar.py` | Always on (Wayfire autostart) | Menu bar |
| Spotlight launcher | `src/mlite-launcher/mlite-launcher.py` | Super + Space | Spotlight |
| Control Center | `src/mlite-control-center/mlite-control-center.py` | Super + Shift + Space | Control Center |
| Notification Center | `src/mlite-notification-center/mlite-notification-center.py` | Click time / Super + C | Notification Center |
| Dock | `plank` (GPL) + `macos-lite` theme | Always on | Dock |
| Notifications | `dunst` (BSD-style) | System events | Notification banners |

## Top bar — `mlite-bar`

GTK4 + LayerShell exclusive-zone surface at the top, 34 px high.

```
┌─────────────────────────────────────────────────────────────────┐
│ macOS-Lite     [active window title]        􀤨 Wi-Fi  􀊩  􀛨  14:30  Oct 9 │
└─────────────────────────────────────────────────────────────────┘
  ↑ left                        ↑ center                 ↑ right
```

- **Left**: "macOS-Lite" menu button — opens Spotlight-like launcher (no Apple
  logo, no "Apple" name).
- **Center**: active-window title, polled from Wayfire via `wlrctl` every 500 ms.
- **Right**: Wi-Fi (nmcli), sound (PipeWire `wpctl`), battery (sysfs), clock.
- Clicking the time opens the Notification Center.
- Rounded corners, `Inter` font, translucent rgba background, blue `#0A84FF`
  accents.

## Spotlight-like launcher — `mlite-launcher`

Center-screen overlay (620×500), rounded 14 px, blue border.

- Search field reads all `.desktop` files from `/usr/share/applications` and
  `~/.local/share/applications`.
- Substring/fuzzy match on name, generic name, comment, categories.
- Keyboard: ↑/↓/Tab to navigate, Enter to launch, Esc to close.
- First result auto-highlighted; pressing Enter launches it.
- Launches via `Exec=` line with desktop field codes stripped.

## Control Center — `mlite-control-center`

Modal window (700×560), slide transition, grid of toggle rows:

| Row | Backend |
|-----|---------|
| Wi-Fi | `nmcli radio wifi toggle` |
| Bluetooth | `bluetoothctl power on/off` |
| Sound | `pavucontrol` |
| Displays | `gnome-control-center display` |
| Appearance | `gsettings color-scheme` (dark/light) |
| About | version + license dialog |

## Notification Center — `mlite-notification-center`

Slide-out overlay anchored top-right, 340 px wide.

- Reads `~/.cache/dunst/history` (dunst notification history).
- Shows app name, title, body for recent notifications.
- "Clear All" restarts dunst to clear history.
- Mini calendar for current month, today highlighted.

## Dock — Plank + `macos-lite` theme

Plank at the bottom, 48 px icons with 1.5× zoom on hover.

Theme `macos-lite` (original, in `/usr/share/plank/themes/macos-lite/`):
- Rounded rectangle radius 22, translucent fill, separators between items.
- `PinOnLaunch = true`, `HideMode = Intelligent`.

## Window management — Wayfire

| macOS gesture | Wayfire binding |
|---------------|-----------------|
| Super + Space | Spotlight launcher |
| Super + Q/W | Close window |
| Super + H | Minimize / tile |
| Super + M | Maximize |
| Super + Arrows | Move focus |
| Super + Shift + Arrows | Move window |
| Super + 1–4 | Switch workspace (4 workspaces) |
| Super + Tab | Window switcher |
| Super + ` | Expo (Mission Control) |
| 4-finger swipe | Swipe workspaces |

Compositor effects: fade, wobbly, scale, dim (inactive windows 55%), smooth 120–180 ms animations.

## Visual style (theme in `src/common/theme.css`)

- Font: Inter (UI), JetBrains Mono (monospace)
- Accent: `#0A84FF` (macOS-like blue)
- Base: `#F2F2F7` light / `#1C1C1E` dark
- Rounded corners: 6–16 px depending on surface
- Buttons: traffic-light colors for close/minimize/maximize (client-side)

## Avoiding Apple IP

| macOS element | macOS-Lite equivalent | Apple IP avoided |
|---------------|----------------------|------------------|
| Apple menu () | "macOS-Lite" text button |  logo, "Apple" name |
| Dock | plank + original theme | "Dock" trade dress |
| SF Pro font | Inter (SIL OFL) | SF Pro trademark |
| macOS icons | Papirus (CC0/CC-BY) | Apple icon artwork |
| Wallpapers | original CC0 geometry | Apple photography |
| "Control Center" name | "System Settings" panel | Apple feature names |

## Packaging & install

Shell components are staged by `config/hooks/0250-install-shell.hook.chroot`
from `config/includes.chroot/opt/macos-lite/src/` into `/usr/bin/`, chmod +x.
Desktop files ship in
`config/includes.chroot/usr/share/applications/`.

Wayfire autostarts `mlite-bar`, `plank`, `dunst` via
`config/xdg/wayfire/config.ini` `[autostart]`.

Build locally:
```bash
./scripts/build-iso.sh default
./scripts/qemu-smoke.sh build/image/macos-lite-default-amd64-*.iso
```
