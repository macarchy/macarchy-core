---
name: omarchy-asahi
description: >
  REQUIRED companion to the omarchy skill on this machine — an aarch64 Asahi
  Linux M2 MacBook, not a stock x86 Omarchy box. ALWAYS read this alongside
  the omarchy skill for anything touching brightness, backlight, battery,
  charging, the Touch Bar, trackpad gestures, pinch/zoom, themes, wallpaper,
  backgrounds, blur/opacity, terminals, package installs, or video playback.
  Custom daemons own several of these subsystems and generic Omarchy guidance
  will fight them.
---

# Omarchy on Asahi (M2 MacBook) — machine-specific facts

This system is Omarchy on Asahi Linux (`linux-asahi`, aarch64). Several
subsystems are owned by custom tooling from the
[macarchy](https://github.com/macarchy) repos. Route requests through the
owners below instead of editing raw sysfs, adding exec rules, or installing
generic tools.

## Custom daemons and tools (installed in `~/.local/bin`)

| Tool | Owns | Notes |
|------|------|-------|
| `omarchy-dfr` | Touch Bar (context-aware pages) | tiny-dfr based; see constraints below |
| `omarchy-als` | Panel + keyboard auto-brightness | learns offsets from manual brightness keys; `omarchy-als toggle` pauses it |
| `omarchy-battery-limit` | 80% charge cap | `toggle|on|off|status`; udev rule restores 80% at boot |
| `omarchy-aquarium` / `-toggle` | Live GLSL wallpaper | layer 1 (`bottom`), above the wallpaper plugin; SUPER+ALT+A. Reactive: fish avoid the cursor, notifications startle the tank via `$XDG_RUNTIME_DIR/omarchy-aquarium.ctl` (fed by `omarchy-aquarium-notify`), jellies glow at night. `--no-react` disables; `omarchy-aquarium-toggle startle` tests |
| `omarchy-pinch` | ≥4-finger pinch gestures | parses libinput events; pinch-in = launcher |
| `omarchy-zoom` | CTRL+scroll magnifier | drives `cursor:zoom_factor` |
| `omarchy-dock`, `omarchy-auto-appearance`, `omarchy-gtk-settings` | Dock, light/dark switching, GTK sync | |

**Sync rule:** these installed scripts are copies of `~/Work/omarchy-mac`.
When editing an installed tool, mirror the change into that repo — or edit
the repo and re-run its `install.sh`. Don't let the two drift.

## Themes and backgrounds

- The active themes `apple-glass` (dark) and `apple-glass-light` in
  `~/.config/omarchy/themes/` are hand-written and are **copies of the
  `~/Work/apple-glass{,-light}` repos** — sync edits both ways deliberately.
- The applied theme at `~/.local/state/omarchy/current/theme` is itself a
  copy: after editing a theme directory, re-run `omarchy theme set <name>`
  or nothing changes (this also restarts the aquarium via its theme-set
  hook).
- The glass blur material (`blur:xray = true`, size 20/4, low vibrancy) is
  **tuned against the animated aquarium**, not a static wallpaper. Turning
  xray off or "cleaning up" the low-contrast values is a look regression.
- Terminal glass is app-side opacity (alacritty/foot/kitty configs shipped
  by the theme) plus `no_blur = true` window rules — do not swap that for
  compositor opacity/blur.
- Background requests: the aquarium draws on layer 1 above the
  `omarchy-background` plugin, so `omarchy theme bg` still works underneath
  it. Toggle the aquarium off (SUPER+ALT+A) if the user wants to actually
  see a static background.
- Beneath the aquarium there is a SECOND mover: the
  `macos-dynamic-wallpaper.timer` user unit fires every ~5 minutes and
  applies a time-of-day image from the set in
  `~/.config/omarchy/dynamic-wallpaper.json` (solar mode — the same lat/lon
  the aquarium's sun tracking reads). A manually set background gets
  overwritten within minutes unless that timer is stopped
  (`systemctl --user disable --now macos-dynamic-wallpaper.timer`) — or
  better, switch the `"set"` in the JSON so the rotation shows what the
  user wants.

## Hyprland gotchas specific to this box

- `hyprctl keyword` is rejected by Omarchy's Lua config parser — live-tune
  with `hyprctl eval 'hl.config({...})'` instead. `hyprctl eval` prints
  only errors, never return values.
- **Do not re-add direct scanout**: layer surfaces (aquarium, shell) keep
  `solitary=0`, so it never fires.
- **Do not re-add a 3-finger swipe**: `drag_3fg = 1` uses three fingers for
  drag; navigation is 4 fingers by design.
- **hyprexpo (and all overview plugins) are dead here**: Omarchy's aarch64
  Hyprland links no capstone, so `CFunctionHook` can't hook. A guarded
  pcall in `input.lua` auto-activates it if that ever changes — don't retry
  manually.

## Packages and media

- aarch64 narrows the AUR: packages shipping x86 binaries don't exist, and
  heavy source builds may be the only option (e.g. ghostty is an AUR zig
  build here; kitty is the default terminal because foot lacks ligatures).
  Check availability before promising an install.
- **No hardware video decode**: the AVD firmware isn't usable from
  userspace, so all video is software-decoded. Don't add `hwdec` to mpv or
  debug its absence as a bug.

## Touch Bar (tiny-dfr) constraints

- uinput capabilities are frozen at daemon start; F13–F24 have no keysyms.
- Reloading tiny-dfr config while a touch is in progress panics the daemon.
- Button icons live in `/etc/tiny-dfr/` (hand-drawn SVGs).

If a task means changing one of these tools' behavior (not just using it),
that's development on the `~/Work` repos — check the repo's own docs first.
