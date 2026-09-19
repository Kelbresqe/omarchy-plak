# TekTube (`tiertek.ytm`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (single agent — CLAUDE.md §5). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Omarchy bar widget + panel that signs in to the user's real YouTube Music account (via a driven Chromium `--app` window), lists and starts their playlists/library, controls playback, shows synced lyrics, likes/dislikes, starts radio and manages the queue — all drawn from the active theme.

**Architecture:** A Python-stdlib bridge daemon (`bin/ytm-bridge`) launches/attaches to a dedicated-profile Chromium window over the Chrome DevTools Protocol and executes the site's own InnerTube calls *inside the page*, serving results as JSON lines on a unix socket. `Service.qml` supervises the bridge, owns the socket and the MPRIS player; `BarWidget.qml`/`Panel.qml` render. MPRIS is the always-on transport; the bridge adds account data.

**Tech Stack:** Quickshell 0.3 QML (`qs.Ui`, `qs.Commons`, `Quickshell.Io.Socket`, `Quickshell.Services.Mpris`), Python 3.12+ stdlib (`socket`, `json`, `http.client`, hand-rolled RFC 6455), bash, node for `.cjs` tests.

**Spec:** `docs/superpowers/specs/2026-09-19-omarchy-tektube-design.md`

## Global Constraints

- Plugin id `tiertek.ytm`; kinds `["bar-widget","service"]`; `keepLoaded: true`.
- No dependency beyond a Chromium-family browser; `cava` optional. No pip, no npm at runtime.
- Id grammar `^[A-Za-z0-9_-]{2,64}$` enforced in `Ytm.js` AND `bin/ytm-bridge` before any id reaches a URL or the page.
- All page JS goes through `Runtime.callFunctionOn` with typed `arguments`; never string-concatenate ids into JS.
- Never Firefox. Browser order: setting → xdg default if Chromium-family → `google-chrome-stable`, `brave`, `chromium`, `vivaldi`, `microsoft-edge-stable`.
- Profile `$XDG_DATA_HOME/tiertek.ytm/profile`; socket `$XDG_RUNTIME_DIR/tiertek.ytm.sock` mode 0600; cache `$XDG_CACHE_HOME/tiertek.ytm/`.
- Theme only: colours from `Color.*` / `bar.foreground` / `Style.*`; no hex literals, no bundled fonts.
- Nothing from the page or the bridge ever reaches `bar.run()` / a shell.
- Git identity `TierTek <28792124+TIerTek@users.noreply.github.com>`; commits only when Charles asks (CLAUDE.md) — the "Commit" steps below are *staging points*, run `git add` only.
- Installed copy must be refreshed with `omarchy restart shell` to see QML changes (hyprpm landmine 1).

---

## File map

| File | Responsibility |
|---|---|
| `manifest.json` | id, kinds, entry points, settings schema |
| `bin/ytm-app` | choose browser, build flags, launch detached; `--print` mode for tests |
| `bin/ytm-bridge` | daemon: attach via CDP, socket server, ops; `--once <op> [json]` CLI mode for tests/spike |
| `bin/page.js` | the ONE JS function injected into the page (InnerTube fetch + SAPISIDHASH + ytcfg) |
| `Ytm.js` | pure JS: id grammar, InnerTube → flat models |
| `Bridge.js` | pure JS: request ids, pending map, line demux, state reducer |
| `Service.qml` | bridge supervisor, Socket, MPRIS pick, shared state, toast, parking |
| `BarWidget.qml` | pill |
| `Panel.qml` + `views/*.qml` | popup, five views, footer transport |
| `hypr/ytm.lua` | optional keybinds |
| `tests/` | see tasks |

---

### Task 1: Scaffold + manifest + test runner

**Files:** Create `manifest.json`, `LICENSE` (MIT, "TierTek"), `tests/run-all.sh`, `.gitignore`.

**Produces:** manifest with settings defaults used by all QML: `browser:""`, `showWhenIdle:true`, `toast:true`, `autoRelaunch:false`, `parkWindow:true`, `visualizer:true`, `maxLabelWidth:180`.

