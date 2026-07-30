# BRICK WARS — Build Order

*How we rebuild the core properly without throwing away what we learned.*

---

## 1 · Not a blank slate — a harvest

"From scratch" is the right instinct about **structure** and the wrong instinct about
**knowledge**. The current build is ~1,500 lines and its structure is unsalvageable for
where we're going — a monolithic `main.gd` where every weapon, vehicle and trench is
hardcoded is the opposite of a data-driven core. That gets deleted without ceremony.

But some of the value in that code isn't the code, it's what we *learned* — facts that
cost days to find and would cost those days again from nothing.

**The distinction that matters:** a *fact* is something we proved. A *placeholder* is a
number that stopped the thing falling over long enough to keep working. The first version
of this list conflated them, and had vehicle physics filed as "proven" when it was never
signed off — CHECKLIST §7 still says `[~] feel sign-off pending`, and your actual verdict
on it was *"the turn radius is shit on a lot of the vehicles."* That's a placeholder. It
gets rebuilt, not ported.

So the list is now three buckets.

### 1a · KEEP — proven, port verbatim

Short by design. These are facts, and re-deriving them would be pure waste.

- **The Jolt config.** `sleep_velocity_threshold = 0.35`, gravity 20, Jolt as the
  engine. This one line is the fix for the entire "world never sleeps, FPS tanks" class
  of bug that cost us the Rust build. It goes in first.
- **The two-physics-frame sleep pattern** at spawn (`sleeping = true` gets overwritten
  if you set it before the body enters the space).
- **The headless autotest harness** and the Xvfb screenshot workflow — these move over
  on day one and gate every milestone after.
- **The palette hex values**, `SHADES`, and the jitter conventions (already lifted into
  ART-BIBLE, so this is bookkeeping).

### 1b · REBUILD — never signed off, redo from first principles

Your call, and I think it's the right one. Vehicles especially: the old model predates
three core systems it never anticipated — **spring suspension** as a real physical
constraint, **IK hands-on-controls**, and **`legged`** as a locomotion type. Porting a
traction model written before any of those exist would mean fighting it in C6 and
rewriting it anyway, with the sunk cost making it harder to throw away the second time.

- **Vehicle traction and handling in full.** Grip, steering, turn radius, weight
  transfer, the tuning constants. The old `1.0 - exp(-grip * dt)` shape is worth
  *knowing about* as one candidate, but it starts as a candidate and not as the answer.
  Turn radius is a named acceptance criterion in C6 now, not something we notice later.
- **The low centre of mass hack** `(0, -0.8, 0)`. This is a symptom-suppressor — the real
  fix is honest mass distribution across the compound collider, which we now have the
  format to express.
- **Plane lift.** The `∝ clamp(speed/takeoff)` model and `accel 28 / takeoff 13 /
  linear_damp 0.08` were tuned against one biplane in one map. Redo against the archetype
  slot, not against that aircraft.
- **Boat buoyancy.** Submersion-depth sampling was a stub; it never met real water.
- **Player movement constants** — WALK 12, SPRINT 22, JUMP 14, GRAV 40. These were set
  early and never revisited, and locomotion now has to feel right alongside foot planting
  and mounts. Retune from scratch; you can always land back on the same numbers.
- **The viewmodel.** `_process`-rate animation is the right *principle* and it survives,
  but the rig itself gets rebuilt as data on the C2 rig system rather than ported.

### 1c · LESSONS — carried as rules, not as code

Not ported and not rebuilt: written into the specs so they can't be repeated.

- **Colliders are 1–4 hand-fitted boxes.** Never one AABB (that bug cost a day), never
  per-part. Already law in FORMAT-SPEC §6 with a validator cap.
- **A rig is not a collider** (RIG-SPEC §3).
- **Animate the viewmodel at render rate, not physics rate.**
- **Procedural `AudioStreamWAV`** works and costs nothing to ship — worth keeping as the
  bootstrapping approach until the audio direction doc says otherwise.

### 1d · Both open items, now closed

Your terrain and blast notes settled the two I'd left hanging, in opposite directions.

