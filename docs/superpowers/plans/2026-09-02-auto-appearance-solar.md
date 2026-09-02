# Auto appearance follows the sun — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an « Auto » appearance mode to the Control Center's Affichage module that switches Apple Glass ↔ Apple Glass Light at sunrise/sunset for the machine's shared location.

**Architecture:** A new `omarchy-sun` CLI (Python, NOAA equation) answers "when does the sun rise/set here" from the lat/lon already in `~/.config/omarchy/dynamic-wallpaper.json`. The existing bash `omarchy-auto-appearance` gains `MODE=solar` (asks `omarchy-sun`) and a `status` line; "Auto" is defined as *its systemd user timer is enabled*, nothing else. The QML module reads `status`, offers a three-way pill, and a « Détecter » button runs a new `omarchy-locate` script (ip-api.com → jq → the JSON).

**Tech Stack:** bash, Python 3 (stdlib only, `unittest`), systemd user timers, jq, curl, QML/Quickshell (`qs.Ui`, `qs.Commons`), qmllint.

**Spec:** `docs/superpowers/specs/2026-09-02-auto-appearance-solar-design.md`

## Global Constraints

- Repo: `~/Work/omarchy-mac`. Scripts live in `style/`, are installed to `~/.local/bin` by `install.sh` (`install -m755 hardware/* style/* "$BIN"/`). New scripts get no extension, `#!` line, mode 755.
- All user-facing text in the Control Center is **French**, sentences end with a period, spec wording copied verbatim.
- Theme names: dark = `apple-glass` / « Apple Glass », light = `apple-glass-light` / « Apple Glass Light ». Slug files: `~/.local/state/omarchy/current/theme.name`.
- Location file: `~/.config/omarchy/dynamic-wallpaper.json`, keys `latitude`, `longitude` (numbers). Never touch its other keys.
- Never write into `~/.config/omarchy/plugins/` at runtime. After installing the plugin, run `omarchy restart shell` in a **separate** command from the file copy (see memory `shell-plugin-reload-restart-race`).
- Python tests: `python3 -m unittest discover -s tests -v`. Bash tests: `bash tests/<name>.sh` (exit 0 = pass).
- QML lint: `ln -sfn /usr/share/omarchy/shell /tmp/claude-1001/-home-phmatray-Work/8b7d644d-bf46-4063-b147-17bbba50a86f/scratchpad/qs && /usr/lib/qt6/bin/qmllint -I /tmp/claude-1001/-home-phmatray-Work/8b7d644d-bf46-4063-b147-17bbba50a86f/scratchpad <file>.qml`. Ignore only `Member "…" not found on type "QObject"` and `Type PanelWindow is not creatable`. (The memory says the shell may also be at `~/.local/share/omarchy/shell`; both exist — use `/usr/share/omarchy/shell`.)
- Commit after every task. Commit message trailer:

  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01G1NEZo5U5Xv89D6ZnkhVN7
  ```

## File map

| File | Responsibility |
| --- | --- |
| `style/omarchy-sun` (new) | Pure solar math + CLI: sunrise/sunset for a lat/lon/day. |
| `tests/test_omarchy_sun.py` (new) | unittest for the math and the CLI. |
| `style/omarchy-auto-appearance` (modify) | Decide which theme the clock wants (`MODE=solar|schedule`), apply it, `status`. |
| `tests/test_auto_appearance.sh` (new) | Bash test with fake `omarchy-sun`, `omarchy`, `systemctl` on PATH. |
| `style/omarchy-locate` (new) | IP geolocation → `dynamic-wallpaper.json`. |
| `tests/test_omarchy_locate.sh` (new) | Bash test with a fake `curl`. |
| `systemd/omarchy-auto-appearance.timer` (modify) | 5-minute cadence. |
| `examples/omarchy.auto-appearance.conf` (new) | Commented default conf, installed to `~/.config/omarchy/auto-appearance.conf` if absent. |
| `install.sh` (modify) | Enable the timer only on first install. |
| `shell-plugins/macarchy.control-center/modules/Display.qml` (modify) | Three-way pill, status sentence, position row, home summary. |
| `shell-plugins/macarchy.control-center/BarWidget.qml` (modify) | Home tile leaves Auto mode when tapped. |
| `README.md`, `agents/skills/omarchy-asahi/SKILL.md` (modify) | Docs. |

---

### Task 1: `omarchy-sun` — solar math and CLI

**Files:**
- Create: `style/omarchy-sun`
- Test: `tests/test_omarchy_sun.py`

**Interfaces:**
- Produces (Python, inside the script): `solar_pair(lat: float, lon: float, when_utc: datetime, altitude: float) -> tuple[datetime, datetime] | "up" | "down"`, `sun_for_day(lat, lon, day: date) -> dict` with keys `state` (`"normal"|"up"|"down"`), `sunrise`, `sunset` (`"HH:MM"` local or `None`), `latitude`, `longitude`; `load_location(path: Path) -> tuple[float, float]` raising `LocationError`.
- Produces (CLI): `omarchy-sun [--lat N --lon N] [--date YYYY-MM-DD] [--json]`. Text output `sunrise HH:MM` / `sunset  HH:MM` lines (omitted when absent). Exit 2 when the location cannot be read.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_omarchy_sun.py
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import time
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "style" / "omarchy-sun"


def load_script():
    loader = importlib.machinery.SourceFileLoader("omarchy_sun", str(SCRIPT))
    spec = importlib.util.spec_from_loader("omarchy_sun", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def minutes(hhmm):
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


class SolarPairTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["TZ"] = "Europe/Brussels"
        time.tzset()
        cls.sun = load_script()

    def assertNear(self, hhmm, expected, tolerance=5):
        self.assertLessEqual(abs(minutes(hhmm) - minutes(expected)), tolerance,
                             f"{hhmm} is not within {tolerance} min of {expected}")

    def test_charleroi_early_september(self):
        result = self.sun.sun_for_day(50.46, 4.45, date(2026, 9, 2))
        self.assertEqual(result["state"], "normal")
        self.assertNear(result["sunrise"], "06:57")
        self.assertNear(result["sunset"], "20:26")

    def test_charleroi_winter_solstice_uses_cet(self):
        result = self.sun.sun_for_day(50.46, 4.45, date(2026, 12, 21))
        self.assertNear(result["sunrise"], "08:40")
        self.assertNear(result["sunset"], "16:40")

    def test_midnight_sun(self):
        result = self.sun.sun_for_day(69.65, 18.96, date(2026, 6, 21))
        self.assertEqual(result["state"], "up")
        self.assertIsNone(result["sunrise"])
        self.assertIsNone(result["sunset"])

    def test_polar_night(self):
        result = self.sun.sun_for_day(69.65, 18.96, date(2026, 12, 21))
        self.assertEqual(result["state"], "down")

    def test_solar_pair_returns_utc_datetimes(self):
        when = datetime(2026, 9, 2, 10, 0, tzinfo=timezone.utc)
        rise, set_ = self.sun.solar_pair(50.46, 4.45, when, -0.833)
        self.assertEqual(rise.tzinfo, timezone.utc)
        self.assertEqual((rise.hour, rise.minute), (4, 57))
        self.assertEqual((set_.hour, set_.minute), (18, 26))

    def test_result_carries_location(self):
        result = self.sun.sun_for_day(50.46, 4.45, date(2026, 9, 2))
        self.assertEqual(result["latitude"], 50.46)
        self.assertEqual(result["longitude"], 4.45)


class LoadLocationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sun = load_script()

    def test_reads_latitude_longitude(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "dynamic-wallpaper.json"
            path.write_text(json.dumps({"latitude": 50.46, "longitude": 4.45, "set": "x"}))
            self.assertEqual(self.sun.load_location(path), (50.46, 4.45))

    def test_missing_file_raises(self):
        with self.assertRaises(self.sun.LocationError):
            self.sun.load_location(Path("/nonexistent/dynamic-wallpaper.json"))

    def test_missing_keys_raise(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "dynamic-wallpaper.json"
            path.write_text(json.dumps({"set": "x"}))
            with self.assertRaises(self.sun.LocationError):
                self.sun.load_location(path)


class CliTest(unittest.TestCase):
    def run_cli(self, *args, home=None):
        env = dict(os.environ, TZ="Europe/Brussels")
        if home:
            env["HOME"] = home
        return subprocess.run([sys.executable, str(SCRIPT), *args],
                              capture_output=True, text=True, env=env)

    def test_text_output(self):
        proc = self.run_cli("--lat", "50.46", "--lon", "4.45", "--date", "2026-09-02")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = proc.stdout.splitlines()
        self.assertEqual(len(lines), 2)
        self.assertRegex(lines[0], r"^sunrise \d\d:\d\d$")
        self.assertRegex(lines[1], r"^sunset  \d\d:\d\d$")

    def test_json_output(self):
        proc = self.run_cli("--lat", "50.46", "--lon", "4.45", "--date", "2026-09-02", "--json")
        data = json.loads(proc.stdout)
        self.assertEqual(sorted(data), ["latitude", "longitude", "state", "sunrise", "sunset"])
        self.assertEqual(data["state"], "normal")

    def test_polar_text_output_omits_times(self):
        proc = self.run_cli("--lat", "69.65", "--lon", "18.96", "--date", "2026-06-21")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "")

    def test_reads_location_from_home_config(self):
        with TemporaryDirectory() as home:
            cfg = Path(home) / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            (cfg / "dynamic-wallpaper.json").write_text(
                json.dumps({"latitude": 50.46, "longitude": 4.45}))
            proc = self.run_cli("--date", "2026-09-02", "--json", home=home)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(json.loads(proc.stdout)["latitude"], 50.46)

    def test_missing_location_exits_2(self):
        with TemporaryDirectory() as home:
            proc = self.run_cli("--date", "2026-09-02", home=home)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("dynamic-wallpaper.json", proc.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Work/omarchy-mac && python3 -m unittest discover -s tests -v 2>&1 | tail -5`
