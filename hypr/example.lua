-- Wiring for the omarchy-mac tools, in Omarchy's Lua config dialect.
-- Merge into ~/.config/hypr/autostart.lua and bindings.lua.

-- autostart.lua
o.exec_on_start("omarchy-dfr daemon")     -- Touch Bar
o.exec_on_start("omarchy-als daemon")     -- ambient-light auto brightness
o.exec_on_start("omarchy-pinch")          -- four-finger pinch gestures
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/omarchy-dock")

-- bindings.lua
o.bind("CTRL + mouse_up", "Screen zoom in", "omarchy-zoom in")
o.bind("CTRL + mouse_down", "Screen zoom out", "omarchy-zoom out")
