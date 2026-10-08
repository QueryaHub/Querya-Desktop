#!/usr/bin/env python3
"""Compare two grid_perf_bench logs and print a Markdown report.

usage: bench_compare.py BASE.log HEAD.log [threshold_percent]

Reads the `BENCH total  p50=.. p90=.. p99=..` line of each log. Always exits 0:
the report is informational. The first output line is `REGRESSION=1` or
`REGRESSION=0` so a workflow can decide whether to comment.
"""
import re
import sys


def parse(path):
    metrics = {}
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return metrics
    m = re.search(r"BENCH total\s+p50=([\d.]+)\s+p90=([\d.]+)\s+p99=([\d.]+)", text)
    if m:
        metrics = {"p50": float(m[1]), "p90": float(m[2]), "p99": float(m[3])}
    s = re.search(r"stutters\(>12\.5ms\)=(\d+)", text)
    if s:
        metrics["stutters"] = float(s[1])
    return metrics


def main():
    base, head = parse(sys.argv[1]), parse(sys.argv[2])
    threshold = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
    if not base or not head:
        print("REGRESSION=0")
        print("Benchmark produced no comparable output (base or head log has no `BENCH total` line).")
        return
    rows, regressed = [], False
    for key in ("p50", "p90", "p99", "stutters"):
        if key not in base or key not in head:
            continue
        b, h = base[key], head[key]
        delta = (h - b) / b * 100 if b else (0.0 if h == 0 else 100.0)
        # Tiny absolute differences are noise on a shared runner.
        worse = delta > threshold and (h - b) > (0.3 if key != "stutters" else 2)
        regressed = regressed or worse
        unit = "" if key == "stutters" else " ms"
        rows.append(f"| {key} | {b:.2f}{unit} | {h:.2f}{unit} | {delta:+.1f}% {'⚠️' if worse else ''} |")
    print(f"REGRESSION={1 if regressed else 0}")
    print("### Grid scroll benchmark")
    print()
    print("| metric | base | PR | change |")
    print("|---|---|---|---|")
    print("\n".join(rows))
    print()
    print(f"Informational only (threshold {threshold:g}%). Shared CI runners are noisy; re-run before trusting a single result.")


main()
