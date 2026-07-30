# BRICK WARS — Master Checklist (now → release)

**How we use this:** one item at a time. I build it → you playtest it → it only gets
checked when you say it *feels* right. Statuses: `[x]` shipped & signed off ·
`[~]` in the game but rough (needs your feel-pass) · `[ ]` not started.

**The order of operations** (this file is structured to enforce it):

> **PART I** standards → **PART II** the core game, era-neutral and complete →
> **PART III** the core gate → **PART IV** era packs as pure content →
> **PART V** platform, process, ship.

No era content gets designed or built until Part III passes. Existing Great War work
isn't lost — it becomes the reference pack and stays in polish, because polishing real
content is how we find out what the core must expose (`CORE-SPEC.md` §6).

**Standards:** `VISION.md` (what the game is) · `CORE-SPEC.md` (core/pack boundary) ·
`RIG-SPEC.md` (joints, IK, gaits) · `ART-BIBLE.md` (visual law) · `PRODUCTION.md`
(quality bar & pass order).

---

# PART I — FOUNDATIONS & STANDARDS

## 0 · Standards & specs ← *nothing else starts until these exist*

- [x] Production discipline (quality bar chain, pass order, definition of done)
- [x] Vision & era thesis
- [x] **Core/pack boundary spec** (what's core, what's pack, what packs cannot do)
- [x] **Art bible** (module system, palette law, silhouette, budgets, materials, gate)
- [ ] **Audio direction doc** (procedural vs recorded, distance-mix philosophy,
      core-vs-pack audio split, loudness targets)
- [ ] **Animation style guide** (state list, timing table, weight/anticipation
      conventions, FP↔TP parity rules, pack pose-data format)
- [x] **Part-table asset format** spec (`FORMAT-SPEC.md` — this *is* the mod format)
      — **all four decisions closed 30 Jul**: JSON · integer modules · `pack:asset` ids ·
      `extends` with full cross-pack reach, depth capped at 3 (`FORMAT-SPEC` §12)
- [x] **Material spec** (`MATERIAL-SPEC.md` — properties, the 30-material set, damage
      types, hardness tiers, support/cohesion/repose, fire)
- [x] **Earth spec** (`EARTH-SPEC.md` — 0.5 m column-span field, continuous height,
      slope-dependent meshing, repose settling, tunnels, event log)
- [~] **Primitive set implemented**: block · wedge · corner wedge · cylinder · sphere
      (ART-BIBLE §1b) — meshes ✓, module-snapped sizing ✓, collider policy ✓ (round two
      analytic, wedges as hulls so a ramp is a ramp), shatter-to-blocks dormant until C5.
      The wedges are hand-built and fix their own winding against the solid's centroid
      rather than trusting a face table — and the engine's winding convention is now
      measured in the suite rather than remembered
- [~] Primitive compliance check in review (70/30 block ratio; the three-tier law holds —
      earth continuous, built things 100% blocks, machines blocks + primitives) — the 70/30
      ratio, the closed five-primitive list and the four-collider cap are machine-checked as
      of the validator; the three-tier law still needs a pair of eyes, because "built things
      are 100% blocks" is a statement about intent that no rule can read off a part table
- [x] **Pack manifest format** spec (`pack.json` and the folder contract — `FORMAT-SPEC` §9)
- [x] **Blast feel fixture harness built** (`blast-fixture/`) — 8 seeded scenarios, impulse
      / wake / shake / knock / earth / settle / scatter + tick timeline + screenshot
      sequence, with a comparison tool that exits non-zero when the feel drifts
- [x] **Fixture hardened against input contamination** (v2) — the first Mac capture was
      spoiled by a single click in the window putting a rifle round into the test wall
      (peak 112 m/s instead of 11) and nothing in the output said so. The run now gags the
      mouse, kills anything fired in the tick it spawns, counts it, writes `"clean": false`
      and exits 3; the comparison tool refuses a contaminated file. A baseline that can be
      changed by touching the window was never a baseline
- [x] **Blast baseline captured on the Mac** — 30 Jul, clean, `fixture_version 2`, Godot
      4.7.1 on the M4, zero strays, 110 frames. Lives at
      `blast-fixture/reference/macos-20260729/`. **This is the authoritative one** — the
      Linux file is now only a curiosity. Against it, 132 of 134 metrics matched inside
      tolerance across two Godot versions and two CPU architectures; the two that didn't
      were `pile_standard_shell` settle time (+13.8%) and max displacement (+10.1%), the
      loose-heap scenario, which is the most chaotic of the eight and the only one that
      ever drifted. Mac-to-Mac is what gates the rebuild from here
- [x] **Flipbook capture fixed** — three frame pairs in the Mac capture came back
      byte-identical because vsync pinned rendering to the same rate as physics, so the
      screenshot half of the baseline was running at half rate through the front-loaded
      window. Vsync is now off, and duplicates are counted as `duplicate_frames` if they
      recur. Pixels only — the numbers were never affected, which is why `fixture_version`
      stays at 2 and the captured baseline stays valid
