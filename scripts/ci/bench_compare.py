#!/usr/bin/env python3
"""Compare grid_perf_bench logs of the base branch and of a PR.

usage: bench_compare.py --base B1.log [B2.log ...] --head H1.log [H2.log ...]
                        [--threshold PERCENT] [--min-ms MS]

Each log holds the `BENCH build|raster|total  p50=.. p90=.. p99=..` lines of one
run. Runs are paired in order (base 1 with PR 1, ...), as the workflow runs
them interleaved, so a runner spike hits both sides.

Only the Dart side decides: `build` p50 and p90. A metric regresses when the
median of the PR runs is worse than the median of the base runs by more than
--threshold percent (default 10) and --min-ms (default 0.2), and the PR is
slower in every pair. raster and total (software rendering, vsync wait) and
the stutter count stay in the table as information.

Always exits 0: the report is informational. The first output line is
`REGRESSION=1` or `REGRESSION=0` so a workflow can decide whether to comment.
"""
import argparse
import re
import statistics

_ROW = re.compile(
    r"BENCH (build|raster|total)\s+p50=([\d.]+)\s+p90=([\d.]+)\s+p99=([\d.]+)")
_STUTTERS = re.compile(r"stutters\(>25ms\)=(\d+)")

# (metric, flagged): flagged metrics can raise a regression.
METRICS = [
    ("build p50", True),
    ("build p90", True),
    ("build p99", False),
    ("raster p50", False),
    ("total p50", False),
    ("total p99", False),
    ("stutters", False),
]


FLAGGED = {key for key, flagged in METRICS if flagged}


def parse(text):
    """Metrics of one run, e.g. {'build p50': 0.45, 'stutters': 3.0}."""
    metrics = {}
    for kind, p50, p90, p99 in _ROW.findall(text):
        metrics[f"{kind} p50"] = float(p50)
        metrics[f"{kind} p90"] = float(p90)
        metrics[f"{kind} p99"] = float(p99)
    s = _STUTTERS.search(text)
    if s:
        metrics["stutters"] = float(s[1])
    return metrics


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return parse(f.read())
    except OSError:
        return {}


def compare(base_runs, head_runs, threshold=10.0, min_ms=0.2):
    """Rows (metric, base median, PR median, change %, regressed) and the verdict.

    Runs without output are dropped; pairs are kept in order up to the shorter
    side.
    """
    base_runs = [r for r in base_runs if r]
    head_runs = [r for r in head_runs if r]
    if not base_runs or not head_runs:
        return [], False
    pairs = list(zip(base_runs, head_runs))
    rows, regressed = [], False
    for key, flagged in METRICS:
        b_vals = [r[key] for r in base_runs if key in r]
        h_vals = [r[key] for r in head_runs if key in r]
        if not b_vals or not h_vals:
            continue
        b, h = statistics.median(b_vals), statistics.median(h_vals)
        change = (h - b) / b * 100 if b else (0.0 if h == 0 else 100.0)
        worse = False
        if flagged:
            slower_everywhere = all(
                hr[key] > br[key] for br, hr in pairs if key in br and key in hr)
            worse = change > threshold and (h - b) > min_ms and slower_everywhere
        regressed = regressed or worse
        rows.append((key, b, h, change, worse))
    return rows, regressed


def report(rows, regressed, runs, threshold, min_ms):
    lines = [f"REGRESSION={1 if regressed else 0}"]
    if not rows:
        lines.append("Benchmark produced no comparable output "
                     "(no `BENCH build` line in the base or the PR logs).")
        return "\n".join(lines)
    lines += [
        "### Grid scroll benchmark",
        "",
        f"Median of {runs} interleaved runs per side.",
        "",
        "| metric | base | PR | change |",
        "|---|---|---|---|",
    ]
    for key, b, h, change, worse in rows:
        unit = "" if key == "stutters" else " ms"
        mark = " ⚠️" if worse else ""
        info = "" if key in FLAGGED else " (info)"
        lines.append(f"| {key}{info} | {b:.2f}{unit} | {h:.2f}{unit} | {change:+.1f}%{mark} |")
    lines += [
        "",
        f"Only `build` p50 / p90 can flag a regression: worse by more than "
        f"{threshold:g}% and {min_ms:g} ms, and slower in every pair. Raster "
        f"is software rendering on a shared runner; stutters count gaps over "
        f"25 ms (a missed vsync at 60 Hz). Informational, never blocks a merge.",
    ]
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", nargs="+", required=True)
    ap.add_argument("--head", nargs="+", required=True)
    ap.add_argument("--threshold", type=float, default=10.0)
    ap.add_argument("--min-ms", type=float, default=0.2)
    args = ap.parse_args(argv)
    base = [read(p) for p in args.base]
    head = [read(p) for p in args.head]
    rows, regressed = compare(base, head, args.threshold, args.min_ms)
    runs = min(len([r for r in base if r]), len([r for r in head if r]))
    print(report(rows, regressed, runs, args.threshold, args.min_ms))


if __name__ == "__main__":
    main()
