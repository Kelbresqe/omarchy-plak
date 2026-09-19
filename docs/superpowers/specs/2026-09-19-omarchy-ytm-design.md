# Omarchy YouTube Music plugin (`tiertek.ytm`) — design

Date: 2026-09-19. Status: approved by the maintainer, built 2026-09-19.

## Goal

An Omarchy shell plugin that lets a user sign in to their real YouTube Music account,
browse and start their own playlists / library / Liked Songs, control playback, read
synced lyrics, like/dislike, start radio, manage the queue — from a bar widget and a
popup panel that are drawn entirely from the active Omarchy theme.

Gap it fills (marketplace survey, 2026-09-19, 3 584 plugins, 35 YouTube-adjacent):
MPRIS controllers (`levi.youtube-music`, `omamusic`) cannot list or pick playlists;
browser-free mpv players (`itsdotdev`, `youtube-shelf`) cannot sign in; the one plugin
that did both (`quickshell.ytmusic`, ★18) has been deleted from GitHub.

## Decisions (locked)

- **Login model: drive the real YouTube Music web app.** A Chromium-family browser is
  launched as an `--app` window with a dedicated profile and a loopback DevTools port.
  The user signs in with normal Google sign-in in that window. The plugin never reads
  cookies, never stores tokens; every authenticated call runs *inside the page* and the
  plugin only sees JSON results. Rejected: embedded QtWebEngine (not a stock dep, Google
  refuses sign-in in embedded views), ytmusicapi + yt-dlp + mpv (clunky auth, breaks on
  YouTube changes, the deleted ★18 precedent), pear-desktop as engine (AUR hard dep).
- **Bridge: long-running Python 3 stdlib daemon** (`bin/ytm-bridge`) holding one CDP
  websocket (hand-rolled RFC 6455 client, no pip deps) and serving JSON-lines on a
  `0600` unix socket in `$XDG_RUNTIME_DIR`. QML talks to it with `Quickshell.Io.Socket`.
  Rejected: per-action CLI (no push, handshake per call), Chrome extension + native
  messaging (users must side-load an extension).
- **MPRIS is the always-on source** for play state, art, position, transport. It is
  matched on the dedicated window class / dbus name, never guessed. If the bridge is
  down the widget degrades to an MPRIS controller, never to blank.
- **Plugin id `tiertek.ytm`** (permanent). Kinds: `bar-widget` + `service`.
- **Closed grammar at every boundary.** Playlist / video / browse ids must match
  `^[A-Za-z0-9_-]{2,64}$` in both `Ytm.js` and the bridge before they touch a URL or a JS
  call. `Runtime.callFunctionOn` with typed `arguments`, never string-built JS. Nothing
  from the page ever reaches `bar.run()`.
- Never Firefox: no `--app`, no CDP. Browser order: user setting → xdg default if
  Chromium-family → first of google-chrome-stable / brave / chromium / vivaldi /
  microsoft-edge found on PATH.
- Silent auto-relaunch of the browser is a setting, **off by default**.
- Identity `TierTek <28792124+TIerTek@users.noreply.github.com>`, repo-local. Public

## Components

```
manifest.json      kinds [bar-widget, service], keepLoaded
BarWidget.qml      now-playing pill; opens Panel
Panel.qml          popup: Player / Playlists / Queue / Lyrics / Search views + footer transport
Service.qml        supervises ytm-bridge (Process, backoff), owns the Socket, shared state,
                   MPRIS player selection, toasts, window parking
Bridge.js          request/response + event demux over the socket (pure JS, testable)
Ytm.js             InnerTube responses → flat models; id grammar (pure JS, testable)
bin/ytm-bridge     Python: browser launch/attach, CDP client, page-context InnerTube calls
bin/ytm-app        launcher: browser choice, flags, dedicated profile
hypr/bindings.lua  optional guarded include (SUPER+M panel, SUPER+SHIFT+M reveal app)
tests/             node .cjs + python + bash, no network, no browser
docs/              this spec + the plan
```

### Browser launch (`bin/ytm-app`)

```
<browser> --app=https://music.youtube.com
  --user-data-dir=$XDG_DATA_HOME/tiertek.ytm/profile
  --remote-debugging-port=0
  --class=tiertek.ytm
  --autoplay-policy=no-user-gesture-required
  --no-first-run --no-default-browser-check
```

launched through `setsid uwsm-app --` like `omarchy-launch-webapp`. Chromium writes
`profile/DevToolsActivePort` (`<port>\n<browser path>`); the bridge polls that file.

### Bridge

- Attach: read `DevToolsActivePort` → `GET /json/version` → browser websocket →
  `Target.getTargets` → attach (flatten) to the `music.youtube.com` page target →
  `Runtime.enable`, `Page.enable`. On `Target.targetDestroyed` → state `no-app`.
- States: `bridge-down` (socket absent) · `no-app` · `attaching` · `signed-out` ·
  `ready`. Signed-in is read from the page's `ytcfg.get('LOGGED_IN')`.