- [x] **Rig spec** (kinematic vs physical joints, IK, gait engine, ragdoll, budgets)
- [ ] Design doc updated from WW1-specific to core-first (supersede DESIGN-WESTERN-FRONT)

---

# PART II — THE CORE GAME

*Everything here is era-neutral. If an item smells like a specific weapon, vehicle, or
period, it belongs in Part IV.*

## 1 · Pack architecture & mod loading

- [x] Palette as core data (`core/data/palette.json`) — authored fresh rather than lifted out
      of `main.gd`, since the old build is archived; six colours carry a written exemption
- [ ] Part tables extracted from build code into data files
- [x] Materials as core data (`core/data/materials.json`), loaded before anything else — 33
      of them, not the 30 MATERIAL-SPEC §5 says in its first line
- [x] Pack loader: read manifest, validate, register content
- [x] Pack validation + clear failure messages (a broken pack must say why) — every message
      carries the file, the line, the offending value and the rule it broke, and the file is
      the one that *wrote* the value rather than the one being validated
- [~] **Material validation**: named references only ✓, `material` required on every part ✓,
      colour must be in the material's colour set ✓ — `extends` multipliers clamped ×0.5–×2.0
      and `class` / `failure` / `hardness` not overridable are declared dormant and reported
      at boot, because both need the pack-material resolver (MATERIAL-SPEC §8) (`FORMAT-SPEC` §10)
- [x] Archetype slot registry (weapons, vehicles, buildables, classes) — `core/data/slots.json`,
      27 era-neutral slots with their required stats, plus `core/data/budgets.json` for the
      part counts. **First cut, mine — worth your eye once weapons are actually in the game**
- [ ] **De-hardcode audit**: no era-specific branch anywhere in core
- [ ] Hot-reload packs in editor (creator workflow, and it speeds up our own work)
- [ ] Pack versioning + core-compatibility checking
- [ ] Naming convention enforced across all assets (`era_class_name`)

Inheritance (`FORMAT-SPEC` §6, decided 30 Jul — full cross-pack, depth 3):

- [x] `extends` resolver: scalar replace, object deep-merge, list replace, `parts+` append,
      `parts~` patch-by-name
- [x] Chain depth cap of 3 enforced, error names the whole chain
- [x] **Semver dependency declaration** required for any cross-pack `extends` — except into
      `core`, which every pack already declares via `core_version` (30 Jul)
- [x] **Deterministic load order**: topological sort of the dependency graph, tie-broken by
      pack id — must be byte-identical on every client, netcode depends on it. `core` is a
      pack like any other and holds an implicit edge to all of them, so it always sorts first
- [x] Cycle detection across packs and within one, error names both ends
- [x] Resolution happens once at load and is baked; nothing resolves at runtime
- [x] **Pack-scoped failure**: a broken or unsatisfiable pack is disabled and reported,
      never half-loaded, never fatal to the game or to other packs — refusal runs in passes,
      because disabling a pack can invalidate an asset in one that extended it
- [ ] **Validator `--resolve <asset_id>`**: prints the fully merged asset with per-field
      provenance. Ships *with* the resolver, not after it — without it `extends` is a trap
- [ ] Modding doc note: pack ids are claimed, pick a distinctive one; an asset others
      extend is public surface and changing it is a breaking change

## 2 · Soldier: locomotion & body

- [ ] Walk / sprint speeds & acceleration feel — **retuned from scratch**, not ported
      (BUILD-ORDER §1b; the old WALK 12 / SPRINT 22 were set early and never revisited,
      and locomotion now has to feel right alongside foot planting and mounts)
- [ ] Jump (height, gravity, air control) — same, retuned
- [ ] Explosion knockback
- [ ] Mantle / vault (against real terrain slope and trench walls, not a fixed step height)
- [ ] Crouch (lower profile, slower move)
- [ ] Prone (crater/parapet play, weapon rested)
- [ ] Landing thump + camera dip
- [ ] Fall damage (or decide: none, arcade)
- [ ] Stamina (sprint limit — yes/no decision)
- [ ] Swimming / wading (currently you walk on the riverbed)
- [ ] Carry weight (hauling cargo slows you — logistics hook)
- [ ] Health / damage / death / respawn loop (currently immortal)
- [ ] Damage model decision: health bar vs hit-location vs one-shot
- [ ] Downed / revive decision (Squad-like medic loop — affects everything downstream)
- [ ] Ragdoll or brick-burst death
- [ ] Environmental hazard framework (gas, fire, drowning — one system, packs configure)
- [ ] Character customisation scope decision (the Roblox audience expects some)

## 3 · Combat core

- [ ] Projectile ballistics: velocity, drop, travel time, penetration
- [ ] Hitscan vs projectile policy per archetype
- [ ] Melee resolution: reach, arc, timing, blocking (needed from ancient/medieval)
- [ ] Damage model: falloff, area-effect, cover/penetration through bricks
- [ ] Hit registration + feedback contract (what the shooter sees on a hit)
- [ ] Recoil/spread system (packs supply curves, core owns the maths)
- [ ] Ammo/magazine/reload system (packs supply counts and timings)
- [ ] Weapon-switching core (raise/lower, sprint-carry, per-slot timings)
- [ ] Aim-down-sights core (FOV, sway, sensitivity scaling, sight alignment)