Expected: errors — `FileNotFoundError` on `style/omarchy-sun`.

- [ ] **Step 3: Write `style/omarchy-sun`**

```python
#!/usr/bin/env python3
"""Sunrise and sunset for the machine's location.

The location is the one shared by the aquarium and the dynamic wallpaper:
latitude/longitude in ~/.config/omarchy/dynamic-wallpaper.json. The math is
the NOAA sunrise equation (good to about a minute), the same one
macos-dynamic-wallpaper carries.

    omarchy-sun [--lat N --lon N] [--date YYYY-MM-DD] [--json]

Text output is two lines, `sunrise HH:MM` and `sunset  HH:MM`, in local time.
When the sun never crosses the horizon that day both lines are omitted and the
JSON form reports state "up" or "down".
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

CONFIG_PATH = Path(os.environ.get("HOME", "~")).expanduser() / ".config" / "omarchy" / "dynamic-wallpaper.json"
OBLIQUITY = math.radians(23.4397)
HORIZON = -0.833  # degrees: refraction plus the sun's radius


class LocationError(Exception):
    pass


def load_location(path=CONFIG_PATH):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise LocationError(f"cannot read {path}: {exc}") from exc
    try:
        return float(data["latitude"]), float(data["longitude"])
    except (KeyError, TypeError, ValueError) as exc:
        raise LocationError(f"{path} has no usable latitude/longitude") from exc


# --- NOAA sunrise equation ---------------------------------------------------

def _to_julian(dt):
    return dt.timestamp() / 86400.0 + 2440587.5


def _from_julian(j):
    return datetime.fromtimestamp((j - 2440587.5) * 86400.0, tz=timezone.utc)


def solar_pair(lat, lon, when, altitude):
    """Rise/set UTC datetimes for a sun altitude; 'up'/'down' if never crossed."""
    n = round(_to_julian(when) - 2451545.0 + 0.0008)
    j_star = n - lon / 360.0
    m = (357.5291 + 0.98560028 * j_star) % 360.0
    m_rad = math.radians(m)
    c = (1.9148 * math.sin(m_rad) + 0.0200 * math.sin(2 * m_rad)
         + 0.0003 * math.sin(3 * m_rad))
    lam = math.radians((m + c + 180.0 + 102.9372) % 360.0)
    j_transit = 2451545.0 + j_star + 0.0053 * math.sin(m_rad) - 0.0069 * math.sin(2 * lam)
    sin_dec = math.sin(lam) * math.sin(OBLIQUITY)
    dec = math.asin(sin_dec)
    phi = math.radians(lat)
    cos_omega = ((math.sin(math.radians(altitude)) - math.sin(phi) * sin_dec)
                 / (math.cos(phi) * math.cos(dec)))
    if cos_omega > 1.0:
        return "down"
    if cos_omega < -1.0:
        return "up"
    omega = math.degrees(math.acos(cos_omega)) / 360.0
    return _from_julian(j_transit - omega), _from_julian(j_transit + omega)


def sun_for_day(lat, lon, day):
    """Sunrise/sunset of the local civil day, as local HH:MM strings."""
    noon_local = datetime(day.year, day.month, day.day, 12, 0).astimezone()
    result = solar_pair(lat, lon, noon_local.astimezone(timezone.utc), HORIZON)
    out = {"latitude": lat, "longitude": lon, "sunrise": None, "sunset": None}
    if isinstance(result, str):
        out["state"] = result
        return out
    rise, set_ = result
    out["state"] = "normal"
    out["sunrise"] = rise.astimezone().strftime("%H:%M")
    out["sunset"] = set_.astimezone().strftime("%H:%M")
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description="Sunrise and sunset for the shared location.")
    parser.add_argument("--lat", type=float)
    parser.add_argument("--lon", type=float)
    parser.add_argument("--date", type=date.fromisoformat, default=None, metavar="YYYY-MM-DD")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    if (args.lat is None) != (args.lon is None):
        parser.error("--lat and --lon go together")
    if args.lat is not None:
        lat, lon = args.lat, args.lon
    else:
        try:
            lat, lon = load_location()
        except LocationError as exc:
            print(f"omarchy-sun: {exc}", file=sys.stderr)
            return 2

    result = sun_for_day(lat, lon, args.date or date.today())
    if args.json:
        print(json.dumps(result))
        return 0
    if result["sunrise"]:
        print(f"sunrise {result['sunrise']}")
        print(f"sunset  {result['sunset']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Then: `chmod 755 style/omarchy-sun`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Work/omarchy-mac && python3 -m unittest discover -s tests -v 2>&1 | tail -5`
