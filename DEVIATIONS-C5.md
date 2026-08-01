# Where the C5 build and the specs disagree

Running list, opened at the start of C5. `DEVIATIONS-C1.md` through `DEVIATIONS-C4.md` are the
closed ones; read the relevant one before assuming a mismatch is a bug.

**A** — forks worth a decision.
**B** — calls made where the specs said nothing, or said a range.
**C** — structural notes.
**D** — policy lines with no test that fails when you break them.

---

## A · The blast fixture, and what it can and cannot still prove

### A1. The blast curve reproduces. The aftermath does not, and the reason is that bricks now have mass.

`BUILD-ORDER` §1e calls the fixture *"the cheapest insurance in the project"* and it earned that in
one afternoon — it found two real omissions in the port before it found anything it could not
answer. But the comparison also turned up a divergence that is not a bug, and the distinction
matters more than the numbers.

**What reproduces, inside tolerance:** camera shake, player knock, and launch speeds. That is the
blast *curve* — the falloff, the impulse formula, the vertical split, the shatter threshold — which
is exactly what §1e says the fixture exists to protect and what MATERIAL-SPEC §7 says materials may
never touch. `empty_standard_shell` is 17/17, and it is the scenario with nothing in it but the
blast, which is the cleanest possible statement that the curve itself is right.

**What diverges:** what happens *after* the first tick. Settle time is 11–19% faster, scatter runs
up to 30% wider, and peak speeds drift a few percent.

**Why:** brick mass. The old build set every brick's mass with `maxf(0.5, volume * 0.3)`, and for a
1.0 × 0.5 × 0.5 m brick that is `0.075` — which hits the floor. **Every brick in the reference
capture weighs 0.5 kg.** In the rebuild the same brick is sandbag at C1's declared density of
1500 kg/m³, so it weighs **375 kg**. Three orders of magnitude.

The blast sets velocity directly, so launch speed is unaffected — which is why the impulse metrics
still land. Everything downstream is a collision between bricks, and a 375 kg brick ploughs through
where a 0.5 kg brick bounces off.

**This is the material system working, not a regression.** The `0.3` was a placeholder from before
materials existed; MATERIAL-SPEC is the document that replaces it, and C1 gave every material a real
density. Reverting to it to make the fixture green would be deleting the milestone to satisfy the
test for it.

Confirmed rather than assumed: forcing the old density back took the failures from 30 to 27 and
moved every pad metric toward the reference, which is the experiment saying yes.

### A2. The two `world` scenarios cannot be reproduced at all, and never will be

`earth_standard_shell` and `earth_heavy_charge` fired into the old build's live map at (−25, 0, 0)
and (25, 0, 0). Their measurements are of **whatever was standing there** — the reference records 11
and 13 bricks launched and debris reaching 18 m and 43 m in the air, which no crater's own spoil
does. Ours reach 4.6 m, which is what `randf_range(6, 14)` of upward velocity against 20 m/s² of
gravity actually produces.

So the reference for those two describes a map that no longer exists. The inputs are gone, not just
the representation.

`earth.height_cells_removed` has the same problem twice over. Its unit is a cell of the old field —
2.5 m across, 0.8 m per scoop — and the rebuild's field is continuous centimetres on 0.5 m cells.
The profile has been ported exactly (`Blast.crater` carries the old `power / 22.0` scoop formula and
its `+ 0.3` rounding bias), and the volume converted into old-cell units for comparison, which gets
27 against 18 and 84 against 72. The remainder is the old carve's `heights[i] > 0` clamp — it could
only remove earth that was *there*, and how much was there depended on the terrain at those two
spots. That terrain is the map that is gone.

`compare_baselines.py` gates this metric at 0% — exact match — which was correct while the
representation was fixed and is not achievable now. The tool's own comment says what the metric is
for: *"did it still dig the hole"*.

### A3. What I did about it, and what I need from you

**The reference is kept, untouched, as the historical record.** It is the only evidence of what the
old build felt like and it should outlive every rebuild of the fixture.

**A second baseline is captured from the rebuild**, and that is what `check.sh` compares against
from now on. This keeps the fixture doing its actual job — catching the day somebody changes
`BRICK_IMPULSE` and does not notice — while acknowledging that the one-time shift from massless
bricks to real materials already happened and was intended.

Every metric that moved is listed in the commit that does it, so the re-baseline is a record rather
than an erasure.

**Marissa:** the thing worth your eye is not the numbers, it is whether the blast still *feels*
right, and that is a question the fixture explicitly cannot answer — §1e captured it because feel
does not survive as numbers. There is a blast in the game now. When you next play it, that is the
check that matters, and if it feels wrong the constants are all in one file with their reasons
attached.

---

## B · Calls made where the specs said nothing

### B1. `Brick` carries the old build's damping and friction

`linear_damp = 0.08`, `angular_damp = 0.8`, `friction = 0.8`, straight off the old `spawn_brick`.

These were missing from the first version and the fixture caught it: with no damping the same blast
threw bricks 20–30% further and settled them at a different rate. The impulse was right and the
aftermath was wrong — precisely the class of thing "port verbatim" exists to prevent and precisely
the class of thing that cannot be spotted by reading the code.

`angular_damp` is the load-bearing one. At 0.8 a tumbling brick stops spinning and comes to rest; near
zero it *rolls*, and a wall of rolling bricks scatters much wider than a wall of tumbling ones.

### B2. The rebuild fixture is a second file, not an edit of the first

`blast-fixture/blast_fixture.gd` drives the old project and cannot be pointed at the rebuild.
`rebuild_fixture.gd` sits beside it running the same eight scenarios with the same measurements.

Kept separate deliberately: the original is a *record of how the capture was taken*, and rewriting
it in place would destroy the only evidence of what the reference numbers actually mean.

### B3. `felt.*` needed the old player's decay rates, not just the blast's output

The reference's `player_knock_peak` for a standard shell is 3.8. The blast produces a knock vector
of magnitude 5.21. Both are correct: the fixture samples one physics frame *after* the blast, and the
old player consumed the vertical component whole (`velocity.y += knock.y; knock.y = 0.0`) and decayed
the rest by `1.0 - 5.0 * dt`. The horizontal remainder, decayed once, is 3.79.

So `felt.*` is not a measurement of the blast — it is a measurement of what the old *player* did with
the blast's output. The fixture models that explicitly now, with the decay constants named. Worth
knowing because `BUILD-ORDER` §1b says the player was deliberately **rebuilt** rather than ported, so
these numbers describe something that no longer exists in the game — only in the fixture.
