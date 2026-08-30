# omarchy-mac

The macOS experience for [Omarchy](https://omarchy.org) on Apple Silicon —
a suite of small daemons and tools that make a MacBook running
Omarchy/Asahi feel like the machine it was built to be.

Companion pieces live in their own repos: the
[omarchy-aquarium](https://github.com/macarchy/omarchy-aquarium) animated
background and the [apple-glass](https://github.com/macarchy/apple-glass) /
[apple-glass-light](https://github.com/macarchy/apple-glass-light) themes.

![Apple Glass, the aquarium and the bar on Omarchy](docs/desktop.png)

## hardware/ — Apple Silicon specific

| Tool | What it does |
| --- | --- |
| `omarchy-dfr` | Context-aware Touch Bar daemon: per-app layouts, media and system keys, notification rendering. Layouts in `~/.config/omarchy-dfr/layouts.toml`. |
| `omarchy-als` | Ambient-light auto brightness for panel and keyboard backlight; learns your preferred offset from manual brightness key presses. |
| `omarchy-battery-limit` | Toggle the battery charge ceiling between 80% (kind to the cells) and 100% (travel mode). Needs the udev rule below for rootless operation. |

`udev/90-battery-charge-limit.rules` caps charging at 80% at boot and lets
the `wheel` group flip the thresholds without root.

## style/ — the Mac feel, portable

| Tool | What it does |
| --- | --- |
| `omarchy-dock` | macOS-style autohiding dock (nwg-dock) with a hotspot reveal. |
| `omarchy-dock-theme` | Regenerates the dock stylesheet from the current Omarchy theme; installed as a `theme-set` hook so the dock follows theme changes. |
| `omarchy-pinch` | Four-finger pinch gestures from libinput (Hyprland only handles swipes). |
| `omarchy-zoom` | macOS-style screen magnifier on Hyprland's cursor zoom (`Ctrl` + scroll). |
| `omarchy-auto-appearance` | Switches between the Apple Glass and Apple Glass Light themes on a schedule, like macOS's "Auto" appearance. Driven by a systemd user timer. |
| `omarchy-gtk-settings` | Keeps GTK's `settings.ini` in step with the current Omarchy theme for apps that ignore gsettings. |

## Install

    ./install.sh          # scripts, hook, timer, example configs
    ./install.sh --udev   # also the battery udev rule (sudo)

Then wire the daemons and keybindings into Hyprland — see
[`hypr/example.lua`](hypr/example.lua).

## License

MIT.
