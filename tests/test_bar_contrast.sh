#!/bin/bash
# tests/test_bar_contrast.sh — the verdict and the shell.toml rewrite, with the
# screen sample injected so no compositor is needed.
set -uo pipefail
cd "$(dirname "$0")/.."
SCRIPT="$PWD/style/omarchy-bar-contrast"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
mkdir -p "$XDG_CONFIG_HOME/omarchy"
CONF="$XDG_CONFIG_HOME/omarchy/shell.toml"
fails=0
check() { local name=$1; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails+1)); fi; }

printf '[font]\nbase-size = 14\n' > "$CONF"
out=$("$SCRIPT" status --sample '#003575')
check "status: dark water wants light text" grep -q 'verdict=light text=#f5f5f7' <<<"$out"
check "status writes nothing" [ "$(cat "$CONF")" = $'[font]\nbase-size = 14' ]

"$SCRIPT" --sample '#003575' >/dev/null
check "light verdict written" grep -q '^text   = "#f5f5f7"$' "$CONF"
check "active written" grep -q '^active = "#ff453a"$' "$CONF"
check "font section preserved" grep -q '^base-size = 14$' "$CONF"
check "one [bar] section" [ "$(grep -c '^\[bar\]' "$CONF")" = 1 ]

before=$(stat -c %Y "$CONF"); sleep 1.1
out=$("$SCRIPT" --sample '#002a60')
check "same verdict: no rewrite" [ "$(stat -c %Y "$CONF")" = "$before" ]
check "same verdict: silent" [ -z "$out" ]

"$SCRIPT" --sample '#e8eef7' >/dev/null
check "light ground flips to dark text" grep -q '^text   = "#1d1d1f"$' "$CONF"
check "still one [bar] section" [ "$(grep -c '^\[bar\]' "$CONF")" = 1 ]
check "font still there" grep -q '^base-size = 14$' "$CONF"
check "single managed block" [ "$(grep -c 'omarchy-bar-contrast' "$CONF")" = 2 ]

rm -f "$CONF"; "$SCRIPT" --sample '#003575' >/dev/null
check "missing conf is created" grep -q '^text   = "#f5f5f7"$' "$CONF"

"$SCRIPT" --sample 'nope' 2>/dev/null; check "bad sample exits 1" [ $? -eq 1 ]

echo; [[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
