#!/usr/bin/env python3
"""
mlite-bar — macOS-Lite top bar.

A GTK4 + LayerShell top bar reproducing the macOS menu bar:
  Left  : Apple-menu replacement (opens app grid / system menu)
  Center: Active-window title (polled from Wayfire via wlrctl/IPC)
  Right : Status indicators — Wi-Fi, Bluetooth, sound, battery, date/time
          Clicking the time opens the Notification Center.

Original code. No Apple code or assets. MIT licensed.
"""
import gi
import signal
import subprocess
import threading
import time

gi.require_version("Gtk", "4.0")
gi.require_version("GLayerShell", "0.1")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")

from gi.repository import Gtk, GLib, GLayerShell, Gdk, Pango  # noqa: E402

ACCENT = "#0a84ff"
BAR_HEIGHT = 34
INTERVAL_TITLE = 0.5   # seconds between active-window title polls
INTERVAL_CLOCK = 1.0   # seconds between clock updates


def run(cmd, timeout=3):
    """Run a shell command, return stripped stdout or empty string."""
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL,
                                      timeout=timeout, text=True)
        return out.strip()
    except Exception:
        return ""


class StatusItem(Gtk.Box):
    """A single right-side status indicator with optional click action."""

    def __init__(self, icon, label="", tooltip="", callback=None):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.set_halign(Gtk.Align.END)
        self.set_valign(Gtk.Align.CENTER)
        self.set_margin_start(8)
        self.set_margin_end(8)
        self.set_margin_top(6)
        self.set_margin_bottom(6)
        self._callback = callback

        self.icon = Gtk.Label(label=icon)
        self.icon.add_css_class("status-icon")
        self.icon.set_halign(Gtk.Align.CENTER)
        self.icon.set_valign(Gtk.Align.CENTER)
        self.append(self.icon)

        if label:
            self.lbl = Gtk.Label(label=label)
            self.lbl.add_css_class("status-label")
            self.lbl.set_halign(Gtk.Align.START)
            self.lbl.set_valign(Gtk.Align.CENTER)
            self.append(self.lbl)

        if tooltip:
            self.set_tooltip_text(tooltip)

        if callback:
            self.set_click_callback(callback)

        self.add_css_class("status-item")

    def set_click_callback(self, callback):
        self._callback = callback
        self.set_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("button-press-event", self._on_click)

    def _on_click(self, widget, event):
        if self._callback:
            GLib.idle_add(self._callback)
        return True

    def set_text(self, text):
        if hasattr(self, "lbl"):
            self.lbl.set_label(text)

    def set_icon(self, icon):
        self.icon.set_label(icon)


class MenuButton(Gtk.Button):
    """Left-side menu button (replaces the Apple menu)."""

    def __init__(self, callback):
        super().__init__()
        self.set_label("macOS-Lite")
        self.add_css_class("menu-button")
        self.set_tooltip_text("macOS-Lite menu")
        self.connect("clicked", lambda b: GLib.idle_add(callback))
        self.set_halign(Gtk.Align.START)
        self.set_valign(Gtk.Align.CENTER)
        self.set_margin_start(10)


class WindowTitle(Gtk.Label):
    """Centered active-window title, updated by polling Wayfire."""

    def __init__(self):
        super().__init__(label="macOS-Lite")
        self.add_css_class("window-title")
        self.set_halign(Gtk.Align.CENTER)
        self.set_valign(Gtk.Align.CENTER)
        self.set_ellipsize(Pango.EllipsizeMode.END)
        self.set_max_width_chars(60)
        self.set_margin_top(2)
        self.set_margin_bottom(2)

    def update(self, title):
        if title and title.strip():
            self.set_label(title[:60])


