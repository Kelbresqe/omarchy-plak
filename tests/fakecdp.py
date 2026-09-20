"""A fake Chromium DevTools endpoint for testing bin/ytm-bridge without a browser.

Speaks just enough HTTP + RFC 6455 + CDP: /json/version, Target.getTargets,
Target.attachToTarget (flatten), Runtime.enable/evaluate, Runtime.callFunctionOn
(answered from `canned` keyed by the op in arguments[0]), and can push
Target.targetDestroyed on demand. Written independently of the bridge on
purpose, so a framing bug on either side shows up as a test failure.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class FakeBrowser:
    def __init__(self, profile_dir):
        self.profile_dir = profile_dir
        self.targets = [{"targetId": "T1", "type": "page", "url": "https://music.youtube.com/", "title": "YouTube Music"}]
        self.canned = {"state": {"loggedIn": True}}
        self.calls = []          # every Runtime.callFunctionOn params, in order
        self.methods = []        # every CDP method name seen
        self._ws = None
        self._ws_lock = threading.Lock()
        self.ws_count = 0        # websocket connections accepted so far
        self._next_session = 0
        fake = self
        os.makedirs(profile_dir, exist_ok=True)

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                if self.path == "/json/version":
                    body = json.dumps({"Browser": "Fake/1", "webSocketDebuggerUrl":
                                       "ws://127.0.0.1:%d/devtools/browser/fake" % fake.port}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                if self.path.startswith("/devtools/browser/"):
                    key = self.headers.get("Sec-WebSocket-Key", "")
                    accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
                    self.send_response(101)
                    self.send_header("Upgrade", "websocket")
                    self.send_header("Connection", "Upgrade")
                    self.send_header("Sec-WebSocket-Accept", accept)
                    self.end_headers()
                    self.wfile.flush()
                    fake._serve_ws(self.connection)
                    return
                self.send_error(404)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    # -- lifecycle -----------------------------------------------------
    def write_port_file(self):
        with open(os.path.join(self.profile_dir, "DevToolsActivePort"), "w") as f:
            f.write("%d\n/devtools/browser/fake\n" % self.port)

    def remove_port_file(self):
        try:
            os.unlink(os.path.join(self.profile_dir, "DevToolsActivePort"))
        except FileNotFoundError:
            pass

    def destroy_target(self, target_id="T1"):
        self.targets = [t for t in self.targets if t["targetId"] != target_id]
        self._send({"method": "Target.detachedFromTarget", "params": {"sessionId": "S1", "targetId": target_id}})
        self._send({"method": "Target.targetDestroyed", "params": {"targetId": target_id}})

    def add_target(self, target_id="T2", url="https://music.youtube.com/watch?v=x"):
        self.targets.append({"targetId": target_id, "type": "page", "url": url, "title": "YouTube Music"})
        self._send({"method": "Target.targetCreated", "params": {"targetInfo": self.targets[-1]}})

    def close(self):
        self.httpd.shutdown()

    def send_raw(self, data):
        """Push bytes straight down the open websocket, no framing. Lets a test
        speak a frame header the fake would never produce (a lying length)."""
        with self._ws_lock:
            ws = self._ws
            if ws is None:
                raise ConnectionError("no websocket")
            ws.sendall(data)

    # -- websocket -----------------------------------------------------
    def _send(self, obj):
        with self._ws_lock:
            ws = self._ws
            if ws is None:
                return
            data = json.dumps(obj).encode()
            hdr = bytes([0x81])
            n = len(data)
            if n < 126:
                hdr += bytes([n])
            elif n < 65536:
                hdr += bytes([126]) + struct.pack(">H", n)
            else:
                hdr += bytes([127]) + struct.pack(">Q", n)
            try:
                ws.sendall(hdr + data)
            except OSError:
                pass

    def _recv_frame(self, conn):
        def read(n):
            buf = b""
            while len(buf) < n:
                chunk = conn.recv(n - len(buf))
                if not chunk:
                    raise ConnectionError
                buf += chunk
            return buf
        b0, b1 = read(2)
        opcode = b0 & 0x0F
        masked = b1 & 0x80
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", read(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", read(8))[0]
        mask = read(4) if masked else None
        payload = read(n)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return opcode, payload

    def _serve_ws(self, conn):
        with self._ws_lock:
            self._ws = conn
            self.ws_count += 1
        try:
            while True:
                opcode, payload = self._recv_frame(conn)
                if opcode == 0x8:
                    break
                if opcode == 0x9:
                    conn.sendall(bytes([0x8A, len(payload)]) + payload)
                    continue
                if opcode != 0x1:
                    continue
                msg = json.loads(payload.decode())
                self._handle(msg)
        except (ConnectionError, OSError, ValueError):
            pass
        finally:
            with self._ws_lock:
                if self._ws is conn:
                    self._ws = None

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
