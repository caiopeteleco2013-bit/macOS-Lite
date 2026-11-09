#!/usr/bin/env python3
"""
mlite-control-center — macOS-Lite System Settings / Control Center.

A modal GTK4 window with a grid of toggles:
  Wi-Fi, Bluetooth, Sound, Brightness, Dark mode, Displays, Users, About.

Triggered from the top bar gear / menu. Original code. No Apple assets.
"""
import gi
import subprocess

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")

from gi.repository import Gtk, GLib, Gdk  # noqa: E402


def run(cmd, timeout=3):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL,
                                       timeout=timeout, text=True).strip()
    except Exception:
        return ""


class ToggleRow(Gtk.Box):
    """A control-center row: icon + label + switch."""

    def __init__(self, icon, label, subtitle, on_toggle, active=False):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        self.set_halign(Gtk.Align.FILL)
        self.set_valign(Gtk.Align.CENTER)
        self.set_margin_top(10)
        self.set_margin_bottom(10)
        self.set_margin_start(20)
        self.set_margin_end(20)
        self.add_css_class("cc-row")

        icon_lbl = Gtk.Label(label=icon)
        icon_lbl.add_css_class("cc-icon")
        icon_lbl.set_halign(Gtk.Align.START)
        self.append(icon_lbl)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_hexpand(True)
        text_box.set_halign(Gtk.Align.START)

        name = Gtk.Label(label=label)
        name.add_css_class("cc-name")
        name.set_halign(Gtk.Align.START)
        name.set_xalign(0)
        text_box.append(name)

        if subtitle:
            sub = Gtk.Label(label=subtitle)
            sub.add_css_class("cc-sub")
            sub.set_halign(Gtk.Align.START)
            sub.set_xalign(0)
            text_box.append(sub)

        self.append(text_box)

        sw = Gtk.Switch()
        sw.set_active(active)
        sw.connect("state-set", lambda s, v: GLib.idle_add(on_toggle, v))
        sw.add_css_class("cc-switch")
        self.append(sw)

    def set_active(self, active):
        for child in self:
            if isinstance(child, Gtk.Switch):
                child.set_active(active)


class CCPage(Gtk.Box):
    """Base control-center page."""

    def __init__(self, on_back):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_hexpand(True)
        self.set_vexpand(True)
        self._on_back = on_back

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        header.set_halign(Gtk.Align.FILL)
        header.set_margin_top(14)
        header.set_margin_bottom(14)
        header.set_margin_start(20)
        header.set_margin_end(20)

        back = Gtk.Button(label="‹  Back")
        back.add_css_class("cc-back")
        back.set_halign(Gtk.Align.START)
        back.connect("clicked", lambda b: GLib.idle_add(on_back))
        header.append(back)

        self.title = Gtk.Label(label="Control Center")
        self.title.add_css_class("cc-page-title")
        self.title.set_halign(Gtk.Align.CENTER)
        self.title.set_hexpand(True)
        header.append(self.title)

        self.append(header)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        self.content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.content.set_halign(Gtk.Align.FILL)
        self.content.set_margin_top(10)
        self.content.set_margin_bottom(10)
        self.content.set_margin_start(20)
        self.content.set_margin_end(20)
        scrolled.set_child(self.content)
        self.append(scrolled)

        self.add_css_class("cc-page")

    def add_row(self, icon, label, subtitle, callback, active=False):
        row = ToggleRow(icon, label, subtitle, callback, active)
        self.content.append(row)
        return row

    def set_title(self, text):
        self.title.set_label(text)


class ControlCenterWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(700, 560)
        self.set_position(Gtk.WindowPosition.CENTER)

        self.set_title("macOS-Lite — System Settings")
        self.add_css_class("cc-window")

        # Main stack: home page + sub pages
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(250)

        self.home = CCPage(self._close)
        self.home.set_title("Control Center")
        self.stack.add_titled(self.home, "home", "Control Center")

        self.stack.set_visible_child_name("home")
        self.set_child(self.stack)

        self._build_home()
        self._apply_css()

    def _build_home(self):
        h = self.home

        # Wi-Fi
        h.add_row("􀤨", "Wi-Fi", "Wireless networking",
                  lambda v: self._run("nmcli", "radio", "wifi", "toggle"),
                  active="enabled" in run("nmcli radio wifi"))
        # Bluetooth
        h.add_row("􀤊", "Bluetooth", "Wireless accessories",
                  lambda v: self._run("bluetoothctl", "power", "on" if v else "off"))
        # Sound
        h.add_row("􀊩", "Sound", "Output and input volume",
                  lambda v: self._run("pavucontrol"))
        # Brightness
        h.add_row("􀭤", "Displays", "Brightness and arrangement",
                  lambda v: self._run("gnome-control-center", "display"))
        # Dark mode
        dark = run("gsettings get org.gnome.desktop.interface color-scheme") == "'prefer-dark'"
        h.add_row("􀪹", "Appearance", "Light / dark mode",
                  lambda v: self._run("gsettings", "set",
                                      "org.gnome.desktop.interface",
                                      "color-scheme",
                                      "prefer-dark" if v else "prefer-light"),
                  active=dark)
        # About
        h.add_row("􀤀", "About", "Version and system information",
                  lambda v: self._show_about())

    def _run(self, *cmd):
        subprocess.Popen(list(cmd))

    def _show_about(self):
        dlg = Gtk.AboutDialog()
        dlg.set_program_name("macOS-Lite")
        dlg.set_version("1.0.0")
        dlg.set_comments("A lightweight, macOS-inspired desktop on Linux.")
        dlg.set_license_type(Gtk.License.MIT_X11)
        dlg.set_website("https://github.com/caiopeteleco2013-bit/macOS-Lite")
        dlg.set_transient_for(self)
        dlg.present()

    def _close(self):
        GLib.idle_add(Gtk.Application.get_default().quit)

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
        .cc-window {
            background-color: #f2f2f7;
            border-radius: 16px;
            border: 1px solid #d1d1d6;
            font-family: "Inter";
        }
        .cc-page {
            background: transparent;
        }
        .cc-back {
            background: transparent;
            border: none;
            border-radius: 6px;
            min-height: 26px;
            color: #0a84ff;
            font-weight: 500;
            padding: 0;
        }
        .cc-back:hover {
            background-color: rgba(10, 132, 255, 0.12);
        }
        .cc-page-title {
            font-size: 20px;
            font-weight: 600;
            color: #1d1d1f;
        }
        .cc-row {
            background-color: #ffffff;
            border-radius: 12px;
            border: 1px solid #e5e5ea;
            color: #1d1d1f;
        }
        .cc-icon {
            font-size: 18px;
            color: #0a84ff;
        }
        .cc-name {
            font-size: 15px;
            font-weight: 500;
            color: #1d1d1f;
        }
        .cc-sub {
            font-size: 12px;
            color: #86868b;
        }
        .cc-switch {
        }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


class ControlCenterApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.macoslite.controlcenter")

    def do_activate(self):
        self.win = ControlCenterWindow(self)
        self.win.present()


def main():
    import signal
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = ControlCenterApp()
    app.run(None)


if __name__ == "__main__":
    main()
