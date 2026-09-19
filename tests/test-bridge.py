"""bin/ytm-bridge against tests/fakecdp.py. No browser, no network."""
import importlib.machinery
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BRIDGE = os.path.join(ROOT, "bin", "ytm-bridge")
sys.path.insert(0, HERE)
from fakecdp import FakeBrowser  # noqa: E402


class Client:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(path)
        self.buf = b""
        self.n = 0

    def raw(self, line):
        self.sock.sendall(line.encode() + b"\n")

    def read(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("bridge closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def call(self, op, **arg):
        self.n += 1
        msg = {"id": self.n, "op": op}
        msg.update(arg)
        self.raw(json.dumps(msg))
        while True:
            m = self.read()
            if m.get("id") == self.n:
                return m

    def wait_event(self, ev, value=None, timeout=5):
        end = time.time() + timeout
        while time.time() < end:
            m = self.read()
            if m.get("ev") == ev and (value is None or m.get(ev) == value):
                return m
        raise AssertionError("no event %s=%s" % (ev, value))

    def close(self):
        self.sock.close()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.profile = os.path.join(self.tmp, "profile")
        self.sockpath = os.path.join(self.tmp, "b.sock")
        self.browser = FakeBrowser(self.profile)
        env = dict(os.environ, YTM_POLL_MS="100")
        self.proc = subprocess.Popen([sys.executable, BRIDGE, "--socket", self.sockpath, "--profile", self.profile,
                                      "--launcher", "/bin/true", "--cache", os.path.join(self.tmp, "cache")], env=env, stderr=subprocess.PIPE)
        for _ in range(50):
            if os.path.exists(self.sockpath):
                break
            time.sleep(0.1)
        else:
            self.fail("socket never appeared: %s" % self.proc.stderr.read().decode())

    def tearDown(self):
        self.proc.terminate()
        try:
            self.proc.wait(3)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.browser.close()

    def wait_state(self, c, want, timeout=5):
        end = time.time() + timeout
        last = None
        while time.time() < end:
            last = c.call("state")["state"]
            if last == want:
                return
            time.sleep(0.1)
        self.fail("state %r, wanted %r" % (last, want))


class BridgeTest(Base):
    def test_socket_is_private(self):
        self.assertEqual(oct(os.stat(self.sockpath).st_mode & 0o777), "0o600")

    def test_state_follows_browser(self):
        c = Client(self.sockpath)
        self.assertEqual(c.call("state")["state"], "no-app")
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.assertIn("Runtime.enable", self.browser.methods)
        self.assertIn("Target.attachToTarget", self.browser.methods)

    def test_signed_out(self):
        self.browser.canned["state"] = {"loggedIn": False}
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "signed-out")
        r = c.call("library.playlists")
        self.assertEqual(r["ok"], False)
        self.assertEqual(r["error"], "signed-out")

    def test_bad_id_never_reaches_page(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        before = len(self.browser.calls)
        r = c.call("playlist.items", list="PL;rm -rf /")
        self.assertEqual(r, {"id": r["id"], "ok": False, "error": "bad-id"})
        self.assertEqual(len(self.browser.calls), before)

    def test_two_clients_get_their_own_ids(self):
        a, b = Client(self.sockpath), Client(self.sockpath)
        for _ in range(3):
            a.n += 10
        ra = a.call("state")
        rb = b.call("state")
        self.assertEqual(ra["id"], a.n)
        self.assertEqual(rb["id"], b.n)

    def test_malformed_line(self):
        c = Client(self.sockpath)
        c.raw("this is not json")
        m = c.read()
        self.assertEqual(m["ok"], False)
        self.assertEqual(m["error"], "bad-request")
        self.assertEqual(c.call("state")["state"], "no-app")   # still connected

    def test_unknown_op(self):
        c = Client(self.sockpath)
        self.assertEqual(c.call("nope")["error"], "bad-request")

    def test_target_destroyed_then_reattach(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.browser.destroy_target("T1")
        c.wait_event("state", "no-app")
        self.browser.add_target("T2")
        c.wait_event("state", "ready", timeout=8)

    def test_page_exception_is_page_error(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.browser.canned["library.playlists"] = RuntimeError("boom")
        r = c.call("library.playlists")
        self.assertEqual(r["error"], "page-error")

    def test_state_reports_browser_pid(self):
        c = Client(self.sockpath)
        self.assertEqual(c.call("state")["pid"], 0)
        os.symlink("host-4242", os.path.join(self.profile, "SingletonLock"))
        self.assertEqual(c.call("state")["pid"], 4242)

    def test_app_launch_uses_launcher(self):
        c = Client(self.sockpath)
        r = c.call("app.launch")
        self.assertTrue(r["ok"])


class OpsTest(Base):
    def ready(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        return c

    def last_call(self):
        p = self.browser.calls[-1]
        return p["arguments"][0]["value"], p["arguments"][1]["value"]

    def test_ops_forward_validated_args(self):
        c = self.ready()
        self.browser.canned.update({"library.playlists": {"x": 1}, "playlist.items": {"y": 2}, "queue": {"source": "none", "items": []},
                                    "like": {}, "lyrics": {}, "search": {}, "now": {"video": "dQw4w9WgXcQ"}, "queue.jump": {"jumped": True}})
        self.assertEqual(c.call("library.playlists")["data"], {"x": 1})
        self.assertEqual(self.last_call(), ("library.playlists", {}))
        self.assertEqual(c.call("playlist.items", list="PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")["data"], {"y": 2})
        self.assertEqual(self.last_call(), ("playlist.items", {"list": "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"}))
        c.call("like", video="dQw4w9WgXcQ")
        self.assertEqual(self.last_call(), ("like", {"video": "dQw4w9WgXcQ"}))
        c.call("queue.jump", index=3)
        self.assertEqual(self.last_call(), ("queue.jump", {"index": 3}))
        self.assertEqual(c.call("queue.jump", index="3")["error"], "bad-request")
        self.assertEqual(c.call("queue.jump", index=-1)["error"], "bad-request")
        self.assertEqual(c.call("like", video="")["error"], "bad-id")
        self.assertEqual(c.call("search", q="x" * 201)["error"], "bad-request")
        self.assertEqual(c.call("search", q="  ")["error"], "bad-request")
        c.call("search", q="rick astley")
        self.assertEqual(self.last_call(), ("search", {"q": "rick astley"}))
        self.assertEqual(c.call("now")["data"]["video"], "dQw4w9WgXcQ")

    def test_play_forwards_shuffle_and_follows_up(self):
        c = self.ready()
        self.browser.canned.update({"play": {"navigated": True}, "player.shuffle": {"shuffled": True}})
        r = c.call("play", list="PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", shuffle=True)
        self.assertTrue(r["ok"])
        ops = [p["arguments"][0]["value"] for p in self.browser.calls]
        self.assertIn("play", ops)
        self.assertEqual(ops[-1], "player.shuffle")
        self.assertEqual(self.browser.calls[ops.index("play")]["arguments"][1]["value"],
                         {"list": "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", "video": None, "shuffle": True})
        self.assertEqual(c.call("play")["error"], "bad-id")

    def test_home_forwards_and_caches(self):
        c = self.ready()
        self.browser.canned["home"] = {"pages": [1]}
        self.assertEqual(c.call("home")["data"], {"pages": [1]})
        self.assertEqual(self.last_call(), ("home", {}))
        self.browser.canned["home"] = RuntimeError("gone")
        r = c.call("home")
        self.assertTrue(r["ok"]); self.assertTrue(r["cached"])

    def test_library_cache_on_page_error(self):
        c = self.ready()
        self.browser.canned["library.playlists"] = {"cached": "yes"}
        c.call("library.playlists")
        self.browser.canned["library.playlists"] = RuntimeError("shape changed")
        r = c.call("library.playlists")
        self.assertTrue(r["ok"])
        self.assertEqual(r["data"], {"cached": "yes"})
        self.assertTrue(r["cached"])

    def test_track_event_on_video_change(self):
        c = self.ready()
        self.browser.canned["state"] = {"loggedIn": True, "video": "dQw4w9WgXcQ"}
        m = c.wait_event("track", timeout=8)
        self.assertEqual(m["video"], "dQw4w9WgXcQ")

    def test_art_only_google_hosts(self):
        c = self.ready()
        self.assertEqual(c.call("art", url="https://evil.example/x.jpg")["error"], "bad-request")
        self.assertEqual(c.call("art", url="http://i.ytimg.com/x.jpg")["error"], "bad-request")


class CheckIdTest(unittest.TestCase):
    def test_check_id(self):
        self.assertEqual(subprocess.call([sys.executable, BRIDGE, "--check-id", "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"]), 0)
        self.assertEqual(subprocess.call([sys.executable, BRIDGE, "--check-id", "PL;rm"]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
