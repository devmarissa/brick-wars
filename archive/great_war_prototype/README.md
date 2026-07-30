# BRICKFIELD: WESTERN FRONT — Godot + Jolt

**The pivot:** trench warfare. Two trench networks face each other across a cratered
no-man’s-land — "Pordier at War, but everything is actually physical." Every trench
wall, sandbag, wire fence and ruin is a real rigid body; artillery genuinely carves
the battlefield. You spawn in the allied trench facing the enemy line.

The full BRICKFIELD prototype ported to **Godot 4.6** with **Jolt Physics** (the engine
behind Horizon Forbidden West, now Godot's default). Same map, same vehicles, same
destruction — on a stronger baseline: stabler stacks, faster solver, a real editor,
and a proven console-port path.

## Run it on your Mac

1. Install Godot 4.6: `brew install --cask godot` — or download it from
   https://godotengine.org/download/macos (universal .dmg, ~50 MB).
2. Open Godot → **Import** → pick this folder (`godot/`) → **Import & Edit**.
3. Press **▶ (Cmd+B / F5)** to play.

## Controls (BattleBit-style: mouse is always captured — Esc releases, click recaptures)

**WASD** move/drive · **Space** jump · **Shift** sprint · **mouse** free look ·
**1 / 2 / 3** rifle / rocket / grenade · **L-click** fire (on foot AND in vehicles) ·
**E** enter/exit vehicle · **V** first/third person · **wheel** zoom · **Esc** release mouse.

## M-EARTH: the ground is real now

No-man's-land is a diggable earth grid (the keystone architecture — every dig/place/
blast is a tiny grid event, which is exactly what the 100v100 netcode will ship).
Press **4** for the SHOVEL: **L-click digs** (you carry the spoil), **R-click builds**
it back — dig a sap across no-man's-land and stack the spoil into a parapet in front
of you. Artillery and rockets carve REAL craters out of the same grid. Dig to bedrock
and the ground is simply gone.

## Every vehicle works now

- **Tank** — drives, and the cannon fires while driving (L-click, with recoil)
- **Jeep** — fast, drifty, hood-mounted MG
- **Plane** — hold W on the ground; past ~13 m/s it lifts off and flies toward your aim.
  MG strafing runs. E to bail out (bring a landing plan)
- **Boat** — floats on the lake (SE corner), drives on water, bow gun
- **Turret / AA / Artillery** — walk up, E to man, aim with mouse, L-click:
  turret = cannon, AA = rapid tracer stream, artillery = huge lobbed shell with real recoil
- **Target dummies** — 8 tan soldiers scattered around; every weapon shatters them

Plus: muzzle flashes, explosion fireballs + smoke + light flashes, procedurally-generated
gunshot/boom audio (no asset files), a real sky with glow, roads, sandbag cover lines,
and a lake.

## What to compare against the Rust build

- **Frame rate**, most importantly during and after big collapses. Watch the
  `awake bricks` HUD counter — it should spike during a collapse and fall back
  to 0 within a couple of seconds of the rubble settling (verified headlessly:
  blast → 214 awake → 0 by ~5s later, no custom governor needed).
- **Vehicle feel** — same force/traction model, but Jolt's solver + a low
  center of mass. Tank should feel planted and punchy.
- **Stack stability** — walls shouldn't creep or jitter.
- **Character feel** — the soldier now runs on Godot's battle-tested
  CharacterBody3D controller instead of our hand-rolled one.

## Where the tuning knobs live

- `vehicle.gd` top: per-vehicle `max_speed / accel / turn_rate / turn_accel / grip`
  (accelerations, so they're mass-independent). Actual values are set in
  `main.gd → _vehicles()`.
- `player.gd` top: `WALK / SPRINT / JUMP / GRAV`.
- `main.gd` top: `BLAST_RADIUS / BLAST_POWER`, mouse sensitivities.
- `project.godot`: world gravity (20 — heavier than real for chunky feel) and the
  Jolt sleep threshold (0.35 — why rubble goes back to sleep).

## Files

- `main.gd` — world build (fort, buildings, trees, terrain, trench field, crates),
  camera, blasts, HUD, headless autotest
- `vehicle.gd` — drivable RigidBody3D with compound hitboxes + arcade traction
- `player.gd` — soldier on CharacterBody3D
- `projectile.gd` — shell → blast on impact

## Headless test (CI-able)

`BRICKFIELD_TEST=1 godot --headless --path .` — builds the world, verifies
everything sleeps, fires a blast, drives the tank, and prints awake-brick counts
until `TEST_DONE`.
