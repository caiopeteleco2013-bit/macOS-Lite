#!/usr/bin/env python3
"""
mlite-notification-center — macOS-Lite Notification Center.

Slide-out panel (top-right) showing recent notifications and a mini calendar.
Triggered by clicking the clock in the top bar. Reads dunst history.

Original code. No Apple code or assets. MIT licensed.
"""
import gi
import os
import time

gi.require_version("Gtk", "4.0")
gi.require_version("GLayerShell", "0.1")
gi.require_version("Gdk", "4.0")

from gi.repository import Gtk, GLib, GLayerShell, Gdk  # noqa: E402


def read_dunst_history():
    """Read recent notifications from dunst history cache."""
    path = os.path.expanduser("~/.cache/dunst/history")
    notes = []
    if not os.path.exists(path):
        return notes
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            data = f.read()
    except Exception:
        return notes
    # Dunst history is newline-separated records; each notification block starts
    # with a '[' timestamp line. We do a best-effort parse.
    blocks = data.split("\n\n")
    for block in blocks[-20:]:
        lines = [l for l in block.splitlines() if l.strip()]
        if not lines:
            continue
        title = ""
        body = ""
        app = "Notification"
        for l in lines:
            if l.startswith("appname="):
                app = l.split("=", 1)[1].strip('"') or app
            elif l.startswith("summary="):
                title = l.split("=", 1)[1].strip('"')
            elif l.startswith("body="):
                body = l.split("=", 1)[1].strip('"')
        notes.append({"app": app, "title": title, "body": body})
    return notes


class NotificationItem(Gtk.Box):
    def __init__(self, note):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_halign(Gtk.Align.FILL)
        self.set_margin_top(8)
        self.set_margin_bottom(8)
        self.set_margin_start(16)
        self.set_margin_end(16)
        self.add_css_class("notif-item")

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.set_halign(Gtk.Align.FILL)
        app = Gtk.Label(label=note["app"])
        app.add_css_class("notif-app")
        app.set_halign(Gtk.Align.START)
        header.append(app)
        time_lbl = Gtk.Label(label="now")
        time_lbl.add_css_class("notif-time")
        time_lbl.set_halign(Gtk.Align.END)
        time_lbl.set_hexpand(True)
        header.append(time_lbl)
        self.append(header)

        if note["title"]:
            title = Gtk.Label(label=note["title"])
            title.add_css_class("notif-title")
            title.set_halign(Gtk.Align.START)
            title.set_xalign(0)
            self.append(title)
        if note["body"]:
            body = Gtk.Label(label=note["body"])
            body.add_css_class("notif-body")
            body.set_halign(Gtk.Align.START)
            body.set_xalign(0)
            body.set_wrap(True)
            body.set_max_width_chars(60)
            self.append(body)


class NotificationCenterWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(340, 520)

        shell = GLayerShell.Shell()
        shell.set_layer(self, GLayerShell.Layer.OVERLAY)
        shell.set_anchor(self,
                         GLayerShell.Edge.TOP |
                         GLayerShell.Edge.RIGHT)
        shell.set_exclusive_zone(self, -1)
        shell.set_margin(self, GLayerShell.Edge.TOP, 44)   # below top bar
        shell.set_margin(self, GLayerShell.Edge.RIGHT, 12)
        shell.set_keyboard_interactivity(self, True)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.add_css_class("nc-root")
        root.set_valign(Gtk.Align.START)
        root.set_hexpand(False)
        self.set_child(root)

        # Header: "Notification Center" + clear
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        header.set_halign(Gtk.Align.FILL)
        header.set_margin_top(12)
        header.set_margin_bottom(10)
        header.set_margin_start(16)
        header.set_margin_end(16)

        title = Gtk.Label(label="Notification Center")
        title.add_css_class("nc-title")
        header.append(title)
        clear = Gtk.Button(label="Clear All")
        clear.add_css_class("nc-clear")
        clear.set_halign(Gtk.Align.END)
        clear.set_hexpand(True)
        clear.connect("clicked", lambda b: self._clear())
        header.append(clear)
        root.append(header)

        separator = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        separator.add_css_class("nc-sep")
        root.append(separator)

        # Notifications list
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_vexpand(True)
        scrolled.set_hexpand(True)
        self.notif_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.notif_box.set_halign(Gtk.Align.FILL)
        self.notif_box.set_margin_start(16)
        self.notif_box.set_margin_end(16)
        self.notif_box.set_margin_top(10)
        self.notif_box.set_margin_bottom(10)
        scrolled.set_child(self.notif_box)
        root.append(scrolled)

        # Calendar mini-view
        cal_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        cal_box.set_halign(Gtk.Align.FILL)
        cal_box.set_margin_top(14)
        cal_box.set_margin_bottom(12)
        cal_box.set_margin_start(16)
        cal_box.set_margin_end(16)
        cal_lbl = Gtk.Label(label=time.strftime("%B %Y"))
        cal_lbl.add_css_class("nc-cal-title")
        cal_lbl.set_halign(Gtk.Align.START)
        cal_box.append(cal_lbl)

        self.cal_grid = Gtk.Grid()
        self.cal_grid.add_css_class("nc-cal-grid")
        self.cal_grid.set_column_homogeneous(True)
        cal_box.append(self.cal_grid)
        root.append(cal_box)

        empty = Gtk.Label(label="No notifications")
        empty.add_css_class("nc-empty")
        empty.set_halign(Gtk.Align.CENTER)
        empty.set_margin_top(40)
        self.notif_box.append(empty)
        self._empty_label = empty

        self._apply_css()
        self.refresh()

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
        .nc-root {
            background-color: #f2f2f7;
            border-radius: 0 0 12px 0;
            border-left: 1px solid #d1d1d6;
            border-bottom: 1px solid #d1d1d6;
            border-right: 1px solid #d1d1d6;
            font-family: "Inter";
            width: 340px;
        }
        .nc-title {
            font-size: 16px;
            font-weight: 600;
            color: #1d1d1f;
        }
        .nc-clear {
            background: transparent;
            border: none;
            border-radius: 6px;
            min-height: 24px;
            color: #0a84ff;
            font-size: 12px;
            font-weight: 500;
            padding: 0 8px;
        }
        .nc-clear:hover {
            background-color: rgba(10, 132, 255, 0.12);
        }
        .nc-sep {
            margin: 0;
        }
        .notif-item {
            border-radius: 10px;
            border: 1px solid #e5e5ea;
            background-color: #ffffff;
            color: #1d1d1f;
        }
        .notif-app {
            font-size: 12px;
            font-weight: 600;
            color: #86868b;
        }
        .notif-time {
            font-size: 11px;
            color: #a1a1a6;
        }
        .notif-title {
            font-size: 13px;
            font-weight: 600;
            color: #1d1d1f;
        }
        .notif-body {
            font-size: 12px;
            color: #4b4b4f;
        }
        .nc-empty {
            color: #86868b;
            font-size: 13px;
        }
        .nc-cal-title {
            font-size: 13px;
            font-weight: 600;
            color: #1d1d1f;
        }
        .nc-cal-grid {
        }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def refresh(self):
        for child in self.notif_box.get_children():
            self.notif_box.remove(child)
        notes = read_dunst_history()
        if not notes:
            empty = Gtk.Label(label="No notifications")
            empty.add_css_class("nc-empty")
            empty.set_halign(Gtk.Align.CENTER)
            empty.set_margin_top(40)
            self.notif_box.append(empty)
        else:
            for note in notes:
                self.notif_box.append(NotificationItem(note))
        self.notif_box.show()
        self._build_calendar()

    def _build_calendar(self):
        for child in self.cal_grid.get_children():
            self.cal_grid.remove(child)
        days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        for c, d in enumerate(days):
            lbl = Gtk.Label(label=d)
            lbl.add_css_class("nc-cal-day")
            lbl.set_halign(Gtk.Align.CENTER)
            self.cal_grid.attach(lbl, c, 0, 1, 1)
        import calendar
        cal = calendar.monthcalendar(time.localtime().tm_year,
                                     time.localtime().tm_mon)
        today = time.localtime().tm_mday
        for r, week in enumerate(cal, start=1):
            for c, day in enumerate(week):
                if day == 0:
                    continue
                lbl = Gtk.Label(label=str(day))
                lbl.set_halign(Gtk.Align.CENTER)
                if day == today:
                    lbl.add_css_class("nc-cal-today")
                self.cal_grid.attach(lbl, c, r, 1, 1)

    def _clear(self):
        subprocess.run(["pkill", "-HUP", "dunst"], check=False)
        GLib.timeout_add_seconds(1, self.refresh)
        return False


class NotificationCenterApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.macoslite.notificationcenter")

    def do_activate(self):
        self.win = NotificationCenterWindow(self)
        self.win.present()


def main():
    import signal
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = NotificationCenterApp()
    app.run(None)


if __name__ == "__main__":
    main()