## 4 · Interaction verbs & tool core

*The fixed vocabulary. Packs fill slots; packs never add verbs (`CORE-SPEC` §5).*

- [~] FIRE · THROW · DIG · BUILD (working, need core-ification)
- [ ] MELEE
- [ ] ENTER / EXIT / MAN
- [ ] CARRY (pick up, haul, drop — logistics and spoil both need it)
- [ ] INTERACT (doors, ladders, switches, resupply)
- [ ] SIGNAL (whistle/horn/flare — the assault cue, era-neutral)
- [ ] Weapon archetype slots defined: ranged-slow · ranged-fast · emplaced/support ·
      sidearm · melee · thrown · signalling · optics · utility · entrenching
- [ ] Tool/weapon slot loadout system (classes pick slots, packs fill them)

## 5 · The Earth (the keystone)

> **Rebuilt, not ported** (`EARTH-SPEC.md`, `BUILD-ORDER` §1d). The 2.5 m × 0.8 m block
> grid is gone — a single cell was wider and taller than a soldier, which is why it read
> as chunky rectangles. Replaced by a 0.5 m column-span field with continuous
> centimetre-quantised height.

- [ ] 0.5 m column-span field, `i16` centimetre heights, chunk-relative
- [ ] Multi-span columns (max 4) — the structure tunnels need, in from day one
- [ ] Chunked slope-dependent meshing: smooth normals below 60°, vertical skirts above
      (organic ground *and* crisp trench walls from one mesher)
- [ ] Per-vertex `SHADES` variation across terrain (`ART-BIBLE` §6b)
- [ ] Chunked Jolt heightfield collision, rebuilt with the mesh
- [ ] Whole playable area diggable (400–800 m per side), full-resolution everywhere
- [ ] **Angle-of-repose settle queue** — event-driven, integer, budgeted, deterministic
- [ ] Shoring / revetment sets a local repose override; removing it wakes the queue
- [ ] Wet-ground repose multiplier (rain, water table, shelling → mud at 15°)
- [ ] Conservation of volume: digging produces spoil, spoil has to go somewhere
- [ ] Crater lips built from displaced spoil (~70% conserved, rest airborne)
- [ ] `disturbed` flag on spans (repose −15°, cohesion ×0.4, support ×0.6)
- [ ] Spoil as physical carriable material (not just a counter)
- [ ] Every span carries a core material — there is no separate soil-type system
      (`MATERIAL-SPEC` §5): dig speed, stability, repose and cut-face strata all fall out
- [ ] Build *upward*: earth piled against a wall (siege ramps — tests build direction)
- [ ] TUNNELS via span splitting: dig into a face, not just downward
- [ ] Tunnel roof support against material `support_vertical` + overburden
- [ ] Tunnel timbering (place props or the span collapses)
- [ ] Tunnel collapse (cave-in, buries, **surface subsides visibly above it**)
- [ ] Mine chambers: pack explosive, wire, blow
- [ ] Counter-mining: hear enemy digging (listening posts)
- [ ] Camouflet charges (collapse enemy tunnels without surface break)
- [ ] Water table: deep digs flood (pumps? design decision)
- [ ] Persistence at scale (1000+ modified columns: perf + save)
- [ ] Earth event log formalised (this is the netcode foundation — §17)

## 6 · Buildable core

- [~] Placement from spoil (rough: places a dirt column, not an object)
- [ ] Buildable archetype slots: barrier · overhead cover · elevated firing position ·
      obstacle · span/bridge · shelter · emplacement mount
- [ ] Placement preview ghost (green/red validity)
- [ ] Build/repair timing + interruption rules
- [ ] Materiel cost system (builds consume delivered materials)
- [ ] Buildables take damage and can be repaired (not just shatter)
- [ ] Snapping/alignment rules so player-built structures read as intentional
- [ ] Radial/quick-select build menu

## 7 · Vehicle core

> **Rebuilt, not ported** (BUILD-ORDER §1b). The prototype's handling was never signed
> off — the verdict was *"the turn radius is shit on a lot of the vehicles"* — and the
> model predates spring suspension, IK hands-on-controls and `legged` locomotion. It
> starts again, in this order: mass distribution → suspension → handling.

- [ ] Honest mass distribution across the compound collider (**no low-COM hack**)
- [ ] Spring suspension as a real physical constraint, with visible travel
- [ ] Ground locomotion (forces, traction, weight transfer) — built on the two above
- [ ] **Turn radius and steering feel — explicit sign-off, wheeled and tracked**
- [ ] Air locomotion (takeoff, aim-steered flight, dive) — retuned per archetype slot,
      not per aircraft
