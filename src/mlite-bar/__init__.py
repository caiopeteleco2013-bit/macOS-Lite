"""macOS-Lite top bar (mlite-bar).

A GTK4 + LayerShell top bar implementing the macOS-like top bar:
app menu (left), active-window title (center), system indicators (right).

No Apple code or assets are used. Original code, MIT licensed.
"""
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("GLayerShell", "0.1")
from gi.repository import Gtk, GLib, GLayerShell  # noqa: E402


def main():
    app = Gtk.Application(application_id="org.macoslite.bar")
    app.connect("activate", on_activate)
    app.run(None)


def on_activate(app):
    window = Gtk.ApplicationWindow(application=app)
    window.set_title("macOS-Lite Bar")
    shell = GLayerShell.Shell()
    shell.set_layer(window, GLayerShell.Layer.TOP)
    shell.set_anchor(window, GLayerShell.Edge.TOP | GLayerShell.Edge.LEFT | GLayerShell.Edge.RIGHT)
    shell.set_exclusive_zone(window, 34)
    window.set_default_size(1920, 34)
    window.present()


if __name__ == "__main__":
    main()
