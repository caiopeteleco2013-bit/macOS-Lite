# mlite-bar — macOS-Lite top bar

GTK4 + LayerShell top bar. Placeholder stub; wire up:

- App menu button ("macOS-Lite", original glyph — no Apple logo)
- Active window title (from Wayfire via IPC / wlrctl)
- System indicators: sound (PipeWire), battery (upower), network (NetworkManager), clock

Build as a Debian package and install to /usr/bin/mlite-bar.
Autostart via /etc/xdg/autostart/mlite-bar.desktop (see config/hooks/0200-desktop-config.hook.chroot).

No Apple code/assets.