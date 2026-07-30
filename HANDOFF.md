# HANDOFF — Brick Wars, mid-C2

Written 30 July 2026, at commit `81b3522`. This is everything a fresh agent needs to pick
the build up without re-deriving it. Read `VISION.md` and `BUILD-ORDER.md` first if you
have not; this file assumes them and only covers what is *not* written down elsewhere.

---

## 1 · Where the build actually is

`BUILD-ORDER.md` splits the core into nine milestones, C0 through C8. **C0 and C1 are
closed and signed off.** C2 is roughly two-thirds done.

C1 closed at commit `7a7f85a` — the content pipeline end to end: pack discovery with
semver ranges and deterministic ordering, the `extends` resolver with provenance, the
validator enforcing every `FORMAT-SPEC` §10 rule pack-scoped, the builder turning part
tables into meshes and colliders, `packs/core` authored as real data, and a `--resolve`
CLI that prints where every field of a resolved asset came from. That milestone was
delivered, playtested and marked.

C2 is "Rigs, IK & the soldier". Its task list runs #60–#69:

| # | Task | State |
|---|---|---|
| 60 | Rig format: `parent`, `joint`, and the rules that police them | done |
| 61 | Rig runtime: build the hierarchy, pose it, keep colliders separate | done |
| 62 | Two-bone IK solver | done |
| 63 | Test ground: uneven greybox to plant feet on before C3 exists | done |
| 64 | Foot planting and body tilt | done |
| 65 | Procedural locomotion driver: gaits from data | **code written, untested** |
| 66 | Author `core:soldier` as data, plus a four-legged test creature | not started |
| 67 | Tests, and a `--rig <id>` inspector CLI | not started |
| 68 | Measure the two constraint budgets; write the animation style guide | not started |
| 69 | Verify C2 done-conditions, screenshot, push | not started |

**#65 is the live edge and it is in a specific, honest state:** `game/core/rig/locomotion.gd`
and `game/core/rig/leg.gd` are written, they parse, they are committed, and **nothing
exercises them**. No test case instantiates `Locomotion`. No fixture declares a
`locomotion` block. The `locomotion` field is listed in `AssetRules.KNOWN_FIELDS` and is
therefore accepted by the validator **entirely unvalidated** — a pack can write any
garbage under that key today and nothing complains. That is the first thing to fix.

The gate is green as of this commit:

```
[1] no source file over 300 lines   ok   largest is game/tests/cases/case_rig.gd (300 lines)
[2] every core module is in the manifest   ok   13 modules, all listed
[3] headless test suite   ok   TEST_DONE cases=15 passed=15 failed=0 checks=684
[4] blast feel matches the reference capture   skip  dormant until C5
```

Green here means "nothing is broken". It does not mean #65 works.

---

## 2 · The working agreement with Marissa

This is the part most easily lost in a handoff, and it matters more than any technical
detail below.

**She approves checklist items, not technical tasks.** Her words: *"i dont want to be
interrupted with technical tasks, only approving checklist items as you do them and
providing guidance at each item if necessary."* Do not ask her which library, which file
layout, or whether to refactor. Decide, do it, and record why in the code.

**Check in at milestone boundaries, not inside them.** Run the whole milestone end to end,
then come back with the thing working, a screenshot, and what it cost. The one exception
is a genuine design fork — a decision that changes what the game *is* rather than how it
is built. Those get a question. Everything else does not.

**The repo is the channel.** She keeps a private GitHub repo (`devmarissa/brick-wars`) and
her Mac only ever pulls. Push every milestone. She does not want to run build commands.

**Nothing gets checked `[x]` in `CHECKLIST.md` until she says it *feels* right.** `[~]`
means in the game but rough. That distinction is load-bearing — it is how the project
avoids declaring victory on things nobody has played.

---

## 3 · Environment facts that will otherwise cost you an hour each

These were all learned the expensive way.

**Godot is 4.7.1.stable.official.a13da4feb** on both her Mac (`godot`) and the build
container (`godot47`). Keep parity; a version drift silently changes physics.

**`godot --headless --path game` never exits.** Always pass `--quit-after 400`. The one
exception, and the fastest way to see a parse error, is running the test scene directly:
`godot --headless --path game res://tests/test_main.tscn` — that exits on its own.

**Adding a file with a new `class_name` requires `godot --headless --path game --import`**
before any script referencing it will parse. Skip it and you get a confusing "identifier
not declared" on a class you can see on disk.

**User arguments go after `--`.** `godot --headless --path game --quit-after 400 --
--resolve core:crate_ammo`. Godot's own flags go before it.

