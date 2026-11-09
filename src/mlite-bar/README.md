# mlite-bar — macOS-Lite top bar

Reproduces the macOS menu bar using GTK4 + LayerShell.

Layout (left → center → right):
- **macOS-Lite menu button** (replaces the Apple menu) → opens Spotlight-like launcher
- **Active window title** (polled from Wayfire every 0.5s)
- **Status indicators**: Wi-Fi, Sound, Battery, Date/Time
- Click the **time** → opens Notification Center

## Key bindings (Wayfire)
| Binding | Action |
|---------|--------|
| Super + Space | Spotlight-like launcher (`mlite-launcher`) |
| Super + Shift + Space | Control Center (`mlite-control-center`) |
| Super + C | Notification Center (`mlite-notification-center`) |
| Super + Q / W | Close window |
| Super + H / M | Minimize / tile |
| Super + Arrows | Move focus / window |
| Super + 1-4 | Switch workspace |
| Super + Tab | Window switcher |
| Super + ` | Expo / Mission Control |

No Apple code or assets. MIT licensed.
