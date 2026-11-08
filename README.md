![Plak](preview.png)

# Plak for YouTube Music

A YouTube Music player for the Omarchy bar. Plak started as a fork of
[TekTube](https://github.com/TIerTek/omarchy-tektube) by TierTek and adds
volume, repeat and shuffle, queue editing, save to playlist, history, a
sleep timer, resume, pausing for other audio, keybindings and a Turkish UI.
Not affiliated with or endorsed by Google or YouTube.

Your real YouTube Music account in the Omarchy bar: your Home rows and mixes,
playlists and Liked Music, the queue, **synced lyrics**, like / dislike,
"start radio", search — drawn from your theme, driven from the keyboard, with
a spinning record and an ambient wash of the cover behind it all.

## Quick start

```sh
omarchy plugin add https://github.com/Kelbresqe/omarchy-plak.git --enable
```

1. Click the new **Plak** pill in the bar → **Open YouTube Music**.
2. The panel says you're not signed in → **Sign in with Google**. A normal
   browser window opens on Google's sign-in page. Sign in, then close it.
3. That's it. Plak reopens by itself, signed in, loads your Home and
   library, and the window tucks itself away in a special workspace.

Needs a Chromium-family browser (Chrome, Brave, Chromium, Vivaldi, Edge) —
nothing else to install. Premium accounts get ad-free playback; media keys
work out of the box.

It works by driving a YouTube Music app window that you sign into yourself.
There is no API key to create, no cookie to paste, and nothing to break when
YouTube changes its stream formats: playback is the real player.

## What you get

- **Bar pill** — artwork in a progress ring, title · artist. Left click
  opens the panel, middle click play/pause, right click next, scroll = volume.
- **Home** — YouTube's rows for *your* account: Listen again, Mixed for you,
  your Supermix, Quick picks, new releases. One click starts any of them.
  This is where the panel opens when nothing is playing.
- **Now playing** — the cover as a spinning record that eases to a stop when
  you pause, a glow tinted from the cover *and* your theme accent, up-next,
  optional spectrum bars (if `cava` is installed).
- **Living header** — the Plak mark with an equalizer that breathes while
  playing (and follows the music when `cava` is present), over an ambient
  wash of the album art blurred behind the whole panel.
- **Playlists** — every playlist in your library including Liked Music; play,
  shuffle, or pick a track. Long playlists load completely.
- **Up next** — the live queue with the current track marked; jump anywhere,
  move rows up and down, remove them. It is read from YouTube Music's own
  queue store, so what you see is exactly what will play.
- **Play next / add to queue** — from search, a playlist or History, by
  keyboard or with the buttons that appear on a row.
- **Save to playlist** — any song, or the one playing, into one of your
  playlists; the ones that already have it are checked.
- **History** — what you played, under YouTube Music's own day headings.
- **Steps aside for other audio** — a video starting in your browser (or mpv,
  Spotify, any MPRIS player) pauses the music; when it stops, the music picks
  up again after a short quiet moment, unless you paused or played it
  yourself in between. Setting: *Pause when another player starts*.
- **Lyrics** — timed, highlighted line by line, click a line to seek; plain
  lyrics when the song has no timings.
- **Search** — songs, albums and playlists; Enter plays.
- **Account actions** — like, dislike, start radio from the current song.
- Track-change notification with artwork, a sleep timer (15 / 30 / 60 min or
  the end of this song, fading out instead of cutting off), and the app window
  kept out of sight in a special workspace.

## Requirements

- Omarchy with the plugin system (Quickshell bar).
- A **Chromium-family browser**: Google Chrome, Brave, Chromium, Vivaldi or
  Edge. Firefox cannot be driven this way. Your default browser is used if it
  qualifies; otherwise the first one found. Set `browser` in the widget
  settings to pick one explicitly.
- Python 3 (standard library only — present on every Omarchy install).
- Optional: [`cava`](https://github.com/karlstav/cava) for the spectrum bars.

## Install

```sh
omarchy plugin add https://github.com/Kelbresqe/omarchy-plak.git --enable
```

The widget lands in the left section of the bar. To move it:

```sh
omarchy bar move io.github.kelbresqe.plak --section center
```

### First run

Click the pill, then **Open YouTube Music**. A YouTube Music window opens
with its own browser profile. While you're signed out, the panel offers
**Sign in with Google**.

Google won't let you sign in from the app window itself ("This browser or
app may not be secure") because the plugin drives that window over
DevTools. So **Sign in with Google** closes it and opens a normal
window on the same profile, without DevTools and with the address bar
showing `accounts.google.com`. Sign in there and close the window. Plak
reopens the app on its own, now signed in, and the panel loads your library.
You won't be asked again; the session lives in that profile.

The window is then moved to the special workspace `ytm` so it stays out of
your way. Bring it back with the ↗ button in the panel, or with
`bin/ytm reveal` (see **Controls**).

When you aren't listening, the ⏻ button in the panel closes the YouTube
Music window and frees its memory (about 700 MB on Chrome). You stay signed
in: **Open YouTube Music** brings it back.

## Controls

| In the bar | |
|---|---|
| Left click | open / close the panel |
| Middle click | play / pause |
| Right click | next track |
| Scroll | music volume (shown on Omarchy's OSD) |

| In the panel | |
|---|---|
| `Tab` / `Shift+Tab` | cycle views |
| `n` `p` `q` `i` `y` `/` | Now playing · Playlists · Queue · History · Lyrics · Search (Home: Tab) |
| `↑ ↓ ← →` or `j k h l` | move; `←` backs out of a playlist; in Now playing, `←` `→` seek 10 s |
| `Enter` / `Space` | play the selected item (Space = play/pause in Now playing; with nothing playing, it resumes the last session) |
| `,` `.` | previous / next track |
| `f` `d` `r` | like · dislike · start radio from the current song |
| `t` | repeat: off → all → this song → off |
| `m` | shuffle on / off (`x` belongs to Omarchy's panel keys as "delete") |
| `e` `E` `b` | on the selected song in Search, a playlist or History: play next · add to queue · save to playlist; in Now playing, `b` saves the playing song |
| `Ctrl+↑` `Ctrl+↓` · `Delete` / `x` | in Up next: move the selected row · remove it (not the one playing) |
| `a` `s` | inside a playlist: play all · shuffle |
| `g` | queue / lyrics: jump back to the current line |
| `R` | Home: refresh the rows |
| `Esc` | close |

Desktop media keys work through MPRIS without any binding.

### Keybindings (optional)

Append `hypr/ytm.lua` from the plugin directory to `~/.config/hypr/bindings.lua`.
Hyprland reloads it on save; `hyprctl configerrors` should print nothing.
Everything sits on M, and `Super+M` itself stays Omarchy's "minimize to the
dock":

| key | |
|---|---|
| `Super+Shift+M` | open / close the panel |
| `Super+Alt+M` | play / pause |
| `Super+Ctrl+M` / `Super+Ctrl+Shift+M` | next / previous track |
| `Super+Ctrl+↑` / `Super+Ctrl+↓` | music volume up / down (hold to repeat; shown on Omarchy's OSD) |

The keyboard's volume keys keep changing the system volume. The same verbs,
and a few more, are available from any script through `bin/ytm`:

```sh
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm toggle
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm view lyrics
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm playPause
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm volumeUp     # or volumeDown
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm repeat       # or shuffle
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm quit         # close the YouTube Music window
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm save         # save the playing song to a playlist
~/.config/omarchy/plugins/io.github.kelbresqe.plak/bin/ytm view history # or player, playlists, queue, lyrics, search
```

### Updating

`omarchy plugin update io.github.kelbresqe.plak` is enough. The shell hot-reloads the QML,
and `ytm-bridge` exits once it sees that its own code (`bin/ytm-bridge` or
`bin/page.js`) has changed, so the shell starts a fresh bridge within a
couple of seconds. A bridge whose socket a newer one has taken over exits
too.

### Picking up where you left off

YouTube Music forgets repeat and shuffle, and stops playing, whenever its
browser restarts (after a reboot, **Sign in with Google**, or the ⏻ button).
The bridge keeps a small record in
`$XDG_STATE_HOME/io.github.kelbresqe.plak/session.json` (mode 0600): the last track, the
list it came from, how far in, the repeat / shuffle settings and the volume.

- While nothing plays, Home and Now playing offer **Resume where you left
  off**: same track, same list, same second. In Now playing, `Enter` /
  `Space` does it too.
- When playback starts in a new browser session, repeat and shuffle are put
  back. A value you already changed in that session is left alone.
- Right after the shell starts, the panel shows the last known volume /
  repeat / shuffle at once (disabled until YouTube Music answers), instead
  of leaving the controls blank.

Delete the file to forget all of it.

### Language

The panel follows Omarchy's language (Setup > Language) live, from flat
catalogs in `i18n/` (`en.json`, `tr.json`). A string missing from a catalog
falls back to English. Adding a language means adding one file with the same
keys; `tests/test-i18n.py` checks the keys and placeholders.

## Settings

Edit them in the bar's widget settings or `~/.config/omarchy/shell.json`:

| key | default | |
|---|---|---|
| `browser` | `""` | executable name of a Chromium-family browser |
| `showWhenIdle` | `true` | keep the pill in the bar when nothing is playing |
| `toast` | `true` | notification on track change (quiet while the panel is open) |
| `autoRelaunch` | `false` | reopen the window automatically if it is closed |
| `parkWindow` | `true` | move the window to the `ytm` special workspace when it appears |
| `visualizer` | `true` | spectrum bars when `cava` is installed |
| `maxLabelWidth` | `180` | width of the bar label in pixels |

## How it works, and what it never does

Plak is the name; the plugin id is `io.github.kelbresqe.plak`.

`bin/ytm-app` launches the browser as an app window with a **dedicated
profile** (`~/.local/share/io.github.kelbresqe.plak/profile`). DevTools runs
over a pipe, not a network port: `bin/ytm-cdp` starts the browser with
`--remote-debugging-pipe` and passes that pipe on through a unix socket only
your user can open. `bin/ytm-bridge` (Python, standard library) attaches
there, installs one function into the page (`bin/page.js`), and serves a
small JSON protocol on a private unix socket that the bar reads.

Every request for your data — playlists, queue, lyrics, likes — runs *inside
the page*, as the site's own JavaScript would, using the session the browser
already holds. The plugin never reads cookies, never stores a token, and has
no credential to leak. Playback control goes over MPRIS, the same interface
Omarchy's own media widget uses.

Your everyday browser profile is untouched and never debuggable, and no
other user or sandboxed app on the machine can reach the plugin's profile
either: there is no localhost port to connect to. See [SECURITY.md](SECURITY.md).

Where things live:

| | |
|---|---|
| browser profile (your session) | `~/.local/share/io.github.kelbresqe.plak/profile/` |
| cache (library snapshot, notification artwork) | `~/.cache/io.github.kelbresqe.plak/` |
| socket | `$XDG_RUNTIME_DIR/io.github.kelbresqe.plak.sock` (mode 0600) |

## Troubleshooting

The panel always tells you which state it is in and offers the one action
that fixes it:

| panel says | meaning |
|---|---|
| *Starting the bridge…* | the shell is starting `ytm-bridge`; give it a second. If it stays, `journalctl --user -f` shows `[io.github.kelbresqe.plak]` lines. |
| *YouTube Music is not open* | no app window. Click **Open YouTube Music**. If the window closed on its own, `journalctl --user -t ytm-cdp` shows why. |
| *Connecting to YouTube Music…* | the window exists, the page is still loading. |
| *Not signed in to YouTube Music* | signed out. Click **Sign in with Google** (see **First run**). |
| *Sign in in the Google window, then close it…* | the plain sign-in window is open. Once you close it, Plak reopens. |
| *YouTube changed something — playback still works* | a response shape moved. Transport keeps working over MPRIS; playlists come from the last good snapshot. Please open an issue with the endpoint name from the journal. |

If the pill shows nothing at all, check the plugin is enabled:
`omarchy plugin list | grep io.github.kelbresqe.plak`.

## Update

```sh
omarchy plugin update io.github.kelbresqe.plak
```

## Remove

```sh
omarchy plugin remove io.github.kelbresqe.plak
```

This removes the plugin and stops the bridge. Your sign-in profile is left in
place so reinstalling does not ask you to log in again; to remove it too:

```sh
rm -rf ~/.local/share/io.github.kelbresqe.plak ~/.cache/io.github.kelbresqe.plak
```

If you appended `hypr/ytm.lua` to your bindings, delete the block between
`-- BEGIN io.github.kelbresqe.plak` and `-- END io.github.kelbresqe.plak`.

## Development

```sh
bash tests/run-all.sh          # launcher, DevTools relay, bridge (against a fake DevTools), parsers, glow maths
omarchy plugin validate .
```

The bridge tests never touch a browser or the network: `tests/fakecdp.py`
speaks just enough of the DevTools protocol, and `tests/fakepipe.py` stands
in for the browser on the other side of `bin/ytm-cdp`. InnerTube parsers are tested
against fixtures in `tests/fixtures/innertube/`, including a scrubbed capture
of the current flat search layout.

## Credits

Plak is built on [TekTube](https://github.com/TIerTek/omarchy-tektube)
by TierTek (MIT): the bridge, the panel, library, lyrics and search are
its work.

Several pieces follow other Omarchy YouTube Music plugins, all MIT
licensed:

- [Solfa](https://github.com/SirAllap/omarchy-solfa) by SirAllap: editing
  the queue through YouTube Music's queue store (ADD_ITEMS, REMOVE_ITEM,
  MOVE_ITEM, SET_INDEX), the History view, recovering a crashed or stuck
  page, the launch-time window rule, and keeping the profile on one
  browser.
- [YouTube Music Player](https://github.com/Dqckey/omarchy-ytmusic-player)
  by Dqckey: the save-to-playlist picker
  (`playlist/get_add_to_playlist`, `DEDUPE_OPTION_SKIP`) and pausing when
  another player starts.
- [ytm-bar](https://github.com/crsstha/ytm-bar) by crsstha: resuming once
  the other audio has been quiet for a moment.

## License

MIT. See [LICENSE](LICENSE).

YouTube and YouTube Music are trademarks of Google LLC.
