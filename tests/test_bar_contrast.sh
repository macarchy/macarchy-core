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

# --- the settle loop -------------------------------------------------------
# The wallpaper rotator, the appearance switcher and this tool used to fire on
# the same five-minute boundary, so a grab could catch the OUTGOING frame and
# latch the previous verdict until the next tick. Sampling must hold still
# before the verdict counts.
FAKE="$TMP/fake-capture"
CALLS="$TMP/calls"
export CALLS OMARCHY_BAR_CONTRAST_SETTLE_GAP=0.02
fake_capture() {  # $1 stale colour for the first two grabs, $2 the arriving one
  printf '#!/bin/bash\nn=$(cat "$CALLS" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$CALLS"\nif ((n <= 2)); then echo %s; else echo %s; fi\n' "$1" "$2" > "$FAKE"
  chmod +x "$FAKE"; rm -f "$CALLS"
}

printf '[font]\nbase-size = 14\n' > "$CONF"
"$SCRIPT" --sample '#040407' >/dev/null            # start from the night verdict
check "night ground parks light text" grep -q '^text   = "#f5f5f7"$' "$CONF"

# The outgoing night frame is still on screen while the day wallpaper lands.
fake_capture "'#040407'" "'#3385bd'"
OMARCHY_BAR_CONTRAST_CAPTURE="$FAKE" "$SCRIPT" >/dev/null 2>&1
check "settling kept sampling past the stale grabs" [ "$(cat "$CALLS" 2>/dev/null || echo 0)" -ge 3 ]
check "transition is not latched from the outgoing frame" \
  grep -q '^text   = "#1d1d1f"$' "$CONF"

# A ground that never moves must settle without draining the retry budget.
fake_capture "'#040407'" "'#040407'"
OMARCHY_BAR_CONTRAST_CAPTURE="$FAKE" "$SCRIPT" >/dev/null 2>&1
check "steady ground flips to light text" grep -q '^text   = "#f5f5f7"$' "$CONF"
check "steady ground settles quickly" [ "$(cat "$CALLS" 2>/dev/null || echo 99)" -le 4 ]

fake_capture "'#040407'" "'#040407'"
out=$(OMARCHY_BAR_CONTRAST_CAPTURE="$FAKE" "$SCRIPT" status 2>/dev/null)
check "status reports the settled sample" grep -q 'sample=#040407 .*verdict=light' <<<"$out"
unset OMARCHY_BAR_CONTRAST_CAPTURE OMARCHY_BAR_CONTRAST_SETTLE_GAP CALLS

# --- the bar layer in flight ----------------------------------------------
# Writing shell.toml makes the shell hot-reload, which unmaps and remaps the
# bar layer. A lookup that lands in that gap used to abort the whole round.
SHIM="$TMP/bin"; mkdir -p "$SHIM"
export HCALLS="$TMP/hcalls"
cat > "$SHIM/hyprctl" <<'EOF'
#!/bin/bash
n=$(cat "$HCALLS" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HCALLS"
if ((n <= 2)); then echo '[]'; else
  echo '{"eDP-1":{"levels":{"2":[{"namespace":"omarchy-bar","x":0,"y":0,"w":1600,"h":33}]}}}'
fi
EOF
cat > "$SHIM/grim" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$SHIM/magick" <<'EOF'
#!/bin/bash
echo 0A0A0D
EOF
chmod +x "$SHIM"/*
rm -f "$HCALLS"
printf '[font]\nbase-size = 14\n' > "$CONF"
"$SCRIPT" --sample '#e8eef7' >/dev/null                # park on the dark verdict
out=$(PATH="$SHIM:$PATH" OMARCHY_BAR_CONTRAST_SETTLE_GAP=0.02 "$SCRIPT" 2>&1)
check "a remapping bar layer is waited out, not skipped" \
  grep -q '^text   = "#f5f5f7"$' "$CONF"
check "no give-up message while the layer is in flight" \
  [ -z "$(grep -c 'no omarchy-bar layer' <<<"$out" | grep -v '^0$')" ]
unset HCALLS

echo; [[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
