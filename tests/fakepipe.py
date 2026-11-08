#!/usr/bin/env python3
"""A browser stand-in for bin/ytm-cdp: DevTools over fds 3/4, NUL-terminated
JSON, quitting when fd 3 closes, as Chromium does with --remote-debugging-pipe.
Appends every argv and every command it receives to $FAKE_LOG, one JSON per
line. Test.slow is answered only after the next Test.flush; Test.exit quits."""
import json
import os
import sys


def note(obj):
    with open(os.environ["FAKE_LOG"], "a") as f:
        f.write(json.dumps(obj) + "\n")


note({"argv": sys.argv[1:]})
if "--remote-debugging-pipe" not in sys.argv:
    sys.exit(0)                    # a second launch: hand over and leave

out = os.fdopen(4, "wb", 0)


def send(obj):
    out.write(json.dumps(obj).encode() + b"\0")


buf = b""
slow = []
while True:
    data = os.read(3, 65536)
    if not data:
        break
    buf += data
    while b"\0" in buf:
        raw, buf = buf.split(b"\0", 1)
        m = json.loads(raw)
        note({"cmd": m})
        method = m["method"]
        if method == "Test.slow":
            slow.append(m["id"])
            continue
        if method == "Test.flush":
            for i in slow:
                send({"id": i, "result": {"late": True}})
            slow = []
        if method == "Test.surrogate":
            send({"id": m["id"], "result": {"title": "cut \ud83d emoji"}})
            continue
        if method == "Test.exit":
            sys.exit(0)
        if method == "Target.attachToTarget":
            sid = "S%d" % m["id"]
            send({"method": "Target.attachedToTarget", "params": {"sessionId": sid}})
            send({"id": m["id"], "result": {"sessionId": sid}})
            continue
        send({"id": m["id"], "result": {"echo": method}})
