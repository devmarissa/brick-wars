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

**Commit before you run it.** The original is restored in a `finally`, so an ordinary Ctrl-C is
safe, but a `kill` at the wrong moment leaves a file edited — and if that file is new and
untracked, `git checkout` cannot put it back and the mutation IS the only version. That happened
once, at C4, to a file that had existed for twenty minutes. Two tracked files went with it and
were restored in one command; the untracked one had to be repaired by hand.

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

    # The guard that refuses a leg whose bones do not meet. It went in after two fixtures spent a
    # fortnight with a 0.2 m gap at the knee and nothing said a word.
    ("game/core/rig/leg.gd",
     "\t\tif gap <= MAX_CHAIN_GAP:",
     "\t\tif true:",
     "a leg with a gap in its chain is never complained about"),

    # The order inside `step` itself, which the pose-versus-plant assertion should now pin.
    ("game/core/rig/locomotion.gd",
     "var into := Transform3D(basis, Vector3(at.origin.x, height, at.origin.z)).affine_inverse()",
     "var into := at.affine_inverse()",
     "the rig is solved against the body that came in, not the one going out"),

    # DEVIATIONS §D2: the hang lag is exponential so a fetlock does not lag further on a slow
    # machine. A plain lerp is the wrong shape and is frame-rate dependent.
    ("game/core/rig/locomotion.gd",
     "var mixed := leg.hang.lerp(down, 1.0 - exp(-FOLLOW_RATE * delta))",
     "var mixed := leg.hang.lerp(down, FOLLOW_RATE * delta)",
     "the hang lag is a plain lerp rather than an exponential follow"),

    # The line that makes a collapse take time rather than happen between two frames.
    ("game/core/earth/settle.gd",
     "var move := mini(excess / 2, MAX_SHED_CM)",
     "var move := excess / 2",
     "a slump resolves instantly instead of settling over frames"),

    # The line that decides whether a planted foot slides. It was `stride * 0.5` until the slide
    # was measured against a moving body, and nothing in the suite noticed.
    ("game/core/rig/gait.gd",
     "var half := stride * hold * 0.5",
     "var half := stride * 0.5",
     "a planted foot travels a full stride relative to the body, so it drags"),

    # --- C4: the verb vocabulary and the first live verb ---

    ("game/core/verbs/verb_set.gd",
     "\t\tif not VOCABULARY.has(name):",
     "        if false:",
     "the vocabulary stops being closed and a pack could invent a verb"),

    ("game/core/verbs/verbs.gd",
     "	if not set.is_live(verb):",
     "	if false:",
     "a declared-but-unbuilt verb dispatches silently instead of refusing"),

    ("game/core/verbs/dig.gd",
     "	field.deposit(spoil, moved)",
     "	field.deposit(spoil, depth_cm)",
     "spoil is what was ASKED for rather than what came out — creates earth against bedrock"),

    ("game/core/verbs/dig.gd",
     "	if spoil == cell:",
     "	if false:",
     "spoil may be thrown into the hole it was cut from, so digging digs nothing"),

    ("game/core/verbs/dig.gd",
     "	if depth_cm > MAX_BITE_CM:",
     "	if false:",
     "a dig may take any depth in one bite, so the ground never slumps between them"),

    ("game/core/verbs/dig.gd",
     "	if absi(away.x) > MAX_THROW_CELLS or absi(away.y) > MAX_THROW_CELLS:",
     "	if false:",
     "spoil may be thrown any distance, so a shovel has infinite reach"),


    # --- C4: firing, and the ballistics under it ---

    ("game/core/verbs/fire.gd",
     "	if rounds <= 0:",
     "	if false:",
     "a weapon never runs out, so `capacity` is a decoration"),

    ("game/core/verbs/fire.gd",
     "	if now < ready_at:",
     "	if false:",
     "there is no time between shots, so a bolt rifle fires like a machine gun"),

    ("game/core/verbs/fire.gd",
     '"state": { "rounds": rounds - 1, "ready_at": now + float(stats["cycle"]) },',
     '"state": { "rounds": rounds, "ready_at": now + float(stats["cycle"]) },',
     "firing does not consume the round it fired"),

    ("game/core/combat/ballistics.gd",
     "	return 0.5 * gravity * t * t",
     "	return gravity * t * t",
     "a projectile falls at twice the rate it should"),

    ("game/core/combat/ballistics.gd",
     "	return scatter(aim, spread, rng) * speed",
     "	return aim.normalized() * speed",
     "spread is computed and then ignored, so every weapon is perfectly accurate"),

    ("game/core/combat/ballistics.gd",
     "	var angle := spread * sqrt(rng.randf())",
     "	var angle := spread * rng.randf()",
     "shots bunch at the centre of the spread disc instead of spreading evenly across it"),

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
