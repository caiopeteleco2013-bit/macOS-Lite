#!/usr/bin/env python3
"""
mlite-launcher — Spotlight-like application launcher.

Center-screen overlay with a search field and fuzzy-matched .desktop results.
Triggered by Super+Space (configured in Wayfire bindings).

Original code. No Apple code or assets. MIT licensed.
"""
import gi
import os
import subprocess

gi.require_version("Gtk", "4.0")
gi.require_version("GLayerShell", "0.1")
gi.require_version("Gdk", "4.0")

from gi.repository import Gtk, GLib, GLayerShell, Gdk  # noqa: E402


def parse_desktop(path):
    """Parse a minimal .desktop file into a dict."""
    entry = {}
    in_section = False
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line == "[Desktop Entry]":
                    in_section = True
                    continue
                if line.startswith("[") and in_section:
                    break
                if in_section and "=" in line:
                    k, v = line.split("=", 1)
                    entry[k.strip()] = v.strip()
    except Exception:
        return None
    if entry.get("NoDisplay") == "true":
        return None
    if entry.get("Terminal") == "true" and not entry.get("Icon"):
        pass
    return entry


def collect_apps():
    """Collect applications from system and user .desktop directories."""
    apps = []
    dirs = [
        "/usr/share/applications",
        os.path.expanduser("~/.local/share/applications"),
        "/usr/local/share/applications",
    ]
    seen = set()
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            if not name.endswith(".desktop"):
                continue
            path = os.path.join(d, name)
            entry = parse_desktop(path)
            if not entry:
                continue
            app_id = entry.get("Exec", name).split()[0]
            if app_id in seen:
                continue
            seen.add(app_id)
            apps.append({
                "name": entry.get("Name", name),
                "generic": entry.get("GenericName", ""),
                "comment": entry.get("Comment", ""),
                "exec": entry.get("Exec", ""),
                "icon": entry.get("Icon", "application-x-executable"),
                "categories": entry.get("Categories", ""),
                "path": path,
            })
    apps.sort(key=lambda a: a["name"].lower())
    return apps


class LauncherRow(Gtk.Box):
    """A single search result row."""

    def __init__(self, app, on_launch):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.set_halign(Gtk.Align.FILL)
        self.set_valign(Gtk.Align.CENTER)
        self.set_margin_top(6)
        self.set_margin_bottom(6)
        self.set_margin_start(14)
        self.set_margin_end(14)
        self.add_css_class("launcher-row")

        # Icon
        icon = Gtk.Image.new_from_icon_name(app["icon"])
        icon.set_pixel_size(32)
        icon.set_halign(Gtk.Align.START)
        self.append(icon)

        # Text
        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_halign(Gtk.Align.START)
        text_box.set_vexpand(True)

        name = Gtk.Label(label=app["name"])
        name.add_css_class("launcher-name")
        name.set_halign(Gtk.Align.START)
        name.set_xalign(0)
        text_box.append(name)

        sub = []
        if app["generic"]:
            sub.append(app["generic"])
        if app["comment"]:
            sub.append(app["comment"])
        if sub:
            sub_lbl = Gtk.Label(label="  •  ".join(sub))
            sub_lbl.add_css_class("launcher-sub")
            sub_lbl.set_halign(Gtk.Align.START)
            sub_lbl.set_xalign(0)
            text_box.append(sub_lbl)

        self.append(text_box)

        # Right arrow / hotkey area (spacer)
        end = Gtk.Box()
        end.set_hexpand(True)
        end.set_halign(Gtk.Align.END)
        self.append(end)

        self._app = app
        self._on_launch = on_launch
        self.set_events(Gdk.EventMask.BUTTON_PRESS_MASK |
                        Gdk.EventMask.ENTER_NOTIFY_MASK)
        self.connect("button-press-event", self._on_click)
        self.connect("enter-notify-event", self._on_enter)

    def _on_click(self, widget, event):
        GLib.idle_add(self._launch)
        return True

    def _on_enter(self, widget, event):
        self.add_css_class("launcher-row-hover")
        return False

    def _launch(self):
        exec_cmd = self._app["exec"]
        # Strip desktop field codes %f, %u, etc.
        import re
        exec_cmd = re.sub(r"%[fFuUknci]", "", exec_cmd).strip()
        subprocess.Popen(exec_cmd, shell=True)
        GLib.idle_add(Gtk.Application.get_default().quit)


class LauncherWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(620, 500)

        shell = GLayerShell.Shell()
        shell.set_layer(self, GLayerShell.Layer.OVERLAY)
        shell.set_anchor(self,
                         GLayerShell.Edge.TOP |
                         GLayerShell.Edge.LEFT |
                         GLayerShell.Edge.RIGHT)
        shell.set_exclusive_zone(self, -1)
        shell.set_margin(self, GLayerShell.Edge.TOP, 120)
        shell.set_margin(self, GLayerShell.Edge.LEFT, 0)
        shell.set_margin(self, GLayerShell.Edge.RIGHT, 0)
        shell.set_keyboard_interactivity(self, True)

        # Root
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.add_css_class("launcher-root")
        root.set_valign(Gtk.Align.CENTER)
        root.set_hexpand(True)
        root.set_halign(Gtk.Align.CENTER)
        self.set_child(root)

        # Search entry
        self.search = Gtk.SearchEntry()
        self.search.add_css_class("launcher-search")
        self.search.set_placeholder_text("Search applications…")
        self.search.set_hexpand(True)
        self.search.set_width_chars(40)
        self.search.connect("search-changed", self._on_search_changed)
        self.search.connect("activate", self._on_activate)
        self.search.connect("key-press-event", self._on_key_press)
        root.append(self.search)

        # Results scrolled window
        scrolled = Gtk.ScrolledWindow()
        scrolled.add_css_class("launcher-scrolled")
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_vexpand(True)
        scrolled.set_hexpand(True)
        root.append(scrolled)

        self.listbox = Gtk.ListBox()
        self.listbox.add_css_class("launcher-list")
        self.listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self.listbox.set_activate_on_single_click(True)
        scrolled.set_child(self.listbox)

        self._all_apps = collect_apps()
        self._rows = []
        self._populate(self._all_apps)

        self._apply_css()

        # Focus search on show
        self.connect("map", lambda w: self.search.grab_focus())

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
        .launcher-root {
            background-color: rgba(28, 28, 30, 0.92);
            border: 1px solid rgba(10, 132, 255, 0.5);
            border-radius: 14px;
            padding: 18px;
            font-family: "Inter";
        }
        .launcher-search {
            font-size: 17px;
            border-radius: 8px;
            border: none;
            padding: 10px 16px;
            background-color: rgba(255,255,255,0.06);
            color: #ffffff;
            margin-bottom: 14px;
            box-shadow: 0 0 0 1px rgba(255,255,255,0.12);
        }
        .launcher-search:focus {
            box-shadow: 0 0 0 2px rgba(10, 132, 255, 0.6);
            background-color: rgba(255,255,255,0.1);
        }
        .launcher-scrolled {
            background: transparent;
            border: none;
        }
        .launcher-list {
            background: transparent;
            border: none;
            outline: none;
        }
        .launcher-row {
            border-radius: 8px;
            color: #e5e5ea;
            font-size: 14px;
        }
        .launcher-row-hover {
            background-color: rgba(10, 132, 255, 0.18);
        }
        .launcher-name {
            color: #ffffff;
            font-size: 14px;
            font-weight: 500;
        }
        .launcher-sub {
            color: #a1a1a6;
            font-size: 12px;
        }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def _populate(self, apps):
        for child in self.listbox.get_children():
            self.listbox.remove(child)
        self._rows = []
        for app in apps[:24]:
            row = LauncherRow(app, self._launch_app)
            self.listbox.append(row)
            self._rows.append(row)
        if self._rows:
            self._rows[0].add_css_class("launcher-row-hover")
        self.listbox.show()

    def _on_search_changed(self, entry):
        text = entry.get_text().lower().strip()
        if not text:
            self._populate(self._all_apps)
            return
        # Simple fuzzy / substring match
        matched = []
        for app in self._all_apps:
            hay = (app["name"] + " " + app["generic"] + " " +
                   app["comment"] + " " + app["categories"]).lower()
            if text in hay:
                matched.append(app)
        # Rank: exact startswith first
        matched.sort(key=lambda a: not a["name"].lower().startswith(text))
        self._populate(matched)

    def _on_activate(self, entry):
        if self._rows:
            GLib.idle_add(self._rows[0]._launch)

    def _on_key_press(self, widget, event):
        key = event.keyval
        if key in (Gdk.KEY_Escape,):
            GLib.idle_add(Gtk.Application.get_default().quit)
            return True
        if key in (Gdk.KEY_Down, Gdk.KEY_Tab):
            self._move_selection(1)
            return True
        if key in (Gdk.KEY_Up,):
            self._move_selection(-1)
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            if self._rows:
                GLib.idle_add(self._rows[0]._launch)
            return True
        return False

    def _move_selection(self, direction):
        if not self._rows:
            return
        # Find current hovered
        current = -1
        for i, row in enumerate(self._rows):
            if "launcher-row-hover" in row.get_css_classes():
                current = i
                break
        nxt = (current + direction) % len(self._rows)
        for row in self._rows:
            row.remove_css_class("launcher-row-hover")
        self._rows[nxt].add_css_class("launcher-row-hover")
        self.listbox.scroll_to_row(self._rows[nxt], 0, 0)


class LauncherApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.macoslite.launcher")

    def do_activate(self):
        self.win = LauncherWindow(self)
        self.win.present()
        self.win.search.grab_focus()


def main():
    import signal
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = LauncherApp()
    app.run(None)


if __name__ == "__main__":
    main()