- **`earth.gd` → REBUILD.** *"The terrain blocks are way too big, terrain should feel more
  organic than a grid of chunky rectangles."* That's a verdict on the representation
  itself, not the tuning — a 2.5 m cell is wider and taller than a soldier, so no amount
  of polish makes it read as ground. `EARTH-SPEC.md` replaces it with a 0.5 m column-span
  field at continuous height. Cell size, height representation, meshing and collision all
  change, so there's almost nothing left to port. What survives is the **design lineage** —
  column rebuild, carve, crater lips, spoil, the event log — and that's genuinely valuable
  even with none of the code attached. Those ideas were right, just expressed on a grid
  five times too coarse.
- **The blast model → KEEP, and protected.** *"I always had fun blowing stuff up, it felt
  good."* That's the only piece of subjective feedback in the project we can't re-derive
  from first principles, so it moves out of "probably fine" and into a defended position.
  See the fixture below.

### 1e · The blast feel fixture — do this before anything else

The risk in a rebuild isn't losing code, it's losing feel you can't describe. So we capture
it while the old build still runs:

1. Build a fixed test scene in `archive/great_war_prototype/` — a standard wall, a standard
   charge at a standard distance, locked camera, fixed seed.
2. Record the numbers: impulse curve, radius, falloff exponent, shatter-vs-shove threshold,
   debris count and lifetime, shake amplitude and decay, timing of each stage.
3. Record a screenshot sequence at fixed frame intervals, and the video.
4. Commit all of it as the **feel regression fixture**.

The rebuilt destruction system has to reproduce that fixture. Materials change what a blast
*does to each thing it touches* — scattering sandbags, punching brick, denting armour — but
they do not touch the impulse curve, the falloff, the shake or the timing
(`MATERIAL-SPEC` §7).

This is maybe two hours of work and it's the cheapest insurance in the project. "It felt
good" is a specification; it just needs writing down before it evaporates.

**Deleted regardless:** `main.gd` in its entirety, every hardcoded world-build function,
every inline weapon and vehicle definition, and anything that assumes the Great War.

The reason to do this *now* rather than in three months is arithmetic: the codebase is
the smallest it will ever be. Every week we add content on the old structure is a week
added to this job.

## 2 · The rule that keeps a rebuild from killing the project

> **Never more than two weeks without something you can play, and never a milestone
> that doesn't end with the headless test green.**

Rewrites die when the build goes dark for a season and momentum goes with it. Every
milestone below ends in something runnable on your Mac, even when it's ugly.

## 3 · Milestones

### C0 · Skeleton *(smallest, most boring, most important)* — **done 30 Jul**

New project layout — `core/` and `packs/` — with real module boundaries instead of one
file: physics, earth, rig, combat, verbs, vehicle, ai, mode, net, ui, audio, vfx,
content. Port the Jolt config and the headless harness. Wire CI so the test gates merges.

**Done when:** a grey box world spawns, bricks fall and sleep, `TEST_DONE` prints green
in CI, and no file is over 300 lines.

**All four hold.** 114 bricks drop, settle in 2.8 s and sleep;
`TEST_DONE cases=4 passed=4 failed=0 checks=30`; the largest file in the project is
`core/kernel.gd` at 153 lines. `game/docs/c0_greybox.png` is what it looks like.

Thirteen modules exist, three of them real (`physics`, `mode`, `ui`) and ten placeholders
that declare their boundary, their milestone, and the fact that they are stubs. The kernel
resolves them with Kahn's algorithm and refuses cycles, undeclared dependencies, missing
files and name mismatches, each by name. `Module.use()` refuses any module the caller did
not declare — the boundary is enforced at runtime, not written down and hoped for.

Three things worth carrying forward out of building it:

The kernel's resolver was the rehearsal for C1's `extends` resolver, and it earned its
keep on the first boot. Sorting `Array[StringName]` does **not** sort alphabetically —
StringName's `<` compares internal pointers, so the modules came out in allocation order
wearing a sort's clothes. It looked plausible. In C1 that same mistake would have made
pack load order vary with something unrelated, which is the exact class of bug the whole
determinism argument exists to prevent.

A failed boot leaked the module it refused: a Node created and abandoned before
`add_child` is never collected. Harmless at thirteen modules, not harmless in C1 where a
pack failing to load is a normal Tuesday.

