# macarchy-core

The macOS experience for [Omarchy](https://omarchy.org) on Apple Silicon —
a suite of small daemons and tools that make a MacBook running
Omarchy/Asahi feel like the machine it was built to be.

> **Renamed from `omarchy-mac`.** That name already belongs to
> [a separate project](https://github.com/omarchy-mac/omarchy-mac), an
> Arch/Hyprland distro for Apple Silicon, and the collision confused people.
> The commands it installs are `macarchy-*` for the same reason.

Companion pieces live in their own repos: the
[macarchy-touchbar](https://github.com/macarchy/macarchy-touchbar) Touch Bar
daemon, the [omarchy-aquarium](https://github.com/macarchy/omarchy-aquarium)
animated background and the
[apple-glass](https://github.com/macarchy/apple-glass) /
[apple-glass-light](https://github.com/macarchy/apple-glass-light) themes.

![Apple Glass, the aquarium and the bar on Omarchy](docs-desktop.png)

## hardware/ — Apple Silicon specific

| Tool | What it does |
| --- | --- |
| `macarchy-als` | Ambient-light auto brightness for panel and keyboard backlight; learns your preferred offset from manual brightness key presses. |
| `macarchy-battery-limit` | Toggle the battery charge ceiling between 80% (kind to the cells) and 100% (travel mode). Needs the udev rule below for rootless operation. |

`udev/90-battery-charge-limit.rules` caps charging at 80% at boot and lets
the `wheel` group flip the thresholds without root.

`libinput/60-apple-mtp-touchpad.quirks` holds touch-size thresholds measured
on the MTP trackpad with `libinput measure touch-size` (finger "down" size,
thumb and palm rejection). Upstream libinput ships USB Magic Trackpad numbers
for this device, which drop light fingers from the count at gesture start.
Installed as `/etc/libinput/local-overrides.quirks`; applies at next login.

## style/ — the Mac feel, portable

| Tool | What it does |
| --- | --- |
| `macarchy-dock` | macOS-style autohiding dock (nwg-dock) with a hotspot reveal. |
| `macarchy-dock-theme` | Regenerates the dock stylesheet from the current Omarchy theme; installed as a `theme-set` hook so the dock follows theme changes. |
| `macarchy-pinch` | Four-finger pinch gestures from libinput (Hyprland only handles swipes). |
| `macarchy-zoom` | macOS-style screen magnifier on Hyprland's cursor zoom (`Ctrl` + scroll). |
| `macarchy-auto-appearance` | Switches between the Apple Glass and Apple Glass Light themes at sunrise and sunset (or on a fixed schedule), like macOS's "Auto" appearance. Driven by a systemd user timer; "Auto" is on exactly when that timer is enabled, and the Control Center's Affichage page flips it. An existing conf without `MODE` now follows the sun; add `MODE=schedule` to keep a fixed `LIGHT_FROM`/`LIGHT_UNTIL` window. |
| `macarchy-sun` | Prints today's sunrise and sunset for the shared location (`~/.config/omarchy/dynamic-wallpaper.json`). |
| `macarchy-bar-contrast` | Picks the transparent bar's text colour from a live capture of the bar strip (Omarchy's own picker samples the wallpaper file and cannot see the aquarium above it), and writes it to `~/.config/omarchy/shell.toml`. Systemd timer, a `theme-set` hook, and an `omarchy-aquarium` hook — toggling the tank repaints the very screen it samples. |
| `macarchy-locate` | Detects the machine's location (ip-api.com) and stores it in the shared location file, for the aquarium, the dynamic wallpaper and the auto appearance alike. |
| `macarchy-gtk-settings` | Keeps GTK's `settings.ini` in step with the current Omarchy theme for apps that ignore gsettings. |

## keys/ — the Cmd key, done the macOS way

`macarchy-keys.lua` extends Omarchy's universal copy/paste to the whole Cmd
vocabulary — select all, undo/redo, save, find, tabs, windows, zoom — with
terminal-aware chords (Cmd+S never freezes your shell, Cmd+Z never suspends
your job). Colliding window-manager binds move to their genuine macOS homes:
fullscreen on `Cmd+Ctrl+F`, hide-to-scratchpad on `Cmd+H`.

## shell-plugins/ — Cmd+Tab

`macarchy.switcher` is an Omarchy shell plugin: hold `Cmd`, tap `Tab`, release
to switch. One icon per app, recency-ordered, a sliding selection pill, real
theme glass, and the quick-tap detail: a fast Cmd+Tab flips to the previous
app without ever flashing UI. Escape or a click outside cancels; clicking an
icon switches to it. The glass needs the theme to blur the
`macarchy-switcher` layer namespace (the apple-glass themes do).

## agents/ — Claude Code

`claude-statusline.sh` is the bottom bar for the Claude Code CLI: model and
reasoning effort, the worktree and branch you are in, an open PR and its review
state, then a context-window gauge with the 5-hour and 7-day quota windows and
what the session has cost. It stays quiet — a quota window or a cost only
appears once it is worth a glance.

It paints with the sixteen ANSI colors and nothing else, which is the whole
point: the palette comes from the terminal, so the bar re-themes itself when
Omarchy switches theme or flips light/dark. No theme hook, no second copy of
the palette to keep in sync. `install.sh` symlinks it into `~/.claude/` and
points `statusLine` at it, leaving a status line you already configured alone.

`agents/skills/omarchy-asahi` is the companion machine skill, symlinked into
`~/.claude/skills`: what an agent has to know about this laptop that the
packaged `omarchy` skill gets wrong.

## Install

    ./install.sh          # scripts, hook, timer, example configs
    ./install.sh --udev   # also the battery udev rule + libinput trackpad quirks (sudo)

Then wire the daemons and keybindings into Hyprland — see
[`hypr/example.lua`](hypr/example.lua).

## License

MIT.