Expected: `OK` with 14 tests.

- [ ] **Step 5: Sanity-run for today**

Run: `TZ=Europe/Brussels style/omarchy-sun --lat 50.46 --lon 4.45`
Expected: two lines, sunrise around 06:57 and sunset around 20:26 for 2026-09-02.

- [ ] **Step 6: Commit**

```bash
cd ~/Work/omarchy-mac && git add style/omarchy-sun tests/test_omarchy_sun.py && git commit -m "Add omarchy-sun: sunrise and sunset for the shared location"
```

---

### Task 2: `omarchy-auto-appearance` — solar mode, `status`, explicit failure

**Files:**
- Modify: `style/omarchy-auto-appearance` (whole file rewritten below)
- Test: `tests/test_auto_appearance.sh`

**Interfaces:**
- Consumes: `omarchy-sun --json` from Task 1 (`state`, `sunrise`, `sunset`).
- Produces: conf keys `MODE` (`solar` default | `schedule`), `LIGHT_FROM`, `LIGHT_UNTIL`; env `AUTO_APPEARANCE_NOW=HH:MM` overrides the clock (tests only); subcommand `status` printing ONE line of `key=value` pairs separated by spaces:
  - solar: `mode=solar enabled=yes|no want=dark|light sunrise=HH:MM sunset=HH:MM` (times absent when state is up/down).
  - schedule: `mode=schedule enabled=yes|no want=dark|light from=HH:MM until=HH:MM`.
  - sun failure (solar): `mode=solar enabled=yes|no error=sun`, exit 0.
  - `enabled` comes from `systemctl --user is-enabled omarchy-auto-appearance.timer` (`yes` iff it prints `enabled`).
- Default action (no argument) applies the theme; on sun failure it prints to stderr and exits 1 without changing anything.

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# tests/test_auto_appearance.sh — runs style/omarchy-auto-appearance against
# fake omarchy-sun / omarchy / systemctl binaries and an injected clock.
set -uo pipefail
cd "$(dirname "$0")/.."

SCRIPT="$PWD/style/omarchy-auto-appearance"
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
cat > "$TMP/bin/omarchy-sun" <<'EOF'
#!/bin/bash
echo "omarchy-sun $*" >> "$FAKE_LOG"
[[ -n ${FAKE_SUN_FAIL:-} ]] && { echo "omarchy-sun: no location" >&2; exit 2; }
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
check "sun failure exits 1" [ "$rc" -eq 1 ]
check "sun failure changes nothing" not_called 'omarchy theme set'
check "sun failure says so" grep -q 'omarchy-sun' <<<"$err"