- [ ] Write `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "tiertek.ytm",
  "name": "YouTube Music",
  "version": "0.1.0",
  "author": "TierTek",
  "license": "MIT",
  "description": "Your real YouTube Music account in the Omarchy bar: playlists, library, queue, synced lyrics, likes and radio, drawn from your theme. Signs in through a normal Google login; no cookies or tokens ever leave the browser.",
  "homepage": "https://github.com/TIerTek/omarchy-tektube",
  "repository": "https://github.com/TIerTek/omarchy-tektube",
  "kinds": ["bar-widget", "service"],
  "keepLoaded": true,
  "entryPoints": { "barWidget": "BarWidget.qml", "service": "Service.qml" },
  "barWidget": {
    "displayName": "YouTube Music",
    "description": "Now playing, playlists, queue and lyrics for your YouTube Music account",
    "category": "Media",
    "allowMultiple": false,
    "defaultSection": "left",
    "defaults": {
      "browser": "", "showWhenIdle": true, "toast": true, "autoRelaunch": false,
      "parkWindow": true, "visualizer": true, "maxLabelWidth": 180
    },
    "schema": [
      {"key":"browser","type":"string","label":"Browser","defaultValue":"","description":"Executable name of a Chromium-family browser. Empty = your default browser if it is Chromium-based, else the first of Chrome, Brave, Chromium, Vivaldi, Edge found."},
      {"key":"showWhenIdle","type":"bool","label":"Show in bar when nothing is playing","defaultValue":true},
      {"key":"toast","type":"bool","label":"Notify on track change","defaultValue":true},
      {"key":"autoRelaunch","type":"bool","label":"Reopen YouTube Music automatically if its window is closed","defaultValue":false},
      {"key":"parkWindow","type":"bool","label":"Keep the YouTube Music window in a hidden special workspace","defaultValue":true},
      {"key":"visualizer","type":"bool","label":"Spectrum bars (needs cava)","defaultValue":true},
      {"key":"maxLabelWidth","type":"number","label":"Bar label width (px)","defaultValue":180}
    ]
  }
}
```

- [ ] Write `tests/run-all.sh`: runs every `tests/test-*.sh`, `python3 tests/test-*.py`, `node tests/*.cjs`, then `omarchy plugin validate .` if `omarchy` on PATH; exits non-zero on first failure.
- [ ] Run `bash tests/run-all.sh` → passes with 0 tests. `omarchy plugin validate .` passes (needs `BarWidget.qml`/`Service.qml` to exist → create one-line `Item {}` stubs).
- [ ] Stage: `git add -A`.

### Task 2: Browser launcher `bin/ytm-app`

**Files:** Create `bin/ytm-app` (bash), `tests/test-app-launch.sh`.

**Interfaces — Produces:** `ytm-app [--browser NAME] [--print]`. `--print` writes the argv it would exec, one arg per line, and exits 0; exit 3 = no Chromium-family browser found. Env `YTM_PROFILE_DIR` overrides the profile dir (tests). Launch = `setsid uwsm-app -- <argv>` when `uwsm-app` exists, else `setsid <argv> &`.

- [ ] Write `tests/test-app-launch.sh` using a fake `$PATH` dir with executable stubs and a fake `xdg-settings`:
  1. only `firefox` present → exit 3, stderr mentions "Chromium-family".
  2. `brave` + `chromium` present, xdg default `firefox.desktop` → picks `brave`? No — order is chrome, brave, chromium: with `google-chrome-stable` absent → `brave`.
  3. xdg default `chromium.desktop` and both present → `chromium`.
  4. `--browser vivaldi` → `vivaldi` even when chrome present; `--browser firefox` → exit 3.
  5. printed argv contains, in order: `--app=https://music.youtube.com`, `--user-data-dir=$YTM_PROFILE_DIR`, `--remote-debugging-port=0`, `--class=tiertek.ytm`, `--autoplay-policy=no-user-gesture-required`, `--no-first-run`, `--no-default-browser-check`; never contains `--remote-debugging-port=9222`.
