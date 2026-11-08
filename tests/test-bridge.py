"""bin/ytm-bridge against tests/fakecdp.py. No browser, no network."""
import importlib.machinery
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BRIDGE = os.path.join(ROOT, "bin", "ytm-bridge")
sys.path.insert(0, HERE)
from fakecdp import FakeBrowser  # noqa: E402

bridge = importlib.machinery.SourceFileLoader("ytm_bridge", BRIDGE).load_module()


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
    launcher = "/bin/true"

    memory = None          # dict to pre-seed session.json with, before the bridge starts
    extra_env = {}         # per-class additions to the bridge's environment

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.profile = os.path.join(self.tmp, "profile")
        self.sockpath = os.path.join(self.tmp, "b.sock")
        # Always a private state file: the default is the user's real one.
        self.state_file = os.path.join(self.tmp, "state", "session.json")
        if self.memory is not None:
            os.makedirs(os.path.dirname(self.state_file))
            with open(self.state_file, "w") as f:
                json.dump(self.memory, f)
        self.browser = FakeBrowser(self.profile)
        env = dict(os.environ, YTM_POLL_MS="100", YTM_CLOSE_WAIT_S="0.5", XDG_STATE_HOME=os.path.join(self.tmp, "xdg-state"))
        env.update(self.extra_env)
        self.proc = subprocess.Popen([sys.executable, BRIDGE, "--socket", self.sockpath, "--profile", self.profile,
                                      "--launcher", self.launcher, "--cache", os.path.join(self.tmp, "cache"),
                                      "--state-file", self.state_file], env=env, stderr=subprocess.PIPE)
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
            self.proc.wait(3)
        self.proc.stderr.close()
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

    def test_oversized_frame_drops_and_reattaches(self):
        # The browser endpoint announces a frame far beyond the limit. The
        # bridge must close that connection instead of buffering towards it,
        # then attach again as if the browser had restarted.
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        conns, enables = self.browser.ws_count, self.browser.methods.count("Runtime.enable")
        self.browser.send_raw(bytes([0x81, 127]) + struct.pack(">Q", bridge.MAX_FRAME + 1) + b"x" * 1024)
        for _ in range(50):
            if self.browser.ws_count > conns:
                break
            time.sleep(0.1)
        self.assertGreater(self.browser.ws_count, conns, "bridge kept the oversized connection open")
        self.wait_state(c, "ready")
        self.assertGreater(self.browser.methods.count("Runtime.enable"), enables)

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

    def test_signin_marker_reads_as_signing_in(self):
        c = Client(self.sockpath)
        self.wait_state(c, "no-app")
        marker = self.sockpath + ".signin"
        with open(marker, "w") as f:
            f.write("%d\n" % os.getpid())          # a live pid: sign-in in progress
        self.wait_state(c, "signing-in")
        with open(marker, "w") as f:
            f.write("999999999\n")                  # no such process: stale marker
        self.wait_state(c, "no-app")


class RecorderBase(Base):
    """A bridge whose launcher records the arguments it was run with."""

    def setUp(self):
        self.rec_dir = tempfile.mkdtemp()
        self.rec = os.path.join(self.rec_dir, "args")
        self.launcher = os.path.join(self.rec_dir, "launcher")
        with open(self.launcher, "w") as f:
            f.write("#!/bin/sh\nprintf '%%s\\n' \"$@\" > '%s'\n" % self.rec)
        os.chmod(self.launcher, 0o755)
        super().setUp()

    def launched_with(self, timeout=3):
        end = time.time() + timeout
        while time.time() < end:
            if os.path.exists(self.rec):
                with open(self.rec) as f:
                    return f.read().split("\n")[:-1]
            time.sleep(0.05)
        return None