- Data ops call the SPA's own `/youtubei/v1/*` endpoints from page context with the
  page's `INNERTUBE_CONTEXT` and a `SAPISIDHASH` computed in-page from `document.cookie`
  exactly as the site does. `play` navigates the SPA to `watch?v=…&list=…`.
- Timed lyrics: signed-in `next` → lyrics tab browseId → **anonymous** `browse`
  (`credentials: omit`, no SAPISIDHASH) with a minimal `ANDROID_MUSIC 7.21.50` context →
  `timedLyricsData`; plain lyrics from the signed-in `browse` as fallback. **Verified live
  2026-09-19:** the mobile client returns HTTP 400 to any request carrying the web session;
  sent anonymously it returns timed lines (37 for a test track).
- Verified the same day: CDP attach to a real Chrome `--app` window, `page.js` install,
  `ytcfg` login flag, library (20 playlists), playlist with continuation (108/108 over 2
  pages), DOM queue (100 rows, current found), flat search layout, MPRIS play/pause.
- **Wayland ignores `--class`.** The app window's class is
  `<browser>-music.youtube.com__-Default`; match on `-music.youtube.com__`. The browser
  pid for MPRIS matching comes from the profile's `SingletonLock` symlink
  (`hostname-pid`).

Protocol (JSON lines; requests carry client-chosen `id`, events carry `ev`):

```
state                         → {state}
library.playlists             → items [{id,title,count,thumb,author}]
playlist.items {list}         → items [{videoId,title,artist,album,dur,thumb,liked}]
play {list?,video?,index?,shuffle?}
queue                         → {items:[…],current}
queue.jump {index}
like|dislike|unlike {video}
radio {video}
lyrics {video}                → {timed:[{t,line}]|null, plain|null, source}
search {q}                    → {songs,albums,playlists}
app.launch | app.reveal | app.hide
events: state, queue, track
```

Every response is `{"id":n,"ok":true,…}` or `{"id":n,"ok":false,"error":"<code>"}`.

### UI

- Bar pill: 16 px rounded art thumb, `title · artist`, marquee only when overflowing,
  1 px accent progress hairline, state glyph. Left click panel, middle play/pause, right
  next, scroll volume. Hidden until first launch unless `showWhenIdle`.
- Panel: Omarchy `Ui/` primitives and theme singletons only — no hex literals, no
  bundled fonts. Left rail (Player · Playlists · Queue · Lyrics · Search), content area,
  footer transport always visible. Art glow = dominant colour of the art mixed 60/40
  toward the theme accent and clamped to the theme background luminance. Lyrics view
  auto-scrolls, current line in accent, click to seek. Cava bars only if `cava` on PATH.
- Keyboard: arrows/Enter/Esc, `/` search, `l` like, `r` radio, `q` queue, `y` lyrics.
- Toast on track change via the Omarchy notifier (art, respects DND, suppressed while
  the panel is open); setting, on by default.
- Signed-out state: one button "Open YouTube Music and sign in"; the panel polls `state`
  until `ready`, then loads the library.
- Window parking: runtime Hyprland rules for `class:tiertek.ytm` → `special:ytm`
  silent, float, sized. `app.reveal` toggles the special workspace.

### Error handling

Every failure is a state rendered as one line + the one action that fixes it. Bridge
crash → `Process` restart with backoff 1 s → 30 s. InnerTube shape change / 401 → the
view shows "YouTube changed something — playback still works", library served from
`$XDG_CACHE_HOME/tiertek.ytm/library.json` (≤ 1 MiB), log line names the endpoint only.

### Tests

- `tests/test-ytm-model.cjs` — fixtures → models, malformed/empty inputs, id grammar.
- `tests/test-bridge.py` — bridge against a fake CDP server (stdlib http + websocket):
  attach, request/response, grammar rejection, reconnect after target destroyed.
- `tests/test-app-launch.sh` — fake `$PATH`: browser choice, flags, never Firefox.
- `tests/test-id-grammar.sh` — JS and Python grammars agree on a shared vector file.
- `omarchy plugin validate .`, `qmllint` on every QML file.
- Live smoke on sarial after the above (`omarchy restart shell` every time).

### Packaging

README (install, remove, deps: Chromium-family browser; optional cava), `SECURITY.md`
(posture above), `preview.png` 1600×900, MIT `LICENSE`. Submit via the marketplace
issue template only after the hyprpm-skill human-review checklist passes.

## Build order

0. Spike: page-context InnerTube + timed lyrics against a real signed-in window
   (throwaway script, answers "does `ANDROID_MUSIC` lyrics work from page context").
1. Launcher + bridge attach + `state` + `library.playlists` + `play` + MPRIS bar pill —
   shippable v0.1.
2. Panel views: Playlists / Queue / Search.
3. Account actions: like/dislike, radio, queue jump, add to playlist.
4. Lyrics view.
5. Eye candy: art glow, toast, cava.
6. Window parking, `bindings.lua`, sleep timer, auto-relaunch setting.