- [ ] Run → fails (file missing).
- [ ] Implement `bin/ytm-app`: `set -euo pipefail`; candidate list; `pick()` checks `command -v`; xdg lookup via `xdg-settings get default-web-browser 2>/dev/null` mapped `google-chrome*→google-chrome-stable`, `brave*→brave`, `chromium*→chromium`, `vivaldi*→vivaldi`, `microsoft-edge*→microsoft-edge-stable`; `mkdir -p "$profile"` (0700); build array; `--print` loops `printf '%s\n'`.
- [ ] Run tests → pass. Stage.

### Task 3: Bridge core — CDP client, attach, socket server, `state`

**Files:** Create `bin/ytm-bridge` (python3, executable), `tests/test-bridge.py`, `tests/fakecdp.py` (fake browser: HTTP `/json/version`, `/json/list`, websocket server implementing `Target.getTargets`, `Target.attachToTarget`, `Runtime.callFunctionOn` returning canned results by function-name marker, `Target.targetDestroyed` on demand).

**Interfaces — Produces:**
- CLI: `ytm-bridge [--socket PATH] [--profile DIR] [--launcher PATH]` (daemon); `ytm-bridge --once OP [JSON]` (attach, run one op, print JSON, exit).
- Socket protocol per spec. Request `{"id":n,"op":"…",…}`; response `{"id":n,"ok":true,…}` / `{"id":n,"ok":false,"error":"code"}`; events `{"ev":"state","state":…}`. Error codes: `bad-request`, `bad-id`, `no-app`, `signed-out`, `page-error`, `timeout`.
- States: `no-app`, `attaching`, `signed-out`, `ready`.
- Python API inside file: `class Cdp` (`connect(ws_url)`, `call(method, params, session=None, timeout=10)`, `events` queue), `class Attacher` (poll `DevToolsActivePort`, find target whose url starts with `https://music.youtube.com`), `class Ops` (one method per op; each validates ids with `VALID_ID = re.compile(r'^[A-Za-z0-9_-]{2,64}$')`).

- [ ] Write `tests/fakecdp.py`: threaded HTTP server on 127.0.0.1:0; writes `DevToolsActivePort` into a temp profile dir; websocket handshake (`Sec-WebSocket-Accept` = base64(sha1(key + GUID))); frames: text, ping/pong, close; dispatch on `method`; `Runtime.callFunctionOn` returns `{"result":{"type":"object","value": canned[fn_marker]}}` where `fn_marker` is parsed from the `functionDeclaration` comment `/*ytm:<op>*/`; helper `destroy_target()` pushes `Target.targetDestroyed`.
- [ ] Write `tests/test-bridge.py` (unittest): (a) `state` is `no-app` when `DevToolsActivePort` absent, becomes `ready` after fake writes it and the page reports `LOGGED_IN:true`; (b) `signed-out` when `LOGGED_IN:false`; (c) `library.playlists` with bad id → n/a; `playlist.items {"list":"PL;rm -rf"}` → `{"ok":false,"error":"bad-id"}` and fake CDP receives NO callFunctionOn; (d) two concurrent clients get their own ids back; (e) `destroy_target()` → event `{"ev":"state","state":"no-app"}` within 2 s, then re-attach when a new target appears; (f) malformed line → `bad-request`, connection stays open.
- [ ] Run → fails (no bridge).
- [ ] Implement `bin/ytm-bridge`:
  - `WebSocket` class: `http.client`-free raw `socket` handshake, client frames masked, server frames unmasked, fragmented text reassembly, 64-bit lengths, `ping→pong`.
  - `Cdp`: reader thread → `pending[id].set(result)` or `events.put(msg)`; `call()` waits with timeout.
  - `Attacher` thread: every 1 s read `profile/DevToolsActivePort`; on change `GET http://127.0.0.1:{port}/json/version` → `webSocketDebuggerUrl`; `Target.getTargets`; pick `type=="page"` with url prefix; `Target.attachToTarget {flatten:true}` → `sessionId`; `Runtime.enable`; state → `attaching` → check login via `page.js` fn `ytmState()` → `ready|signed-out`; on `Target.targetDestroyed`/socket error → `no-app`, broadcast event.
  - `Server`: `AF_UNIX` listen, `os.chmod(path,0o600)`, one thread per client, JSON-lines; `broadcast(ev)`.
  - Ops table `OPS = {"state":..., ...}`; unknown → `bad-request`. Only `state`, `app.launch` in this task; the rest in Task 5.
  - Signals: SIGTERM → close socket, unlink path.
