# Desktop stack — reproducing macOS interactions (no Apple assets)

This document specifies the exact components and configuration used to reproduce
each macOS-like interaction. Wayfire owns window management; a small custom GTK4
shell owns the chrome. No Apple code, icons, fonts, or artwork is used.

## Component map

```
┌─────────────────────────────────────────────────────────┐
│  macOS-Lite custom shell (Python + GTK4 + LayerShell)   │
│  ├─ mlite-bar        (top bar / system menu / clock)    │
│  ├─ mlite-cc         (control center)                   │
│  ├─ mlite-notif      (notification-center panel)        │
│  └─ mlite-launcher   (wofi wrapper = Spotlight search)  │
├─────────────────────────────────────────────────────────┤
│  plank                     (dock, GPL, macOS-like)      │
│  dunst                     (notifications, BSD-like)    │
│  wofi                      (app/file/settings finder)   │
├─────────────────────────────────────────────────────────┤
│  Wayfire compositor (wlroots) — window mgmt, animations │
│  seatd / elogind           — seat management            │
│  pipewire                  — audio                      │
│  network-manager           — networking                 │
└─────────────────────────────────────────────────────────┘
```

---

## 1. Wayfire — compositor & window manager

Config: `config/includes.chroot/etc/xdg/wayfire/config.ini`

Key macOS-like settings:

```ini
[core]
# start on seat, no titlebar shadows from a DE
disable_startup_notification = true

[output]
# output-specific settings go here (per monitor)

[workarounds]
# macOS: no focus stealing, no client-side decorations for old apps
inhibit_idle = false
focus_feedback = true

[view]
# honor client side decorations, but apply our own frame rules
maximized_are_fullscreen = true

[workspace]
workspaces = 4

[window-rules]
# example: terminal always centered, browser fullscreen on workspace 2
# rules are matched by app-id / title

[wobbly]
enabled = true          # macOS-like window drag feedback
duration = 150

[fade]
enabled = true
duration = 120

[scale]
enabled = true          # "Mission Control" equivalent (Super + ↑ or hot corner)
duration = 150

[dim]
enabled = true
inactive_dim = 0.55     # dim unfocused windows (macOS vibe)

[animation]
# workspaces & view appear/disappear with ease-out
duration = 180

[gestures]
workspace_swipe = true   # 4-finger swipe between desktops

[expo]
enabled = true           # overview of all workspaces

[cube]
enabled = false          # keep it clean, not gimmicky

[switcher]
# Alt-Tab like macOS Cmd-Tab
mode = window
```

Session launch (`config/includes.chroot/etc/xdg/wayfire/session` or systemd user unit):
```ini
# ~/.config/systemd/user/wayfire.service
[Unit]
Description=Wayfire compositor
After=graphical-session.target

[Service]
ExecStart=/usr/bin/wayfire
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

---

## 2. Top bar — `mlite-bar` (custom GTK4 LayerShell)

A full-width LayerShell surface at `top`, exclusive-zone, ~34 px high.

Layout (left → center → right):
- **[Left]** "macOS-Lite" menu button (text only, no Apple logo) → app grid / system menu.
- **[Center]** active window title (from Wayfire via `wlrctl`/`wlroots` IPC or a small `wayfire` plugin emitting title changes).
- **[Right]** indicators: accessibility, VPN, sound (pipewire), battery (upower), network (nmcli), date/time.

Implementation notes:
- Language: Python 3 (`gi.repository.Gtk4`, `Gio`, `GLayerShell`).
- LayerShell layer = `top`, keyboard-interactivity = none for indicators, anchor = top+left+right.
- CSS: transparent/rgba background, 8px radius, no border, system font Inter 11.
- Autostarted by Wayfire session (`.config/wayfire.ini` `[autostart]` or session script).

Avoid Apple trademarks: menu button says "macOS-Lite" or a generic geared/apple-shaped **original** glyph; never ``.

---

## 3. Dock — `plank`

Plank is GPL, actively maintained, lightweight, and has a native macOS look.

Config (`config/includes.chroot/etc/xdg/plank/dock1.settings`):
```ini
[Dock1]
# position
Screen = 0
Monitor = 0
IconSize = 48
ZoomAmount = 1.45
HideMode = Intelligent
HideDelay = 500
UnhideDelay = 100
Offset = 0
ItemsAlign = Center
PinOnLaunch = true
LauncherPosition = 0

