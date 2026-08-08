#!/usr/bin/env python3
"""Generate common AER event-arrival traces shared across team designs.

Format (see progress.md #9): CSV lines of `arrival_cycle,source_index`.
source_index in [0, N). Consumers map source_index to their own native
interface (row*4+col for us, direct index for ready-valid designs).
"""
import argparse
import csv
import random

CYCLES = 3000
LOAD_PCT = {"sparse": 5, "normal": 15, "near_saturation": 40, "overload": 80}


def uniform(n, pct, seed):
    rng = random.Random(seed)
    events = []
    for cyc in range(CYCLES):
        for src in range(n):
            if rng.randrange(100) < pct:
                events.append((cyc, src))
    return events


def simultaneous_burst(n, pct, seed):
    rng = random.Random(seed)
    period = max(1, 100 // max(pct, 1))
    events = []
    for cyc in range(0, CYCLES, period):
        for src in range(n):
            events.append((cyc, src))
    return events


def hotspot(n, pct, seed):
    rng = random.Random(seed)
    hot = n // 2
    events = []
    for cyc in range(CYCLES):
        if rng.randrange(100) < pct:
            events.append((cyc, hot))
        for src in range(n):
            if src != hot and rng.randrange(100) < LOAD_PCT["sparse"]:
                events.append((cyc, src))
    return events


def moving_hotspot(n, pct, seed):
    rng = random.Random(seed)
    dwell = 200
    events = []
    for cyc in range(CYCLES):
        hot = (cyc // dwell) % n
        if rng.randrange(100) < pct:
            events.append((cyc, hot))
        for src in range(n):
            if src != hot and rng.randrange(100) < LOAD_PCT["sparse"]:
                events.append((cyc, src))
    return events


PATTERNS = {
    "uniform": uniform,
    "simultaneous_burst": simultaneous_burst,
    "hotspot": hotspot,
    "moving_hotspot": moving_hotspot,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=16, help="number of sources")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--outdir", default="common_traces")
    args = ap.parse_args()

    import os
    os.makedirs(args.outdir, exist_ok=True)

    for load_name, pct in LOAD_PCT.items():
        for pattern_name, fn in PATTERNS.items():
            events = sorted(fn(args.n, pct, args.seed))
            path = f"{args.outdir}/{pattern_name}_{load_name}_N{args.n}.csv"
            with open(path, "w", newline="") as f:
                w = csv.writer(f)
                w.writerow(["arrival_cycle", "source_index"])
                w.writerows(events)
            print(f"{path}: {len(events)} events")


if __name__ == "__main__":
    main()
