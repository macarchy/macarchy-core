#!/bin/bash
# Install the omarchy-mac suite: scripts into ~/.local/bin, the theme hook,
# the auto-appearance timer, and (with sudo) the battery udev rule.
set -euo pipefail
cd "$(dirname "$0")"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
find hardware style -maxdepth 1 -type f -exec install -m755 -t "$BIN" {} +

mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"
install -m755 hooks/omarchy-dock-theme "$HOME/.config/omarchy/hooks/theme-set.d/"
install -m755 hooks/dynamic-wallpaper "$HOME/.config/omarchy/hooks/theme-set.d/"
install -m755 hooks/omarchy-bar-contrast "$HOME/.config/omarchy/hooks/theme-set.d/"
# ... and the same tool on the aquarium's own hook path: toggling the tank
# repaints the screen the bar is sampling. Harmless if the aquarium is absent.
install -d "$HOME/.config/omarchy-aquarium/hooks"
install -m755 hooks/aquarium/omarchy-bar-contrast "$HOME/.config/omarchy-aquarium/hooks/"

mkdir -p "$HOME/.config/systemd/user"
# "Auto" appearance is on exactly when this timer is enabled, and the Control
# Center flips it. Only a first install turns it on; a reinstall keeps the
# user's choice.
first_install=1
[[ -e "$HOME/.config/systemd/user/omarchy-auto-appearance.timer" ]] && first_install=0
install -m644 systemd/omarchy-auto-appearance.{service,timer} "$HOME/.config/systemd/user/"
# The bar-contrast timer is not a user choice: it only matters with the bar in
# transparent mode, and does nothing visible otherwise, so it is always on.
install -m644 systemd/omarchy-bar-contrast.{service,timer} "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
if (( first_install )); then
    systemctl --user enable --now omarchy-auto-appearance.timer
fi
systemctl --user enable --now omarchy-bar-contrast.timer

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

# Cmd-key grammar and the app switcher. On this machine Omarchy already made
# ~/.config/hypr, but on a genuinely bare box it does not exist yet and, under
# `set -e`, the install dies here before anything below it runs.
mkdir -p "$HOME/.config/hypr"
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
fi

echo "Installed. Wire the daemons and bindings into Hyprland: see hypr/example.lua"
