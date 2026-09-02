#!/bin/bash
# tests/test_omarchy_locate.sh — omarchy-locate against a fake curl and a fake
# omarchy-auto-appearance.
set -uo pipefail
cd "$(dirname "$0")/.."

SCRIPT="$PWD/style/omarchy-locate"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
mkdir -p "$XDG_CONFIG_HOME/omarchy" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
export FAKE_LOG="$TMP/calls"
JSON="$XDG_CONFIG_HOME/omarchy/dynamic-wallpaper.json"

cat > "$TMP/bin/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$FAKE_LOG"
[[ -n ${FAKE_CURL_FAIL:-} ]] && exit 7
if [[ -n ${FAKE_CURL:-} ]]; then echo "$FAKE_CURL"; else echo '{"status":"success","lat":50.4108,"lon":4.4446,"city":"Charleroi"}'; fi
EOF
cat > "$TMP/bin/omarchy-auto-appearance" <<'EOF'
#!/bin/bash
echo "omarchy-auto-appearance $*" >> "$FAKE_LOG"
EOF
chmod +x "$TMP/bin"/*

fails=0
check() { local name=$1; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails+1)); fi; }
reset() { : > "$FAKE_LOG"; unset FAKE_CURL FAKE_CURL_FAIL
  printf '%s\n' '{"theme":"apple-glass","mode":"solar","latitude":48.8566,"longitude":2.3522,"set":"tahoe-beach","sets":{"tahoe-beach":{"day":"a.jpg"}}}' > "$JSON"; chmod 644 "$JSON"; }

reset
out=$("$SCRIPT"); rc=$?
check "success exits 0" [ "$rc" -eq 0 ]
check "prints lat lon city" [ "$out" = "50.4108 4.4446 Charleroi" ]
check "latitude written" [ "$(jq -r .latitude "$JSON")" = "50.4108" ]
check "longitude written" [ "$(jq -r .longitude "$JSON")" = "4.4446" ]
check "other keys intact" [ "$(jq -c '.sets' "$JSON")" = '{"tahoe-beach":{"day":"a.jpg"}}' ]
check "theme key intact" [ "$(jq -r .theme "$JSON")" = "apple-glass" ]
check "applies the theme afterwards" grep -qx 'omarchy-auto-appearance ' "$FAKE_LOG"
check "asks ip-api over http" grep -q 'ip-api.com/json' "$FAKE_LOG"
check "preserves file mode" [ "$(stat -c %a "$JSON")" = "644" ]

reset; export FAKE_CURL_FAIL=1
err=$("$SCRIPT" 2>&1 >/dev/null); rc=$?
check "curl failure exits 1" [ "$rc" -eq 1 ]
check "curl failure leaves the file" [ "$(jq -r .latitude "$JSON")" = "48.8566" ]
check "curl failure explains" grep -qi 'hors ligne\|offline\|curl' <<<"$err"
check "curl failure does not apply" [ -z "$(grep 'omarchy-auto-appearance' "$FAKE_LOG")" ]

reset; export FAKE_CURL='{"status":"fail","message":"private range"}'
"$SCRIPT" 2>/dev/null; rc=$?
check "api failure exits 1" [ "$rc" -eq 1 ]
check "api failure leaves the file" [ "$(jq -r .longitude "$JSON")" = "2.3522" ]

reset; rm -f "$JSON"
"$SCRIPT" 2>/dev/null; rc=$?
check "missing json exits 1" [ "$rc" -eq 1 ]
check "missing json is not created" [ ! -e "$JSON" ]

reset; export FAKE_CURL='{"status":"success","city":"Nowhere"}'
err=$("$SCRIPT" 2>&1 >/dev/null); rc=$?
check "no coordinates exits 1" [ "$rc" -eq 1 ]
check "no coordinates leaves the file" [ "$(jq -r .latitude "$JSON")" = "48.8566" ]
check "no coordinates does not apply" [ -z "$(grep 'omarchy-auto-appearance' "$FAKE_LOG")" ]

echo; [[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