- [ ] Run tests → pass. Stage.

### Task 4: Shared id grammar

**Files:** Create `Ytm.js` (start), `tests/fixtures/ids.txt`, `tests/test-id-grammar.sh`, `tests/test-ytm-model.cjs` (start).

**Interfaces — Produces:** `Ytm.isValidId(s) → bool` (JS, `.pragma library`); bridge `--check-id S` exits 0/1.

- [ ] `tests/fixtures/ids.txt` lines `ok|PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf`, `ok|dQw4w9WgXcQ` (11 chars ≥ 8 ✓), `ok|VLPL123456789`, `ok|MPLYt_abcdef12345`, `bad|` , `bad|abc`, `bad|PL;touch`, `bad|PL 123456789`, `bad|--help1234`(✓ allowed? starts with `-` → the grammar allows it; args are never passed to a shell, only to JSON → keep allowed), `bad|` + 65 chars.
  Decision: `-` first char IS allowed (real ids start with `-`); safety comes from ids never reaching a shell.
- [ ] `tests/test-id-grammar.sh`: for each line run `node -e` with `Ytm.js` and `bin/ytm-bridge --check-id` and assert both agree with the expected column.
- [ ] Implement both; run; pass. Stage.

### Task 5: InnerTube ops in the bridge + page function + model parsers

**Files:** Create `bin/page.js`; extend `bin/ytm-bridge` (Ops), `Ytm.js`, `tests/test-ytm-model.cjs`, `tests/fixtures/innertube/*.json` (hand-written minimal shapes now, replaced by scrubbed real captures after the live spike).

**Interfaces — Produces (bridge ops, all validated):**
`library.playlists` → `{items:[{id,title,count,thumb,author}]}`; `playlist.items{list}` → `{items:[{videoId,title,artist,album,dur,thumb,liked}]}`; `play{list?,video?,index?,shuffle?}` → `{}`; `queue` → `{items:[…],current}`; `queue.jump{index}`; `like|dislike|unlike{video}`; `radio{video}`; `lyrics{video}` → `{timed:[{t,line}]|null, plain|null, source}`; `search{q}` (q ≤ 200 chars, any text — it goes only into a JSON body) → `{songs,albums,playlists}`; `art{url}` → `{path}` (downloads thumbnail to cache, for toasts).

`bin/page.js` exports one function `ytm(op, arg)` installed into the page via `Runtime.evaluate` once per attach (`window.__ytm`), then every op is `Runtime.callFunctionOn {functionDeclaration:"function(op,arg){return window.__ytm(op,arg)}", arguments:[{value:op},{value:arg}], awaitPromise:true, returnByValue:true}`. Inside: 