class SigninTest(RecorderBase):
    """app.signin closes the app over DevTools, then hands over to
    `ytm-app --signin --marker <socket>.signin`."""

    def test_signin_closes_app_and_hands_over(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        r = c.call("app.signin", browser="google-chrome-stable")
        self.assertTrue(r["ok"] and r["started"], r)
        self.assertIn("Browser.close", self.browser.methods)
        self.assertEqual(self.launched_with(), ["--signin", "--marker", self.sockpath + ".signin",
                                                "--browser", "google-chrome-stable"])

    def test_signin_refused_while_profile_is_busy(self):
        c = Client(self.sockpath)
        # A live process holds the profile and will not quit.
        os.symlink("host-%d" % os.getpid(), os.path.join(self.profile, "SingletonLock"))
        r = c.call("app.signin")
        self.assertEqual((r["ok"], r["started"], r["reason"]), (True, False, "busy"))
        self.assertIsNone(self.launched_with(timeout=0.5))
        self.assertFalse(os.path.exists(self.sockpath + ".signin"))

    def test_quit_closes_app_over_devtools(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        r = c.call("app.quit")
        self.assertEqual((r["ok"], r["closed"]), (True, True))
        self.assertIn("Browser.close", self.browser.methods)
        self.assertIsNone(self.launched_with(timeout=0.3))   # quitting never relaunches

    def test_signin_rejects_hostile_browser(self):
        c = Client(self.sockpath)
        self.assertEqual(c.call("app.signin", browser="brave; touch /tmp/x")["error"], "bad-request")
        self.assertIsNone(self.launched_with(timeout=0.5))


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

    def test_volume_forwards_validated_level(self):
        c = self.ready()
        self.browser.canned.update({"volume.get": {"volume": 40}, "volume.set": {"volume": 65}})
        self.assertEqual(c.call("volume.get")["data"], {"volume": 40})
        self.assertEqual(self.last_call(), ("volume.get", {}))
        self.assertEqual(c.call("volume.set", volume=65)["data"], {"volume": 65})
        self.assertEqual(self.last_call(), ("volume.set", {"volume": 65}))
        n = len(self.browser.calls)
        for bad in (-1, 101, 0.5, "50", True, None):
            self.assertEqual(c.call("volume.set", volume=bad)["error"], "bad-request", bad)
        self.assertEqual(len(self.browser.calls), n)   # nothing invalid reached the page

    def test_repeat_forwards_validated_mode(self):
        c = self.ready()
        self.browser.canned.update({"repeat.get": {"mode": "NONE"}, "repeat.set": {"mode": "ONE"}})
        self.assertEqual(c.call("repeat.get")["data"], {"mode": "NONE"})
        self.assertEqual(self.last_call(), ("repeat.get", {}))
        self.assertEqual(c.call("repeat.set", mode="ONE")["data"], {"mode": "ONE"})
        self.assertEqual(self.last_call(), ("repeat.set", {"mode": "ONE"}))
        n = len(self.browser.calls)
        for bad in ("one", "", "ALL ", 1, None, ["ALL"]):
            self.assertEqual(c.call("repeat.set", mode=bad)["error"], "bad-request", bad)
        self.assertEqual(len(self.browser.calls), n)   # nothing invalid reached the page

    def test_shuffle_forwards_validated_flag(self):
        c = self.ready()
        self.browser.canned.update({"shuffle.get": {"on": False}, "shuffle.set": {"on": True}})
        self.assertEqual(c.call("shuffle.get")["data"], {"on": False})
        self.assertEqual(self.last_call(), ("shuffle.get", {}))
        self.assertEqual(c.call("shuffle.set", on=True)["data"], {"on": True})
        self.assertEqual(self.last_call(), ("shuffle.set", {"on": True}))
        n = len(self.browser.calls)
        for bad in ("true", 1, 0, None, [True]):
            self.assertEqual(c.call("shuffle.set", on=bad)["error"], "bad-request", bad)
        self.assertEqual(len(self.browser.calls), n)   # nothing invalid reached the page

    def test_queue_edits_forward_validated_args(self):
        c = self.ready()
        self.browser.canned.update({"queue.add": {"added": 1, "index": 5}, "queue.remove": {"removed": True},
                                    "queue.move": {"moved": True}})
        self.assertEqual(c.call("queue.add", video=VID, next=True)["data"], {"added": 1, "index": 5})
        self.assertEqual(self.last_call(), ("queue.add", {"video": VID, "next": True}))
        c.call("queue.add", video=VID)
        self.assertEqual(self.last_call(), ("queue.add", {"video": VID, "next": False}))
        c.call("queue.remove", index=3)
        self.assertEqual(self.last_call(), ("queue.remove", {"index": 3}))
        c.call("queue.move", **{"from": 2, "to": 7})
        self.assertEqual(self.last_call(), ("queue.move", {"from": 2, "to": 7}))
        n = len(self.browser.calls)
        self.assertEqual(c.call("queue.add", video="x;y")["error"], "bad-id")
        self.assertEqual(c.call("queue.add", video=VID, next="yes")["error"], "bad-request")
        for bad in (-1, True, "3", None, 10001):
            self.assertEqual(c.call("queue.remove", index=bad)["error"], "bad-request", bad)
        self.assertEqual(c.call("queue.move", **{"from": 1})["error"], "bad-request")
        self.assertEqual(len(self.browser.calls), n)   # nothing invalid reached the page

    def test_history_save_targets_and_fade(self):
        c = self.ready()
        self.browser.canned.update({"history": {"h": 1}, "playlist.targets": {"t": 1}, "player.fade": {"faded": True}})
        self.assertEqual(c.call("history")["data"], {"h": 1})
        self.assertEqual(c.call("playlist.targets", video=VID)["data"], {"t": 1})
        self.assertEqual(self.last_call(), ("playlist.targets", {"video": VID}))
        self.assertEqual(c.call("player.fade", seconds=10)["data"], {"faded": True})
        self.assertEqual(self.last_call(), ("player.fade", {"seconds": 10}))
        n = len(self.browser.calls)
        self.assertEqual(c.call("playlist.targets", video="")["error"], "bad-id")
        for bad in (0, 16, "10", True, None):
            self.assertEqual(c.call("player.fade", seconds=bad)["error"], "bad-request", bad)
        self.assertEqual(len(self.browser.calls), n)

    def test_play_forwards_shuffle_and_follows_up(self):
        c = self.ready()
        # In-app navigation: the list is up when `play` returns, so shuffle
        # follows at once instead of waiting for a page load.
        self.browser.canned.update({"play": {"navigated": True, "reloaded": False}, "player.shuffle": {"shuffled": True}})
        t0 = time.time()
        r = c.call("play", list="PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", shuffle=True)
        self.assertTrue(r["ok"])
        self.assertLess(time.time() - t0, 3)
        ops = [p["arguments"][0]["value"] for p in self.browser.calls]
        self.assertIn("play", ops)
        self.assertEqual(ops[-1], "player.shuffle")
        self.assertEqual(self.browser.calls[ops.index("play")]["arguments"][1]["value"],
                         {"list": "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", "video": None, "shuffle": True})
        self.assertEqual(c.call("play")["error"], "bad-id")

    def test_shuffle_play_after_fallback_reload_waits_for_the_page(self):
        c = self.ready()
        self.browser.canned.update({"play": {"navigated": True, "reloaded": True}, "player.shuffle": {"shuffled": True}})
        gen_before = len([m for m in self.browser.methods if m == "Runtime.evaluate"])
        r = c.call("play", list="PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", shuffle=True)
        self.assertTrue(r["ok"])
        ops = [p["arguments"][0]["value"] for p in self.browser.calls]
        self.assertEqual(ops[-1], "player.shuffle")
        # page.js was installed again after the (fake) reload, before shuffling
        self.assertGreater(len([m for m in self.browser.methods if m == "Runtime.evaluate"]), gen_before)

    def test_leave_prompt_is_confirmed_only_for_beforeunload(self):
        self.ready()
        self.browser._send({"method": "Page.javascriptDialogOpening", "sessionId": "S1",
                            "params": {"type": "alert", "message": "hi"}})
        time.sleep(0.4)
        self.assertNotIn("Page.handleJavaScriptDialog", self.browser.methods)
        self.browser._send({"method": "Page.javascriptDialogOpening", "sessionId": "S1",
                            "params": {"type": "beforeunload", "message": ""}})
        end = time.time() + 3
        while "Page.handleJavaScriptDialog" not in self.browser.methods and time.time() < end:
            time.sleep(0.05)
        self.assertIn("Page.handleJavaScriptDialog", self.browser.methods)

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


class RawServer:
    """A TCP endpoint that runs `script(conn)` for the one client that connects."""

    def __init__(self, script):
        self.srv = socket.socket()
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen(1)
        self.port = self.srv.getsockname()[1]
        self.script = script
        self.client_gone = threading.Event()
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        conn, _ = self.srv.accept()
        conn.settimeout(5)
        try:
            self.script(conn)
        except OSError:
            pass
        finally:
            self.client_gone.set()
            conn.close()
            self.srv.close()

    def url(self):
        return "ws://127.0.0.1:%d/x" % self.port


def upgrade_101(conn):
    # Read the client's request, answer 101. Accept key unchecked: the client
    # under test does not verify it and that is not what these tests cover.
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += conn.recv(4096)
    conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")


def frame(payload, fin=True, opcode=0x1):
    hdr = bytes([(0x80 if fin else 0) | opcode])
    n = len(payload)
    if n < 126:
        hdr += bytes([n])
    elif n < 65536:
        hdr += bytes([126]) + struct.pack(">H", n)
    else:
        hdr += bytes([127]) + struct.pack(">Q", n)
    return hdr + payload


class WebSocketLimitTest(unittest.TestCase):
    """bin/ytm-bridge's WebSocket client against a hostile endpoint. Every
    limit must close the connection before the offending bytes are buffered."""

    def test_handshake_without_terminator(self):
        def script(conn):
            conn.recv(4096)
            # Header lines forever, never a blank one.
            for _ in range(bridge.MAX_HANDSHAKE // 64 + 8):
                conn.sendall(b"X-Filler: " + b"a" * 52 + b"\r\n")
        srv = RawServer(script)
        with self.assertRaisesRegex(bridge.WebSocketClosed, "handshake too long"):
            bridge.WebSocket(srv.url())
        self.assertTrue(srv.client_gone.wait(5))

    def test_frame_length_over_limit(self):
        def script(conn):
            upgrade_101(conn)
            conn.sendall(bytes([0x81, 127]) + struct.pack(">Q", bridge.MAX_FRAME + 1))
            conn.sendall(b"y" * 4096)
            self.assertEqual(conn.recv(1), b"")     # client hung up without reading it
        srv = RawServer(script)
        ws = bridge.WebSocket(srv.url())
        with self.assertRaisesRegex(bridge.WebSocketClosed, "frame too large"):
            ws.recv_text()
        self.assertTrue(srv.client_gone.wait(5))

    def test_fragments_over_limit(self):
        # Each fragment is legal on its own; together they exceed the message cap.
        piece = b"z" * (64 * 1024)
        pieces = bridge.MAX_MESSAGE // len(piece) + 2

        def script(conn):
            upgrade_101(conn)
            conn.sendall(frame(piece, fin=False))
            for _ in range(pieces):
                conn.sendall(frame(piece, fin=False, opcode=0x0))
            conn.sendall(frame(piece, fin=True, opcode=0x0))
        srv = RawServer(script)
        ws = bridge.WebSocket(srv.url())
        with self.assertRaisesRegex(bridge.WebSocketClosed, "message too large"):
            ws.recv_text()
        self.assertTrue(srv.client_gone.wait(5))

    def test_message_under_limit_still_arrives(self):
        # Largest real payload measured on a live account was ~1.4 MB (home);
        # a 4 MB message split into fragments must still get through.
        body = b"{" + b"\"k\":\"" + b"v" * (4 * 1024 * 1024) + b"\"}"
        half = len(body) // 2

        def script(conn):
            upgrade_101(conn)
            conn.sendall(frame(body[:half], fin=False))
            conn.sendall(frame(body[half:], fin=True, opcode=0x0))
            conn.recv(1)
        srv = RawServer(script)
        ws = bridge.WebSocket(srv.url())
        self.assertEqual(ws.recv_text(), body.decode())
        ws.close()


class RecoveryTest(RecorderBase):
    """A crashed or stuck page is reloaded; still stuck after that, the
    browser is restarted through the launcher."""
    extra_env = {"YTM_LOGIN_POLL_S": "0.1", "YTM_FAIL_LIMIT": "2", "YTM_LIVENESS_TIMEOUT_S": "1"}

    def wait_for(self, pred, timeout=5):
        end = time.time() + timeout
        while time.time() < end and not pred():
            time.sleep(0.05)
        return pred()

    def test_crash_reloads_the_page(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.browser._send({"method": "Target.targetCrashed", "params": {"targetId": "T1", "status": "crashed", "errorCode": 139}})
        self.assertTrue(self.wait_for(lambda: "Page.reload" in self.browser.methods))

    def test_other_targets_crashing_is_ignored(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.browser._send({"method": "Target.targetCrashed", "params": {"targetId": "T9", "status": "crashed"}})
        time.sleep(0.5)
        self.assertNotIn("Page.reload", self.browser.methods)

    def test_stuck_page_is_reloaded_then_the_browser_restarted(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.browser.canned["state"] = RuntimeError("page is stuck")
        self.assertTrue(self.wait_for(lambda: "Page.reload" in self.browser.methods))
        self.assertTrue(self.wait_for(lambda: os.path.exists(self.rec)), "launcher never ran")
        self.assertIn("Browser.close", self.browser.methods)

    def test_a_page_that_answers_again_is_left_alone(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        self.browser.canned["state"] = RuntimeError("blip")
        time.sleep(0.15)                                  # one miss, under the limit
        self.browser.canned["state"] = {"loggedIn": True}
        self.wait_state(c, "ready")                       # polling continues in "attaching"
        time.sleep(0.5)
        self.assertNotIn("Page.reload", self.browser.methods)


VID = "dQw4w9WgXcQ"
LIST = "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"


class MemoryTest(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(tempfile.mkdtemp(), "state", "session.json")

    def saved(self):
        with open(self.path) as f:
            return json.load(f)

    def test_clean_keeps_only_valid_fields(self):
        self.assertEqual(bridge.Memory._clean({"video": "bad id!", "repeat": "SOME", "shuffle": "yes", "volume": 300}), {})
        self.assertEqual(
            bridge.Memory._clean({"video": VID, "list": "x;y", "time": -1, "title": 5, "repeat": "ALL",
                                  "shuffle": False, "volume": 55.4}),
            {"video": VID, "list": "", "time": 0, "title": "", "artist": "", "repeat": "ALL", "shuffle": False, "volume": 55})
        self.assertEqual(bridge.Memory._clean(["not", "a", "dict"]), {})

    def test_bad_file_reads_as_empty(self):
        os.makedirs(os.path.dirname(self.path))
        with open(self.path, "w") as f:
            f.write("{not json")
        self.assertEqual(bridge.Memory(self.path).get(), {})

    def test_position_only_changes_are_throttled(self):
        m = bridge.Memory(self.path)
        m.note(VID, {"time": 10, "repeat": "NONE"})
        self.assertEqual(self.saved()["time"], 10)
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)
        m.note(VID, {"time": 12, "repeat": "NONE"})          # only the position moved: not written yet
        self.assertEqual((self.saved()["time"], m.get()["time"]), (10, 12))
        m.note(VID, {"time": 13, "repeat": "ALL"})           # a setting changed: written at once
        self.assertEqual((self.saved()["time"], self.saved()["repeat"]), (13, "ALL"))
        m.note("", {"time": 99})                             # nothing playing: ignored
        self.assertEqual(m.get()["time"], 13)


class MemoryOpsTest(Base):
    memory = {"video": VID, "list": LIST, "time": 95, "title": "Song", "artist": "Artist",
              "repeat": "ONE", "shuffle": True, "volume": 40}

    def calls_of(self, op):
        return [p["arguments"][1]["value"] for p in self.browser.calls if p["arguments"][0]["value"] == op]

    def ready(self):
        c = Client(self.sockpath)
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        return c

    def test_state_carries_last_settings(self):
        c = Client(self.sockpath)
        self.assertEqual(c.call("state")["memo"], {"volume": 40, "repeat": "ONE", "shuffle": True})

    def test_resume_offered_only_while_nothing_plays(self):
        c = self.ready()
        self.assertEqual(c.call("resume.get")["resume"],
                         {"video": VID, "list": LIST, "time": 95, "title": "Song", "artist": "Artist"})
        self.browser.canned["state"] = {"loggedIn": True, "video": "oHg5SJYRHA0"}
        end = time.time() + 5
        while c.call("state")["video"] != "oHg5SJYRHA0" and time.time() < end:
            time.sleep(0.1)
        self.assertIsNone(c.call("resume.get")["resume"])

    def test_resume_plays_the_list_then_seeks(self):
        c = self.ready()
        self.browser.canned.update({"play": {"navigated": True}, "player.seek": {"seeked": True}})
        self.assertTrue(c.call("resume.play")["resumed"])
        self.assertEqual(self.calls_of("play")[-1], {"video": VID, "list": LIST, "shuffle": False})
        self.assertEqual(self.calls_of("player.seek")[-1], {"video": VID, "t": 95})

    def test_restores_repeat_and_shuffle_once_when_playback_starts(self):
        c = Client(self.sockpath)
        session = {"repeat": "NONE", "shuffle": False, "time": 3, "list": "", "title": "Song", "artist": "Artist", "volume": 40}
        self.browser.canned.update({"repeat.set": {"mode": "ONE"}, "shuffle.set": {"on": True},
                                    "state": {"loggedIn": True, "video": VID, "session": session}})
        self.browser.write_port_file()
        c.wait_event("player")
        # The page now reports what was restored; later polls must not restore again.
        self.browser.canned["state"] = {"loggedIn": True, "video": VID, "session": dict(session, repeat="ONE", shuffle=True)}
        time.sleep(0.6)
        self.assertEqual(self.calls_of("repeat.set"), [{"mode": "ONE"}])
        self.assertEqual(self.calls_of("shuffle.set"), [{"on": True}])
        with open(self.state_file) as f:
            saved = json.load(f)
        self.assertEqual((saved["repeat"], saved["shuffle"], saved["video"]), ("ONE", True, VID))

    def test_user_choice_in_this_session_is_not_overridden(self):
        c = Client(self.sockpath)
        session = {"repeat": "ALL", "shuffle": False, "time": 3}     # user already picked ALL
        self.browser.canned.update({"repeat.set": {"mode": "ONE"}, "shuffle.set": {"on": True},
                                    "state": {"loggedIn": True, "video": VID, "session": session}})
        self.browser.write_port_file()
        self.wait_state(c, "ready")
        time.sleep(0.5)
        self.assertEqual(self.calls_of("repeat.set"), [])            # ALL is kept
        self.assertEqual(self.calls_of("shuffle.set"), [{"on": True}])


class SelfWatchTest(unittest.TestCase):
    """The daemon exits on its own when its code changes or when a newer
    daemon takes over the socket, and never unlinks a socket it lost."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.bin = os.path.join(self.tmp, "bin")
        os.mkdir(self.bin)
        for name in ("ytm-bridge", "page.js"):
            with open(os.path.join(ROOT, "bin", name), "rb") as src, open(os.path.join(self.bin, name), "wb") as dst:
                dst.write(src.read())
        self.sockpath = os.path.join(self.tmp, "b.sock")
        self.procs = []

    def tearDown(self):
        for p in self.procs:
            if p.poll() is None:
                p.kill()
                p.wait(3)

    def start(self):
        env = dict(os.environ, YTM_POLL_MS="100", YTM_SELF_CHECK_S="0.2", XDG_STATE_HOME=os.path.join(self.tmp, "xdg-state"))
        p = subprocess.Popen([sys.executable, os.path.join(self.bin, "ytm-bridge"), "--socket", self.sockpath,
                              "--profile", os.path.join(self.tmp, "profile"), "--launcher", "/bin/true",
                              "--cache", os.path.join(self.tmp, "cache"),
                              "--state-file", os.path.join(self.tmp, "session.json")], env=env, stderr=subprocess.DEVNULL)
        self.procs.append(p)
        end = time.time() + 5
        while time.time() < end:
            try:
                if Client(self.sockpath).call("state")["ok"]:
                    return p
            except OSError:
                pass
            time.sleep(0.05)
        self.fail("bridge never answered")

    def test_exits_when_code_changes(self):
        p = self.start()
        time.sleep(0.3)
        page = os.path.join(self.bin, "page.js")
        st = os.stat(page)
        os.utime(page, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000_000))
        self.assertEqual(p.wait(5), 0)
        self.assertFalse(os.path.exists(self.sockpath))

    def test_older_daemon_yields_the_socket(self):
        old = self.start()
        new = self.start()                        # rebinds the same path
        self.assertEqual(old.wait(5), 0)
        self.assertIsNone(new.poll())
        c = Client(self.sockpath)                 # the old one did not unlink it
        self.assertTrue(c.call("state")["ok"])
        c.close()


class CheckIdTest(unittest.TestCase):
    def test_check_id(self):
        self.assertEqual(subprocess.call([sys.executable, BRIDGE, "--check-id", "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"]), 0)
        self.assertEqual(subprocess.call([sys.executable, BRIDGE, "--check-id", "PL;rm"]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
