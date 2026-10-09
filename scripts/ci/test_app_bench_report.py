#!/usr/bin/env python3
"""Tests for app_bench_report.py (#1173). Run: python3 scripts/ci/test_app_bench_report.py"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(__file__))
import app_bench_report as abr  # noqa: E402


def line(name, build=(1.0, 2.0, 5.0), raster=(4.0, 6.0, 9.0), frames=120, stutters=2):
    return (f"BENCH {name.ljust(20)} frames={str(frames).rjust(4)} "
            f"build p50/p90/max={build[0]:.1f}/{build[1]:.1f}/{build[2]:.1f} "
            f"raster p50/p90/max={raster[0]:.1f}/{raster[1]:.1f}/{raster[2]:.1f} "
            f"over8.3 build=0 raster=3 stutters={stutters} gap p50=16.67ms")


def all_ok():
    return "\n".join(line(n) for n in abr.LIMITS) + "\nBENCH multi_tab_run panes rebuilt=1\n"


class ParseTest(unittest.TestCase):
    def test_reads_the_app_bench_line(self):
        scenarios, panes = abr.parse(line("erd_hover", build=(0.8, 3.2, 7.5)))
        s = scenarios["erd_hover"]
        self.assertEqual(s["frames"], 120)
        self.assertEqual(s["build_p90"], 3.2)
        self.assertEqual(s["build_max"], 7.5)
        self.assertEqual(s["raster_p50"], 4.0)
        self.assertEqual(s["stutters"], 2)
        self.assertIsNone(panes)

    def test_reads_the_pane_count(self):
        _, panes = abr.parse("BENCH multi_tab_run panes rebuilt=5")
        self.assertEqual(panes, 5)


class ReportTest(unittest.TestCase):
    def test_everything_within_limits(self):
        over, body = abr.report(all_ok())
        self.assertEqual(over, 0)
        self.assertNotIn("⚠️", body)
        for name in abr.LIMITS:
            self.assertIn(f"| {name} |", body)

    def test_a_slow_scenario_is_flagged(self):
        text = all_ok().replace(line("erd_hover"), line("erd_hover", build=(2.0, 12.0, 20.0)))
        over, body = abr.report(text)
        self.assertEqual(over, 1)
        self.assertIn("12.0 (8.3)", body)

    def test_a_missing_scenario_is_flagged(self):
        text = all_ok().replace(line("erd_drag") + "\n", "")
        over, body = abr.report(text)
        self.assertEqual(over, 1)
        self.assertIn("| erd_drag | — |", body)

    def test_rebuilding_every_pane_is_flagged(self):
        text = all_ok().replace("panes rebuilt=1", "panes rebuilt=5")
        over, body = abr.report(text)
        self.assertEqual(over, 1)
        self.assertIn("**5**", body)

    def test_main_prints_the_count_first(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "app.log")
            with open(p, "w", encoding="utf-8") as f:
                f.write(all_ok())
            out = io.StringIO()
            with redirect_stdout(out):
                abr.main(["app_bench_report.py", p])
            self.assertTrue(out.getvalue().startswith("OVER=0\n"))

    def test_no_log_reports_every_scenario_missing(self):
        out = io.StringIO()
        with redirect_stdout(out):
            abr.main(["app_bench_report.py", "/nonexistent.log"])
        self.assertTrue(out.getvalue().startswith(f"OVER={len(abr.LIMITS)}\n"))


if __name__ == "__main__":
    unittest.main()
