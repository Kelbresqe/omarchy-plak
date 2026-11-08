-- TekTube (tiertek.ytm) keybindings.
--
-- Append this block to ~/.config/hypr/bindings.lua; Hyprland reloads it on
-- save (check with `hyprctl configerrors`).
--
-- Omarchy loads exactly one user bindings file, after its own defaults, so a
-- snippet in that file is the reliable way in. The BEGIN/END markers let it
-- be found and removed again.
--
-- Everything sits on M ("music"); SUPER + M itself stays Omarchy's
-- "minimize to the dock". The keyboard's own media keys keep working through
-- MPRIS, and its volume keys keep changing the system volume; SUPER + CTRL +
-- UP/DOWN change only the music (shown on Omarchy's OSD).

-- BEGIN tiertek.ytm
local ytm = os.getenv("HOME") .. "/.config/omarchy/plugins/tiertek.ytm/bin/ytm"

o.bind("SUPER + SHIFT + M", "TekTube panel", ytm .. " toggle")
o.bind("SUPER + ALT + M", "Music: play / pause", ytm .. " playPause")
o.bind("SUPER + CTRL + M", "Music: next track", ytm .. " next")
o.bind("SUPER + CTRL + SHIFT + M", "Music: previous track", ytm .. " prev")
o.bind("SUPER + CTRL + UP", "Music: volume up", ytm .. " volumeUp", { repeating = true })
o.bind("SUPER + CTRL + DOWN", "Music: volume down", ytm .. " volumeDown", { repeating = true })
-- END tiertek.ytm