# --- schedule mode -----------------------------------------------------------
reset; theme apple-glass; conf 'MODE=schedule' 'LIGHT_FROM=07:00' 'LIGHT_UNTIL=20:00'
AUTO_APPEARANCE_NOW=12:00 "$SCRIPT"
check "schedule: daytime switches to light" called 'omarchy theme set Apple Glass Light'
check "schedule: never asks the sun" not_called 'omarchy-sun'

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

echo; [[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/Work/omarchy-mac && bash tests/test_auto_appearance.sh`
Expected: several `FAIL` lines (solar cases, status cases); exit 1.

- [ ] **Step 3: Rewrite `style/omarchy-auto-appearance`**

```bash
#!/bin/bash
# Switch between Apple Glass and Apple Glass Light, the way macOS's "Auto"
# appearance setting does — by default at sunrise and sunset for the location
# shared with the aquarium and the dynamic wallpaper (omarchy-sun), or on a
# fixed schedule (MODE=schedule).
#
#   omarchy-auto-appearance          apply the theme the clock wants
#   omarchy-auto-appearance status   one line: mode= enabled= want= …
#
# "Auto" is on exactly when omarchy-auto-appearance.timer is enabled; nothing
# else stores that state.
#
# Two deliberate guards:
#   - If the current theme is neither Apple Glass variant, do nothing. Picking
#     any other theme is treated as an override, so this never yanks a theme
#     out from under a deliberate choice.
#   - If the correct theme is already set, do nothing. `omarchy theme set` is
#     not free -- it restarts terminals and retints the browser -- so it should
#     not fire on every timer tick.
# And one refusal: when the sun cannot be computed (no location), the solar
# mode does NOT fall back to the fixed schedule. It says so and leaves the
# theme alone, so a broken location never masquerades as a working Auto.

set -uo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/auto-appearance.conf"
MODE=solar
LIGHT_FROM=07:00
LIGHT_UNTIL=20:00
DARK_THEME="Apple Glass"
LIGHT_THEME="Apple Glass Light"
TIMER=omarchy-auto-appearance.timer

# shellcheck source=/dev/null
[[ -r $CONF ]] && source "$CONF"

action=${1:-apply}

to_minutes() {
  local h=${1%%:*} m=${1##*:}
  echo $((10#$h * 60 + 10#$m))
}

# AUTO_APPEARANCE_NOW=HH:MM lets the tests pin the clock.
now=$(to_minutes "${AUTO_APPEARANCE_NOW:-$(date +%H:%M)}")

# Decide `want` (dark|light) and the extra status fields.
extra=""
if [[ $MODE == schedule ]]; then
  from=$(to_minutes "$LIGHT_FROM")
  until_=$(to_minutes "$LIGHT_UNTIL")
  if (( from <= until_ )); then
    (( now >= from && now < until_ )) && want=light || want=dark
  else
    # Light window wraps past midnight.
    (( now >= from || now < until_ )) && want=light || want=dark
  fi
  extra="from=$LIGHT_FROM until=$LIGHT_UNTIL"
else
  if ! sun=$(omarchy-sun --json 2>/dev/null) || [[ -z $sun ]]; then
    want=""
  else
    state=$(jq -r '.state' <<<"$sun")
    sunrise=$(jq -r '.sunrise // empty' <<<"$sun")
    sunset=$(jq -r '.sunset // empty' <<<"$sun")
    case $state in
      up)   want=light ;;
      down) want=dark ;;
      *)
        from=$(to_minutes "$sunrise")
        until_=$(to_minutes "$sunset")
        (( now >= from && now < until_ )) && want=light || want=dark
        extra="sunrise=$sunrise sunset=$sunset"
        ;;
    esac
  fi
fi

if [[ $action == status ]]; then
  enabled=no
  [[ $(systemctl --user is-enabled "$TIMER" 2>/dev/null) == enabled ]] && enabled=yes
  if [[ -z $want ]]; then
    echo "mode=$MODE enabled=$enabled error=sun"
  else
    echo "mode=$MODE enabled=$enabled want=$want${extra:+ $extra}"
  fi
  exit 0
fi

if [[ -z $want ]]; then
  echo "omarchy-auto-appearance: omarchy-sun could not compute today's sun; theme left alone" >&2
  exit 1
fi

[[ $want == light ]] && want_theme=$LIGHT_THEME || want_theme=$DARK_THEME

current_slug=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'; }

case "$current_slug" in
  "$(slug "$DARK_THEME")" | "$(slug "$LIGHT_THEME")") ;;
  *) exit 0 ;;  # user chose something else; leave it alone
esac

[[ $current_slug == "$(slug "$want_theme")" ]] && exit 0

