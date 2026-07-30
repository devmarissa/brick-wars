#!/usr/bin/env python3
"""Break one policy line at a time and check that a test notices.

A policy line with no test that fails when you break it is decoration. This is how the rig
system's policy lines earn the comments above them: each entry below names a line, the wrong
version of it, and what going wrong would mean. The harness edits the file, runs the whole
suite, puts the file back, and reports whether anything went red.

    tools/mutate.py

It takes a couple of minutes — the suite runs once per mutation. Nothing is left modified: the
original is restored in a `finally`, so a Ctrl-C between runs is the one way to leave a file
edited, and `git diff` will say so.

Run it after adding a policy line, not before a release. It found three lines in the C2 driver
that no test covered at all, two of them invisible because every fixture happened to make the
buggy and the correct formula agree. `DEVIATIONS-C2.md` §D lists what it still does not cover.
"""
import pathlib, re, subprocess, sys

GAME = pathlib.Path(__file__).resolve().parent.parent

MUTATIONS = [
    ("game/core/rig/locomotion.gd",
     "var offset := float(phases[i]) if i < phases.size() else leg.phase",
     "var offset := float(phases[i]) + leg.phase if i < phases.size() else leg.phase",
     "a gait's phases ADD to the leg's own instead of replacing them"),

    ("game/core/rig/locomotion.gd",
     "drop = minf(drop, leg.drop)",
     "drop = maxf(drop, leg.drop)",
     "drop is the most permissive leg rather than the most constrained"),

    ("game/core/rig/locomotion.gd",
     "stand = -total / legs.size()",
     "stand = total / legs.size()",
     "stance height loses its sign"),

    ("game/core/rig/locomotion.gd",
     "stand = -total / legs.size()",
     "stand = -total",
     "stance height is a sum rather than a mean"),

    ("game/core/rig/locomotion.gd",
     "var height := Footing.support(standing if not standing.is_empty() else plants,",
     "var height := Footing.support(plants,",
     "body height counts swinging feet as well as planted ones"),

    ("game/core/rig/locomotion.gd",
     "var basis := Footing.level(normals, forward, body_pitch)",
     "var basis := Footing.level([], forward, body_pitch)",
     "body tilt ignores the ground entirely"),

    ("game/core/rig/locomotion.gd",
     "return clampf(-lean_into_turn * turn, -limit, limit)",
     "return -lean_into_turn * turn",
     "the lean into a turn is uncapped"),

    ("game/core/rig/leg.gd",
     "leg.reach = maxf(span - anchor.distance_to(leg.home), MIN_REACH)",
     "leg.reach = span - anchor.distance_to(leg.home)",
     "a straight leg's reach is allowed to go negative"),

    ("game/core/rig/leg.gd",
     "\tif out.length_squared() <= TINY:",
     "\tif true:",
     "the bend direction is always forward, never read off the pose"),

    ("game/core/rig/gait.gd",
     "return absf(speed) * delta / stride",
     "return delta / stride",
     "the cycle advances by time rather than by distance"),

    # `Walker`'s own copy of the order policy, one level up from `Locomotion.step`'s. Its
    # docstring makes the same claim — move the body first, pose the rig against where it ended
    # up — and this is the line that says whether anything is holding it.
    ("game/core/rig/walker.gd",
     "\tvar turned := _move(delta)\n\t_pose(delta, turned / maxf(delta, 0.0001))",
     "\t_pose(delta, 0.0)\n\t_move(delta)",
     "the walker poses the rig before moving the body"),

    ("game/core/rig/walker.gd",
     "if lowest == INF or lowest <= STILL:",
     "if true:",
     "a walker never warns that its collision stops above its feet"),

    # The line that decides whether a planted foot slides. It was `stride * 0.5` until the slide
    # was measured against a moving body, and nothing in the suite noticed.
    ("game/core/rig/gait.gd",
     "var half := stride * hold * 0.5",
     "var half := stride * 0.5",
     "a planted foot travels a full stride relative to the body, so it drags"),
]


def run_suite() -> tuple[bool, str]:
    out = subprocess.run(
        ["godot", "--headless", "--path", "game", "res://tests/test_main.tscn"],
        cwd=GAME, capture_output=True, text=True, timeout=600).stdout
    m = re.search(r"TEST_DONE cases=(\d+) passed=(\d+) failed=(\d+) checks=(\d+)", out)
    if not m:
        return False, "no TEST_DONE line — the suite did not finish"
    failed = int(m.group(3))
    reds = re.findall(r"^  FAIL  (\S+)", out, re.M)
    return failed == 0, ("green" if failed == 0
                         else "%d case(s) red: %s" % (failed, ", ".join(reds)))


def main() -> int:
    caught, missed = [], []
    for rel, before, after, what in MUTATIONS:
        p = GAME / rel
        original = p.read_text()
        if before not in original:
            print("SKIP  %-62s  (line not found in %s)" % (what, rel))
            continue
        p.write_text(original.replace(before, after, 1))
        try:
            green, detail = run_suite()
        finally:
            p.write_text(original)
        if green:
            print("MISSED  %-60s  suite stayed green" % what)
            missed.append(what)
        else:
            print("caught  %-60s  %s" % (what, detail))
            caught.append(what)

    print("\n%d caught, %d missed" % (len(caught), len(missed)))
    for what in missed:
        print("  no test fails when: " + what)
    return 0


if __name__ == "__main__":
    sys.exit(main())
