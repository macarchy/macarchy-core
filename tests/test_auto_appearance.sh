#!/bin/bash
# tests/test_auto_appearance.sh — runs style/macarchy-auto-appearance against
# fake macarchy-sun / omarchy / systemctl binaries and an injected clock.
set -uo pipefail
cd "$(dirname "$0")/.."

SCRIPT="$PWD/style/macarchy-auto-appearance"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
mkdir -p "$HOME/.local/state/omarchy/current" "$XDG_CONFIG_HOME/omarchy" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
LOG="$TMP/calls"

# --- fakes -------------------------------------------------------------------
cat > "$TMP/bin/omarchy" <<'EOF'
#!/bin/bash
echo "omarchy $*" >> "$FAKE_LOG"
EOF
cat > "$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$FAKE_LOG"
echo "${FAKE_ENABLED:-disabled}"
[[ ${FAKE_ENABLED:-disabled} == enabled ]]
EOF
cat > "$TMP/bin/macarchy-sun" <<'EOF'
#!/bin/bash
echo "macarchy-sun $*" >> "$FAKE_LOG"
[[ -n ${FAKE_SUN_FAIL:-} ]] && { echo "macarchy-sun: no location" >&2; exit 2; }
if [[ -n ${FAKE_SUN:-} ]]; then echo "$FAKE_SUN"; else echo '{"state":"normal","sunrise":"06:57","sunset":"20:26"}'; fi
EOF
chmod +x "$TMP/bin"/*
export FAKE_LOG="$LOG"

fails=0
check() {  # check <name> <condition...>
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails+1)); fi
}
reset() { : > "$LOG"; unset FAKE_SUN FAKE_SUN_FAIL FAKE_ENABLED; }
theme() { echo "$1" > "$HOME/.local/state/omarchy/current/theme.name"; }
conf()  { printf '%s\n' "$@" > "$XDG_CONFIG_HOME/omarchy/auto-appearance.conf"; }
called() { grep -qx "$1" "$LOG"; }
not_called() { ! grep -q "$1" "$LOG"; }

# --- solar mode (default when no conf) ---------------------------------------
reset; rm -f "$XDG_CONFIG_HOME/omarchy/auto-appearance.conf"; theme apple-glass
AUTO_APPEARANCE_NOW=12:00 "$SCRIPT"
check "solar: daytime on dark theme switches to light" called 'omarchy theme set Apple Glass Light'

reset; theme apple-glass-light
AUTO_APPEARANCE_NOW=21:00 "$SCRIPT"
check "solar: night on light theme switches to dark" called 'omarchy theme set Apple Glass'

reset; theme apple-glass-light
AUTO_APPEARANCE_NOW=12:00 "$SCRIPT"
check "solar: already correct does nothing" not_called 'omarchy theme set'

reset; theme tokyo-night
AUTO_APPEARANCE_NOW=12:00 "$SCRIPT"
check "third-party theme is left alone" not_called 'omarchy theme set'

reset; theme apple-glass; export FAKE_SUN='{"state":"up","sunrise":null,"sunset":null}'
AUTO_APPEARANCE_NOW=02:00 "$SCRIPT"
check "midnight sun wants light" called 'omarchy theme set Apple Glass Light'

reset; theme apple-glass-light; export FAKE_SUN='{"state":"down","sunrise":null,"sunset":null}'
AUTO_APPEARANCE_NOW=12:00 "$SCRIPT"
check "polar night wants dark" called 'omarchy theme set Apple Glass'

reset; theme apple-glass; export FAKE_SUN_FAIL=1
err=$(AUTO_APPEARANCE_NOW=12:00 "$SCRIPT" 2>&1); rc=$?
# A sun it cannot compute means "leave the theme alone", which is a decision and
# not a failure. It used to exit 1, which parked the unit in `systemctl --user
# --failed` for ever and fired its OnFailure= notifier on every machine with no
# coordinates set (macarchy-install#9). Doing nothing still has to be SILENT in
# the exit status and LOUD in the journal, so all three of these matter.
check "a sun it cannot compute is a skip, not a failure" [ "$rc" -eq 0 ]
check "sun failure changes nothing" not_called 'omarchy theme set'
check "sun failure still says so" grep -q 'macarchy-sun' <<<"$err"

# --- schedule mode -----------------------------------------------------------
reset; theme apple-glass; conf 'MODE=schedule' 'LIGHT_FROM=07:00' 'LIGHT_UNTIL=20:00'
AUTO_APPEARANCE_NOW=12:00 "$SCRIPT"
check "schedule: daytime switches to light" called 'omarchy theme set Apple Glass Light'
check "schedule: never asks the sun" not_called 'macarchy-sun'

reset; theme apple-glass-light; conf 'MODE=schedule' 'LIGHT_FROM=07:00' 'LIGHT_UNTIL=20:00'
AUTO_APPEARANCE_NOW=20:00 "$SCRIPT"
check "schedule: until is exclusive" called 'omarchy theme set Apple Glass'

reset; theme apple-glass; conf 'MODE=schedule' 'LIGHT_FROM=22:00' 'LIGHT_UNTIL=02:00'
AUTO_APPEARANCE_NOW=23:30 "$SCRIPT"
check "schedule: window wrapping midnight" called 'omarchy theme set Apple Glass Light'

# --- status ------------------------------------------------------------------
reset; theme apple-glass; rm -f "$XDG_CONFIG_HOME/omarchy/auto-appearance.conf"; export FAKE_ENABLED=enabled
out=$(AUTO_APPEARANCE_NOW=12:00 "$SCRIPT" status)
check "status solar line" [ "$out" = "mode=solar enabled=yes want=light sunrise=06:57 sunset=20:26" ]
check "status does not switch" not_called 'omarchy theme set'

reset; theme apple-glass; conf 'MODE=schedule' 'LIGHT_FROM=07:00' 'LIGHT_UNTIL=20:00'
out=$(AUTO_APPEARANCE_NOW=23:00 "$SCRIPT" status)
check "status schedule line" [ "$out" = "mode=schedule enabled=no want=dark from=07:00 until=20:00" ]

reset; theme apple-glass; rm -f "$XDG_CONFIG_HOME/omarchy/auto-appearance.conf"; export FAKE_SUN_FAIL=1
out=$("$SCRIPT" status 2>/dev/null); rc=$?
check "status on sun failure" [ "$out" = "mode=solar enabled=no error=sun" ]
check "status on sun failure exits 0" [ "$rc" -eq 0 ]

reset; theme apple-glass; export FAKE_SUN='{"state":"up","sunrise":null,"sunset":null}'
out=$("$SCRIPT" status)
check "status polar omits times" [ "$out" = "mode=solar enabled=no want=light" ]

# --- garbled macarchy-sun output does not silently force a theme ---------------
# The invariant these three inputs defend is "it must not GUESS a theme", and
# that is `does not switch`. The exit code was never the point: all three reach
# the same "no answer, changed nothing" branch, which exits 0 like the script's
# own "user chose something else" branch two screens down.
reset; theme apple-glass; export FAKE_SUN='{"state":""}'
err=$(AUTO_APPEARANCE_NOW=12:00 "$SCRIPT" 2>&1); rc=$?
check "empty state is a skip too"   [ "$rc" -eq 0 ]
check "empty state does not switch" not_called 'omarchy theme set'

reset; theme apple-glass; export FAKE_SUN='{"state":""}'
out=$(AUTO_APPEARANCE_NOW=12:00 "$SCRIPT" status)
check "empty state status line" [ "$out" = "mode=solar enabled=no error=sun" ]

reset; theme apple-glass; export FAKE_SUN='not json'
err=$(AUTO_APPEARANCE_NOW=12:00 "$SCRIPT" 2>&1); rc=$?
# Same branch as above, reached by a different input, so the same verdict: it
# changed nothing, so it did not fail. The error stays legible where an error
# belongs -- `status` reports `error=sun`, and the message is in the journal.
check "garbled sun json is a skip too"   [ "$rc" -eq 0 ]
check "garbled sun json does not switch" not_called 'omarchy theme set'

reset; theme apple-glass; export FAKE_SUN='not json'
out=$(AUTO_APPEARANCE_NOW=12:00 "$SCRIPT" status)
check "garbled sun json status line" [ "$out" = "mode=solar enabled=no error=sun" ]

echo; [[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
