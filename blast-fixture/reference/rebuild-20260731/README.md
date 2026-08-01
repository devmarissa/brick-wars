# Rebuild baseline — captured 31 Jul 2026, C5

This is **not** a replacement for `../macos-20260729/`. That one is the record of how the *old
build* felt, it is the only evidence of it that exists, and it should outlive every rebuild of
this fixture. Nothing should ever overwrite it.

This one is the rebuild's own numbers, captured once the blast was ported, and it is what
`tools/check.sh` compares against from now on. That keeps the fixture doing the job it was built
for — catching the day somebody changes `BRICK_IMPULSE` and does not notice — rather than
re-litigating a shift that already happened on purpose.

## What moved between the two, and why

**The blast curve reproduces.** Shake, knock and launch speeds are within a few percent, and
`empty_standard_shell` — the scenario with nothing in it but the blast — matches 17/17. That is the
falloff, the impulse formula, the vertical split and the shatter threshold, which is what
`BUILD-ORDER` §1e says the fixture exists to protect.

**The aftermath moved, because bricks now have mass.** The old build set every brick to
`maxf(0.5, volume * 0.3)`, which for a fixture brick is 0.075 and therefore the 0.5 kg floor —
*every brick in the old capture weighs half a kilo.* The same brick here is sandbag at C1's declared
1500 kg/m³, so it weighs 375 kg. Launch speed is unaffected (the blast sets velocity directly);
everything after the first collision is not. Settle is 11–19% faster and scatter up to 30% wider.

**The two `world` scenarios are not comparable at all.** They fired into the old build's live map,
and their 11 and 13 launched bricks with debris reaching 18 m and 43 m were pieces of *that map*
near the crater. It no longer exists. See `DEVIATIONS-C5.md` A2.

## Re-capturing

    godot --headless --path game res://../blast-fixture/rebuild_fixture.tscn
    python3 blast-fixture/compare_baselines.py \
        blast-fixture/reference/rebuild-20260731/blast_baseline.json \
        blast-fixture/out/blast_baseline.json

Do not re-capture to make a red gate green. A red gate means the blast changed; the only honest
reasons to move this file are a deliberate retune or a physics-engine change, and either belongs in
a commit message that says so.