exec omarchy theme set "$want_theme"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/Work/omarchy-mac && bash tests/test_auto_appearance.sh`
Expected: every line `ok`, then `all passed`, exit 0.

- [ ] **Step 5: Check the real thing on this box, without switching anything**

Run: `style/omarchy-auto-appearance status`
Expected: `mode=solar enabled=no want=… sunrise=… sunset=…` (Paris coordinates for now — fine).

- [ ] **Step 6: Commit**

```bash
cd ~/Work/omarchy-mac && git add style/omarchy-auto-appearance tests/test_auto_appearance.sh && git commit -m "Auto appearance: follow the sun by default, add status"
```

---

### Task 3: Packaging — timer cadence, example conf, first-install-only enable

**Files:**
- Modify: `systemd/omarchy-auto-appearance.timer`
- Create: `examples/omarchy.auto-appearance.conf`
- Modify: `install.sh:14-17`

**Interfaces:**
- Consumes: conf keys from Task 2.
- Produces: `~/.config/omarchy/auto-appearance.conf` gets installed from the example when absent (install.sh's existing `examples/*` loop maps `omarchy.auto-appearance.conf` → `~/.config/omarchy/auto-appearance.conf`).

- [ ] **Step 1: Timer at 5 minutes**

Replace the `[Timer]` block of `systemd/omarchy-auto-appearance.timer` with:

```ini
[Timer]
# Every five minutes on the clock, like the dynamic wallpaper, so a sunset is
# followed within five minutes; and shortly after login, so the appearance is
# already correct by the time the desktop is usable. Persistent catches a
# boundary crossed while the machine was asleep.
OnBootSec=1min
OnCalendar=*:0/5
Persistent=true
```

- [ ] **Step 2: Example conf**

Create `examples/omarchy.auto-appearance.conf`:

```bash
# omarchy-auto-appearance — when the light theme is active.
#
# MODE=solar     light between sunrise and sunset at the location in
#                ~/.config/omarchy/dynamic-wallpaper.json (omarchy-locate
#                fills it in). This is the default.
# MODE=schedule  light between LIGHT_FROM and LIGHT_UNTIL, dark otherwise.
#                The window may wrap past midnight.
MODE=solar
LIGHT_FROM=07:00
LIGHT_UNTIL=20:00
```

- [ ] **Step 3: install.sh enables the timer only the first time**

Replace lines 14–17 of `install.sh`:

```bash
mkdir -p "$HOME/.config/systemd/user"
install -m644 systemd/omarchy-auto-appearance.{service,timer} "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-auto-appearance.timer
```

with:

```bash
mkdir -p "$HOME/.config/systemd/user"
# "Auto" appearance is on exactly when this timer is enabled, and the Control
# Center flips it. Only a first install turns it on; a reinstall keeps the
# user's choice.
first_install=1
[[ -e "$HOME/.config/systemd/user/omarchy-auto-appearance.timer" ]] && first_install=0
install -m644 systemd/omarchy-auto-appearance.{service,timer} "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
if (( first_install )); then
    systemctl --user enable --now omarchy-auto-appearance.timer
fi
```

(`if`, not `(( first_install )) &&`: the script runs under `set -e` and a false arithmetic test would abort it.)

- [ ] **Step 4: Syntax-check and dry-read**

Run: `bash -n install.sh && systemd-analyze --user verify systemd/omarchy-auto-appearance.timer 2>&1 | grep -v 'Unit .* is not loaded' ; echo "verify rc=$?"`
Expected: no output from `bash -n`; verify prints nothing relevant (a missing-service warning is fine because the service file is referenced by a relative name).

- [ ] **Step 5: Commit**

```bash
cd ~/Work/omarchy-mac && git add systemd/omarchy-auto-appearance.timer examples/omarchy.auto-appearance.conf install.sh && git commit -m "Auto appearance: 5-minute timer, example conf, enable on first install only"
```

---

### Task 4: `omarchy-locate` — IP geolocation into the shared JSON

**Files:**
- Create: `style/omarchy-locate`
- Test: `tests/test_omarchy_locate.sh`

**Interfaces:**
- Produces: `omarchy-locate` — on success prints `<lat> <lon> <city>` on one line, rewrites `latitude`/`longitude` in `${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/dynamic-wallpaper.json` (other keys intact, atomic), then runs `omarchy-auto-appearance` (ignoring its exit code), exit 0. On failure (curl error, `status != success`, no JSON file to update) prints to stderr, writes nothing, exit 1.

- [ ] **Step 1: Write the failing test**

```bash
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
  printf '%s\n' '{"theme":"apple-glass","mode":"solar","latitude":48.8566,"longitude":2.3522,"set":"tahoe-beach","sets":{"tahoe-beach":{"day":"a.jpg"}}}' > "$JSON"; }

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

reset; export FAKE_CURL_FAIL=1
err=$("$SCRIPT" 2>&1 >/dev/null); rc=$?
check "curl failure exits 1" [ "$rc" -eq 1 ]
check "curl failure leaves the file" [ "$(jq -r .latitude "$JSON")" = "48.8566" ]
check "curl failure explains" grep -qi 'hors ligne\|offline\|curl' <<<"$err"
check "curl failure does not apply" ! grep -q 'omarchy-auto-appearance' "$FAKE_LOG"

reset; export FAKE_CURL='{"status":"fail","message":"private range"}'
"$SCRIPT" 2>/dev/null; rc=$?
check "api failure exits 1" [ "$rc" -eq 1 ]
check "api failure leaves the file" [ "$(jq -r .longitude "$JSON")" = "2.3522" ]

reset; rm -f "$JSON"
"$SCRIPT" 2>/dev/null; rc=$?
check "missing json exits 1" [ "$rc" -eq 1 ]
check "missing json is not created" [ ! -e "$JSON" ]

echo; [[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/Work/omarchy-mac && bash tests/test_omarchy_locate.sh`
Expected: `FAIL` lines (script not found), exit 1.

- [ ] **Step 3: Write `style/omarchy-locate`**

```bash
#!/bin/bash
# Find where this machine is and store it as the location shared by the
# aquarium, the dynamic wallpaper and the auto appearance:
# latitude/longitude in ~/.config/omarchy/dynamic-wallpaper.json.
#
# Uses ip-api.com (no key, plain HTTP, 45 requests a minute). Nothing is sent
# but the request itself, and the worst a forged answer can do is shift a
# theme switch by an hour, so that is fine for a button pressed by hand.
#
# Prints "<lat> <lon> <city>" and re-applies the auto appearance on success;
# writes nothing and exits 1 on any failure.
set -uo pipefail

JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/dynamic-wallpaper.json"
URL='http://ip-api.com/json/?fields=status,message,lat,lon,city'

if [[ ! -f $JSON ]]; then
  echo "omarchy-locate: $JSON is missing; nothing to update" >&2
  exit 1
fi

if ! reply=$(curl -fsS --max-time 5 "$URL"); then
  echo "omarchy-locate: détection impossible — hors ligne ? (curl a échoué)" >&2
  exit 1
fi

status=$(jq -r '.status // empty' <<<"$reply" 2>/dev/null)
if [[ $status != success ]]; then
  echo "omarchy-locate: ip-api.com refused: $(jq -r '.message // "unexpected reply"' <<<"$reply" 2>/dev/null)" >&2
  exit 1
fi

lat=$(jq -r '.lat' <<<"$reply")
lon=$(jq -r '.lon' <<<"$reply")
city=$(jq -r '.city // ""' <<<"$reply")

tmp=$(mktemp "${JSON}.XXXXXX")
if ! jq --argjson lat "$lat" --argjson lon "$lon" '.latitude = $lat | .longitude = $lon' "$JSON" > "$tmp"; then
  rm -f "$tmp"
  echo "omarchy-locate: could not rewrite $JSON" >&2
  exit 1
fi
mv -f "$tmp" "$JSON"

echo "$lat $lon $city"
omarchy-auto-appearance || true
exit 0
```

Then `chmod 755 style/omarchy-locate`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/Work/omarchy-mac && bash tests/test_omarchy_locate.sh`
Expected: all `ok`, `all passed`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/omarchy-mac && git add style/omarchy-locate tests/test_omarchy_locate.sh && git commit -m "Add omarchy-locate: IP geolocation into the shared location"
```

---

### Task 5: Display module — Auto pill, status sentence, position row

**Files:**
- Modify: `shell-plugins/macarchy.control-center/modules/Display.qml`

**Interfaces:**
- Consumes: `omarchy-auto-appearance status` line (Task 2), `omarchy-locate` (Task 4), `jq`.
- Produces: module `summary` string per spec; no new contract properties.

- [ ] **Step 1: Replace the summary and add the appearance state**

In `Display.qml`, replace

```qml
  readonly property string summary:
    (mod.lightMode ? "Clair" : "Sombre") + " · auto " + mod.alsWord
```

with

```qml
  readonly property string summary:
    mod.autoOn
      ? "Auto · " + (mod.lightMode ? "Clair" : "Sombre")
      : (mod.lightMode ? "Clair" : "Sombre") + " · luminosité " + mod.alsWord
```

Directly after `readonly property bool lightMode: themeName === "apple-glass-light"` add:

```qml
  // ---- automatic appearance: "Auto" means the systemd timer is enabled,
  // read back from `omarchy-auto-appearance status`. Nothing else stores it.
  property bool autoOn: false
  property string autoMode: "solar"      // "solar" | "schedule"
  property string sunrise: ""
  property string sunset: ""
  property string autoFrom: ""
  property string autoUntil: ""
  property bool sunError: false
  property string latitude: ""
  property string longitude: ""
  property bool locating: false
  property bool locateFailed: false

  readonly property bool appleGlass:
    themeName === "apple-glass" || themeName === "apple-glass-light"
  readonly property string appearanceValue:
    autoOn ? "auto" : (lightMode ? "light" : "dark")

  function appearanceSentence() {
    if (!autoOn) return "L'apparence automatique est désactivée."
    if (!appleGlass) return "En attente : le thème actif n'est pas Apple Glass."
    if (autoMode === "schedule")
      return "Claire de " + autoFrom + " à " + autoUntil + ", sombre le reste du temps."
    if (sunError) return "Position inconnue — appuie sur Détecter."
    if (sunrise === "") return "Suit le soleil."
    return "Suit le soleil — lever " + sunrise + ", coucher " + sunset + "."
  }

  function positionSentence() {
    if (locateFailed) return "Détection impossible — hors ligne ?"
    if (latitude === "") return "Position inconnue"
    return "Position " + Number(latitude).toFixed(2) + ", " + Number(longitude).toFixed(2)
  }
```

- [ ] **Step 2: Replace `setAppearance` with the three-way setter and add `locate`**

Replace

```qml
  function setAppearance(light) {
    themeName = light ? "apple-glass-light" : "apple-glass"
    Quickshell.execDetached(["omarchy-theme-set", themeName])
    slowRecheck.restart()
  }
```

with

```qml
  // "auto" | "light" | "dark". Auto is the timer being enabled; an explicit
  // choice disables it first, like picking Light or Dark on macOS.
  function setAppearance(value) {
    if (value === "auto") {
      autoOn = true
      Quickshell.execDetached(["bash", "-c",
        "systemctl --user enable --now omarchy-auto-appearance.timer; exec omarchy-auto-appearance"])
    } else {
      autoOn = false
      themeName = value === "light" ? "apple-glass-light" : "apple-glass"
      Quickshell.execDetached(["bash", "-c",
        "systemctl --user disable --now omarchy-auto-appearance.timer; exec omarchy-theme-set " + themeName])
    }
    slowRecheck.restart()
  }

  function locate() {
    if (locating) return
    locating = true
    locateFailed = false
    locateProc.running = true
  }
```

- [ ] **Step 3: Probe the status line and the position**

In `refresh()`, add `autoProc.running = true` and `locationProc.running = true`. In `onPanelOpenChanged`, add `autoProc.running = true` after `themeProc.running = true` (the summary needs `autoOn`).

After the `themeProc` `Process`, add:

```qml
  Process {
    id: autoProc
    command: ["omarchy-auto-appearance", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fields = {}
        String(text).trim().split(/\s+/).forEach(function(pair) {
          var eq = pair.indexOf("=")
          if (eq > 0) fields[pair.slice(0, eq)] = pair.slice(eq + 1)
        })
        mod.autoOn = fields.enabled === "yes"
        mod.autoMode = fields.mode || "solar"
        mod.sunError = fields.error === "sun"
        mod.sunrise = fields.sunrise || ""
        mod.sunset = fields.sunset || ""
        mod.autoFrom = fields.from || ""
        mod.autoUntil = fields.until || ""
      }
    }
  }

  Process {
    id: locationProc
    command: ["jq", "-r", '"\\(.latitude) \\(.longitude)"',
      Quickshell.env("HOME") + "/.config/omarchy/dynamic-wallpaper.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length === 2 && isFinite(Number(parts[0])) && isFinite(Number(parts[1]))) {
          mod.latitude = parts[0]
          mod.longitude = parts[1]
        } else {
          mod.latitude = ""
          mod.longitude = ""
        }
      }
    }
  }

  Process {
    id: locateProc
    command: ["omarchy-locate"]
    onExited: function(exitCode) {
      mod.locating = false
      mod.locateFailed = exitCode !== 0
      // omarchy-locate re-applies the theme; give omarchy-theme-set time.
      mod.refresh()
      slowRecheck.restart()
    }
  }
```

- [ ] **Step 4: The page — three-way pill, sentence, position row**

Replace the whole `PanelSectionHeader { text: "Apparence" … }` block through the closing `Text { … "L'apparence automatique peut reprendre la main à son horaire." }` with:

```qml
      PanelSectionHeader {
        text: "Apparence"
        foreground: Color.popups.text
      }

      PillRow {
        Layout.fillWidth: true
        options: [
          { value: "dark", label: "Sombre" },
          { value: "light", label: "Claire" },
          { value: "auto", label: "Auto" }
        ]
        value: mod.appearanceValue
        foreground: Color.popups.text
        fontSize: Style.font.caption
        onChanged: function(v) { mod.setAppearance(v) }
      }

      Text {
        Layout.fillWidth: true
        text: mod.appearanceSentence()
        color: Util.alpha(Color.popups.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Text {
          Layout.fillWidth: true
          text: mod.positionSentence()
          color: Util.alpha(Color.popups.text, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Button {
          text: mod.locating ? "…" : "Détecter"
          enabled: !mod.locating
          bordered: true
          fontSize: Style.font.caption
          foreground: Color.popups.text
          onClicked: mod.locate()
        }
      }
```

- [ ] **Step 5: Lint**

Run:

```bash
S=/tmp/claude-1001/-home-phmatray-Work/8b7d644d-bf46-4063-b147-17bbba50a86f/scratchpad
ln -sfn /usr/share/omarchy/shell "$S/qs"
cd ~/Work/omarchy-mac/shell-plugins/macarchy.control-center
/usr/lib/qt6/bin/qmllint -I "$S" modules/Display.qml 2>&1 | grep -v -E 'not found on type "QObject"|PanelWindow is not creatable'
```

Expected: no output (only the two noise classes were filtered). Fix anything else before moving on — in particular `Unqualified access` means an id is read from inside the page `Component` without `mod.`; the file already has `pragma ComponentBehavior: Bound`.

- [ ] **Step 6: Commit**

```bash
cd ~/Work/omarchy-mac && git add shell-plugins/macarchy.control-center/modules/Display.qml && git commit -m "Control Center: Auto appearance follows the sun, with a Détecter button"
```

---

### Task 6: Home tile leaves Auto mode

**Files:**
- Modify: `shell-plugins/macarchy.control-center/BarWidget.qml:275-280`

**Interfaces:**
- Consumes: the timer name `omarchy-auto-appearance.timer`.

- [ ] **Step 1: Disable the timer before switching**

Replace

```qml
  function toggleAppearance() {
    var next = lightMode ? "apple-glass" : "apple-glass-light"
    themeName = next
    Quickshell.execDetached(["omarchy-theme-set", next])
    slowRecheck.restart()
  }
```

with

```qml
  // An explicit tap is a choice: it leaves the automatic appearance (the
  // timer) the way picking Light or Dark does on macOS. Entering Auto is the
  // Affichage page's job.
  function toggleAppearance() {
    var next = lightMode ? "apple-glass" : "apple-glass-light"
    themeName = next
    Quickshell.execDetached(["bash", "-c",
      "systemctl --user disable --now omarchy-auto-appearance.timer; exec omarchy-theme-set " + next])
    slowRecheck.restart()
  }
```

- [ ] **Step 2: Lint**

Run:

```bash
S=/tmp/claude-1001/-home-phmatray-Work/8b7d644d-bf46-4063-b147-17bbba50a86f/scratchpad
cd ~/Work/omarchy-mac/shell-plugins/macarchy.control-center
/usr/lib/qt6/bin/qmllint -I "$S" BarWidget.qml 2>&1 | grep -v -E 'not found on type "QObject"|PanelWindow is not creatable'
```

Expected: identical to `git stash; <same command>; git stash pop` — i.e. no new warnings.

- [ ] **Step 3: Commit**

```bash
cd ~/Work/omarchy-mac && git add shell-plugins/macarchy.control-center/BarWidget.qml && git commit -m "Control Center: the Apparence tile leaves Auto mode"
```

---

### Task 7: Docs

**Files:**
- Modify: `README.md:39`
- Modify: `agents/skills/omarchy-asahi/SKILL.md` (the `dynamic-wallpaper` paragraph around lines 56–64, and the tools table line 31)

- [ ] **Step 1: README table**

Replace line 39 of `README.md` with three rows:

```markdown
| `omarchy-auto-appearance` | Switches between the Apple Glass and Apple Glass Light themes at sunrise and sunset (or on a fixed schedule), like macOS's "Auto" appearance. Driven by a systemd user timer; "Auto" is on exactly when that timer is enabled, and the Control Center's Affichage page flips it. |
| `omarchy-sun` | Prints today's sunrise and sunset for the shared location (`~/.config/omarchy/dynamic-wallpaper.json`). |
| `omarchy-locate` | Detects the machine's location (ip-api.com) and stores it in the shared location file, for the aquarium, the dynamic wallpaper and the auto appearance alike. |
```

- [ ] **Step 2: SKILL.md**

In the tools table line that lists `omarchy-auto-appearance`, add `omarchy-sun`, `omarchy-locate` to the same cell. After the `dynamic-wallpaper.json` bullet (the one ending "shows what the user wants."), add:

```markdown
- That same `latitude`/`longitude` is ALSO what `omarchy-auto-appearance`
  (via `omarchy-sun`) uses to switch Apple Glass ↔ Apple Glass Light at
  sunrise/sunset. "Auto" appearance == `omarchy-auto-appearance.timer` is
  enabled; the Control Center's Affichage page and its Apparence tile flip
  that timer, so check `systemctl --user is-enabled
  omarchy-auto-appearance.timer` before wondering why a theme "changed by
  itself". `omarchy-locate` rewrites the coordinates from ip-api.com; the
  aquarium only re-reads them on its next start.
```

- [ ] **Step 3: Commit**

```bash
cd ~/Work/omarchy-mac && git add README.md agents/skills/omarchy-asahi/SKILL.md && git commit -m "Document omarchy-sun, omarchy-locate and the Auto appearance state"
```

---

### Task 8: Install, fix the location, verify live

**Files:** none in the repo. Installed copies under `~/.local/bin`, `~/.config/systemd/user`, `~/.config/omarchy/plugins/macarchy.control-center`.

- [ ] **Step 1: Run the full test suite once more**

Run: `cd ~/Work/omarchy-mac && python3 -m unittest discover -s tests -v 2>&1 | tail -3 && bash tests/test_auto_appearance.sh | tail -1 && bash tests/test_omarchy_locate.sh | tail -1`
Expected: `OK`, `all passed`, `all passed`.

- [ ] **Step 2: Install the scripts and units**

Run: `cd ~/Work/omarchy-mac && ./install.sh 2>&1 | tail -5`
Expected: no error. Because the timer unit already existed, `install.sh` must NOT enable it: `systemctl --user is-enabled omarchy-auto-appearance.timer` still prints `disabled`.

- [ ] **Step 3: Install the plugin — as its own command — then restart the shell in a second command**

Run first: `rsync -a --delete ~/Work/omarchy-mac/shell-plugins/macarchy.control-center/ ~/.config/omarchy/plugins/macarchy.control-center/` (check how previous sessions installed it: `ls -la ~/.config/omarchy/plugins/ | grep control-center` — if it is a symlink into `~/Work`, skip the rsync).
Then, in a **separate** Bash call: `omarchy restart shell`.

- [ ] **Step 4: Fix Paris → real location**

Run: `omarchy-locate`
Expected: `50.4… 4.4… Charleroi` (or wherever the machine is), then `jq '{latitude,longitude,set,mode}' ~/.config/omarchy/dynamic-wallpaper.json` shows the new coordinates with `set`/`mode` unchanged. `omarchy-sun` now prints Belgian times.

- [ ] **Step 5: Screenshot the page**

Run: `omarchy-shell macarchy.control-center page macarchy.cc.display` then, in the next call, `grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" "$S/display-page.png"` and Read the image.
Expected: the Apparence section shows the three chips (Sombre / Claire / Auto), the sentence « L'apparence automatique est désactivée. », and « Position 50.41, 4.44 [Détecter] ».

- [ ] **Step 6: Exercise Auto end to end (no synthetic clicks on this box — drive the same commands the QML runs)**

```bash
bash -c "systemctl --user enable --now omarchy-auto-appearance.timer; exec omarchy-auto-appearance"
sleep 6
systemctl --user is-enabled omarchy-auto-appearance.timer   # enabled
omarchy-auto-appearance status                                # enabled=yes want=<matches the hour>
cat ~/.local/state/omarchy/current/theme.name                 # matches want
systemctl --user list-timers omarchy-auto-appearance.timer    # next fire within 5 min
```

Then re-open the page (`omarchy-shell macarchy.control-center page macarchy.cc.display`, `grim`): the Auto chip is lit and the sentence reads « Suit le soleil — lever HH:MM, coucher HH:MM. »; the home row summary reads « Auto · Clair » or « Auto · Sombre ».

- [ ] **Step 7: Leave the machine in the state the user wants**

Auto is the point of this feature: leave the timer **enabled**. Report the final `omarchy-auto-appearance status` line in the summary.

- [ ] **Step 8: Update memory**

Add to `~/.claude/projects/-home-phmatray-Work/memory/control-center-plugin.md` (Modules paragraph): Display's Apparence section drives `omarchy-auto-appearance.timer`; "Auto" == timer enabled; location comes from `dynamic-wallpaper.json` via `omarchy-locate`. One line in `MEMORY.md` is NOT needed (the existing entry covers the plugin).