Theme = Gtk+         # or a custom macOS-like theme in assets/icons/plank-theme
Current = Gtk+
Position = Bottom
```

Theme: create `assets/icons/plank-theme/` (CC0) with rounded dock background and separator. Dock items are `.desktop` files from `/usr/share/applications` + `~/.local/share/applications`.

Avoid Apple: no "Dock" trademarked styling claims in docs; call it "the dock". Icons are Papirus-derived, not macOS icons.

---

## 4. Control center — `mlite-control-center` (custom GTK4 app)

Grid view toggles, super+Search or menu → "System Settings":

| Tile | Backend |
|------|---------|
| Wi-Fi | `nmcli` / NetworkManager DBus |
| Bluetooth | `bluetoothctl` / BlueZ DBus (opt-in firmware) |
| Sound | PipeWire (`pw-cli` / `wpctl`) |
| Brightness | `brightnessctl` / `ddcutil` |
| Dark/light mode | GTK `settings-gtk-application-prefer-dark-theme` |
| Displays | `wlr-randr` + Wayfire output config |
| Users | `accounts-daemon` / `useradd` DBus |
| About | `lsb_release`, kernel, version |

Launch: hotkey or top-bar rightmost gear icon. Implemented as a modal GTK4 window (layer=overlay, center, 700×560).

---

## 5. Notification center — `dunst` + panel

`dunst` is lightweight, BSD-style license, highly themeable.

Config (`config/includes.chroot/etc/dunst/dunstrc`):
```ini
[global]
    monitor = 0
    follow = none
    geometry = "300x5-30+30"
    indicate_hidden = yes
    shrink = no
    sort = yes
    idle_threshold = 120
    font = Inter 11
    line_height = 0
    transparency = 0
    icon_position = left
    sticky_history = yes
    history_length = 20
    show_age_threshold = 60
    word_wrap = yes
    ellipse_length = 50
    ignore_newline = no
    stack_duplicates = true
    hide_duplicate_count = no
    show_indicators = yes

    frame_width = 0
    frame_color = "#aaaaaa"

    separator_height = 2
    padding = 10
    horizontal_padding = 10

    startup_notification = false
    dmenu = /usr/bin/wofi --dmenu

    mouse_left_click = close
    mouse_middle_click = do_action, close
    mouse_right_click = close
    mouse_scroll_up = prev, do_action
    mouse_scroll_down = next, do_action

    filter = ""

[shortcuts]
    close = ctrl+shift+space
    close_all = ctrl+shift+period
    history = ctrl+shift+grave
    context = ctrl+shift+semicolon

[urgency_low]
    background = "#2e3440"
    foreground = "#d8dee9"
    timeout = 10
    icon = /usr/share/icons/Papirus/16x16/apps/...

[urgency_normal]
    background = "#2e3440"
    foreground = "#d8dee9"
    timeout = 10

[urgency_critical]
    background = "#bf616a"
    foreground = "#d8dee9"
    timeout = 0
```

A "Notification Center" panel (custom GTK4) reads `~/.cache/dunst/history` and shows recent notifications with a calendar; triggered by top-right clock click (macOS: click date/time → Notification Center).

---

## 6. Spotlight-like search — `wofi`

`wofi` is a Wayland-native dmenu/rofi alternative, MIT/GPL, very fast.

Launcher (`mlite-launcher` wrapper, bound to `Super+Space` in Wayfire `[bindings]`):
```ini
[bindings]
# Super + Space = Spotlight-like search
<super> KEY_SPACE = exec wofi --show drun --prompt "Search" \
    --width 500 --height 400 --cache-file /var/cache/wofi/applications.cache \
    --normal-window --allow-images --show-drun
```

`wofi --show drun` reads `.desktop` files → app search. For file/settings search, a secondary mode uses `locate`/`fd` over `$HOME` + settings `.desktop` entries. Theme CSS to match top bar (rounded, Inter font, blue accent).

---

## 7. Avoiding Apple trademarks & art assets

| macOS element | macOS-Lite equivalent | Apple IP avoided |
|---------------|----------------------|------------------|
| Apple menu () | "macOS-Lite" text menu button + original glyph |  logo, "Apple" name |
| Dock | plank (original dock UI) | "Dock" trade dress claims avoided in branding |
| SF Pro font | Inter / JetBrains Mono (SIL OFL) | SF Pro trademark/license |
| macOS icons | Papirus (CC0/CC-BY) + original icons | Apple icon artwork |
| "Control Center" name | generic "System Settings" panel | avoid claiming Apple feature names |
| Wallpapers | original CC0 geometry/gradient | Apple wallpaper photography |

Brand name: **macOS-Lite** is descriptive ("macOS-like, lightweight"). In final release branding we recommend confirming trademark clearance for "macOS-Lite" or choosing an original name (e.g., "LiteDesk", "Horizon"). All code/assets in this repo are original or openly licensed.

---

## 8. Startup order (systemd user session)

1. `seatd` → grants input/DRM access.
2. `wayfire` (compositor).
3. Wayfire autostarts: `mlite-bar`, `plank`, `dunst`, `nm-applet` (or nm-cli indicator), `mlite-control-center` (lazy), `wofi` cache warmer.
4. User logs in automatically (or via `greetd`+`tuigreet`).
