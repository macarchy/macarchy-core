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
            # Isolate from the real desktop session's XDG_CONFIG_HOME so this
            # exercises the $HOME/.config fallback, not whatever config dir
            # happens to be set in the environment running the tests.
            env.pop("XDG_CONFIG_HOME", None)
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
