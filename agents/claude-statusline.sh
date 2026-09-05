#!/usr/bin/env bash
# Claude Code statusline for macarchy — a fuel gauge, not a dashboard.
#
# ANSI-16 only on purpose: colors come from the terminal palette, so the bar
# re-themes itself when Omarchy flips light/dark — no theme hook needed.
# Quiet by default: a segment appears only once it carries information.

set -u

OUT='' LEN=0 BUDGET=0

# Append a colored segment, preceded by `gap` spaces, if it still fits.
seg() { # <ansi-color> <text> [gap=2]
  local gap=${3-2} w bare
  ((LEN == 0)) && gap=1
  # Nerd Font icons come from the non-Mono family and take two cells each.
  bare=${2//[$'\ue0a0'$'\uf407'$'\uf0e7']/}
  w=$((gap + ${#2} + ${#2} - ${#bare}))
  ((LEN + w > BUDGET)) && return 1
  printf -v OUT '%s%*s\033[%sm%s\033[0m' "$OUT" "$gap" '' "$1" "$2"
  LEN=$((LEN + w))
}

num() { local v="${1%%.*}"; echo "${v:-0}"; }

# calm / warn / critical -> ansi color and fill glyph. Density rises with
# danger so the gauge reads without color.
heat()  { local p; p=$(num "$1"); ((p>=85)) && echo 31 || { ((p>=60)) && echo 33 || echo 32; }; }
glyph() { local p; p=$(num "$1"); ((p>=85)) && echo '█' || { ((p>=60)) && echo '▓' || echo '▒'; }; }

gauge() { # <pct> -> 12-cell bar, fill darkens as it rises
  local p n i f s=''; p=$(num "$1"); ((p>100)) && p=100
  f=$(glyph "$p"); n=$((p * 12 / 100))
  ((p > 0 && n == 0)) && n=1   # a needle just off zero beats a gauge that looks off
  for ((i=0;i<12;i++)); do ((i<n)) && s+=$f || s+='░'; done
  printf '%s' "$s"
}

eta() { # unix epoch -> "2h14" / "47m", empty if past
  local s=$(( $(num "$1") - $(date +%s) ))
  ((s<=0)) && return
  ((s>=3600)) && printf '%dh%02d' $((s/3600)) $((s%3600/60)) || printf '%dm' $((s/60))
}

render() {
  local F
  mapfile -t F < <(jq -r '[
    .model.display_name // "?",
    .effort.level // "",
    (.fast_mode // false),
    .workspace.current_dir // .cwd // "",
    (.worktree.name // .workspace.git_worktree // ""),
    (.pr.number // ""), (.pr.review_state // ""),
    (.context_window.used_percentage // 0),
    (.rate_limits.five_hour.used_percentage // 0),
    (.rate_limits.seven_day.used_percentage // 0),
    (.rate_limits.seven_day.resets_at // 0),
    (.cost.total_cost_usd // 0),
    (.cost.total_lines_added // 0), (.cost.total_lines_removed // 0),
    (.agent.name // ""),
    (.session_id // "")
  ] | .[] | tostring | gsub("\n";" ")' 2>/dev/null)
  [ "${#F[@]}" -ge 16 ] || return 0
  local model=${F[0]} effort=${F[1]} fast=${F[2]} dir=${F[3]} wt=${F[4]}
  local pr=${F[5]} prstate=${F[6]} ctx=${F[7]} h5=${F[8]} d7=${F[9]} d7r=${F[10]}
  local cost=${F[11]} added=${F[12]} removed=${F[13]} agent=${F[14]} sid=${F[15]}

  # Line 1 — where I am. Line 2 — what it costs.
  BUDGET=${COLUMNS:-200}; BUDGET=$((BUDGET - 1))

  OUT='' LEN=0
  seg 36 "$model"
  [ -n "$effort" ] && seg 36 "$effort" 1
  [ "$fast" = true ] && seg 93 $'\uf0e7' 1
  [ -n "$agent" ] && seg 95 "@$agent"

  # `wt/` spells out a worktree: a glyph would be prettier and would not
  # render on half the fonts out there.
  if [ -n "$wt" ]; then seg 34 "wt/$wt"
  elif [ -n "$dir" ]; then seg 34 "${dir##*/}"; fi

  if [ -n "$dir" ] && [ -d "$dir" ]; then
    local gs branch dirty
    gs=$(git -C "$dir" status --porcelain -b 2>/dev/null) && {
      branch=$(head -n1 <<<"$gs"); branch=${branch#\#\# }; branch=${branch%%...*}
      dirty=$(( $(wc -l <<<"$gs") - 1 ))
      seg 35 $'\ue0a0'" $branch"
      ((dirty > 0)) && seg 33 "●$dirty" 1
    }
  fi

  # Review state gets a shape as well as a color.
  if [ -n "$pr" ]; then
    local pc=90 mark=''
    case "$prstate" in
      approved)          pc=32 mark='✓' ;;
      changes_requested) pc=31 mark='✗' ;;
      pending)           pc=33 mark='·' ;;
    esac
    seg "$pc" $'\uf407'" $pr$mark"
  fi

  [ "$(head -n1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.ponytail-active" 2>/dev/null | tr -d '[:space:]')" ] &&
    seg 32 'ponytail'

  local line1=$OUT

  # The gauge leads: leftmost cells are where peripheral vision catches change.
  OUT='' LEN=0
  seg "$(heat "$ctx")" "$(gauge "$ctx")"
  seg "$(heat "$ctx")" "$(num "$ctx")%" 1

  # Quota windows stay hidden until a quarter burned — silence is the signal.
  [ "$(num "$h5")" -ge 25 ] && seg "$(heat "$h5")" "5h $(num "$h5")%"
  if [ "$(num "$d7")" -ge 25 ]; then
    seg "$(heat "$d7")" "7d $(num "$d7")%"
    local left; left=$(eta "$d7r"); [ -n "$left" ] && seg 90 "↻$left" 1
  fi

  # Tail: droppable first when the terminal is narrow.
  awk "BEGIN{exit !($cost >= 0.10)}" 2>/dev/null && seg 90 "$(printf '$%.2f' "$cost")"
  ((added + removed > 0)) && seg 90 "+$added/-$removed"

  printf '%s\n%s\n' "$line1" "$OUT"

  # Leave the context reading where macarchy-touchbar's `claude` module can
  # find it: one file per session, on tmpfs, so a logout clears them all.
  # No-op when nothing reads it.
  local d=${XDG_RUNTIME_DIR:-}/macarchy-claude
  [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -n "$sid" ] && mkdir -p "$d" 2>/dev/null &&
    printf '%s\n' "$(num "$ctx")" >"$d/$sid" 2>/dev/null
  return 0
}

if [ "${1:-}" != "--test" ]; then render; exit 0; fi

# --- self-check -------------------------------------------------------------
fail() { echo "FAIL: $1"; exit 1; }
has()  { case "$2" in *"$1"*) ;; *) fail "missing '$1' in: $2";; esac; }
hasnt(){ case "$2" in *"$1"*) fail "unexpected '$1' in: $2";; esac; }

[ "$(heat 42)" = 32 ] && [ "$(heat 60)" = 33 ] && [ "$(heat 85)" = 31 ] || fail 'heat thresholds'
[ "$(glyph 42)" = '▒' ] && [ "$(glyph 60)" = '▓' ] && [ "$(glyph 85)" = '█' ] || fail 'glyph ramp'
[ "$(gauge 0)" = '░░░░░░░░░░░░' ] || fail "gauge 0: $(gauge 0)"
[ "$(gauge 1)" = '▒░░░░░░░░░░░' ] || fail "gauge 1: $(gauge 1)"
[ "$(gauge 50)" = '▒▒▒▒▒▒░░░░░░' ] || fail "gauge 50: $(gauge 50)"
[ "$(gauge 100)" = '████████████' ] || fail "gauge 100: $(gauge 100)"
[ "$(gauge 120)" = '████████████' ] || fail 'gauge clamp'
[ -z "$(eta 1)" ] || fail 'past reset must be empty'

busy=$(COLUMNS=200 render <<JSON
{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":91},
 "effort":{"level":"xhigh"},"fast_mode":true,"agent":{"name":"auto-dev"},
 "workspace":{"current_dir":"$PWD"},"worktree":{"name":"wake-daemon"},
 "pr":{"number":284,"review_state":"changes_requested"},
 "rate_limits":{"five_hour":{"used_percentage":62},
                "seven_day":{"used_percentage":91,"resets_at":$(( $(date +%s) + 8040 ))}},
 "cost":{"total_cost_usd":1.8432,"total_lines_added":312,"total_lines_removed":77}}
JSON
)
for w in '██████████░░' '91%' 'Opus 5' 'xhigh' $'\uf0e7' '@auto-dev' 'wt/wake-daemon' \
         $'\uf407'" 284✗" '5h 62%' '7d 91%' '↻2h' '$1.84' '+312/-77'; do has "$w" "$busy"; done

# A fresh session says almost nothing.
calm=$(COLUMNS=200 render <<<'{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":4},
 "rate_limits":{"five_hour":{"used_percentage":3},"seven_day":{"used_percentage":11}},
 "cost":{"total_cost_usd":0.02}}')
for w in '5h' '7d' '$'; do hasnt "$w" "$calm"; done
has '▒' "$calm"

# Narrow terminals truncate instead of wrapping.
narrow=$(COLUMNS=28 render <<<'{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":50},
 "cost":{"total_cost_usd":9.99},"rate_limits":{"seven_day":{"used_percentage":80}}}')
while IFS= read -r l; do
  plain=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$l")
  [ ${#plain} -le 27 ] || fail "narrow width ${#plain}: $plain"
done <<<"$narrow"
hasnt '$9.99' "$narrow"

# The Touch Bar hand-off: one file per session, named by session id.
export XDG_RUNTIME_DIR=$(mktemp -d)
render <<<'{"session_id":"s1","context_window":{"used_percentage":73}}' >/dev/null
[ "$(cat "$XDG_RUNTIME_DIR/macarchy-claude/s1" 2>/dev/null)" = 73 ] || fail 'context not handed off'
rm -rf "$XDG_RUNTIME_DIR"; unset XDG_RUNTIME_DIR

render </dev/null; render <<<'not json'   # must not crash
printf '%s\n%s\n' "$busy" "$calm"; echo OK