- [ ] Water locomotion + buoyancy — the old submersion sampling was a stub
- [ ] Mounted weapons fire while moving, with recoil + shake
- [ ] Vehicle archetype slots: armoured breakthrough · fast transport · air · water ·
      siege engine · emplacement
- [ ] Multi-crew seats (driver + gunner + passengers — the Squad-scale hook)
- [ ] Seated soldier visible, hands on controls (IK or posed)
- [ ] Smooth enter/exit animation (lerp to seat, hatch/door moment)
- [ ] Turret/barrel visually tracks aim (currently guns fire off-axis)
- [ ] Damage states short of shatter (smoke → fire → boom)
- [ ] Subsystem damage (mobility kill vs firepower kill vs destroyed)
- [ ] Terrain interaction: bogging in craters/mud, crushing obstacles
- [ ] Engine/movement audio loop framework (packs supply the voice)
- [ ] Indirect-fire system (map coordinates + observer spotting, not line-of-sight)
- [ ] Vehicle respawn/delivery rules for the siege loop
- [ ] Stall/spin behaviour for aircraft at low speed
- [ ] Landing gear feel, rearm/refuel at a base

## 8 · Destruction & physics

> **Materials drive all of this** (`MATERIAL-SPEC.md`). There is no global destruction
> rule and no hit-point number on anything — what happens to a thing is decided by what
> it's made of. The blast model is the one exception, and it's protected: the existing
> feel is the specification (§1e fixture, `BUILD-ORDER`).

- [x] Brick world: rigid bodies, Jolt, sleeps at zero cost
- [x] Blast system (radius, falloff, wake-column, shatter vs shove) — **KEEP, protected**
- [x] **Blast feel fixture harness** built and verified against the archive (`blast-fixture/`).
      Six of its eight scenarios are bit-identical run to run; the two that fire on the live
      earth field are held to loose tolerances on purpose and exist to catch "the crater
      stopped happening", not to police decimals. `wake.peak_awake` is ungated in the world
      scenarios — measured 16 to 49 on an unchanged build, which no percentage straddles
      usefully; `earth.height_cells_removed` carries that job instead and must match exactly
- [x] **Blast baseline captured on the Mac** — done 30 Jul, clean run, stored at
      `blast-fixture/reference/macos-20260729/`. Every comparison from here compares
      against that file on that machine
- [~] Blast fixture wired into CI as a standing regression test — `compare_baselines.py`
      already exits non-zero on drift, so this is a CI job, not a research problem.
      Proven to fail 34 metrics on a 12% impulse change, which is a difference you might
      not notice playing and would definitely regret shipping. The CI job must treat exit 3
      (contaminated run) as a failure to re-run, not as drift to investigate.
      **Slot is wired, check is dormant** (30 Jul): `tools/check.sh` step 4 holds the place
      and prints `skip — dormant until C5` on every run, because the rebuild has no blast
      in it yet to compare. It turns on the moment C5 restores one. Announcing it every run
      is deliberate — a dormant check that stays quiet is one nobody remembers to enable
- [~] Debris behaviour (damping/settle — watch big collapses)

Material behaviour:

- [ ] Six damage types resolved separately: `kinetic` · `blast` · `crushing` · `cutting` ·
      `fire` · `dig`
- [ ] Per-class resistance table + per-material overrides (`MATERIAL-SPEC` §3)
- [ ] Failure modes distinct and readable: `shatter` · `crumble` · `splinter` · `tear` ·
      `deform` · `burn`
- [ ] Spall: hard materials throw fragments on the far face; soft ones don't
- [ ] Integrity accumulates per damage type — a wall shrugs off rifle fire and falls to a charge
- [ ] Small-arms destruction tuning (a shot chips a single brick believably)

Tool gating:

- [ ] Hardness tiers 0–5 on every material, `tool_power` on every tool
- [ ] Tool works material only where `tool_power >= hardness`
- [ ] **A tool that can't do the job says so** — named feedback, never a silent no-op
- [ ] `work_rate` scales dig/cut speed per material

Fire:

- [ ] Ignition, spread, burn-through, extinguish (medieval needs it, all eras use it)
- [ ] Propagation driven by `flammability`, not by object type
- [ ] `on_burnt` state transitions (`timber` → `charred_timber`, support 70 → 20)
- [ ] Wet / rain / water suppresses ignition and spread

Structural integrity:

- [ ] Structural integrity as a **load calculation** against `support_vertical`,
      `support_lateral` and `cohesion` — not a global "unsupported things fall" rule