**GDScript warnings are errors in this project.** Two specific traps: `var x :=
some_callable.call(...)` is a hard parse failure, so every `Callable.call` result needs an
explicit type (`var under: Dictionary = probe.call(ideal)`); and every Dictionary lookup
used as a typed value needs a cast (`var pos: Vector3 = p["position"]`).

**`String()` in Godot 4 only accepts string-ish types.** `String(some_array)` throws at
runtime. Use `str()`.

**No source file may exceed 300 lines.** `tools/check.sh` globs `*.gd`, `*.tscn`, `*.sh`
under `game` and `tools`; JSON and Markdown are exempt. The test is `n > 300`, so exactly
300 passes. Several files are at or near the cap — `case_rig.gd` is at 300 exactly and
`case_validator.gd` at 299, which means **new assertions cannot go in either file.** When
something does not fit, split it along a real conceptual seam rather than trimming the
prose comments; the comments are the design record and are the reason this codebase can be
handed over at all. `leg.gd` exists because of exactly this pressure and is a good example
of the seam being genuine rather than arbitrary.

**Run `./tools/check.sh` before every push.** It is the whole gate.

**The GitHub REST API is blocked from the build container** (403 at the proxy). Git over
HTTPS works fine. You cannot poll CI status; do not waste calls trying.

---

## 4 · What #65 needs next, in order

The design decisions below are already made and are embedded in the committed code with
their reasoning. **Do not relitigate them** — implement against them.

1. **Get it under test.** Write `game/tests/cases/case_driver.gd`, add it to the `CASES`
   array in `game/tests/test_runner.gd` (cases are listed, never discovered — a test that
   silently stops running is worse than no test), `--import`, run. Follow `case_footing.gd`
   for style: assert numbers, not vibes.

2. **Write `game/core/rig/locomotion_rules.gd`** (`class_name LocomotionRules`), modelled
   exactly on `rig_rules.gd`: a `check(asset, at)` that fills `errors` and `warnings`,
   hooked into `validator.gd`'s `_validate` right beside `RigRules` and collected with
   `_collect(...)`. It must be its own file — `RigRules` is 228 lines and `AssetRules` 232,
   neither has room. What it checks: the block is an object; `type` is present and in
   `Locomotion.TYPES`; for `legged`, `legs` is a non-empty array whose entries name real
   `root` and `foot` parts with `foot` descending from `root`, and `phase` in [0,1);
   `gaits` entries have `name`, `speed` as `[low, high]` with `low < high`, `phases` sized
   to the leg count, `stride > 0`, `lift >= 0`, `duty` in (0,1); a leg straight at rest
   gets the "give its upper joint a `rest` angle" complaint; a non-`legged` type that
   declares `legs` or `gaits` gets a warning.

