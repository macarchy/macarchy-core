-- macarchy-keys: the Cmd key, done the macOS way.
--
-- Omarchy already ships universal copy/paste/cut on SUPER+C/V/X, and
-- SUPER+Q closes the window just like Cmd+Q quits. This module extends the
-- grammar to the rest of the Cmd vocabulary and rehomes the five colliding
-- window-manager binds:
--
--   fullscreen        SUPER+F -> SUPER+CTRL+F   (macOS's own combo;
--                                tiled fullscreen -> SUPER+CTRL+SHIFT+F)
--   float toggle      SUPER+T -> SUPER+ALT+T
--   layout toggle     SUPER+L -> SUPER+ALT+L
--   scratchpad        SUPER+S -> SUPER+H        (Cmd+H hides on a Mac)
--   close window      SUPER+W -> (SUPER+Q already does it)
--
-- Terminals get chords that respect the shell: Cmd+S must never send the
-- XOFF freeze and Cmd+Z must never suspend the foreground job, while
-- kitty's ctrl+shift defaults line up with tabs and windows unchanged.

local function send_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

local function is_terminal()
  local window = hl.get_active_window()
  if not window then return false end
  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then return true end
  end
  return false
end

local function cmd(default_mods, default_key, term_mods, term_key)
  return function()
    if is_terminal() then
      send_once(term_mods, term_key)()
    else
      send_once(default_mods, default_key)()
    end
  end
end

-- ---- rehome the collisions ----------------------------------------------
hl.unbind("SUPER + F")
hl.unbind("SUPER + T")
hl.unbind("SUPER + S")
hl.unbind("SUPER + L")
hl.unbind("SUPER + W")
hl.unbind("SUPER + CTRL + F")
o.bind("SUPER + CTRL + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("SUPER + CTRL + SHIFT + F", "Tiled full screen", "omarchy-hyprland-window-tiled-fullscreen-toggle")
o.bind("SUPER + ALT + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
o.bind("SUPER + ALT + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("SUPER + H", "Hide to scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))

-- ---- the Cmd vocabulary -------------------------------------------------
o.bind("SUPER + A", "Select all", cmd("CTRL", "A", "CTRL SHIFT", "A"))
o.bind("SUPER + Z", "Undo", cmd("CTRL", "Z", "CTRL SHIFT", "Z"))
o.bind("SUPER + SHIFT + Z", "Redo", cmd("CTRL SHIFT", "Z", "CTRL SHIFT", "Z"))
o.bind("SUPER + S", "Save", cmd("CTRL", "S", "CTRL SHIFT", "S"))
o.bind("SUPER + F", "Find", cmd("CTRL", "F", "CTRL SHIFT", "F"))
o.bind("SUPER + T", "New tab", cmd("CTRL", "T", "CTRL SHIFT", "T"))
o.bind("SUPER + W", "Close tab", cmd("CTRL", "W", "CTRL SHIFT", "W"))
o.bind("SUPER + N", "New window", cmd("CTRL", "N", "CTRL SHIFT", "N"))
o.bind("SUPER + R", "Reload", cmd("CTRL", "R", "CTRL", "R"))
o.bind("SUPER + L", "Location bar / clear terminal", cmd("CTRL", "L", "CTRL", "L"))
o.bind("SUPER + EQUAL", "Zoom in (app)", cmd("CTRL", "EQUAL", "CTRL SHIFT", "EQUAL"))
o.bind("SUPER + MINUS", "Zoom out (app)", cmd("CTRL", "MINUS", "CTRL SHIFT", "MINUS"))

-- ---- Cmd+Tab app switcher ----------------------------------------------
-- Workspace cycling stays on gestures and SUPER+number; Cmd+Tab belongs to
-- the app switcher (macarchy.switcher shell plugin). Selection commits when
-- SUPER is released, exactly like holding and releasing Cmd.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "App switcher",
  "omarchy-shell -q shell summon macarchy.switcher '{\"action\":\"next\"}'")
o.bind("SUPER + SHIFT + TAB", "App switcher (back)",
  "omarchy-shell -q shell summon macarchy.switcher '{\"action\":\"prev\"}'")
-- The commit lives inside the overlay itself: while open it holds the
-- keyboard and watches for the Super release directly — release binds on a
-- modifier do not fire reliably after a combo has been pressed.
-- Cmd+. is macOS's cancel key; SUPER+ESCAPE stays the Omarchy system menu.
o.bind("SUPER + PERIOD", "App switcher (cancel)",
  "omarchy-shell -q shell summon macarchy.switcher '{\"action\":\"cancel\"}'")
