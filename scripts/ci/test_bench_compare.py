#!/usr/bin/env python3
"""Tests for bench_compare.py (#1132). Run: python3 scripts/ci/test_bench_compare.py"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(__file__))
import bench_compare as bc  # noqa: E402


def log(build=(0.45, 0.60, 1.2), raster=(6.0, 9.0, 14.0), total=(11.0, 16.0, 30.0),
        stutters=3):
    lines = [
        "BENCH mode=scroll rows=50000 cols=12 frames=300",
        f"BENCH build   p50={build[0]:.2f}  p90={build[1]:.2f}  p99={build[2]:.2f}  max=2.00  over8.33ms=0/300",
        f"BENCH raster  p50={raster[0]:.2f}  p90={raster[1]:.2f}  p99={raster[2]:.2f}  max=20.00  over8.33ms=9/300",
        f"BENCH total   p50={total[0]:.2f}  p90={total[1]:.2f}  p99={total[2]:.2f}  max=40.00  over8.33ms=290/300",
    ]
    if stutters is not None:
        lines.append(
            "BENCH frames: 300 in 5.0 s = 60 fps, gap p50=16.67 p99=33.00 max=40.0 ms, "
            f"stutters(>12.5ms)=290 stutters(>25ms)={stutters}")
    return "\n".join(lines)


def runs(*texts):
    return [bc.parse(t) for t in texts]


class ParseTest(unittest.TestCase):
    def test_reads_build_raster_total_and_60hz_stutters(self):
        m = bc.parse(log())
        self.assertEqual(m["build p50"], 0.45)
        self.assertEqual(m["build p90"], 0.60)
        self.assertEqual(m["raster p50"], 6.0)
        self.assertEqual(m["total p99"], 30.0)
        self.assertEqual(m["stutters"], 3)

    def test_120hz_stutter_count_is_not_used(self):
        self.assertNotIn("stutters", bc.parse(log(stutters=None)))

    def test_no_bench_lines_gives_nothing(self):
        self.assertEqual(bc.parse("flutter crashed"), {})


class CompareTest(unittest.TestCase):
    def verdict(self, base, head, **kw):
        return bc.compare(runs(*base), runs(*head), **kw)[1]

    def test_slower_build_in_every_pair_is_a_regression(self):
        base = [log(build=(0.45, 0.60, 1.0))] * 3
        head = [log(build=(0.80, 1.00, 1.5))] * 3
        self.assertTrue(self.verdict(base, head))

    def test_one_slow_pair_out_of_three_is_noise(self):
        base = [log(build=(0.45, 0.60, 1.0))] * 3
        head = [log(build=(0.80, 1.00, 1.5)),
                log(build=(0.80, 1.00, 1.5)),
                log(build=(0.40, 0.55, 1.0))]
        self.assertFalse(self.verdict(base, head))

    def test_raster_and_total_never_flag(self):
        # The #1131 case: total p50 and p99 moved, build did not.
        base = [log(total=(15.75, 20.0, 30.0))] * 3
        head = [log(total=(16.78, 22.0, 35.4))] * 3
        rows, regressed = bc.compare(runs(*base), runs(*head))
        self.assertFalse(regressed)
        total = [r for r in rows if r[0] == "total p50"][0]
        self.assertFalse(total[4])

    def test_small_absolute_change_is_not_a_regression(self):
        # +20% but only +0.09 ms.
        base = [log(build=(0.45, 0.60, 1.0))] * 3
        head = [log(build=(0.54, 0.70, 1.0))] * 3
        self.assertFalse(self.verdict(base, head))

    def test_under_threshold_is_not_a_regression(self):
        base = [log(build=(4.0, 5.0, 6.0))] * 3
        head = [log(build=(4.3, 5.4, 6.0))] * 3   # +7.5%, +8%
        self.assertFalse(self.verdict(base, head))

    def test_medians_ignore_one_outlier_run(self):
        base = [log(build=(0.45, 0.60, 1.0)), log(build=(5.0, 6.0, 9.0)),
                log(build=(0.46, 0.61, 1.0))]
        head = [log(build=(0.47, 0.62, 1.0))] * 3
        rows, _ = bc.compare(runs(*base), runs(*head))
        b50 = [r for r in rows if r[0] == "build p50"][0]
        self.assertEqual(b50[1], 0.46)

    def test_a_missing_side_gives_no_rows(self):
        rows, regressed = bc.compare(runs(log()), [{}])
        self.assertEqual(rows, [])
        self.assertFalse(regressed)


class ReportTest(unittest.TestCase):
    def test_first_line_is_the_verdict_and_info_rows_are_marked(self):
        rows, regressed = bc.compare(runs(log()), runs(log()))
        text = bc.report(rows, regressed, 1, 10, 0.2)
        self.assertTrue(text.startswith("REGRESSION=0\n"))
        self.assertIn("| build p50 |", text)
        self.assertIn("| raster p50 (info) |", text)
        self.assertIn("| stutters (info) |", text)

    def test_main_reads_log_files(self):
        with tempfile.TemporaryDirectory() as d:
            paths = {}
            for name, text in {"b": log(), "h": log(build=(0.9, 1.2, 2.0))}.items():
                paths[name] = os.path.join(d, name + ".log")
                with open(paths[name], "w", encoding="utf-8") as f:
                    f.write(text)
            out = io.StringIO()
            with redirect_stdout(out):
                bc.main(["--base", paths["b"], "--head", paths["h"]])
            self.assertTrue(out.getvalue().startswith("REGRESSION=1"))

    def test_missing_logs_report_no_output(self):
        out = io.StringIO()
        with redirect_stdout(out):
            bc.main(["--base", "/nonexistent/a.log", "--head", "/nonexistent/b.log"])
        self.assertIn("no comparable output", out.getvalue())


if __name__ == "__main__":
    unittest.main()