3. **Add fixtures.** Valid `biped.json` and `quadruped.json` go under
   `game/tests/fixtures/rig/core/`, following `leg.json`'s conventions exactly — `kind:
   "prop"`, `class: "small_prop"`, bones pointing down their own −Z, sized `[thickness,
   thickness, length]`, pivot at the bone's own top end, and **legs bent at rest** so
   `bend` and `reach` are derivable. Each carries a `locomotion` block in `RIG-SPEC` §5's
   shape. **Broken fixtures cannot go under `fixtures/rig/`** — `case_rig.gd` asserts
   nothing there is refused. Put them under a new root
   `game/tests/fixtures/locomotion/broken/` with its own `pack.json`.

4. **Mutation-test the load-bearing policy lines**, as was done for `Footing` at #64: break
   one line, confirm a test goes red, put it back. A policy line with no test that fails
   when you break it is decoration.

5. **Then #66**, which is where the milestone's done-condition actually gets met: author
   `core:soldier` as pure data and a four-legged test creature, retune walk/sprint/jump
   from scratch (do not port the old build's numbers), and **swap the sandbox world over to
   `TestGround`**. That last part has a trap noted below.

6. **Un-stub `game/core/rig/rig_module.gd`** before C2 closes. It still returns
   `module_is_stub() -> true`. `content_module.gd`'s un-stubbing docstring is the pattern:
   justify it against `BUILD-ORDER`'s C2 sentence in prose.

---

## 5 · Design decisions already made, and why

**A leg's bend direction is derived, not declared.** A human knee points forward and a
horse's hock points backward. That difference could have been a `bend` field in the format
— one more thing to document, validate, and get silently wrong in a mod. Instead it is
read off the rest pose: the component of the hip→knee vector perpendicular to the hip→ankle
line *is* the bend direction. An author who bent the leg has already said which way. A leg
drawn straight has said nothing, and that is the case that warns and falls back to forward.
This is why the validator has to ask for a `rest` angle, and why the fixtures must be
authored bent.

**Reach and stance height are derived too.** `reach = max(span − distance(anchor, home),
MIN_REACH)` — literally "how much further can this leg straighten". `stand` is the negated
mean of the legs' resting sole heights. Both come off the rest pose, so an author retunes a
creature's stance by moving its bones rather than by writing the same number twice in two
places that can disagree.

**`chain[0]` and `chain[1]` are solved by IK; everything past them is passive.** A fetlock
or pastern hangs and lags, which is what makes a horse read as a horse rather than a stick
creature, and it costs almost nothing. The IK pair is therefore solved to where the *ankle*
must be for the passive segments to put the sole on the target — not to the target itself.
The lag is `1 − e^(−rate·dt)`, frame-rate independent on purpose: a fetlock that lagged
further on a slow machine is one more thing two clients would disagree about.

**Order inside `step()` is load-bearing.** Feet are planted against the transform that came
in, the new body height and tilt are computed from where they landed, and only then are the
world foot targets brought into the *new* body's space to be solved. The other way round
costs exactly one frame of lag — invisible standing still, and read as skating feet the
moment the creature turns.

**Body height uses stance feet only; tilt uses every foot.** A swinging foot's plant is the
ground under it, which is the right thing to tilt to and the wrong thing to stand on. A
creature stepping over a ditch must not drop into it halfway through the stride.

**A gait's `phases` replace a leg's own `phase`; they do not add.** A pack that writes both
has said the same thing twice, and adding them turns a trot into a shuffle the moment
somebody tunes one of the two.

**`step()` returns the body's height and orientation rather than writing them.** The caller
owns the body — it is a physics object with a collider, and a driver that moved it directly
would be a kinematic system arguing with a simulated one. The *rig* is posed as a side
effect, because that is the part nothing else can do.

**A rig is not a collider** (`RIG-SPEC` §3). `Rig` builds meshes and nothing else.
Collision stays the one to four hand-fitted boxes the asset declared. A horse gets a body
box and maybe a head box, not eight leg colliders — partly for cost, mostly because a rig
that collides with itself fights its own solver, and the fight is visible.

---

## 6 · Traps

**Do not swap the sandbox world to `TestGround` casually.** `core:watchtower` spawns at
y=0 at (−5, ·, −2.4), which is inside the test bowl where the ground is ≈ −0.358; several
crates land partly inside the terrain too. Every `LAYOUT` entry needs lifting by
`TestGround.height_at(x, z)` and the camera reframing. That is #66 work.

**`Sandbox.make_ground()` and `Sandbox.DROP_HEIGHT` must stay** even after the swap —
`case_bricks_fall.gd` needs a flat plate to be meaningful.

**"Leaked instance dependency" and "Pages in use exist at exit" warnings at test exit are
pre-existing** — 78 of them on HEAD. They are not yours. Do not chase them.

**`ContentLoader` strips any dictionary key starting with `_`.** That is how prose comments
(`_note`) go into fixture JSON without tripping the unknown-field warning. Use it.

**`core` is itself a pack** (`res://packs/core`, its own `pack.json`). Core *data* lives at
`game/core/data/`. Those are different things and the distinction bites.

**A part's `offset` is the centre of its box.** This is what forced `joint.pivot` to exist,
and it is the single most common source of "why is the leg attached to the middle of the
thigh" confusion.

**Godot 4 winds front faces clockwise.** For triangle `a, b, c` the outward normal is
`(c − a).cross(b − a)`. The suite measures this rather than trusting memory.

---

## 7 · Still open, beyond C2

Deferred deliberately, each with a home: the audio direction doc and the animation style
guide (the latter is #68); the pack-material resolver from `MATERIAL-SPEC` §8, which is
what would let the validator enforce derived-material multipliers — currently one of three
rules `AssetValidator.DORMANT` declares but does not enforce, and it announces that at boot
rather than pretending; ice, glass and water material numbers; and a review of the 26-slot
archetype registry, which lands at C4.

`DEVIATIONS-C1.md` records where the C1 build knowingly diverged from spec and why. Read it
before assuming a mismatch is a bug.

---

## 8 · Security

**The fine-grained GitHub token in the previous session's chat history should be revoked.**
It is scoped to `brick-wars` alone, so the blast radius is one game repo, but it exists in
plain text in a transcript. Revoke it and issue a fresh one when the next agent needs push
access. In the build container it only ever lived at `/root/.bw_token` and
`/root/.git-credentials`, both `chmod 600`, both destroyed with the session. It must never
be echoed into command output, written into a tracked file, or committed.
