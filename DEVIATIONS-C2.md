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

### C3. `game/tests/fixture_world.gd` is new, and two older cases still do not use it

Three cases needed the same fifteen lines of "load a fixture root through the real pipeline", so it
is one static helper now. `case_rig.gd` (300 lines) and `case_validator.gd` (299) still carry their
own copies and were left alone, because folding them in means editing a file that has no room for
the edit. Whoever next needs a line in either of them should fold it in then.

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

### D1. The order-of-operations policy has no test, in either of the two places it appears

`Locomotion.step`'s docstring emphasises this hardest of anything in the file: feet are planted
against the transform that came in, the new body height and tilt are computed from where they
landed, and only then are the world foot targets brought into the *new* body's space to be solved.
`Walker._physics_process` makes the same claim one level up — move the body, then pose the rig
against where it ended up. Doing either the other way round costs exactly one frame of lag.

Nothing fails if either is reversed, and the walker one is confirmed rather than suspected:
`tools/mutate.py`'s "the walker poses the rig before moving the body" comes back MISSED.

Two attempts at pinning it, and why neither worked, so the next person does not repeat them:

- **World slide of a stance foot** does not discriminate. A stale body transform advances by the
  same `speed * dt` each frame as a current one, and the swing advances identically, so the
  per-frame delta is unchanged. The wrong order produces a *constant* offset of about 3.7 cm at a
  walk — the rig trailing its own collider — not a growing one.
- **Lean into a turn** looks like it should work, because the yaw rate only exists after the body
  has moved, and a faithful swap has none to lean by. But the obvious measurement,
  `rig.root.basis.x.angle_to(Vector3.RIGHT)`, conflates the roll with the *yaw error* — and the
  wrong order leaves the rig a whole frame of turning behind, which at `TURN_RATE` is 8.6°. So the
  assertion passes for the wrong reason. `case_walker` keeps that lean test because it does pin
  something real, that the controller wires `lean_into_turn` through at all; it just does not pin
  the order.

What would work is isolating the roll about the creature's own forward axis, or comparing the
posed sole to the plant it was solved to in world space. Both need a helper that does not exist.

### D2. The hang lag's frame-rate independence has no test

`_solve` uses `1 − e^(−rate·dt)` rather than `rate · dt` precisely so that a fetlock does not lag
further on a slow machine. `case_body.gd`'s `_same_answer_every_time` proves two identical runs
agree, which is determinism and a different claim. The test would be that one step of `dt` and two
of `dt/2` land on the same hang direction — exact for the exponential and visibly not for a lerp —
and it needs a non-level body basis to have anything to converge toward, since with an identity
basis the hang starts at its own target and never moves.

