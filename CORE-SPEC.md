# BRICK WARS — Core / Pack Boundary

*What the engine owns forever, and what an era or a mod is allowed to be.*

This is the most consequential document in the project. Every "is this core or content?"
argument gets settled here, and a wrong line drawn now costs months later. Read it
before adding anything.

---

## 1 · The boundary test

Three questions, in order. First "no" decides it.

1. **Would medieval AND modern both need this?** If yes → core.
2. **Is this a rule, a system, or a physical law?** If yes → core.
3. **Is this a specific object, look, or sound?** If yes → pack.

Worked examples:

| Thing | Verdict | Why |
|---|---|---|
| Projectile flight, drop, impact | **core** | arrows and bullets are the same maths |
| The bolt-action rifle | pack | one specific object |
| "Ranged weapon, slow rhythm" archetype slot | **core** | the slot every era fills |
| Reload/cycle animation *state* | **core** | states are shared |
| Reload *timing and pose* for the rifle | pack | data filling a core state |
| Digging, spoil, crater lips | **core** | every era digs |
| A trench ⟨GW⟩ vs a siege ramp ⟨ANC⟩ | pack | shapes built from core dig |
| Fire spread | **core** | medieval needs it, GW uses it |
| Barbed wire | pack | a specific obstacle |
| "Obstacle that snags soldiers" buildable archetype | **core** | wire and caltrops are one thing |
| Mud, stone, wood, canvas materials | **core** | every era is made of these |
| "Stone is harder than cloth" | **core** | a physical law, and the same law in every era |
| A sandbag wall topples, packed earth slumps | **core** | falls out of material properties |
| *Which* materials a faction builds from | pack | identity, chosen from the core set |
| Field grey / allied drab | pack | faction identity is era identity |
| Helmet silhouette rules | **core** (standard) | the *rule* is core, the *helmet* is pack |

**The rule of thumb**: the core is a *vocabulary*, a pack is a *sentence*.

## 2 · What the core owns — systems

Non-negotiable, never in a pack:

- **Materials** (`MATERIAL-SPEC.md`) — the material set, the property schema, the six
  damage types, failure modes, hardness tiers and tool gating, directional support and
  cohesion, angle of repose, fire propagation. Everything in the world is made of
  something, and the material decides what happens to it. Packs reference materials by
  name and may derive bounded variants; they cannot invent physics.
- **Physics & destruction** — bricks, Jolt config, blast propagation, structural
  integrity (a load calculation against material support, not a global rule), debris
  lifecycle, fire spread
- **The earth** (`EARTH-SPEC.md`) — the 0.5 m column-span field, continuous
  centimetre-quantised height, dig/build/carve, spoil and conservation of volume,
  angle-of-repose slumping, shoring, tunnels and mining, collapse, water table, and the
  event log that becomes netcode
- **Soldier locomotion** — walk/sprint/jump/crouch/prone/mantle/swim, knockback,
  health/damage/death, carry weight
- **Combat maths** — projectile ballistics, melee resolution, damage model, hit
  detection, area-effect falloff
- **The animation state machine** — the finite list of *player* states and the timing
  table. Packs supply poses; **packs cannot define new player states.** (This does not
  restrict rigs — see below.)
- **Rigs, joints & constraints** (`RIG-SPEC.md`) — kinematic joint types, physical
  constraint types, the two-bone IK solver, foot planting, the procedural gait engine,
  ragdoll conversion, and the budgets that keep all of it affordable. Packs declare
  hierarchies and gait data; the core drives them. This is what makes a modded,
  properly-articulated horse possible without core code.
- **Locomotion types** — wheeled, tracked, **legged**, flying, floating, static
- **Camera** — FP/TP, ADS, shake, FOV rules, viewmodel rig
- **Interaction verbs** — dig, build, fire, throw, melee, enter/exit, man, carry.
  **Packs cannot define new verbs.** A pack wanting one is a core change request.
