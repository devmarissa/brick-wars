# BRICK WARS — Rigs, Joints & Constraints

*How parts connect, articulate, and animate — and why a modder can build a horse.*

---

## 1 · The horse test

The extensibility benchmark for the whole rig system, stated as an acceptance criterion:

> **A modder, using only data files, can add a horse that walks, trots and gallops with
> correctly articulated two-bone legs, plants its feet on dug-up uneven ground, can be
> mounted and ridden, and ragdolls when killed — without a single line of core code.**

If that works, the rig system is done. It also means mechs, oxen, war elephants, dogs,
and whatever a modder dreams up all work, because they're the same system with
different numbers.

## 2 · Two joint systems, one rule

This is the fork that decides everything downstream, so it's decided here.

**KINEMATIC rigs** — a parent/child transform hierarchy, driven procedurally. No
simulation. Cheap, perfectly deterministic, and replicates as a handful of floats.
**This is the default and it's what animates creatures.**

**PHYSICAL constraints** — real Jolt joints with motors and springs. Genuinely
simulated. Expensive, nondeterministic, and does not replicate cheaply.

> **The rule: anything that must look right on every client is kinematic. Anything
> that's allowed to differ slightly between clients may be physical.**

| Use | System |
|---|---|
| Creature legs, necks, tails | kinematic |
| Soldier limbs (already is) | kinematic |
| Turret traverse, barrel elevation | kinematic |
| Hands on a wheel / controls | kinematic (IK) |
| Vehicle suspension travel | physical (spring) |
| Doors, hatches, drawbridges | physical (hinge + motor) |
| Trebuchet arm & counterweight | physical (the fun *is* the simulation) |
| Chains, tow ropes, drawn wire | physical (distance/rope) |
| Ragdoll on death | physical, local-only |
| Anything at 100v100 scale, hot path | kinematic |

Physical constraints are **budgeted**: a per-object cap and a per-scene cap, enforced by
the pack validator. A pack cannot ship a 200-joint creature and tank the server.

**The two numbers are not written down yet, and the validator rule that would enforce them
is dormant and says so at every boot.** Both caps have to come out of measurement — the
per-object one from the horse, which is the formal extensibility target and the densest
rig we intend to allow, and the per-scene one from a full sandbox with vehicles in it.
Guessing them here would mean either a cap so generous it protects nothing or one so tight
the horse fails its own test. **They land at the end of C2**, alongside the animation style
guide, and this sentence is the marker that they are owed rather than forgotten.

## 3 · Kinematic rigs — the format

A natural extension of the part table. Parts gain an optional parent and a joint:

```json
{
  "name": "foreleg_l_upper",
  "parent": "chest",
  "shape": "block",
  "offset": [3, -2, 6],
  "size": [2, 7, 2],
  "colour": "leather",
  "joint": {
    "type": "hinge", "axis": "x", "limits": [-70, 25], "rest": 0,
    "pivot": [0, 3, 0]
  }
}
```

- **Joint types (kinematic)**: `hinge` (one axis), `ball` (two/three axis with cone
  limits), `slider` (linear travel), `fixed` (rigid weld, the default).
- Every distance here is **whole modules** and every angle is **degrees**, exactly as in
  `FORMAT-SPEC` §3 — a rigged part is a part first. Slider limits are modules of travel;
  everything else's are degrees.
- **`pivot`** is where the joint turns, as an offset in whole modules from the part's own
  origin. Default `[0, 0, 0]`.
- Limits are mandatory. An unlimited joint is a bug — it's how you get legs bending
  backwards through the body.

### Why `pivot` exists — added at C2

The rule this replaces read "joints pivot at the child's origin, which sits on the module
grid like everything else. No off-grid pivots." The second half survives; the first half
turned out not to be workable, and building the rig rules is what surfaced it.