class TopBar(Gtk.ApplicationWindow):
    """The LayerShell top bar window."""

    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(1, BAR_HEIGHT)

        # LayerShell: exclusive top layer spanning full width
        shell = GLayerShell.Shell()
        shell.set_layer(self, GLayerShell.Layer.TOP)
        shell.set_anchor(self,
                         GLayerShell.Edge.TOP |
                         GLayerShell.Edge.LEFT |
                         GLayerShell.Edge.RIGHT)
        shell.set_exclusive_zone(self, BAR_HEIGHT)
        shell.set_margin(self, GLayerShell.Edge.TOP, 0)

        # Root box
        root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        root.add_css_class("top-bar")
        root.set_halign(Gtk.Align.FILL)
        root.set_valign(Gtk.Align.FILL)
        root.set_height_request(BAR_HEIGHT)
        self.set_child(root)

        # ── Left: menu button ──
        self.menu_btn = MenuButton(self._open_menu)
        root.append(self.menu_btn)

        # ── Center: window title ──
        center_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        center_box.set_halign(Gtk.Align.CENTER)
        center_box.set_valign(Gtk.Align.CENTER)
        self.title = WindowTitle()
        center_box.append(self.title)
        root.append(center_box)

        # ── Right: status indicators ──
        right_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        right_box.set_halign(Gtk.Align.END)
        right_box.set_valign(Gtk.Align.CENTER)

        # Wi-Fi
        self.wifi = StatusItem("􀤨", tooltip="Wi-Fi", callback=self._toggle_wifi)
        right_box.append(self.wifi)

        # Sound
        self.sound = StatusItem("􀊩", tooltip="Sound", callback=self._toggle_sound)
        right_box.append(self.sound)

        # Battery
        self.battery = StatusItem("􀛨", tooltip="Battery", callback=self._toggle_battery)
        right_box.append(self.battery)

        # Date/time (click → notification center)
        self.clock = StatusItem("", tooltip="Open Notification Center",
                                callback=self._open_notification_center)
        self.clock.add_css_class("clock")
        self.clock.set_hexpand(False)
        right_box.append(self.clock)

        root.append(right_box)

        # Apply CSS
        self._apply_css()

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
        .top-bar {
            background-color: rgba(242, 242, 247, 0.85);
            border-bottom: 1px solid rgba(0,0,0,0.08);
            font-family: "Inter";
            font-size: 13px;
        }
        .menu-button {
            border-radius: 0;
            min-height: 22px;
            font-weight: 600;
            color: #1d1d1f;
            background: transparent;
            border: none;
            box-shadow: none;
        }
        .menu-button:hover {
            background-color: rgba(0,0,0,0.06);
        }
        .window-title {
            font-size: 13px;
            font-weight: 500;
            color: #1d1d1f;
            background: transparent;
        }
        .status-item {
            background: transparent;
            color: #1d1d1f;
        }
        .status-icon {
            font-size: 13px;
        }
        .status-label {
            font-size: 12px;
            color: #4b4b4f;
        }
        .clock {
            font-size: 13px;
            font-weight: 600;
            color: #1d1d1f;
            margin-end: 12px;
        }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    # ── callbacks ──
    def _open_menu(self):
        """Open the app/system menu (Spotlight-like launcher fallback)."""
        subprocess.Popen(["wofi", "--show", "drun", "--prompt", "Menu",
                          "--width", "500", "--height", "400"])

    def _toggle_wifi(self):
        subprocess.Popen(["nmcli", "radio", "wifi", "toggle"])

    def _toggle_sound(self):
        subprocess.Popen(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])

    def _toggle_battery(self):
        subprocess.Popen(["gnome-control-center", "power"])

    def _open_notification_center(self):
        subprocess.Popen(["mlite-notification-center"])

    # ── periodic updates ──
    def update_title(self):
        title = run(["wlrctl", "active-title"]) or run(["ydotool", "getactivewindow-title"])
        self.title.update(title)
        return True  # keep GLib timeout running

    def update_clock(self):
        now = time.strftime("%H:%M")
        date = time.strftime("%b %d")
        self.clock.set_label(f"{now}   {date}")
        return True

    def update_wifi(self):
        ssid = run(["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"])
        if ssid and ssid.startswith("yes:"):
            self.wifi.set_icon("􀤨")
            self.wifi.set_text(ssid.split(":", 1)[1] if ":" in ssid else "")
        else:
            self.wifi.set_icon("􀙖")
            self.wifi.set_text("")
        return True

    def update_sound(self):
        vol = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
        muted = "MUTED" in vol
        self.sound.set_icon("􀊠" if muted else "􀊩")
        return True

    def update_battery(self):
        cap = run(["cat", "/sys/class/power_supply/*/capacity"], timeout=2)
        status = run(["cat", "/sys/class/power_supply/*/status"], timeout=2)
        icon = "􀛨"
        if "Charging" in status:
            icon = "􀢋"
        elif "Discharging" in status:
            icon = "􀛨"
        self.battery.set_icon(icon)
        self.battery.set_text(cap if cap else "")
        return True


class BarApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.macoslite.bar")

    def do_activate(self):
        self.bar = TopBar(self)
        self.bar.show()

        # Polling loops
        GLib.timeout_add_seconds(int(INTERVAL_TITLE), self.bar.update_title)
        GLib.timeout_add_seconds(int(INTERVAL_CLOCK), self.bar.update_clock)
        GLib.timeout_add_seconds(5, self.bar.update_wifi)
        GLib.timeout_add_seconds(5, self.bar.update_sound)
        GLib.timeout_add_seconds(15, self.bar.update_battery)


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = BarApp()
    app.run(None)


if __name__ == "__main__":
    main()