The first grey-box screenshot showed the wall's corner lying on the ground. The running
bond offset every odd course by half a brick without shortening it, so the end brick of
each odd course hung half over nothing. Real masonry ends those courses short. Physics was
right; the wall was wrong — which is the reminder that the fixture measures what the
simulation does, not whether what we built it out of made sense.

### C1 · The content pipeline

The part-table format (`{shape, offset, rotation, size, material, colour, jitter}`), the
five primitives (block, wedge, corner wedge, cylinder, sphere), **the material set as
data**, the palette as data, the `pack.json` manifest, the loader, and the validator with
human-readable failures.

**Materials land here, not at C5.** Their *behaviour* arrives later, but `material` is a
required field on every part, mass derives from density, and colours resolve through
materials — so the table has to exist before the first asset is authored. Adding it later
means rewriting every asset written before it.

**`extends` lands here too** (`FORMAT-SPEC` §6, decided 30 Jul): the merge resolver,
the depth-3 cap, semver dependency declaration, deterministic topological load order,
cycle detection, pack-scoped failure, and the validator's `--resolve` provenance output.
The provenance dump is part of this milestone, not a later nicety — an inheritance system
you can't inspect is worse than no inheritance system at all.

Proven by building content *only* from JSON: a crate, then a wall, then a small
structure. **This is the milestone that decides the whole project's ceiling** — if the
format is wrong, everything authored on it is wrong.

**Done when:** I can add a new prop to the game by writing a JSON file and nothing else;
a variant of that prop costs five lines via `extends` and `--resolve` shows me where every
field came from; and a deliberately broken pack fails with a message that says exactly
why, without taking anything else down with it.

**Done, 30 Jul.** Walked in that order, against the shipped game rather than a harness.
`packs/core/table.json` went in as one file and the asset count went 7 → 8 with no code
touched. `packs/core/table_map.json` is five lines of `extends` on top of it, and
`--resolve core:table_map` prints all forty-odd fields with `← core:table` or
`← core:table_map` against each. `--pack-root res://tests/fixtures/broken` disables two
packs that are wrong on purpose — naming file, line, value and rule, all four of one pack's
problems at once — while the other nine assets boot untouched. `content` stops reporting
itself a stub here; nine of thirteen modules still do.

### C2 · Rigs, IK & the soldier

The kinematic rig system, joint types with limits, the two-bone IK solver, foot planting,
and the procedural gait engine (`RIG-SPEC.md`). The core soldier body becomes a
data-defined rig — no helmet, no kit, no faction colour.

**Done when:** a soldier defined entirely in data walks, sprints and jumps over uneven
ground with feet that plant correctly, and **a four-legged test creature walks using the
same system**. The horse test starts passing here, long before any horse art exists.

### C3 · The earth *(rebuilt — `EARTH-SPEC.md`)*

The 0.5 m column-span field with centimetre-quantised continuous height. Chunked
slope-dependent meshing (smooth ground below 60°, vertical skirts above it), chunked Jolt
heightfield collision, the angle-of-repose settle queue, spoil with conservation of volume,
the `disturbed` flag, and the event log formalised from day one because it's the netcode
foundation.

Tunnels and shoring can trail into C3b if the first pass is taking too long, but the span
structure goes in from the start — retrofitting spans onto a flat heightfield is a rewrite.

**Also here:** the flat-colour-versus-subtle-grain decision (`ART-BIBLE` §8), because this
is the first point where there's real ground to judge it on.

**Done when:** you can dig anywhere on the map, a trench you cut has vertical walls that
slump organically when shelled, craters have raised rims made of their own spoil, chalk
holds a steeper face than sand without a line of special-case code, and every modification
is a serialised event you could replay.

### C4 · Verbs, combat & tools

The fixed verb vocabulary as a real system (fire, throw, dig, build, melee, carry,
enter, man, interact, signal), the weapon archetype slots, ballistics, damage, and the
loadout system. **TESTPACK gets its first item here: a bow**, purely to prove the core
doesn't assume gunpowder.

**Done when:** a weapon defined in data fires, a bow and a rifle are the same code path,
and TESTPACK's bow works with zero core changes.

### C5 · Destruction & physics

