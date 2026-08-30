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

if [[ ${1-} == --udev ]]; then
    sudo install -m644 udev/90-battery-charge-limit.rules /etc/udev/rules.d/
    sudo udevadm control --reload
    echo "udev battery rule installed (applies on next battery 'add' event or reboot)"
fi

echo "Installed. Wire the daemons and bindings into Hyprland: see hypr/example.lua"
