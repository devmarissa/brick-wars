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

### D1. **A posed foot lands 0.2 m from the plant it was solved to.** Confirmed, and it blocks C2

This started as "the order-of-operations policy has no test" and turned into something worse while
a test for it was being written. It is the reason C2 is **not** verified.

**The reproduction**, on `core:quadruped`, flat ground, standing still, one step:

```
REST  tip_of(last)=(-0.3, 0.0, -1.5)  home=(-0.3, 0.0, -1.5)  equal=true
      upper=1.200 lower=1.200 trail=0.400  anchor=(-0.3, 2.4, -0.9)
AFTER ankle=(-0.3, 0.548, -2.055) wanted=(-0.3, 0.4, -1.92)  off=0.2000  strain=0.0000
      |anchor→wanted|=2.2451  upper+lower=2.4000  height=0.0000
```

The first line rules out the measurement: at rest the posed sole read back through the rig is
exactly `home`, to four decimals, so `Leg.tip_of` and the transform reconstruction are sound. The
third is the finding. `Locomotion._solve` asked for the ankle at `target - hang * trail`, the
solver returned an `end` **0.2 m away from that**, and reported `strain` of zero — on a target
2.245 m from the anchor against a leg that is 2.4 m of upper plus lower, so comfortably reachable.

**Why nothing caught it.** Every foot-planting assertion in the suite — including
`case_walker`'s "on the surface to 2 mm" — reads `leg.plant`, which is `Footing`'s answer about
where the foot *should* go. Nothing read back where the foot was actually *posed*. So the suite
has been asserting the driver's intent rather than the rig's result, and the two differ by 20 cm.
Earlier commit messages in this milestone claim feet planting to 2 mm; that claim is about
`leg.plant` and does not survive contact with the pose.

**Where to look**, in order of suspicion: `TwoBoneIK.solve` returning an `end` that is not `lower`
away from its own `joint`, in which case `Rig.aim` reconstructs a different ankle than the solver
intended and the error is the difference; or `_solve` aiming `chain[1]` at a point it cannot place
because `aim` sets a direction while the bone keeps its own length. The 0.2 is suspiciously
`trail / 2`, which may mean something or may be arithmetic coincidence on this fixture — check a
second creature before reading anything into it.

The test that found this is not in the suite, because it fails and the tree does not stay red. It
is four lines and it belongs in `case_body.gd` the moment the defect is fixed: step the driver,
rebuild the reported body transform as `Transform3D(out.basis, (at.x, out.height, at.z))`, and
assert that `posed * Leg.tip_of(rig, leg.chain[-1])` is on `leg.plant["position"]` for every leg
in stance.

**The original D1 still stands underneath this**, unresolved and now secondary: the
order-of-operations policy in `Locomotion.step` and again in `Walker._physics_process` has no
test, and `tools/mutate.py` reports the walker half as MISSED. The two earlier attempts at pinning
it are worth not repeating — world slide cannot see it, because a stale transform advances by the
same amount per frame as a current one; and the obvious lean measurement passes for the wrong
reason, because `rig.root.basis.x.angle_to(RIGHT)` conflates roll with a frame of yaw error. The
pose-versus-plant assertion above is the thing that would pin both, once it can pass.

### D2. The hang lag's frame-rate independence has no test

`_solve` uses `1 − e^(−rate·dt)` rather than `rate · dt` precisely so that a fetlock does not lag
further on a slow machine. `case_body.gd`'s `_same_answer_every_time` proves two identical runs
agree, which is determinism and a different claim. The test would be that one step of `dt` and two
of `dt/2` land on the same hang direction — exact for the exponential and visibly not for a lerp —
and it needs a non-level body basis to have anything to converge toward, since with an identity
basis the hang starts at its own target and never moves.