Blast model ported against the §1e fixture, **material behaviour switched on** — the six
damage types, failure modes, spall, tool gating, fire propagation and `on_burnt` states —
structural integrity as a load calculation against material support and cohesion, debris
lifecycle and cleanup policy, primitives shattering into blocks.

**Done when:** the blast fixture still reproduces, a wall collapses correctly when you take
its base out, a sandbag parapet topples sideways where a clay one slumps, a shovel refuses
stone with a message that says why, and the world is back to zero awake bodies within
seconds.

The medieval mining loop (`MATERIAL-SPEC` §6) is the acceptance test for materials the way
the horse test is for rigs: **prop a tunnel, burn the props, watch the wall above come
down, with no code written for any of those steps.**

### C6 · Vehicles & locomotion

All five locomotion types including **legged**, multi-crew seats, enter/exit animation,
hands-on-controls via the C2 IK, turret tracking, suspension via spring constraints,
damage states, and ragdoll conversion.

Handling is **built here, not ported** (§1b). Spring suspension and honest mass
distribution come first and the handling model is tuned on top of them, rather than the
other way round.

**Done when:** **the horse test passes in full** — a ridable, articulated, ragdolling
quadruped added in data alone — a wheeled vehicle has visible suspension travel, and
**you sign off on turn radius and handling feel for one wheeled, one tracked and one
flying vehicle.** That last one is a named gate because it's the thing the old build
never got, and it doesn't get skipped this time.

### C7 · Modes, AI & logistics

Siege/skirmish/sandbox loops, phases, capture, respawn geography, the AI behaviour set,
bot fill, classes and the supply chain.

**Done when:** you can play a complete siege against bots, start to finish, and win.

### C8 · Netcode

Authority model, interest management, earth-event encoding, late-join replay, dedicated
server, then the 32-player milestone and the 100v100 bot stress test.

**Done when:** 32 real players in a siege, and the measured 100v100 number is written
down rather than hoped for.

### Then: the gate (`CHECKLIST.md` Part III), then eras become content.

## 4 · What happens to the Great War work

It stays playable and untouched in `archive/great_war_prototype/` as a reference build for
as long as it's useful — something to play against, and the source of §1a and §1c above.
As C1–C6 land, its content is re-expressed as the **reference pack** (`packs/great_war/`)
in data form.

What comes back is the **shape** of that content — the tank's silhouette, its part table,
its role — not its handling numbers. Those go through C6's sign-off gate like everything
else. The archive is a reference, not a source of truth.

## 5 · Immediate next actions

1. ~~Capture the blast feel fixture~~ — **done 30 Jul.** Harness built, hardened after the
   first capture was spoiled by a click firing a rifle round into the test wall, and then
   captured clean on the Mac: `blast-fixture/reference/macos-20260729/`, Godot 4.7.1, zero
   strays, 110 frames. That directory is now the definition of what the blast is supposed
   to feel like, and `compare_baselines.py` against it is the gate every rebuild milestone
   passes through. The one irreplaceable thing in the old project is no longer at risk.
2. ~~Lock the format decisions~~ — **done 30 Jul.** JSON, integer modules, `pack:asset`
   ids, and `extends` with full cross-pack reach capped at 3 levels (`FORMAT-SPEC` §12).
   C1 is unblocked.
3. ~~Build **C0**, the skeleton, and get CI green~~ — **done 30 Jul.** Thirteen modules,
   deterministic boot, a grey box world that settles and sleeps, four test cases and thirty
   checks, and `tools/check.sh` wired to a pre-push hook. The gate is local for now, with
   `.github/workflows/ci.yml` written and dormant so adding a remote later is a push rather
   than a project. The blast comparison is dormant until C5 and announces that on every
   single run, because a quiet dormant check is a forgotten one.
4. Build **C1** and prove it with a crate authored in JSON.

The `extends` decision added real work to C1 that wasn't there before — a dependency
resolver, deterministic topological load order, cycle detection, and the validator's
`--resolve` provenance output. That last one is not a follow-up task: it ships in the same
milestone as the resolver, because an inheritance system you can't inspect is worse than
no inheritance system. Budget for it up front rather than discovering it in C4 when a
number three levels up is wrong and there's no way to see where it came from.

Everything after that is the list above, one item at a time, with a playtest at the end
of each.
