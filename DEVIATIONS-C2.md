# Where the C2 build and the specs disagree

Running list, opened at task #65. `DEVIATIONS-C1.md` is the closed one for the milestone before
this; read that first if a mismatch looks like a bug rather than a decision.

Same sorting as C1 — by what I need from you, not by subject. Nothing here blocks the rest of C2.

**A** — forks worth a decision. One so far.
**B** — calls made where the specs said nothing. All reversible, all cheap to reverse now.
**C** — structural notes: places the shape of the code was decided by the 300-line cap rather
than by the design. Recorded because "why is this two files" is otherwise a question with no
answer in the repo.

---

## A · One fork, and I picked a side

### A1. The straight-leg complaint lives in the driver, not in the validator

The handoff for #65 asked `LocomotionRules` to enforce, among the rest of RIG-SPEC §5, the
complaint about a leg drawn straight at rest — the one that says *"which way its knee bends is a
guess — give its upper joint a `rest` angle"*. It does not, and this is the only item on the
handoff's list I did not build.

The reason is that the check is not computable from what the validator has. Straightness means
*the knee is on the line from the hip to the ankle in the rest pose*, and the rest pose is three
things composed: each part's authored `rotation` down the chain, each joint's `pivot` offset from
its part's centre, and each joint driven to its own `rest` angle. `Rig` does all three. The
validator has a part table and no `Rig`, because it runs *before* anything is allowed to build
one — that ordering is the whole point of a gate.

That left two honest options and one dishonest one:

1. **Reimplement pose composition inside the validator.** Correct on the day it is written, and
   a second copy of the rig's arithmetic to keep in step with the first forever. The two
   disagreeing is a much worse failure than the one being fixed: a warning about a leg that is
   fine, or silence about one that is not.
2. **Check a proxy** — "the upper joint declares no `rest`, so the leg is probably straight".
   Cheap, and wrong for any leg bent by its authored `rotation` or by its offsets, which is
   exactly how `biped.json` and `quadruped.json` are bent. It would print a boot warning about
   two legs that are correct. A warning nobody should act on is worse than no warning.
3. **Leave it in `Leg._bend`, where a posed rig exists, and say so.** Which is what I did.

The complaint still fires, with the leg's own name in it, the moment anything sets a driver up —
`case_leg.gd` asserts both the wording and the fix it names. What is lost is the `file:line` a
validator message would carry. For a warning whose text already identifies the leg, that seemed a
fair price for not having two copies of the pose maths.

**If you want it in the validator anyway**, option 1 is about 60 lines and the honest version of it
is to have `Rig` expose the composition as a static function both callers use, so there is one
copy rather than two. Say the word.

---

## B · Calls where the specs said nothing

### B1. A `legged` thing with no `gaits` is refused

RIG-SPEC §5 shows a gait table and never says what happens without one. `Gait.for_speed` answers
an empty list with `{}`, `Locomotion.step` returns `{}` on that, and the creature holds its rest
pose for the rest of the match in complete silence. That is the exact failure shape
`LocomotionRules` was written to end, so it is an error rather than a warning. Same for an empty
`legs` array.

### B2. Gaits out of ascending speed order are a warning

Not in the spec, but `Gait._usable`'s own comment says *"a pack whose gaits arrive out of order is
not an error — the validator says so as a warning"*. The validator did not say so. Now it does,
and the message states that core sorts them so it costs the pack nothing — otherwise the warning
sends somebody looking for a bug that is not there.

### B3. A leg `phase` outside [0, 1) is a warning, not an error

`Leg.measure` runs it through `fposmod`, so 1.25 loads and means 0.25. The warning states the
number it becomes rather than only that the range was broken, because the two authors who write
1.25 want opposite things: one meant "a quarter of a cycle after the leg before" and got it by
accident, and one meant "one and a quarter cycles" and did not get it at all. Only the second can
tell from a message that names the result.

### B4. `Footing.support`'s third parameter is called `reach` and is handed `drop`

Not a bug — worth writing down before somebody "fixes" it. The parameter means *how far above the
lowest foot the body's origin may sit*, and `Locomotion` passes `drop`, which is the least of the
legs' `span − hip height`. Both are the same quantity under two names. If either gets renamed,
rename both.

### B5. The test fixtures are bent by an offset jog, not by a `rest` angle

`biped.json` and `quadruped.json` need genuinely bent legs, or `bend` is a guess and `reach`
collapses to its floor. They are bent by putting each shin's top two modules forward (or back, for
a hock) of its thigh's bottom, rather than by giving the knee a `rest` angle — which is what the
warning in A1 tells authors to do.