- [ ] Low-cohesion stacks topple as units; high-cohesion mass slumps (the sandbag rule)
- [ ] Unsupported structures collapse in order (roofs after walls)
- [ ] Load propagates through the earth too — a tunnel roof carries its overburden
- [ ] Primitives shatter into blocks (curves don't survive destruction)

- [ ] Debris cleanup policy (fade vs persist — perf vs consequence)
- [ ] Destruction budget under 100v100 load
- [ ] **Acceptance test — the medieval mining loop** (`MATERIAL-SPEC` §6): dig a tunnel,
      prop it with timber, burn the props, watch the wall above come down — with **no code
      written for any of those steps.** This is to materials what the horse test is to rigs.

## 9 · AI core

- [ ] Soldier AI: aims, fires, takes cover, dies into bricks
- [ ] Cover use: parapet peek, duck on fire
- [ ] Garrison behaviour (man positions, walls, firing steps)
- [ ] Assault wave behaviour (advance through broken ground)
- [ ] Sapper AI (they dig too — repairs, counter-saps)
- [ ] Melee AI (required for ancient/medieval)
- [ ] Squad/officer AI + signal-triggered waves
- [ ] Friendly AI (your side fills the line — 100v100 *feel* before netcode)
- [ ] Bot fill for multiplayer (Roblox-audience essential: never an empty server)
- [ ] Difficulty/accuracy parameters exposed to packs (period-appropriate, not aimbots)
- [ ] Performance: 100+ active AI budget (LOD their thinking by distance)

## 10 · Game modes & the siege loop

- [ ] **SIEGE**: sector control, who holds what, front-line state
- [ ] Phase system: quiet → bombardment → assault → consolidation
- [ ] Win conditions: push the line / morale collapse
- [ ] Respawn waves + rear spawn, walk/ride up (death has geography)
- [ ] Consolidation: reverse a captured position / repair a breach
- [ ] Scripted barrage event (advance behind a creeping bombardment)
- [ ] Match length/pacing tuning (one siege = 20–40 min?)
- [ ] **SANDBOX**: no objectives, all tools (the Teardown/Roblox on-ramp; where big
      group events and mod showcases live)
- [ ] **SKIRMISH**: small, quick, bot-filled (the casual entry point)
- [ ] Mode parameters exposed as data (so packs ship modes, not just maps)

## 11 · Logistics core

- [ ] Class/role system: which slots each role gets (roles era-neutral, kits per pack)
- [ ] Supply points & resupply interaction
- [ ] Cargo: physical objects that are loaded, carried, delivered
- [ ] Consumption: siege engines and builds draw on delivered supply
- [ ] Supply starvation is felt (cut the road, the guns go quiet — the design promise)
- [ ] Squad system (join/create, markers)
- [ ] Command layer decision: Squad-style hierarchy vs Roblox-style free-for-all

## 12 · Animation core

*Blocked on the animation style guide (§0).*

- [~] FP viewmodel rig (sway, bob, kick, raise, ADS, cycle, reload, throw)
- [~] TP body animation (walk cycle + fire/dig/throw poses)
- [ ] **Canonical state list locked** (packs supply poses, never new states)
- [ ] **Timing table locked** (durations per action, so eras stay consistent)
- [ ] Default pose for every state (a pack with no anim data must still look right)
- [ ] FP↔TP parity audit (every FP state has a matching TP pose)
- [ ] Melee swing set
- [ ] Mantle/vault, crouch/prone transitions
- [ ] Enter/exit vehicle, seated poses
- [ ] Death/ragdoll transition
- [ ] Pack pose-data format + a pose authoring path

## 12b · Rigs, joints & IK

*Spec: `RIG-SPEC.md`. Acceptance criterion for the whole section is the **horse test**:
a modder adds an articulated, ridable, ragdolling horse in data alone.*

- [ ] Part hierarchy + parent/joint fields in the part-table format
- [ ] Kinematic joint types: fixed · hinge · ball · slider (with mandatory limits)
- [ ] **Two-bone IK solver** (serves legs, hands-on-controls, foot planting — build once)
- [ ] Foot planting against the live earth grid (our ground moves; this is load-bearing)
- [ ] Passive follow segments (the fetlock trick — cheap, sells the silhouette)
- [ ] **Procedural gait engine**: phase-driven steps, gait blending by speed, body
      bob/pitch/lean, turn-in-place
- [ ] `legged` locomotion type wired into the vehicle core (a horse is a fast transport)
- [ ] Mount/ride/dismount as the existing enter/exit verb (no new verb)
- [ ] Physical constraints: hinge · slider · ball · spring · motor · distance/rope
- [ ] Constraint budgets + pack validation with clear failure messages
- [ ] Ragdoll conversion (kinematic → physical on death, limits carried over)
- [ ] Ragdolls are local-only, lifetime-capped, and decay into blocks
- [ ] Rig replication format (root transform + gait phase + driver floats)
- [ ] Retrofit: soldier limbs and turret traverse onto the rig system
- [ ] Vehicle suspension via spring constraints (visible wheel travel)
- [ ] **Horse test passes** — the gate item

## 13 · Camera, UI & input core

- [~] FP/TP camera, ADS, shake, FOV rules
- [~] Debug HUD — replace entirely
- [ ] HUD framework: ammo, health, stamina, crosshair states, hitmarkers
- [ ] Kill/event feed
- [ ] Sector map (front line, objectives, fire-mission UI)
- [ ] Class/spawn select, era & mode select
- [ ] Main menu, settings, pause, scoreboard
- [ ] Server browser + party/invite flow
- [ ] HUD theming hooks (packs restyle, don't rebuild)
- [ ] Onboarding: teach dig/build/vehicles in under two minutes
- [ ] **Control philosophy lock**: Roblox-simple, one key per verb, no modifier combos
- [ ] Full rebindable keys, invert-Y, sensitivity + ADS multiplier, FOV slider
- [ ] Gamepad support at full parity (console + accessibility)
- [ ] Touch controls decision (the Roblox audience is literally on mobile — in or out?)
- [ ] Aim assist policy for gamepad/touch
- [ ] Colourblind modes (faction colour is load-bearing — this is a real problem)
- [ ] Captions for gameplay-critical audio (the incoming-shell cue especially)
- [ ] Motion-sickness options (shake/sway/bob toggles)
- [ ] Photosensitivity: flash/strobe intensity limits (barrages are a genuine risk)
- [ ] Text scaling & high-contrast HUD

## 14 · Audio core

*Blocked on the audio direction doc (§0).*

- [~] Procedural gunshot + boom (placeholder)
- [ ] **Direction decision**: procedural vs recorded (blocks everything below)
- [ ] Distance mixing: far rumble vs close snaps (THE war soundscape)
- [ ] Occlusion/reverb zones: enclosed vs open vs underground
- [ ] Incoming-projectile warning cue system (gameplay-relevant, not flavour)
- [ ] Footsteps by surface
- [ ] Dig 3-stage set (thunk-scrape-scatter)
- [ ] Impact/ricochet/debris/collapse set
- [ ] Ambient bed framework (packs supply the bed)
- [ ] Vehicle engine loop framework
- [ ] UI sound set
- [ ] Music: theme + sparse stingers, or diegetic-only decision
- [ ] Voice chat: proximity vs squad vs none (design + moderation decision)

## 15 · VFX core

- [~] Explosions (fireball, smoke, lingering dust, light flash)
- [~] Muzzle flashes, tracers
- [ ] Explosion scaling by charge size (pop vs earthquake — one system, parameterised)
- [ ] Dirt fountain columns for earth impacts
- [ ] Smoke screens (drifting, vision-blocking)
- [ ] Fire & burning propagation VFX
- [ ] Gas/cloud volume system (hugs low ground)
- [ ] Dynamic light events (flares, torches, fire — flickering shadows)
- [ ] Weather particles (rain, wind-blown dust)
- [ ] Hit feedback (brick chips — tone per ART-BIBLE §9)
- [ ] Scorch/crater decal quality
- [ ] VFX performance budget at barrage scale

## 16 · Core content set (the shared substrate)

*The art the engine ships so packs and mods start from something, not nothing
(`CORE-SPEC` §3).*

- [ ] **Core palette** finalised: earth, clay, stone, wood, metal, gunmetal, canvas,
      rope, leather, vegetation, water, skin, neutral values — no faction colours
- [ ] **Core material set**: the thirty materials of `MATERIAL-SPEC` §5, ancient → modern,
      each with its density, hardness, support/cohesion, repose, flammability, failure mode
      and default colour set. Content as much as system — it's the substrate every pack is
      made of, and why a stone wall in a medieval mod behaves like one in the Great War pack
- [ ] Every core material's numbers checked against each other, not just in isolation
      (the whole point is the *relative* feel: brick vs cloth, packed earth vs sandbags)
- [ ] **Core soldier body**: 15-part frame, no headgear, no kit, no faction colour
- [ ] **Core props**: crate, barrel, plank, post, sandbag, stake, ladder, wheel,
      rope coil, rubble chunk
- [ ] **Core structural kit**: wall segment, floor/roof slab, doorway, stair, arch, column
- [ ] Core VFX set complete (§15) and parameterised for packs
- [ ] Core audio set complete (§14)
- [ ] Core default animation poses (§12)
- [ ] Water material pass (flow, reflections within budget)
- [ ] **Texture decision**: flat colour vs subtle per-material noise — prototype both
      on one scene, pick, write it into the bible (ART-BIBLE §8). Upstream of texture packs:
      if flat wins there's nothing to skin
- [ ] Optional detail-map slot reserved on the material schema at C1, filled at C3 or never
      — nearly free to leave open, expensive to retrofit through 30 materials
- [ ] **Texture-pack support** (ART-BIBLE §8b): skins override a core material's greyscale
      detail map, resolution and tiling capped, palette colour untouched, physical
      properties untouchable, client-side cosmetic only
- [ ] **Widened `style.json`** as the answer to shaders: grading, fog curves, sun angle and
      warmth, bloom, vignette, bounded named post effects — enough range that a gas-lit 1917
      dawn and a bright Bronze Age afternoon are both reachable without GPU code
- [ ] **No pack shaders** enforced by the loader, not by review (`CORE-SPEC` §5) — a
      depth-test-off shader is a wallhack and this game is about hiding in the ground
- [ ] Guard against a custom shader becoming load-bearing during C3 water/smoke work
- [ ] Retrofit audit: existing assets brought up to art-bible compliance

## 17 · Netcode core (the 100v100 ladder)

- [ ] Refactor: split `main.gd` into modules/scenes (pre-net cleanliness)
- [ ] Earth events as a serialized deterministic log
- [ ] Godot high-level multiplayer prototype: 2–4 players LAN vs AI
- [ ] Authority model: server-authoritative near players, cosmetic debris client-side
- [ ] Interest management (relevance radius, nearest-K)
- [ ] Grid-event encoding (2-byte indices — harness validated)
- [ ] Late-join sync via event-log replay
- [ ] 32-player playtest milestone
- [ ] Dedicated server build (headless Godot — we run headless daily already)
- [ ] 100v100 stress test with bots (the big promise, measured)
- [ ] Cross-platform play + account/identity model
- [ ] Anti-cheat / server validation scope
- [ ] **Hosting model decision**: community-hosted (mod-friendly) vs official — this
      determines the entire mod security story, decide before §22

---

# PART III — THE CORE GATE

## 18 · Gate: is the core solid?

*No era content is designed or built until every line below is true.*

- [ ] Every Part II item signed off
- [ ] Fully playable end-to-end — spawn, move, fight, dig, build, drive, win a siege —
      using only the reference pack
- [ ] **TESTPACK loads and plays with zero core code changes**
- [ ] **The horse test passes** (`RIG-SPEC` §1) — articulated, ridable, ragdolling
      quadruped added in data alone
- [ ] **The medieval mining loop passes** (`MATERIAL-SPEC` §6) — tunnel, props, fire,
      charred timber, collapse, subsidence, wall down, with no code written for any step
- [ ] **The blast feel fixture still matches** (`BUILD-ORDER` §1e) — the thing that felt
      good in the prototype still feels good after everything under it was rebuilt
- [ ] De-hardcode audit closed
- [ ] Core content set complete and art-bible compliant
- [ ] Animation state list + timing table locked; default pose for every state
- [ ] 32-player netcode milestone hit
- [ ] Headless autotest + screenshot regression green in CI, including TESTPACK
- [ ] Marissa's sign-off: the core *feels* like a game, not a toolkit

---

# PART IV — ERA PACKS (content, once the gate passes)

## 19 · Reference pack: GREAT WAR

*Already built; refactored into pack form and kept in polish throughout Part II because
it's how we test the core.*

- [~] Bolt-action rifle (viewmodel, cycle, recoil, ADS) — needs iron sights, reload, bayonet
- [~] Rocket/AT launcher — decide: AT rifle or trench mortar
- [~] Grenades — arc line style, cook timer, smoke + gas variants
- [~] Entrenching shovel — 3-stage sound, follow-through swing, melee use
- [ ] MG (emplaced on parapet, not hip-fired)
- [ ] Sidearm, flare pistol, trench club, wire cutters, binoculars, whistle
- [~] Tank — rhomboid redesign, trench-crossing, wire crushing, sponson guns, interior
- [~] Jeep — split into armoured car + supply truck, visible spinning/steering wheels
- [~] Biplane — bombs, recon photography, spinning prop, engine drone
- [~] Boat — purpose pass (river crossing), period launch silhouette
- [~] Emplacements: turret / AA / artillery — crew loop, flak bursts, gunner poses
- [ ] Buildables: sandbag wall, duckboard, ladder, firing step, revetment, wire, dugout,
      MG nest, periscope
- [ ] Gas mechanic + mask
- [ ] Soldier kit: uniforms, webbing, puttees, distinct class silhouettes
- [ ] Faction identity: allied drab vs field grey, helmet profiles
- [ ] Era style sheet (sky, sun, fog, ambience, tone statement — ART-BIBLE §9)
- [~] Western Front map v1 — balance pass, boundaries, skybox, ambient life
- [ ] Second map (village fight or river crossing)
- [ ] Night variant + flares; rain/mud variant
- [ ] Prop set: ammo boxes, stretchers, crates, telegraph poles, shrines

## 20 · TESTPACK (the canary)

- [ ] Four items — bow, catapult, shield, stone wall — plus one faction colour
- [ ] Loads and plays with zero core changes
- [ ] Wired into CI next to the headless autotest
- [ ] Any core patch it demands is logged as a boundary-spec bug

## 21 · Era production pipeline

- [ ] **Era 2: MEDIEVAL** — the real proof (no firearms at all: bows, trebuchets, siege
      towers, undermining walls, fire). If this needs core changes, the boundary was wrong.
- [ ] Era 3: MODERN (the Squad-adjacent mode, biggest audience pull)
- [ ] Era 4: WWII (combined arms, most familiar)
- [ ] Era 5: ANCIENT (shield walls, ramps, ballistae, formation play)
- [ ] Era 6: GUNPOWDER / NAPOLEONIC (star forts, line infantry, siege parallels)
- [ ] Cavalry content per era (the *system* is core §12b; each era supplies the mount)
- [ ] Era production template: how long an era takes, what it contains, what it costs
- [ ] Cross-era balance policy (are eras ever mixed? probably not — state it)

---

# PART V — PLATFORM, PROCESS & SHIP

## 22 · Modding (creator-facing)

- [ ] Mod loading + hot-reload (shared with §1)
- [ ] Custom map support (earth grid + placements from file)
- [ ] Scripting surface decision: data-only (safe) vs sandboxed scripting (powerful)
- [ ] **Mod security model** at 100v100 (gates on the hosting decision, §17)
- [ ] Workshop / distribution strategy (Steam Workshop first)
- [ ] Creator documentation + starter template pack
- [ ] Mod content policy (tone rules from ART-BIBLE §9, stated for creators)
- [ ] Moderation & reporting for user content
- [ ] Big-event tooling: admin controls, spectator/observer camera, match scripting

## 23 · Performance & tech

- [x] Jolt sleep threshold config (world at 0 awake at rest)
- [x] Headless autotest harness
- [ ] Frame budget audit on M-chip at 1440p (draw calls, physics spikes on collapse)
- [ ] Earth chunk meshing (§5 — render scaling)
- [ ] **Earth budgets held** (`EARTH-SPEC` §9): ≤8 chunk remeshes/frame, ≤512 settle
      cells/frame, ≤4 spans/column, ~8 MB of field at 800 m square
- [ ] Deformation stays full-resolution everywhere — render LOD only, never sim LOD
- [ ] Settle queue determinism verified: same event log → identical terrain on every client
- [ ] Chunk rolling hashes catch drift and trigger resync (`EARTH-SPEC` §5)
- [ ] Brick pooling for debris (churn during barrages)
- [ ] Scalability settings (low-end + Steam Deck targets)
- [ ] Save/load (persistent battlefield between sessions?)
- [ ] Crash/error telemetry decision
- [ ] Mac + Windows + Linux export presets, signing/notarization

## 24 · Build & CI

- [x] Repo structure + version-control hygiene — done 30 Jul. `git init` at the project
      root, `.gitignore` covering Godot's import cache and the archived Bevy prototype's
      7.8 GB `target/` directory, and `tools/install-hooks.sh` pointing `core.hooksPath` at
      `tools/` so the hook is version controlled rather than a thing each clone remembers
      to copy. No LFS yet: the whole repo including the blast reference is under 25 MB, and
      LFS is a thing to add when a specific file forces it, not in advance
- [ ] Automated build on commit (all desktop targets)
- [x] Headless autotest as a merge gate — done 30 Jul. `tools/check.sh` runs the suite and
      refuses anything that isn't `failed=0`, and `tools/pre-push` refuses the push. Four
      cases, thirty checks: the Jolt values, the module graph (including that an undeclared
      `use()` is refused and that a cycle is caught by name), bricks falling and settling,
      and the delayed-sleep pattern. `--no-verify` still overrides it on purpose — a gate
      you can't override in an emergency is one people stop using
- [ ] TESTPACK load test as a merge gate
- [ ] Automated screenshot regression (the ART-BIBLE §10 shots)
- [ ] Build versioning + changelog generation
- [ ] Tester distribution channel (itch? Steam playtest branch?)
- [ ] Crash reporting pipeline from testers

## 25 · Playtest & QA

- [ ] Playtest cadence formalised (every pass ends on hardware — already the rule)
- [ ] Feel-notes template (comparable feedback pass to pass)
- [ ] Bug tracker + triage severity definitions
- [ ] External playtester group (you can't see your own game fresh twice)
- [ ] New-player observation (can someone dig a trench without being told?)
- [ ] Performance test protocol (fixed scenario, measured, tracked over time)
- [ ] Multiplayer test protocol (how do we get 32 people in a room, repeatedly?)

## 26 · Store, community & release

- [ ] **Name lock**: "Brick Wars" trademark + storefront search check (*Brick Rigs* is
      adjacent; LEGO-adjacent branding invites scrutiny) → likely needs a subtitle
- [ ] Logo + brand kit
- [ ] Steam page: capsule art, screenshots, GIFs (destruction + digging ARE the marketing)
- [ ] Trailer: 60 s — dig, build, bombardment, mine detonation, over the top
- [ ] Devlog / social cadence (destruction clips are inherently viral)
- [ ] Creator/streamer outreach (the big-group-event angle is the hook)
- [ ] Community hub (Discord) + modder channel
- [ ] Demo scope (Next Fest: single-player siege vs sandbox)
- [ ] Closed alpha + wishlist funnel
- [ ] Price point + public roadmap to 1.0
- [ ] Age rating submissions (ESRB/PEGI — plan for it)
- [ ] Localization scope (UI strings minimal by design — cheap win)
- [ ] Console feasibility pass (Godot console ports via W4/partners — after Steam traction)

---

*Next up: finish Part I (audio direction, animation guide, part-table + manifest specs),
then Part II §1 — extract the palette and part tables into data and run the de-hardcode
audit while the codebase is still small enough that it's a day's work, not a month's.*