A part's origin is the **centre of its box** — `PartGeometry.mesh_for` sizes a part in
metres and centres it on its own origin. So a bone that pivots at its origin pivots about
its own middle, and a leg that bends halfway up the thigh is not a leg. There is nowhere
else to put the correction: in this format a part is its own bone *and* its own geometry,
with no separate node to offset one from the other the way an imported skeleton would have.

`pivot` is that offset, in whole modules like every other distance in the format, which
keeps the guarantee that actually mattered — **pivots land on the grid** — while making a
knee possible. In the example above the thigh is 7 modules long and hangs from a hip 3
modules above its centre, which is the top of the bone.

`RigRules` enforces the grid rule on the field: a `pivot` of `[0, 3.5, 0]` is refused,
because half a module up a bone is not a place a joint can be.
- **A rig is not a collider.** Rigged parts are visual. Collision stays the 1–4
  hand-fitted compound boxes (`CORE-SPEC` §2, ART-BIBLE §7). A horse gets a body box and
  maybe a head box, not eight leg colliders.

## 4 · The IK solver

**Two-bone IK** is the single highest-value piece of core tech here, because one solver
serves everything:

- Creature legs (the horse's "two joint" requirement, exactly)
- Soldier hands onto a steering wheel, throttle, gun grip, ladder rung
- Soldier feet planting on a trench lip or crater slope
- Loader arms, shovel hands, stretcher carries

**Foot planting** matters more in this game than in most, because our ground is
*constantly being dug up*. A horse whose hooves slide through a fresh crater lip
destroys the illusion instantly. So: raycast down from each foot's ideal position,
plant on whatever the earth field currently is, solve the leg to reach it, and tilt the
body to match the average. This is also why we can't ship canned animation clips for
locomotion — the ground won't hold still.

The continuous heightfield (`EARTH-SPEC` §1) makes this both easier and more necessary
than the old block grid did: there's a real surface normal to plant against and no
staircase to fight, but there's also no longer a flat cell top to get away with.

**The horse leg specifically**: two IK-driven bones (upper and lower) plus an optional
passive third segment (the fetlock) that lags behind with a spring-follow. That third
passive bone is what makes it read as *horse* rather than *stick creature*, and it costs
almost nothing.

## 5 · Procedural locomotion driver

How a modder gets a gait without animating a frame. All data:

```json
"locomotion": {
  "type": "legged",
  "legs": [
    {"root": "foreleg_l_upper", "foot": "hoof_l",  "phase": 0.0},
    {"root": "foreleg_r_upper", "foot": "hoof_r",  "phase": 0.5},
    {"root": "hindleg_l_upper", "foot": "hoof_bl", "phase": 0.5},
    {"root": "hindleg_r_upper", "foot": "hoof_br", "phase": 0.0}
  ],
  "gaits": [
    {"name": "walk",   "speed": [0, 4],   "phases": [0.0, 0.5, 0.25, 0.75], "stride": 1.2, "lift": 0.25, "duty": 0.7},
    {"name": "trot",   "speed": [4, 9],   "phases": [0.0, 0.5, 0.5, 0.0],   "stride": 2.0, "lift": 0.45, "duty": 0.5},
    {"name": "gallop", "speed": [9, 20],  "phases": [0.0, 0.1, 0.5, 0.6],   "stride": 3.4, "lift": 0.8,  "duty": 0.35}
  ],
  "body_bob": 0.12, "body_pitch": 0.08, "lean_into_turn": 0.3
}
```

The core owns: gait blending by speed, phase-driven step cycles, IK targets, foot
planting, body bob/pitch/lean, and turn-in-place. Packs own: how many legs, where they
attach, phase offsets, stride and lift, and the tuning numbers.

**`duty`** — added at C2, when the step cycle was actually built — is the fraction of a
leg's cycle spent on the ground. It is what separates a walk from a gallop more than
stride length does: at `0.7` a quadruped has three feet down at any moment and reads as
unhurried, and at `0.35` the whole animal is briefly airborne. Without the field every
gait was a walk with longer steps, which reads as a horse skating. It is optional and
defaults to `0.66`, the safe end — a gallop with a walk's duty looks laboured, a walk with
a gallop's looks broken.

**Blending is the overlap.** Two gaits whose speed ranges overlap blend across the overlap,
so an author who writes walk `[0, 4]` and trot `[3, 9]` has said "take a whole unit of
speed to change gait" — more control than a dedicated field would give. Ranges that merely
touch, as the example above does, blend across a tenth of the narrower range rather than
snapping. Phase offsets blend the short way round a circle, so a leg going from `0.9` to
`0.1` steps a fifth of a cycle forward rather than four fifths backwards.

**Locomotion types in the core**: `wheeled` · `tracked` · `legged` · `flying` ·
`floating` · `static`. Adding `legged` alongside the existing three is what makes
mountable creatures a vehicle archetype rather than a special case — a horse is a fast
transport vehicle with legs, which is exactly what it is.

## 6 · Physical constraints — the sanctioned set

Closed list, same discipline as the primitive set (ART-BIBLE §1b):

| Constraint | Use |
|---|---|
| **hinge** | doors, hatches, drawbridges, trebuchet arms, gun cradles |
| **slider** | recoil travel, pistons, telescoping |
| **ball / socket** | ragdoll joints, universal mounts |
| **spring** | suspension, recoil recuperators, bounce |
| **motor** (on hinge or slider) | powered doors, elevated bridges, winches |
| **distance / rope** | chains, tow cables, drawn wire, counterweights |

Every one takes limits, stiffness, damping, and a motor target where applicable — all
pack-settable within core-defined ranges. Packs cannot invent a constraint type.

Medieval pays for this system on its own: a trebuchet with a real hinged arm and a real
counterweight on a rope is a genuinely better toy than a scripted animation, and the
same joints do castle drawbridges and portcullises.

## 7 · Ragdoll

On death, a kinematic rig converts to a physical one: each rigged part becomes a small
rigid body, joints become ball constraints with the same limits, and the whole thing
falls. Because limits carry over, ragdolls don't do the horrible spaghetti thing.

Ragdolls are **local and cosmetic** — never replicated, never authoritative, always on a
lifetime timer. This is how we get satisfying deaths at 100v100 without paying for them
on the wire. Then they settle and eventually break into blocks like any other debris.

## 8 · Core vs pack

**Core owns**: joint types, constraint types, the IK solver, the gait engine, foot
planting, ragdoll conversion, budgets and validation, and the replication format.

**Packs declare**: part hierarchies, joint placements and limits, leg/gait data, IK
target bindings (hands to this control, feet to the ground), constraint parameters,
and ragdoll masses.

**Clarifying an earlier rule**: `CORE-SPEC` §5 says packs cannot define new animation
states. That applies to the **player state machine** (fire, reload, mantle, and so on) —
it does not restrict rigs. A pack may declare any rig hierarchy and any gait it likes,
because those are driven by the core's solvers rather than by new bespoke logic. Rigs
are data; player verbs are vocabulary. Different things.

## 9 · Netcode implications

- A kinematic rig replicates as **root transform + gait phase + a few driver floats**.
  A hundred horses is cheap. This is the entire reason kinematic is the default.
- Physical constraints do **not** replicate cheaply. Server-owned physical joints
  (doors, drawbridges, trebuchets) are fine because there are few of them and they're
  slow. Cosmetic physical joints (ragdolls, chains) stay client-local.
- The pack validator enforces this: a pack that puts physical joints on a
  high-count entity fails validation with a message saying why.

## 10 · What this unlocks

Horses and cavalry · mechs and walkers · war elephants and oxen teams · working vehicle
suspension · doors, hatches and drawbridges · trebuchet arms and counterweights · chains,
tow cables and winches · turret traverse that visibly tracks · hands actually on the
wheel · feet that plant on ground we just dug up · ragdoll deaths · and a modder
building a creature nobody on this project imagined.

That last one is the point.
