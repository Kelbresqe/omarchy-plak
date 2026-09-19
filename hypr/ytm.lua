-- TekTube (tiertek.ytm) keybindings.
--
-- Append this block to ~/.config/hypr/bindings.lua, then reload with
--   omarchy restart hyprland
--
-- Omarchy loads exactly one user bindings file, after its own defaults, so a
-- snippet in that file is the reliable way in. The BEGIN/END markers let it
-- be found and removed again.
--
-- Media keys (play/pause, next, previous) already work through MPRIS with no
-- binding at all; these are for the panel itself.

-- BEGIN tiertek.ytm
local ytm = os.getenv("HOME") .. "/.config/omarchy/plugins/tiertek.ytm/bin/ytm"

o.bind("SUPER + M", "TekTube panel", ytm .. " toggle")
o.bind("SUPER + SHIFT + M", "TekTube window", ytm .. " reveal")
o.bind("SUPER + ALT + M", "TekTube lyrics", ytm .. " view lyrics")
-- END tiertek.ytm
