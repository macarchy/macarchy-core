#!/bin/bash
# Install the omarchy-mac suite: scripts into ~/.local/bin, the theme hook,
# the auto-appearance timer, and (with sudo) the battery udev rule.
set -euo pipefail
cd "$(dirname "$0")"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
install -m755 hardware/* style/* "$BIN"/

mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"
install -m755 hooks/omarchy-dock-theme "$HOME/.config/omarchy/hooks/theme-set.d/"

mkdir -p "$HOME/.config/systemd/user"
install -m644 systemd/omarchy-auto-appearance.{service,timer} "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-auto-appearance.timer

for ex in examples/*; do
    name=${ex#examples/}
    tool=${name%%.*}
    rest=${name#*.}
    dest="$HOME/.config/$tool/$rest"
    if [[ ! -e $dest ]]; then
        mkdir -p "$(dirname "$dest")"
        install -m644 "$ex" "$dest"
    fi
done

# Machine-specific agent skill (companion to the packaged omarchy skill)
mkdir -p "$HOME/.claude/skills"
ln -sfn "$PWD/agents/skills/omarchy-asahi" "$HOME/.claude/skills/omarchy-asahi"

# Cmd-key grammar and the app switcher.
install -m644 keys/macarchy-keys.lua "$HOME/.config/hypr/macarchy-keys.lua"
grep -q macarchy-keys "$HOME/.config/hypr/bindings.lua" 2>/dev/null || cat >> "$HOME/.config/hypr/bindings.lua" <<'LUA'

-- macarchy-keys: Cmd behaves like macOS (see github.com/macarchy/omarchy-mac)
dofile(os.getenv("HOME") .. "/.config/hypr/macarchy-keys.lua")
LUA
mkdir -p "$HOME/.config/omarchy/plugins"
cp -r shell-plugins/macarchy.switcher shell-plugins/macarchy.control-center shell-plugins/phmatray.notification-center "$HOME/.config/omarchy/plugins/"
omarchy-shell -q shell enablePlugin macarchy.switcher '{}' || true

if [[ ${1-} == --udev ]]; then
    sudo install -m644 udev/90-battery-charge-limit.rules /etc/udev/rules.d/
    sudo udevadm control --reload
    echo "udev battery rule installed (applies on next battery 'add' event or reboot)"
    # Measured libinput touch-size thresholds for the MTP trackpad (finger
    # counting, thumb and palm rejection). libinput reads exactly this file;
    # it is applied when the device is (re)added, i.e. after logout/reboot.
    sudo install -d /etc/libinput
    sudo install -m644 libinput/60-apple-mtp-touchpad.quirks /etc/libinput/local-overrides.quirks
    echo "libinput trackpad quirks installed (takes effect at next login)"
    # Touch Bar button icons: omarchy-dfr's layouts reference them by name
    # from /etc/tiny-dfr, next to the config.toml it renders there.
    if [[ -d /etc/tiny-dfr || -n $(command -v tiny-dfr) ]]; then
        sudo install -d /etc/tiny-dfr
        sudo install -m644 icons/*.svg /etc/tiny-dfr/
        echo "Touch Bar icons installed to /etc/tiny-dfr"
    fi
fi

echo "Installed. Wire the daemons and bindings into Hyprland: see hypr/example.lua"
