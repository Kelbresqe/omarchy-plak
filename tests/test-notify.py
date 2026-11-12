"""bin/ytm-notify against a fake notification server on a private D-Bus.
Nothing reaches the desktop's real notification daemon."""
import importlib.machinery
import json
import os
import subprocess
import sys
import threading
import unittest

from gi.repository import Gio, GLib

HERE = os.path.dirname(os.path.abspath(__file__))
NOTIFY = os.path.join(os.path.dirname(HERE), "bin", "ytm-notify")
notify = importlib.machinery.SourceFileLoader("ytm_notify", NOTIFY).load_module()

IFACE = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.Notifications">
  <method name="Notify">
    <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
    <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
    <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/>
  </method>
</interface></node>""").interfaces[0]


class ParseTest(unittest.TestCase):
    def test_body_is_escaped_and_icon_must_be_a_local_path(self):
        title, body, icon = notify.parse(json.dumps({"title": "AC<DC>", "body": "R&B <b>x</b>", "icon": "/tmp/.art"}))
        self.assertEqual((title, body, icon), ("AC<DC>", "R&amp;B &lt;b&gt;x&lt;/b&gt;", "/tmp/.art"))
        self.assertEqual(notify.parse(json.dumps({"title": "t", "icon": "https://evil.example/a.png"}))[2], "")

    def test_bad_input(self):
        for raw in ("not json", "[]", json.dumps({"body": "no title"}), json.dumps({"title": 5})):
            with self.assertRaises(ValueError, msg=raw):
                notify.parse(raw)

    def test_caps(self):
        title, body, _ = notify.parse(json.dumps({"title": "t" * 1000, "body": "b" * 1000}))
        self.assertEqual((len(title), len(body)), (300, 600))


class BusTest(unittest.TestCase):
    def setUp(self):
        self.daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                                       stdout=subprocess.PIPE, text=True)
        self.address = self.daemon.stdout.readline().strip()
        self.calls = []
        self.loop = GLib.MainLoop()
        conn = Gio.DBusConnection.new_for_address_sync(
            self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)

        def on_call(_conn, _sender, _path, _iface, method, params, invocation):
            self.calls.append(params.unpack())
            invocation.return_value(GLib.Variant("(u)", (1,)))
        conn.register_object("/org/freedesktop/Notifications", IFACE, on_call, None, None)
        conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                       GLib.Variant("(su)", ("org.freedesktop.Notifications", 4)), None, 0, 5000, None)
        self.conn = conn
        threading.Thread(target=self.loop.run, daemon=True).start()

    def tearDown(self):
        self.loop.quit()
        self.conn.close_sync(None)
        self.daemon.terminate()
        self.daemon.wait(5)

    def test_track_goes_over_dbus_not_argv(self):
        payload = {"title": "Oyuncak Gibi", "body": "Aleyna Tilki  ·  Album", "icon": "/tmp/.com.google.Chrome.x"}
        env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=self.address)
        # One line, as Service.qml writes it; stdin stays open like a QProcess's.
        p = subprocess.Popen([sys.executable, NOTIFY], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=env, text=True)
        p.stdin.write(json.dumps(payload) + "\n")
        p.stdin.flush()
        self.assertEqual(p.wait(10), 0, p.stderr.read())
        p.stdin.close()
        p.stdout.close()
        p.stderr.close()
        self.assertEqual(len(self.calls), 1)

        app, replaces, icon, summary, body, actions, hints, timeout = self.calls[0]
        self.assertEqual((app, replaces, icon, summary, body, actions, timeout),
                         ("Plak", 0, payload["icon"], payload["title"], payload["body"], [], 4000))
        self.assertEqual(hints, {"x-canonical-private-synchronous": "io.github.kelbresqe.plak", "transient": True})


if __name__ == "__main__":
    unittest.main()
