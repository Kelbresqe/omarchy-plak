"""A fake Chromium DevTools endpoint for testing bin/ytm-bridge without a browser.

Listens where bin/ytm-cdp would (the bridge's --devtools path) and speaks its
framing, NUL-terminated JSON, plus just enough CDP: Target.getTargets,
Target.attachToTarget (flatten), Runtime.enable/evaluate,
Runtime.callFunctionOn (answered from `canned` keyed by the op in
arguments[0]), and can push Target.targetDestroyed on demand. Written
independently of the bridge on purpose, so a framing bug on either side shows
up as a test failure.
"""
import json
import os
import socket
import threading


class Seq:
    """Canned answers handed out in turn; the last one repeats."""

    def __init__(self, *values):
        self.values = list(values)

    def next(self):
        return self.values.pop(0) if len(self.values) > 1 else self.values[0]


class FakeBrowser:
    def __init__(self, profile_dir):
        self.profile_dir = profile_dir
        self.path = os.path.join(profile_dir, "devtools.sock")
        self.targets = [{"targetId": "T1", "type": "page", "url": "https://music.youtube.com/", "title": "YouTube Music"}]
        self.canned = {"state": {"loggedIn": True}}
        self.calls = []          # every Runtime.callFunctionOn params, in order
        self.methods = []        # every CDP method name seen
        self._conn = None
        self._lock = threading.Lock()
        self.conn_count = 0      # connections accepted so far
        self._next_session = 0
        self._srv = None
        os.makedirs(profile_dir, exist_ok=True)

    # -- lifecycle -----------------------------------------------------
    def start(self):
        """The app window comes up: listen where the relay would."""
        self._srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._srv.bind(self.path)
        self._srv.listen(4)
        threading.Thread(target=self._accept, args=(self._srv,), daemon=True).start()

    def destroy_target(self, target_id="T1"):
        self.targets = [t for t in self.targets if t["targetId"] != target_id]
        self._send({"method": "Target.detachedFromTarget", "params": {"sessionId": "S1", "targetId": target_id}})
        self._send({"method": "Target.targetDestroyed", "params": {"targetId": target_id}})

    def add_target(self, target_id="T2", url="https://music.youtube.com/watch?v=x"):
        self.targets.append({"targetId": target_id, "type": "page", "url": url, "title": "YouTube Music"})
        self._send({"method": "Target.targetCreated", "params": {"targetInfo": self.targets[-1]}})

    def close(self):
        if self._srv:
            self._srv.close()
        with self._lock:
            if self._conn:
                self._conn.close()
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass

    def send_raw(self, data):
        """Push bytes straight down the open connection, no framing. Lets a
        test send what the relay would never pass on (an endless message)."""
        with self._lock:
            conn = self._conn
            if conn is None:
                raise ConnectionError("no connection")
        try:
            conn.sendall(data)
        except OSError:
            pass                 # the bridge hung up mid-way, which is the point

    # -- transport -----------------------------------------------------
    def _send(self, obj):
        with self._lock:
            conn = self._conn
            if conn is None:
                return
            try:
                conn.sendall(json.dumps(obj).encode() + b"\0")
            except OSError:
                pass

    def _accept(self, srv):
        while True:
            try:
                conn, _ = srv.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        with self._lock:
            self._conn = conn
            self.conn_count += 1
        buf = b""
        try:
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\0" in buf:
                    raw, buf = buf.split(b"\0", 1)
                    self._handle(json.loads(raw.decode()))
        except (OSError, ValueError):
            pass
        finally:
            with self._lock:
                if self._conn is conn:
                    self._conn = None

    def _handle(self, msg):
        method = msg.get("method", "")
        params = msg.get("params", {}) or {}
        self.methods.append(method)
        result = {}
        if method == "Target.getTargets":
            result = {"targetInfos": list(self.targets)}
        elif method == "Target.attachToTarget":
            self._next_session += 1
            result = {"sessionId": "S%d" % self._next_session}
        elif method == "Runtime.evaluate":
            result = {"result": {"type": "undefined"}}
        elif method == "Runtime.callFunctionOn":
            self.calls.append(params)
            args = params.get("arguments", [])
            op = args[0].get("value") if args else None
            value = self.canned.get(op)
            if isinstance(value, Seq):
                value = value.next()
            if isinstance(value, Exception):
                result = {"result": {"type": "object"}, "exceptionDetails": {"text": str(value)}}
            else:
                result = {"result": {"type": "object", "value": value}}
        reply = {"id": msg.get("id"), "result": result}
        if "sessionId" in msg:
            reply["sessionId"] = msg["sessionId"]
        self._send(reply)
        # A real `play` reloads the page; mimic the navigation event the
        # bridge waits for (and the __ytm reinstall it triggers).
        if method == "Runtime.callFunctionOn" and params.get("arguments", [{}])[0].get("value") == "play":
            self._send({"method": "Page.frameNavigated", "sessionId": msg.get("sessionId"),
                        "params": {"frame": {"id": "F1", "url": "https://music.youtube.com/watch"}}})
