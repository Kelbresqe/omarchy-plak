"""bin/ytm-cdp against tests/fakepipe.py. No browser, no network."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
RELAY = os.path.join(os.path.dirname(HERE), "bin", "ytm-cdp")
FAKE = os.path.join(HERE, "fakepipe.py")


class Conn:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(path)
        self.buf = b""

    def send(self, i, method, params=None):
        self.sock.sendall(json.dumps({"id": i, "method": method, "params": params or {}}).encode() + b"\0")

    def read(self):
        while b"\0" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("relay closed")
            self.buf += chunk
        raw, self.buf = self.buf.split(b"\0", 1)
        return json.loads(raw)

    def reply(self, i):
        while True:
            m = self.read()
            if m.get("id") == i:
                return m

    def close(self):
        self.sock.close()


class RelayTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "cdp.sock")
        self.log = os.path.join(self.tmp, "log")
        self.env = dict(os.environ, FAKE_LOG=self.log)
        self.proc = self.launch()
        for _ in range(50):
            if os.path.exists(self.path):
                break
            time.sleep(0.1)
        else:
            self.fail("relay socket never appeared")

    def launch(self):
        return subprocess.Popen([sys.executable, RELAY, self.path, sys.executable, FAKE, "--x",
                                 "--remote-debugging-pipe"], env=self.env, stderr=subprocess.DEVNULL)

    def tearDown(self):
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait(5)

    def entries(self, key):
        with open(self.log) as f:
            return [e[key] for e in map(json.loads, f) if key in e]

    def wait_for(self, pred, timeout=5):
        end = time.time() + timeout
        while time.time() < end and not pred():
            time.sleep(0.05)
        return pred()

    def test_socket_is_private_and_relays(self):
        self.assertEqual(oct(os.stat(self.path).st_mode & 0o777), "0o600")
        self.assertEqual(self.entries("argv"), [["--x", "--remote-debugging-pipe"]])
        c = Conn(self.path)
        c.send(7, "Browser.getVersion")
        self.assertEqual(c.reply(7), {"id": 7, "result": {"echo": "Browser.getVersion"}})

    def test_second_client_is_refused(self):
        a = Conn(self.path)
        b = Conn(self.path)
        self.assertEqual(b.sock.recv(1), b"")
        a.send(1, "Ping")
        self.assertEqual(a.reply(1)["result"], {"echo": "Ping"})

    def test_reply_for_an_earlier_client_is_dropped(self):
        a = Conn(self.path)
        a.send(1, "Test.slow")
        time.sleep(0.2)
        a.close()
        time.sleep(0.2)
        b = Conn(self.path)
        b.send(1, "Test.flush")        # same id the first client used
        self.assertEqual(b.read(), {"id": 1, "result": {"echo": "Test.flush"}})

    def test_leaving_client_sessions_are_detached(self):
        a = Conn(self.path)
        a.send(1, "Target.attachToTarget", {"targetId": "T1", "flatten": True})
        self.assertEqual(a.reply(1)["result"], {"sessionId": "S1"})
        a.close()
        cmds = lambda: [c["method"] for c in self.entries("cmd")]
        self.assertTrue(self.wait_for(lambda: "Target.setDiscoverTargets" in cmds()))
        detach = [c for c in self.entries("cmd") if c["method"] == "Target.detachFromTarget"]
        self.assertEqual([c["params"] for c in detach], [{"sessionId": "S1"}])
        b = Conn(self.path)                # the next client gets in afterwards
        b.send(2, "Ping")
        self.assertEqual(b.reply(2)["result"], {"echo": "Ping"})

    def test_lone_surrogate_passes_through(self):
        # Page data can carry half an emoji; the relay must pass it on and
        # keep relaying afterwards.
        c = Conn(self.path)
        c.send(1, "Test.surrogate")
        self.assertEqual(c.reply(1)["result"], {"title": "cut \ud83d emoji"})
        c.send(2, "Ping")
        self.assertEqual(c.reply(2)["result"], {"echo": "Ping"})

    def test_malformed_command_drops_the_client(self):
        a = Conn(self.path)
        a.sock.sendall(b'{"method":"x"}\0')     # no id
        self.assertEqual(a.sock.recv(1), b"")
        b = Conn(self.path)
        b.send(1, "Ping")
        self.assertEqual(b.reply(1)["result"], {"echo": "Ping"})

    def test_second_launch_hands_over_without_the_pipe(self):
        second = self.launch()
        self.assertEqual(second.wait(5), 0)
        self.assertEqual(self.entries("argv")[-1], ["--x"])
        self.assertTrue(os.path.exists(self.path))
        c = Conn(self.path)
        c.send(1, "Ping")
        self.assertEqual(c.reply(1)["result"], {"echo": "Ping"})

    def test_relay_ends_with_the_browser(self):
        c = Conn(self.path)
        c.send(1, "Test.exit")
        self.assertEqual(self.proc.wait(5), 0)
        self.assertFalse(os.path.exists(self.path))

    def test_stale_socket_is_replaced(self):
        self.proc.kill()                   # no cleanup: the socket file stays
        self.proc.wait(5)
        self.assertTrue(os.path.exists(self.path))
        self.proc = self.launch()
        self.assertTrue(self.wait_for(lambda: len(self.entries("argv")) == 2))
        c = Conn(self.path)
        c.send(1, "Ping")
        self.assertEqual(c.reply(1)["result"], {"echo": "Ping"})


if __name__ == "__main__":
    unittest.main()