```js
async function innertube(endpoint, body, clientOverride) {
  const cfg = window.ytcfg.get('INNERTUBE_CONTEXT');
  const ctx = JSON.parse(JSON.stringify(cfg));
  if (clientOverride) Object.assign(ctx.client, clientOverride);
  const sapisid = (document.cookie.match(/(?:^|; )SAPISID=([^;]+)/)||[])[1];
  const ts = Math.floor(Date.now()/1000);
  const hash = await sha1hex(`${ts} ${sapisid} https://music.youtube.com`);
  const r = await fetch(`/youtubei/v1/${endpoint}?prettyPrint=false`, {
    method:'POST', credentials:'include',
    headers:{'Content-Type':'application/json','Authorization':`SAPISIDHASH ${ts}_${hash}`,
      'X-Goog-AuthUser': String(window.ytcfg.get('SESSION_INDEX')||0),
      'X-Origin':'https://music.youtube.com','X-Youtube-Client-Name':'67',
      'X-Youtube-Client-Version': ctx.client.clientVersion},
    body: JSON.stringify({context: ctx, ...body})});
  if (!r.ok) throw new Error('http-'+r.status);
  return r.json();
}
```
Ops map: `library.playlists → browse {browseId:'FEmusic_liked_playlists'}`; `playlist.items → browse {browseId:'VL'+list}` (strip existing `VL`); `queue → next {videoId, playlistId, enablePersistentPlaylistPanel:true, isAudioOnly:true}` merged with the SPA's own queue read from `document.querySelector('ytmusic-player-queue')?.__data?.queue?.store?.getState?.()` — try the DOM first, fall back to `next`; `play → window.location.assign('/watch?v=…&list=…')` built with `URLSearchParams`; `like → like/like {target:{videoId}}`, `dislike → like/dislike`, `unlike → like/removelike`; `radio → play with list:'RDAMVM'+videoId`; `lyrics → next` → find tab with `browseId` starting `MPLYt` → `browse {browseId}` with `clientOverride:{clientName:'ANDROID_MUSIC',clientVersion:'7.21.50'}` → `contents.sectionListRenderer…timedLyricsData` else plain `contents…description.runs` text; `search → search {query, params:'EgWKAQIIAWoKEAoQCRADEAQQBQ%3D%3D'}` (songs filter) — return raw JSON, parse in `Ytm.js`. `state → {loggedIn: !!window.ytcfg.get('LOGGED_IN'), account: window.ytcfg.get('DATASYNC_ID')?'set':''}`.

`Ytm.js` parsers (pure, fixture-tested): `parsePlaylists(browseJson)`, `parsePlaylistItems(browseJson)`, `parseQueue(nextJson|domQueue)`, `parseLyrics(browseJson)`, `parseSearch(searchJson)`. Each returns `[]`/`null` on unknown shape, never throws. Bridge returns raw InnerTube JSON for `library.playlists`, `playlist.items`, `queue`, `lyrics`, `search`; QML parses via `Ytm.js`. (Keeps the Python side dumb and the parsers testable in node.)

- [ ] Write `tests/test-ytm-model.cjs` with minimal hand-built fixtures for each parser + empty `{}` + `null` inputs.
- [ ] Extend `tests/test-bridge.py`: each op sends exactly one `callFunctionOn` with `arguments[0].value == op` and `arguments[1].value` equal to the validated arg; `play` with `shuffle:true` passes it through; `search` q >200 → `bad-request`; ops while `signed-out` → `signed-out` (except `state`, `app.*`).
- [ ] Run → fail. Implement. Run → pass. Stage.

### Task 5b: LIVE SPIKE (needs the maintainer to sign in once)

- [ ] `bin/ytm-app` on sarial → window opens → **the maintainer signs in**.
- [ ] `bin/ytm-bridge --once state` → `ready`. Then `--once library.playlists`, `playlist.items`, `queue`, `lyrics` on a popular track, `search`. Save scrubbed responses (strip `trackingParams`, `clickTrackingParams`, account fields) as fixtures, replacing the hand-built ones. Fix parsers to real shapes.
- [ ] Decision recorded in the spec: does `ANDROID_MUSIC` timed lyrics work from page context? If not: plain lyrics only for v1, timed marked deferred.

### Task 6: `Bridge.js` + `Service.qml`

**Files:** Create `Bridge.js`, `Service.qml`, `tests/test-bridge-js.cjs`.

**Interfaces — Produces:** `Bridge.js` (`.pragma library`): `newClient()` → `{nextId, pending:{}}`; `encode(client, op, arg) → {id, line}`; `feed(client, chunk) → {responses:[{id,msg}], events:[msg], rest}` (handles partial lines); `reduce(state, msg)` → new state object `{link:"down|up", app:"no-app|attaching|signed-out|ready"}`.
`Service.qml` (`Item`, `property var shell`): `readonly property string link`, `readonly property string app`, `readonly property var player` (MPRIS player with `desktopEntry`/`dbusName` containing `tiertek.ytm` or `identity` matching the browser AND trackArtUrl present — first choice: the player whose `dbusName` ends with the chromium instance created with our class; fallback: any browser player currently playing with title), `function request(op, arg, cb)`, `function launchApp()`, `function revealApp()`, `function hideApp()`, `signal event(var msg)`, `property var library`, `property var queue`, `property var lyrics`, `property string currentVideoId`. `Process` bridge with restart backoff 1→30 s; `Socket { path: runtimeDir + "/tiertek.ytm.sock"; parser: SplitParser { splitMarker: "\n" } }` reconnect timer 2 s.
- [ ] Tests for `Bridge.js` (ids increment, partial-line reassembly, response routing, reducer transitions). Run → fail → implement → pass.
- [ ] `Service.qml` per above; also `Timer` polling `state` every 5 s only while `app != ready`.
- [ ] Stage.

### Task 7: `BarWidget.qml` pill

- [ ] Mirror `omarchy.media/BarWidget.qml` structure; `readonly property var svc: bar?.shell?.pluginServiceFor("tiertek.ytm","tiertek.ytm")`; art thumb `Image` 16 px radius 3 (via `OpacityMask`-free approach: `BorderSurface` + `Image` PreserveAspectCrop); title·artist marquee only when overflowing and panel closed; 1 px accent `Rectangle` at bottom with width = position/length; glyph `󰗃` (YouTube) when idle. Visible = `hasMedia || setting("showWhenIdle")`. Buttons: left toggle panel, middle play/pause, right next, wheel volume ±5 % via `player.volume` when `player.volumeSupported`.
- [ ] Loader for `Panel.qml` as in scratchpad-deck; `IpcHandler target "tiertek.ytm"`: `open/close/toggle/playPause/next/prev/reveal/launch`.
- [ ] `qmllint -I /usr/share/omarchy/shell BarWidget.qml`; install to `~/.config/omarchy/plugins/tiertek.ytm`, add to `shell.json`, `omarchy restart shell`, verify pill. Stage.

### Task 8: `Panel.qml` + views

**Files:** `Panel.qml`, `views/PlayerView.qml`, `views/PlaylistsView.qml`, `views/QueueView.qml`, `views/SearchView.qml`, `views/LyricsView.qml`, `views/Transport.qml`, `views/Rail.qml`, `views/SignIn.qml`.

- [ ] `Panel.qml`: `Panel { moduleName:"tiertek.ytm"; manageIpc:false }`, width `Style.space(560)`, height `Style.space(420)`; `property string view: "player"`; shows `SignIn` when `svc.app != "ready"` with the line for each state and one button (`launchApp` / "Waiting for sign-in…" / "Starting bridge…"); else `Rail` + `Loader` of the view + `Transport`.
- [ ] `Transport`: prev/play/next/shuffle/repeat glyph buttons, `PanelSlider` seek bound to `player.position/length` (write `player.position = v` on release), volume slider, like button (calls `svc.request("like"/"unlike")`, optimistic toggle).
- [ ] `PlaylistsView`: `svc.request("library.playlists")` on first show → `Ytm.parsePlaylists`; grid of cards (thumb 96 px, title, count); Enter/click → `PlaylistItems` sub-list with Play all / Shuffle / row play.
- [ ] `QueueView`: `svc.queue` list, current row in accent, click → `queue.jump`.
- [ ] `SearchView`: `TextField`, debounce 300 ms, `search` → `Ytm.parseSearch`; sections Songs/Albums/Playlists; Enter plays; `r` on a row → radio.
- [ ] `LyricsView`: `svc.lyrics`; if `timed` → `ListView` auto-`positionViewAtIndex(current, Center)` where current = last line with `t <= player.position*1000`, accent colour + slightly larger; click → `player.position = t/1000`; else plain text; else "No lyrics for this track".
- [ ] `PlayerView`: big art (`Style.space(180)`), title/artist/album, glow (Task 9), cava (Task 9).
- [ ] Keys via `PanelKeyCatcher`: `/` search, `l` like, `r` radio on current, `q` queue, `y` lyrics, `p` playlists, `Esc` close, arrows/Enter in lists, `Space` play/pause.
- [ ] `qmllint` all; restart shell; walk every view live. Stage.

### Task 9: Eye candy

- [ ] Glow: `Canvas` 16×16 drawing the art scaled down, `getImageData` → mean RGB (skip near-black/near-white) → `Qt.rgba` → `Color.mix`-style manual mix 0.6 art / 0.4 `Color.accent`, then clamp lightness toward `Color.background` (`Qt.hsla` with l = bg.l ± 0.12). Applied as a `RadialGradient`-free soft rectangle: two stacked `Rectangle`s with opacity 0.18/0.08 behind the art. Test: `tests/test-glow.cjs` for the pure mixing math extracted to `Glow.js`.
- [ ] Toast: on `svc.currentVideoId` change while `player.isPlaying` and panel closed and `setting("toast")`: `svc.request("art",{url:artUrl})` → `notify-send --app-name="YouTube Music" -i <path> -h string:x-canonical-private-synchronous:tiertek.ytm "<title>" "<artist>"` via `Process` with an argv array (no shell). Replace-id keeps one toast.
- [ ] Cava: if `cava` on PATH and `setting("visualizer")`: `Process ["cava","-p",<config in cache dir: raw output, ascii, 16 bars>]`, parse `;`-separated ints, 16 `Rectangle`s in accent at 0.5 opacity; only while `player.isPlaying && panel opened`.
- [ ] Stage.

### Task 10: Window parking, keybinds, sleep timer, auto-relaunch

- [ ] `Service.qml`: on `app` → `attaching` and `setting("parkWindow")`: `hyprctl dispatch_lua_expression` rule via `hl.rules` is not stable across versions — instead react to the window: watch `Hyprland.toplevels` for `class == "tiertek.ytm"`; when it appears and is not on `special:ytm`, `hl.dsp.window.move({ window = "class:tiertek.ytm", workspace = "special:ytm", follow = false })`. `revealApp()` = `hl.dsp.workspace.toggle_special("ytm")`.
- [ ] `hypr/ytm.lua`: guarded, `SUPER+M` → `omarchy-shell ipc call tiertek.ytm toggle`? (use `qs -p /usr/share/omarchy/shell ipc call tiertek.ytm toggle`), `SUPER+SHIFT+M` → `reveal`, media keys already via MPRIS. README snippet `pcall(dofile, …/hypr/ytm.lua)`.
- [ ] Sleep timer: `Transport` overflow menu 15/30/60 min → `Timer` → `player.pause()`.
- [ ] Auto-relaunch: if `setting("autoRelaunch")` and `app` goes `ready→no-app` (not on first start), `launchApp()` once, then wait 60 s before allowing another.
- [ ] Stage.

### Task 11: README, SECURITY.md, preview, validate, install

- [ ] README: what it does, install (`omarchy plugin add https://github.com/TIerTek/omarchy-tektube.git --enable`), first run (sign in), requirements (Chromium-family browser; optional cava), controls table, keybinds, settings, how it works + privacy (dedicated profile, loopback debug port, no cookies/tokens), remove (`omarchy plugin remove tiertek.ytm`; profile dir left in place, how to delete it), troubleshooting per state.
- [ ] SECURITY.md: threat model, the closed grammar, `callFunctionOn` discipline, socket perms, what a reviewer should look at (`bin/page.js`, `Ops` in bridge).
- [ ] `preview.png` 1600×900 via `grim` on an empty workspace with the panel open on a real playlist.
- [ ] `bash tests/run-all.sh`, `omarchy plugin validate .`, `qmllint`. Report what to commit.