The reason is that `pivot` must be whole modules and a bone's pivot sits half its length along its
own axis, so any rotation that is not a multiple of 90° puts the joint at an irrational offset and
forces a non-grid `offset` to compensate. Bending by `rest` would make every expected number in
`case_leg.gd` a trig expression, which is exactly what `case_rig.gd`'s "whole modules and right
angles" fixture philosophy exists to avoid. The cost is a visible 0.2 m step at each knee. On a
box creature in a test fixture that is a fair trade; it would not be on shipped content, and
`core:soldier` at #66 should be bent by `rest` angles like a real asset.

### B6. `skin` was a palette colour no material would accept, and now `hide` accepts it

Core data, changed rather than worked around. `palette.json` declares `skin` and argues for it at
length — it is the only entry that breaks two palette laws, and its own `why` says that is
deliberate because *"faces have to read at range against every terrain colour in the file, and
every terrain colour in the file is a mid-value brown"*. So the palette was written in the
expectation of faces.

No material listed it in `colour_allow`. Not `hide`, not `canvas`, not anything — which means
that from C1 until now the colour was unreachable: declared, argued for, and refused by every
material in the game. `core:soldier` is the first asset that ever asked for it, and the refusal it
got was correct and useless.

`skin` is now on `hide`'s list, which is where it belongs — `hide` *is* skin, and a face is the
only thing that would use it. One word of data, no spec edit, because `colour_allow` is a data
concept that MATERIAL-SPEC's table does not describe. Reversible by deleting it, at the cost of
the soldier's head and hands going back to `tan`.

---

## C · Shape decided by the line cap

### C1. `LocomotionRules` is two files

`locomotion_rules.gd` and `gait_rules.gd`. One file came out at 312 lines against a cap of 300.
The seam is real rather than arbitrary — the legs half asks whether the block describes *this
asset* and answers with the hierarchy; the gaits half asks whether a set of numbers means what it
says and answers with arithmetic, and needs no `ResolvedAsset` at all — but one file is what I
would have written if the cap were 400.

### C2. #65's tests are three cases, not one

`case_leg.gd` (what a leg is, measured off the rest pose), `case_driver.gd` (the cycle: where the
feet go and when) and `case_body.gd` (what the body does about where they landed). The last split
happened at 316 lines. Again the seam is genuine — it is `Locomotion.step`'s own two halves — but
it was the cap that forced the question.

### C3. `game/tests/fixture_world.gd` is new, and one older case still does not use it

Three cases needed the same fifteen lines of "load a fixture root through the real pipeline", so it
is one static helper now. `case_rig.gd` (300 lines) still carries its own copy and was left alone,
because folding it in means editing a file that has no room for the edit. Whoever next needs a line
in it should fold it in then.

`case_validator.gd` was the other one, and #68 forced the issue: adding four words to its
dormant-rule assertion put it two lines past the cap. It is now `case_validator.gd` (the rules —
what gets refused, and whether the message is worth reading) and `case_refusal.gd` (what a refusal
costs, and what the validator admits it is not checking), both on `FixtureWorld`. The seam is
genuine — one asks whether content is legal, the other asks what happens to the world when it is
not — but the cap is what forced the question, which is the pattern this section exists to record.

### C4. The animation state list is 24 names, and gaits are deliberately not among them

`ANIMATION-SPEC.md` §2 is a closed list, in the same sense as the joint types and
`Locomotion.TYPES`. The judgement worth flagging is what is *absent*: there is no `walk`, no `run`,
no `sprint`. Those are gait names out of a pack's own table — `core:soldier` calls its fast one
`sprint` and `testpack:horse` calls its `trot` — and `CORE-SPEC` §5 exempts rigs from the
no-new-states rule for exactly that reason. A core state list that enumerated gaits would have to
grow every time somebody authored a creature, which is the definition of not closed. So the list
has one `locomote` and the gait engine owns the detail.

Twelve of the 24 are reserved to C4, three to C5, two to C6. That is a lot of names for things
nothing can play, and the alternative — adding them one at a time as each verb lands — means the
list is never a list. They are marked reserved with the milestone named, and the validator rule is
meant to say which milestone rather than "unknown state", because those two send an author to
different places.

---

## D · Untested, and named rather than left quiet

