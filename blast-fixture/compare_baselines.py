#!/usr/bin/env python3
"""BRICK WARS — blast baseline comparison.

    ./compare_baselines.py baseline.json candidate.json [--strict]

Answers one question: does the new build's blast still feel like the old one's?

Exit code 0 means yes (within tolerance), 1 means a metric drifted, 2 means the two
files aren't comparable at all. That makes it usable as a CI gate directly
(CHECKLIST §8, "blast fixture wired into CI as a standing regression test").

Tolerances are per-metric, not global, because the metrics don't all mean the same
thing. Launch speed drifting 5% is a tuning change you'd want flagged; the count of
bricks awake at the peak is a noisy integer and only matters if it moves a lot.

The six `pad` scenarios are deterministic to the last digit on a given machine, so
they get tight tolerances. The two `world` scenarios run in the live map, where
solver ordering across many islands is not reproducible run to run; they get loose
ones and exist to catch "the crater stopped happening", not to police decimals.
"""

import argparse
import json
import sys

# metric path -> (pad tolerance, world tolerance), as a fraction; None = ignore
TOLERANCES = {
    "impulse.peak_speed":              (0.02, 0.15),
    "impulse.mean_launch_speed":       (0.02, 0.20),
    "impulse.max_launch_speed":        (0.02, 0.20),
    "impulse.bricks_launched_first_tick": (0.02, 0.25),
    "wake.peak_height":                (0.05, 0.20),
    # In the live world this is genuinely noise — measured between 16 and 49 across runs of
    # an unchanged build, which no percentage can straddle usefully. Gated on the pad, where
    # it is exact, and ignored in the world, where "did it still dig the hole" is carried by
    # earth.height_cells_removed instead.
    "wake.peak_awake":                 (0.10, None),
    "felt.shake_peak":                 (0.02, 0.10),
    "felt.shake_seconds":              (0.10, 0.25),
    "felt.player_knock_peak":          (0.02, 0.10),
    "felt.observer_drift":             (0.05, 0.20),
    "earth.height_cells_removed":      (0.00, 0.00),   # integer, must match exactly
    "earth.debris_spawned":            (0.30, 0.50),
    "settle.seconds":                  (0.10, 0.35),
    "scatter.moved_over_half_metre":   (0.05, 0.30),
    "scatter.mean_displacement":       (0.05, 0.25),
    "scatter.max_displacement":        (0.10, 0.30),
    "scatter.left_the_world":          (0.00, 0.00),
}

# Absolute floors, so a metric that is legitimately near zero doesn't fail on a
# percentage. Below this delta, we don't care.
FLOORS = {
    "felt.shake_peak": 0.01,
    "felt.shake_seconds": 0.05,
    "felt.player_knock_peak": 0.2,
    "impulse.peak_speed": 0.2,
    "impulse.mean_launch_speed": 0.2,
    "impulse.max_launch_speed": 0.2,
    "wake.peak_height": 0.2,
    "felt.observer_drift": 0.05,
    "settle.seconds": 0.1,
    "scatter.mean_displacement": 0.1,
    "scatter.max_displacement": 0.2,
}


def dig(d, path):
    for part in path.split("."):
        if not isinstance(d, dict) or part not in d:
            return None
        d = d[part]
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline")
    ap.add_argument("candidate")
    ap.add_argument("--strict", action="store_true",
                    help="hold world scenarios to pad tolerances too")
    ap.add_argument("--quiet", action="store_true",
                    help="only print failures")
    args = ap.parse_args()

    try:
        base = json.load(open(args.baseline))
        cand = json.load(open(args.candidate))
    except Exception as e:
        print(f"cannot read baselines: {e}", file=sys.stderr)
        return 2

    if base.get("fixture_version") != cand.get("fixture_version"):
        print("fixture_version differs — recapture the baseline before comparing",
              file=sys.stderr)
        return 2

    # A run in which anything was fired measured the interference as well as the blast.
    # Refuse it outright rather than reporting drift that isn't drift.
    for label, doc in (("baseline", base), ("candidate", cand)):
        if doc.get("clean") is False:
            n = doc.get("stray_projectiles", "?")
            print(f"the {label} is a contaminated run — {n} projectile(s) were fired while "
                  f"it was measuring. Re-run it without touching the window.", file=sys.stderr)
            return 2

    if base.get("platform") != cand.get("platform"):
        print(f"WARNING: baseline is {base.get('platform')}, candidate is "
              f"{cand.get('platform')}. Jolt is not bit-identical across platforms; "
              f"these numbers are not strictly comparable.\n", file=sys.stderr)

    by_name = {s["name"]: s for s in cand.get("scenarios", [])}
    failures = []
    checked = 0

    for b in base.get("scenarios", []):
        name = b["name"]
        c = by_name.get(name)
        if c is None:
            failures.append((name, "-", "scenario missing from candidate", "", ""))
            continue

        world = b.get("isolation", "pad") == "world" and not args.strict
        lines = []
        for path, (tol_pad, tol_world) in TOLERANCES.items():
            bv, cv = dig(b, path), dig(c, path)
            if bv is None or cv is None:
                continue
            tol = tol_world if world else tol_pad
            if tol is None:      # deliberately not gated in this isolation mode
                continue
            checked += 1
            delta = abs(cv - bv)
            if delta <= FLOORS.get(path, 0.0):
                ok = True
            elif bv == 0:
                ok = delta == 0
            else:
                ok = delta / abs(bv) <= tol + 1e-9
            pct = (delta / abs(bv) * 100) if bv else float("inf") if delta else 0.0
            if not ok:
                failures.append((name, path, f"{bv} → {cv}", f"{pct:+.1f}%",
                                 f"tol {tol*100:.0f}%"))
            lines.append((ok, path, bv, cv, pct))

        if not args.quiet:
            bad = sum(1 for ok, *_ in lines if not ok)
            tag = "OK  " if bad == 0 else f"FAIL"
            print(f"{tag}  {name:<24} {b.get('isolation','pad'):<6} "
                  f"{len(lines) - bad}/{len(lines)} metrics within tolerance")

    extra = set(by_name) - {s["name"] for s in base.get("scenarios", [])}
    for name in sorted(extra):
        print(f"note  {name:<24} new scenario, no baseline to compare against")

    print()
    if failures:
        print(f"{len(failures)} metric(s) outside tolerance ({checked} checked):\n")
        for name, path, change, pct, tol in failures:
            print(f"  {name:<24} {path:<34} {change:<22} {pct:>8}  {tol}")
        print("\nThe blast does not feel the same. Either fix it, or — if the change was "
              "deliberate and better — recapture the baseline and say so in the commit.")
        return 1

    print(f"All {checked} metrics within tolerance. The blast still feels like the blast.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
