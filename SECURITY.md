# Security notes

This plugin drives a browser. That deserves a plain statement of what it can
and cannot reach, and where a reviewer should look.

## What it touches

| component | privilege | notes |
|---|---|---|
| `bin/ytm-app` | none | launches the user's browser through `bin/ytm-cdp` with a **dedicated** `--user-data-dir` (made 0700) and `--remote-debugging-pipe`. No TCP debug port is ever opened. With `--signin` it instead opens a plain window on the same profile at a fixed `https://accounts.google.com/ServiceLogin` URL, **without** DevTools, refuses if another live browser holds the profile, and records its own pid in `$XDG_RUNTIME_DIR/io.github.kelbresqe.plak.sock.signin` (removed on exit). No sudo, no installer, no network. |
| `bin/ytm-cdp` | none | Python 3 standard library. Starts the browser with DevTools on fds 3/4 (Chromium's pipe mode) and lives exactly as long as it. Relays the pipe on `<profile>/Plak-DevTools.sock`, created with umask 0177 and chmod 0600 inside the 0700 profile, to one client at a time; a client's leftover sessions are detached when it leaves. |
| `bin/ytm-bridge` | none | Python 3 standard library. Connects to `<profile>/Plak-DevTools.sock`; listens on `$XDG_RUNTIME_DIR/io.github.kelbresqe.plak.sock`, created with umask 0177 and chmod 0600. |
| `bin/page.js` | page context | the only code evaluated inside the YouTube Music page. Installed once per attach with `Runtime.evaluate`; every later call is `Runtime.callFunctionOn` with **typed arguments**, never string-built JavaScript. |
| `Service.qml` | shell | spawns the bridge, `notify-send`, `which cava`, `cava`, and `hyprctl dispatch_lua_expression` with fixed argument arrays. |

## What it never does

- Read cookies, local storage, or any browser file. The bridge talks to the
  page only through DevTools calls; the page's own `fetch` carries the
  session. The bridge sees JSON responses and nothing else.
- Store a token or credential anywhere. The only persistent state is
  Chromium's own profile directory (which the user owns and can delete), a
  cached copy of the playlist list, and downloaded artwork for notifications.
- Open a DevTools port. A `--remote-debugging-port` listener on 127.0.0.1
  has no authentication: any local user, or a sandbox or container sharing
  the host network, could attach to the signed-in profile and read its
  cookies. The pipe and the 0600 socket in the 0700 profile are reachable
  only by the user who owns them.
- Expose DevTools on the user's everyday profile. Chromium ≥ 136 refuses
  remote debugging on the default profile regardless; the plugin never asks
  for it.
- Send anything to a third party. All requests go to `music.youtube.com`
  (page context) or to Google's image hosts (artwork for notifications,
  restricted by an allowlist of hostnames).
- Run a shell on user- or page-supplied strings. Nothing that comes back
  from the page reaches `bar.run()`, `execDetached` or a shell. Window
  operations use a fixed class pattern.

## Input validation

Identifiers that come from the UI (playlist, video and browse ids) are
checked in **both** languages before use — `Ytm.isValidId` in QML/JS and
`VALID_ID` in the bridge — against `^[A-Za-z0-9_-]{2,64}$`.
`tests/test-id-grammar.sh` asserts the two agree on a shared vector file. Ids
are then placed only into JSON bodies or `URLSearchParams`.

Search queries are free text capped at 200 characters and travel only as a
JSON string in a POST body. Queue indexes must be integers in `[0, 10000]`.
Artwork URLs must match `https://*.{googleusercontent,ytimg,ggpht,gstatic}.com/…`.

The bridge's protocol rejects unknown ops, malformed JSON and oversized
lines without dropping the client; the fake-DevTools test suite covers each.

## What comes back from the browser is bounded

The DevTools channel carries JSON shaped by the remote page, so every read
from it has a hard cap: one message is at most 16 MiB. Past that the bridge
closes its connection rather than buffer, and the relay skips the message
(it cannot close the browser's pipe without closing the browser). The
largest real reply measured on a live account is `home` at 1.35 MB on the
wire. Artwork downloads stop at 2 MiB. The tests drive the limit from a
hostile endpoint and check the bridge re-attaches afterwards.

## The timed-lyrics request

Timed lyrics are only served to YouTube's mobile clients. That one request is
made with an `ANDROID_MUSIC` client context and — deliberately — **without**
credentials (`credentials: "omit"`, no `SAPISIDHASH`): the mobile client
rejects web sessions, and lyrics need no account. The lyrics id it uses comes
from the signed-in `next` call for the current track.

## Where to look

1. `bin/page.js` — everything that runs inside the page (≈ 200 lines).
2. `Ops` in `bin/ytm-bridge` — the op table and its validation.
3. `Service.qml` — every `Process` command array and `dispatch()` call.

## Reporting

Open an issue on the repository. If it concerns something you would rather
not post publicly, say so in the issue and a private channel will be arranged.
