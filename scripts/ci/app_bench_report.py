#!/usr/bin/env python3
"""Markdown report of app_perf_bench scenarios against per-scenario limits.

usage: app_bench_report.py APP_BENCH.log

Reads the `BENCH <scenario> frames=.. build p50/p90/max=.. raster ..` lines and
checks each scenario of LIMITS: build p90 against its limit (ms), and for
multi_tab_run the number of query panes rebuilt by one run. The first output
line is `OVER=<n>`, the number of scenarios over a limit or missing.
Informational: always exits 0.
"""
import re
import sys

# build p90 limits in ms. A frame budget at 60 Hz is 16.7 ms; opening a
# diagram or laying it out again is one long frame by design.
LIMITS = {
    "charts_5000": 16.7,
    "groupings_5000": 16.7,
    "multi_tab_run": 16.7,
    "erd_open_200": 50.0,
    "erd_hover": 8.3,
    "erd_drag": 16.7,
    "erd_auto_layout": 50.0,
}

# A run in one tab should rebuild that tab's pane only.
MAX_PANES_REBUILT = 1

_LINE = re.compile(
    r"BENCH (\S+)\s+frames=\s*(\d+)\s+"
    r"build p50/p90/max=([\d.]+)/([\d.]+)/([\d.]+)\s+"
    r"raster p50/p90/max=([\d.]+)/([\d.]+)/([\d.]+).*?stutters=(\d+)")
_PANES = re.compile(r"BENCH multi_tab_run panes rebuilt=(\d+)")


def parse(text):
    scenarios = {}
    for m in _LINE.finditer(text):
        scenarios[m[1]] = {
            "frames": int(m[2]),
            "build_p50": float(m[3]),
            "build_p90": float(m[4]),
            "build_max": float(m[5]),
            "raster_p50": float(m[6]),
            "stutters": int(m[9]),
        }
    panes = _PANES.search(text)
    return scenarios, (int(panes[1]) if panes else None)


def report(text):
    scenarios, panes = parse(text)
    over = 0
    lines = [
        "### App benchmark: ERD, charts and groupings, multi-tab SQL",
        "",
        "| scenario | frames | build p50 | build p90 (limit) | build max | raster p50 | stutters | |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for name, limit in LIMITS.items():
        s = scenarios.get(name)
        if s is None:
            over += 1
            lines.append(f"| {name} | — | — | — ({limit:g}) | — | — | — | ⚠️ missing |")
            continue
        bad = s["build_p90"] > limit
        over += bad
        lines.append(
            f"| {name} | {s['frames']} | {s['build_p50']:.1f} | "
            f"{s['build_p90']:.1f} ({limit:g}) | {s['build_max']:.1f} | "
            f"{s['raster_p50']:.1f} | {s['stutters']} | {'⚠️' if bad else 'ok'} |")
    if panes is not None:
        bad = panes > MAX_PANES_REBUILT
        over += bad
        lines += ["", f"Query panes rebuilt by one run in one of five tabs: "
                      f"**{panes}** (limit {MAX_PANES_REBUILT}){' ⚠️' if bad else ''}."]
    lines += ["", "Times in ms, profile build under xvfb with software "
                  "rendering. Informational, never blocks a merge."]
    return over, "\n".join(lines)


def main(argv):
    try:
        with open(argv[1], encoding="utf-8", errors="replace") as f:
            text = f.read()
    except (IndexError, OSError):
        text = ""
    over, body = report(text)
    print(f"OVER={over}")
    print(body)


if __name__ == "__main__":
    main(sys.argv)
