-- Wiring for the macarchy-core tools, in Omarchy's Lua config dialect.
-- Merge into ~/.config/hypr/autostart.lua and bindings.lua.

-- autostart.lua
o.exec_on_start("systemctl --user start macarchy-touchbar.service")  -- Touch Bar
o.exec_on_start("macarchy-als daemon")     -- ambient-light auto brightness
o.exec_on_start("macarchy-pinch")          -- four-finger pinch gestures
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/macarchy-dock")

-- bindings.lua
o.bind("CTRL + mouse_up", "Screen zoom in", "macarchy-zoom in")
o.bind("CTRL + mouse_down", "Screen zoom out", "macarchy-zoom out")
