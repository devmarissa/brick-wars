# The deliberately broken packs

This folder exists to be pointed at. It is the standing proof of the second half of C1's
done-condition — *a deliberately broken pack fails with a message that says exactly why,
without taking anything else down with it* — and the only honest way to demonstrate that is
against the real game rather than a test harness:

    godot --headless --path game -- --pack-root res://tests/fixtures/broken

Two things should happen, and both of them matter. Both packs are disabled and say why,
naming the file, the line, the offending value and the rule. And the boot log underneath is
*unchanged*: two packs, seven assets, the sandbox standing up exactly as it does without the
flag. `tests/cases/case_cli.gd` asserts both halves so they cannot quietly stop being true.

Both manifests are deliberately correct. Manifest-level refusal is already covered from
every angle by `case_pack_order.gd`; what a manifest test cannot cover is a pack that gets
all the way to having its assets read and *then* turns out to be wrong, which is the shape
almost every real workshop upload takes.

**`brokenpack`** breaks four rules in one part, on purpose, because a validator that reports
the first problem and stops makes an author fix things one slow run at a time:

- `size` is `[10, 0.5, 10]`, and a module is not divisible
- `rotation` is 22°, and a block turns in steps of 15°
- `material` is `stainless_steel`, which is not a material — the closest real one is `steel`
- `colour` is `hot_pink`, which is not in the palette

**`orphanpack`** breaks something else: it `extends` `core:crate_of_holding`, which does not
exist. It is a separate pack rather than a second file in the first one because a missing
base is caught during resolution and the four rules above are caught during validation —
one pass earlier. Put them together and the pack is disabled before the validator ever sees
it, so the four-at-once report never prints and the fixture quietly stops proving the thing
it was written to prove.

A missing base is also the failure that most looks like a typo in *your* file when it is
actually a typo in somebody else's, which is why its message names both ends.