The harness that finds these is `tools/mutate.py`, and it is in the repo so the claim is
reproducible rather than a number in a commit message. It currently reports **12 caught, 1 missed**.
The one it misses is D1 below; D2 is not in its list at all, for the reason given there. Recorded
here rather than left as a silent gap, because #69 cannot honestly say C2 is *verified* while they
are unmentioned.

**One of these was found and fixed while writing this section.** The harness had a fourteenth entry
that came back MISSED: `Gait.foot_cycle`'s stance amplitude was `stride * 0.5`, which travels a full
stride relative to the body while the body only covers `duty * stride` — so every planted foot slid
backward by `(1 - duty) * stride`, 0.32 m per step for a soldier at a walk. That is precisely the
skating the whole file is written to prevent, and the existing test asserted the sliding formula.
Measuring it made it undeniable: 0.00714 m of world slide per frame against a body covering
0.01667, exactly `speed * (1/duty - 1) * dt`. Fixed, and `case_driver._a_planted_foot_stays_put`
now pins it in world space against a moving body, which is the only place the claim is checkable.

### D1. ~~A posed foot lands 0.2 m from the plant~~ — **found, diagnosed, fixed**

Kept in full because the diagnosis was wrong twice before it was right, and the wrong turns are
the useful part.

**What it looked like.** A test written to pin the order-of-operations policy read back where a
foot was actually *posed*, rather than where the driver decided it should go. It missed the plant
by 0.2 m — on flat ground, standing still, with zero strain reported, on a target well inside the
leg's reach. That looked like a defect in the IK solver, and it was written up here and reported
as one.

**What it actually was.** The solver is correct. `core:biped` and `core:quadruped` were authored
with each shin's joint two modules forward of its thigh's tip — a cheap way to get a bend at rest
while keeping every offset on the grid, recorded in B5 below as a fixture convention with a
cosmetic cost. It is not cosmetic. A two-bone solver answers a question about two segments that
*meet*; a chain with a gap has a third length nobody told it about, and the gap arrives at the
sole unchanged. The shipped content — `core:soldier` and `testpack:horse`, both bent by `rest`
angles with their joints coincident — was measured at the same time and missed by **0.0000 m**.

So the engine was never wrong. Two test fixtures were unphysical, and the tests that should have
noticed were asking the wrong question.

**Why nothing caught it, which is the part worth keeping.** Every foot-planting assertion in this
milestone read `leg.plant` — `Footing`'s answer about where the foot *should* go. Not one read the
rig back. The suite was asserting the driver's intention and never its result, so a 0.2 m gap
between the two was invisible for as long as it existed.

**What changed.** Both fixtures are re-authored bent by `rest` angles at 30° and 60°, which keeps
every derived value an exact closed form (`2.4 - 1.2*sqrt(3)`, `3.0 - sqrt(4.68)`) and makes the
knee and hock come out as exactly `(0, 0, -1)` and `(0, 0, 1)` rather than approximately.
`Leg.MAX_CHAIN_GAP` refuses a disjointed chain in words at rig-build time, with the size of the
gap in the message, and `core:disjointed` is the fixture that keeps that complaint alive.
`case_body._the_foot_ends_up_where_it_was_solved_to` and its counterpart in `case_walker` ask the
second question now.

**And the original D1 is closed with it.** The pose-versus-plant assertion is exactly what pins
the order-of-operations policy, in both places it appears: `tools/mutate.py` now reports *"the rig
is solved against the body that came in, not the one going out"* and *"the walker poses the rig
before moving the body"* as **caught**. The two earlier attempts that failed — world slide, which
cannot see it, and the lean measurement, which passes for the wrong reason — are why this took
three tries.

### D2. The hang lag's frame-rate independence has no test — **still open, and now self-reporting**

`_solve` uses `1 − e^(−rate·dt)` rather than `rate · dt` precisely so that a fetlock does not lag
further on a slow machine. `case_body.gd`'s `_same_answer_every_time` proves two identical runs
agree, which is determinism and a different claim.

This is the one thing in the rig system with no test that fails when you break it: `tools/mutate.py`
carries the mutation and reports it **MISSED** on every run, so the gap announces itself rather
than living only in this document. Everything else is 15 caught, 0 missed.

The test would be that one step of `dt` and two of `dt/2` land on the same hang direction — exact
for the exponential, visibly not for a lerp. What makes it awkward is isolation: the hang only
moves when the body basis is not level, the basis comes from the ground under the feet, and the
two runs diverge in phase after the first half-step, so the feet sample slightly different ground
and the difference being measured is about the same size as the noise. It wants either a seam that
lets the lag be driven directly, or a fixture whose ground is tilted and uniform.
