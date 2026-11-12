# Security notes

This plugin drives a browser. That deserves a plain statement of what it can
and cannot reach, and where a reviewer should look.

The boundary it keeps is the user's own account: nothing it creates can be
read or reached by another local user, or by a sandbox that only shares the
host network.

## What it touches

| component | privilege | notes |
|---|---|---|
| `bin/ytm-app` | none | launches the user's browser through `bin/ytm-cdp` with a **dedicated** `--user-data-dir` (made 0700) and `--remote-debugging-pipe`. No TCP debug port is ever opened. Refuses to run without `$XDG_RUNTIME_DIR` (no `/tmp` fallback). With `--signin` it instead opens a plain window on the same profile at a fixed `https://accounts.google.com/ServiceLogin` URL, **without** DevTools, refuses if another live browser holds the profile, and records its own pid in `$XDG_RUNTIME_DIR/io.github.kelbresqe.plak.sock.signin` (removed on exit). No sudo, no installer, no network. |
| `bin/ytm-cdp` | none | Python 3 standard library. Starts the browser with DevTools on fds 3/4 (Chromium's pipe mode) and lives exactly as long as it; if it dies, the browser closes. Relays the pipe on `$XDG_RUNTIME_DIR/io.github.kelbresqe.plak/devtools.sock` (directory 0700, socket umask 0177 and chmod 0600) to one client at a time; a client's leftover sessions are detached when it leaves. Logs to the journal (`journalctl --user -t ytm-cdp`): exit codes, exception types and tracebacks, never message contents. |
| `bin/ytm-bridge` | none | Python 3 standard library. Connects to that relay socket; listens on `$XDG_RUNTIME_DIR/io.github.kelbresqe.plak.sock` (umask 0177, chmod 0600). Refuses to start without `$XDG_RUNTIME_DIR`. Makes no network requests of its own. |
| `bin/ytm-notify` | none | Python 3 with PyGObject (`python-gobject`, part of Omarchy's base install). Reads the track toast as JSON on **stdin** and sends one `Notify` call over the session bus, so titles never appear in a command line (`/proc/<pid>/cmdline` is world-readable). The body is markup-escaped, the icon must be a local path, and the toast is transient (kept out of notification history). |
| `bin/page.js` | page context | the only code evaluated inside the YouTube Music page (≈ 560 lines). Installed once per attach with `Runtime.evaluate`; every later call is `Runtime.callFunctionOn` with **typed arguments**, never string-built JavaScript. |
| `Service.qml` | shell | spawns, with argument arrays: the bridge, `bin/ytm-notify` (data on stdin), `which cava`, `cava -p <config>`, `omarchy-osd` (a number or a fixed message), `hyprctl dispatch_lua_expression` and `hyprctl eval` (constant Lua; no page or settings text reaches it). Nothing from the page or from MPRIS is placed in any argv. |

## What it stores

Every directory that holds this data is 0700 and every file 0600, whatever
the umask; a cache directory left 0755 by an older version is closed up at
start.

| what | where |
|---|---|
| Chromium's profile, including the Google session | `~/.local/share/io.github.kelbresqe.plak/profile/` (and `Plak-Browser`, the name of the browser that built it) |
| last track, list and position (Resume), repeat, shuffle, volume | `~/.local/state/io.github.kelbresqe.plak/session.json` |
| last good copy of the library and home shelves (playlist names and ids) | `~/.cache/io.github.kelbresqe.plak/{library,home}.json` |

No token, cookie or credential is ever written by the plugin; the session
lives only in Chromium's own (encrypted) cookie store.

## What it never does

- Read cookies, local storage, or any browser file. The bridge talks to the
  page only through DevTools calls; the page's own `fetch` carries the
  session. The bridge sees JSON responses and nothing else.
- Open a DevTools port. A `--remote-debugging-port` listener on 127.0.0.1
  has no authentication: any local user, or a sandbox or container sharing
  the host network, could attach to the signed-in profile and read its
  cookies. The pipe and the 0600 socket in a 0700 runtime directory are
  reachable only by the user who owns them.
- Expose DevTools on the user's everyday profile. Chromium ≥ 136 refuses
  remote debugging on the default profile regardless; the plugin never asks
  for it.
- Put account data where others can see it: not in a command line, not in a
  world-readable file, not in a log line, not in notification history.
- Send anything to a third party. Requests go to `music.youtube.com` (page
  context). Thumbnails, which the shell loads itself, are used only from
  `https://*.{googleusercontent,ytimg,ggpht,gstatic}.com/`; any other URL in
  page data is ignored. Notification artwork is the local file Chromium
  hands MPRIS; nothing is downloaded for it.
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

The bridge's protocol answers unknown ops and malformed JSON with an error
and keeps the client; a line that grows past 1 MiB without ending drops that
client. The fake-DevTools test suite covers each.

## What comes back from the browser is bounded

The DevTools channel carries JSON shaped by the remote page, so every read
from it has a hard cap: one message is at most 16 MiB. Past that the bridge
closes its connection rather than buffer, and the relay skips the message
(it cannot close the browser's pipe without closing the browser). The
largest real reply measured on a live account is `home` at 1.35 MB on the
wire. The tests drive the limit from a hostile endpoint and check the bridge
re-attaches afterwards.

## The timed-lyrics request

Timed lyrics are only served to YouTube's mobile clients. That one request is
made with an `ANDROID_MUSIC` client context and — deliberately — **without**
credentials (`credentials: "omit"`, no `SAPISIDHASH`): the mobile client
rejects web sessions, and lyrics need no account. The lyrics id it uses comes
from the signed-in `next` call for the current track.

## Where to look

1. `bin/page.js` — everything that runs inside the page.
2. `Ops` in `bin/ytm-bridge` — the op table and its validation.
3. `Service.qml` — every `Process` command array and `dispatch()` call.
4. `bin/ytm-cdp` — the only process that can talk to the browser.

## Reporting

Open an issue on the repository. If it concerns something you would rather
not post publicly, say so in the issue and a private channel will be arranged.