- **Vehicle simulation** — ground/air/water locomotion, seats, crew, damage states
- **AI behaviour** — cover, garrison, assault, sap, squad logic (packs tune parameters,
  not the behaviour tree)
- **Game modes** — siege/skirmish/sandbox loop, phases, capture, respawn, win conditions
- **Logistics** — supply points, cargo, consumption, resupply rules
- **Netcode** — authority, interest management, event encoding, replication
- **UI framework** — HUD elements, menus, map, scoreboard (packs theme, don't rebuild)
- **Audio engine-side** — mixing, distance model, occlusion, reverb zones
- **Mod loading, validation, and sandboxing**

## 3 · What the core owns — content (yes, including art)

You asked the right question: **the core does ship art.** Not era art — the shared
substrate every pack builds on. Without it, a modder starts from nothing and the game
loses its visual coherence in the first week of workshop uploads.

**Core art standards** (`ART-BIBLE.md`) — the module system, palette laws, silhouette
rules, part budgets, material standards, review gate. Binding on core and packs alike.
A pack that violates the bible is a broken pack, not a stylistic choice.

**Core content set** — shipped with the engine, available to every pack:

- **Core palette** — earth, clay, stone, wood, metal, gunmetal, canvas, rope, leather,
  vegetation, water, skin, and the neutral grey/black value anchors. Explicitly *not*
  faction colours; those are per-pack.
- **Core material set** — the thirty materials in `MATERIAL-SPEC` §5, spanning ancient to
  modern, each carrying its own default colours. This is content as much as it is system:
  it's the substrate every pack is made of, and it's why a stone wall in a medieval mod
  behaves like a stone wall in the Great War pack.
- **Core soldier body** — the 15-part frame with no headgear, no webbing, no faction
  colour. Packs attach headgear + kit + faction colour. This is why silhouette
  readability can be guaranteed globally: the body is always the same body.
- **Core props** — crate, barrel, plank, post, sandbag, stake, ladder, wheel, rope coil,
  rubble chunk, corpse-brick. The generic set every era's world is dressed with.
- **Core structural kit** — wall segment, floor/roof slab, doorway frame, stair, arch,
  column. Packs and map authors compose buildings from these.
- **Core VFX** — explosion, dust, smoke, fire, dirt fountain, water splash, muzzle flash,
  tracer, impact chips, blood/brick-burst. Packs tune scale and colour, don't author new.
- **Core audio set** — footsteps by surface, dig 3-stage, impact/ricochet, debris,
  brick collapse, water, wind bed. Packs supply weapon and vehicle voices only.
- **Core animation poses** — a default pose for every state, so a pack that ships a new
  weapon with no animation data still looks correct rather than T-posing.

The line: **core art is materials, bodies, and physics-facing objects. Pack art is
identity — what era it is and whose side you're on.**

## 4 · What a pack owns

An era pack (and therefore any mod) is a manifest plus data:

```
pack/
  pack.json          name, era, version, dependencies, core version required
  palette.json       faction colours (2 + 2 shadows) + era material additions
  weapons/           part tables + stats + timings, filling core archetype slots
  vehicles/          part tables + physics params + seats, filling core slots
  buildables/        part tables + costs, filling core buildable archetypes
  kits/              classes: which slots each role gets
  style.json         sky, sun, fog, tonemap, ambience bed (per ART-BIBLE §9)
  audio/             weapon and vehicle voices only
  maps/              earth grid + placements + objectives
  modes/             mode parameter sets (phase timings, win conditions)
  strings/           names and localisation
```

Everything above is **data**. No pack ships executable code in v1 — see §5.

## 5 · What a pack cannot do

These constraints are what keep the core shippable, the netcode viable, and the
workshop safe. They are load-bearing:

- **No new verbs.** The interaction vocabulary is fixed.
- **No new player animation states.** Only poses and timings for existing ones.
  *Rigs are exempt*: a pack may declare any part hierarchy, joint layout and gait it
  likes, because the core's solvers drive them (`RIG-SPEC` §8).
- **No new joint or constraint types**, and physical joints stay inside the per-object
  and per-scene budgets the validator enforces (`RIG-SPEC` §2, §9).
- **No new physics.** Packs set parameters within core-defined ranges.
- **No new materials from nothing.** A pack derives one via `extends` on a core material,
  clamped to ×0.5–×2.0 per property, inheriting `class`, `failure` and `hardness`
  (`MATERIAL-SPEC` §8). Identity is a pack's to define; durability is not. Without this
  rule the first weekend of workshop uploads produces indestructible walls.
- **No extending outside a declared dependency.** Cross-pack `extends` is allowed and
  encouraged (`FORMAT-SPEC` §6), but a pack must name what it depends on with a semver
  range. Reaching into a pack that happens to be loaded is an error, not luck. A pack
  whose dependencies aren't satisfiable is disabled and reported — never half-loaded.
- **No new core systems.** A pack cannot add a game system; it configures existing ones.
- **No colours outside the palette law** (ART-BIBLE §2 value/saturation bounds).
- **No executable code in v1.** Data only. Scripting is a later, sandboxed decision
  (checklist §19) and it gates on the mod security model, which gates on the hosting
  model. Don't let this slip in accidentally.
- **No pack shaders, and this one doesn't expire with v1.** A shader is executable code on
  the GPU, but the disqualifying reason is competitive rather than architectural: *a shader
  that disables depth testing is a wallhack*, and in a game built on digging in and
  attacking unseen, seeing through terrain deletes the premise. No review process survives
  that at workshop scale. Packs get **parameterised style instead** — a widened
  `style.json` covering grading, fog, sun, bloom and a bounded set of named post effects
  (`ART-BIBLE` §8b). An effect the parameters can't reach is a core change request, exactly
  like a new verb.
- **Texture packs are cosmetic and material-scoped.** A skin overrides a core material's
  greyscale detail map within a fixed resolution and tiling budget; it never replaces
  palette colour and never touches density, hardness, support or flammability. Because
  everything resolves through materials, skinning the thirty core materials skins the whole
  game — including packs that don't exist yet.
- **No client-authoritative gameplay values** once netcode lands — the server owns the
  numbers regardless of what a client's pack says.

Every one of these is a "we said no early so we didn't have to say no painfully later."

## 6 · The reference pack, and the canary

The core can't be tested in a vacuum — you need *something* loaded to play it. Two
things fill that role:

**GREAT WAR = the reference pack.** Everything already built (trenches, bolt-action,
shovel, tank, biplane, artillery) gets refactored *in place* into pack form. None of
that work is thrown away, and craft passes on it continue — polishing real content is
exactly how we discover what the core needs to expose. It is simultaneously the first
shipping era and the core's test harness.

**TESTPACK = the canary.** A deliberately tiny, deliberately alien pack: a bow, a
catapult, a shield, a stone wall, one faction colour. Four items, an afternoon's work.
Its only job is to **fail loudly the moment the core assumes gunpowder.** It runs in CI
alongside the headless autotest. If TESTPACK loads and plays, the pack format is real;
if it needs a core patch, we found a hardcoded assumption for the price of a day
instead of a month.

This is the cheap version of the medieval test, available from week one.

## 7 · The core gate

Era content production does not begin until every one of these is true:

- [ ] Every **Part II** checklist item signed off (the core systems)
- [ ] The game is fully playable — spawn, move, fight, dig, build, drive, win a siege —
      using only the reference pack
- [ ] **TESTPACK loads and plays with zero core code changes**
- [ ] The de-hardcode audit is closed: no era-specific branch anywhere in core
- [ ] Core content set complete and art-bible compliant
- [ ] Animation timing table locked and every core state has a default pose
- [ ] 32-player netcode milestone hit on the reference pack
- [ ] Headless autotest + screenshot regression green in CI, including TESTPACK

Then, and only then, eras become a content pipeline instead of a research project —
and each new era costs weeks instead of months.
