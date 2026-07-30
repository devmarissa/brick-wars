# Animation style guide

The closed list of animation states, what a pack may say about them, and the conventions that
make a body read as having weight. Written at the end of C2, which is the first point there was
a running game to write it against — a soldier and a horse walking over uneven ground.

It exists to unblock one specific thing. `FORMAT-SPEC` §7 says *"`anim` supplies timings for
existing core states only. A key that isn't a core state is rejected"*, and `CORE-SPEC` §5 says
*"no new player animation states"*. Neither could be enforced, because nothing had ever written
down what the states **are** — so `AssetValidator.DORMANT` announced the gap at every boot rather
than pretending. §2 below is that list.

---

## 1 · Two systems, and the line between them

The most important sentence in this document is one somebody will otherwise get backwards.

**Locomotion is procedural and packs own its data.** How a creature walks is a `locomotion` block
— legs, gaits, strides, phases — and a pack may declare any of it, for any creature, with any
number of legs. `CORE-SPEC` §5 states the exemption explicitly: *"Rigs are exempt: a pack may
declare any part hierarchy, joint layout and gait it likes, because the core's solvers drive
them."* There is no clip and no state name involved. `testpack:horse` proves it — a four-legged
creature that walks, out of a non-core pack, with no core change.

**Actions are a closed set and core owns the list.** Firing, reloading, digging, mounting, dying:
these are states the game reasons about. Other systems ask "is this soldier reloading" and the
answer has to mean the same thing in every pack ever uploaded. A pack supplies **timings and
poses** for a state on this list. It cannot add one, for the same reason it cannot add a verb or
a joint type — each name is something somebody in core has to have written the driver for.

So: **no clips for locomotion, ever; no new names for actions, ever.** `RIG-SPEC` §4 gives the
first half's reason and it is specific to this game — our ground is dug up by the time anybody
walks on it, so a keyframed footfall is authored against a surface that no longer exists. A phase
and a stride length survive a crater.

---

## 2 · The state list

Closed, in the same sense as `RIG-SPEC` §3's joint types and `Locomotion.TYPES`. **Live** means
something in the build drives it today. **Reserved** means the name is claimed and the milestone
that fills it is named — a pack may not use it yet, and the validator says which milestone it is
waiting for rather than "unknown state", because those send an author to different places.

### Locomotion — core drives these, and the gait data is the pack's

| State | Status | What it means |
|---|---|---|
| `idle` | **live** (C2) | Standing. The rest pose, feet planted, body at `stand` above them. |
| `locomote` | **live** (C2) | Moving on the ground. Which gait is the pack's business; that it is walking is core's. |
| `airborne` | **live** (C2) | No foot in stance and none within reach — `Footing.unsupported`, or a jump. |
| `land` | reserved (C4) | The compression on touchdown. Needs the landing thump, checklist §2. |
| `crouch` | reserved (C4) | Lowered profile, slower move. |
| `prone` | reserved (C4) | Crater and parapet play, weapon rested. |
| `mantle` | reserved (C4) | Vaulting a trench wall or a parapet, against real slope. |
| `swim` | reserved (C4) | Wading and swimming. You currently walk on the riverbed. |

`locomote` deliberately does not split into `walk` / `run` / `sprint`. Those are *gait names*, they
come out of a pack's own table, and `core:soldier` calling its fast one `sprint` while
`testpack:horse` calls its `trot` is the system working. A core state list that enumerated gaits
would have to grow every time somebody authored a creature, which is the definition of not closed.

### Actions — one per verb in `CORE-SPEC` §4's fixed vocabulary

| State | Status | Verb |
|---|---|---|
| `raise` · `lower` | reserved (C4) | Bringing a tool up and putting it away |
| `fire` | reserved (C4) | FIRE — the shot itself |
| `cycle` | reserved (C4) | FIRE — working a bolt, lever or pump between shots |
| `reload` | reserved (C4) | FIRE — a magazine, a clip, a single round |
| `throw` | reserved (C4) | THROW |
| `melee` | reserved (C4) | MELEE |
| `dig` | reserved (C4) | DIG |
| `build` | reserved (C4) | BUILD |
| `carry` | reserved (C4) | CARRY — the hauling pose, not the pickup |
| `interact` | reserved (C4) | INTERACT — doors, ladders, switches, resupply |
| `signal` | reserved (C4) | SIGNAL — whistle, horn, flare |
| `enter` · `exit` | reserved (C6) | ENTER / EXIT a vehicle or emplacement |
| `man` | reserved (C6) | MAN — hands on controls, driven by `RIG-SPEC` §4's IK |

### Damage

| State | Status | What it means |
|---|---|---|
| `hit` | reserved (C5) | Flinch. Never interrupts a gait — see §4. |
| `down` | reserved (C5) | Downed, if the revive loop happens. Checklist §2 has it as an open decision. |
| `die` | reserved (C5) | The handover to ragdoll, `RIG-SPEC` §7. |

**Twenty-four names, and that is the whole list.** Adding one is a core change request, exactly
like a new verb.

---

## 3 · The timing table

`anim` maps a state name to **a duration in seconds**. `FORMAT-SPEC` §7's example is the shape:

```json
"anim": { "fire": 0.12, "cycle": 1.15, "reload": 3.4, "raise": 0.35 }
```

Core owns a default for every state. A pack overriding one is saying "this rifle is slower than
the average rifle", which is a legitimate and interesting thing to say — so it is allowed, and
**bounded to ×0.5–×2.0 of the core default**, the same clamp `MATERIAL-SPEC` §8 puts on derived
material properties, for the same reason. Identity is a pack's to define; the shape of the game
is not. A reload that takes a fifth of a second is not a fast pack, it is a pack that has removed
reloading.

| State | Default | Why that number |
|---|---|---|
| `raise` | 0.35 s | Fast enough not to punish switching, slow enough to be a commitment. |
| `lower` | 0.25 s | Putting a thing away is quicker than bringing it to bear. |
| `fire` | 0.12 s | The visible recoil impulse, not the projectile. |
| `cycle` | 1.15 s | A bolt action. This is the number that makes a bolt rifle feel like one. |
| `reload` | 3.40 s | Long on purpose: it is the decision to be out of the fight for a moment. |
| `throw` | 0.80 s | Includes the wind-up, which is most of what makes it readable to an enemy. |
| `melee` | 0.60 s | |
| `dig` | 1.00 s | One stroke. The earth system decides how much comes away. |
| `build` | 1.00 s | Matches `dig`, so the two read as the same kind of labour. |
| `carry` | — | A sustained pose, not a timed action. No duration. |
| `interact` | 0.50 s | |
| `signal` | 1.20 s | A whistle blast is a long, deliberate, audible commitment. |
| `land` | 0.25 s | The compression, not the recovery. |
| `crouch` · `prone` | 0.40 s · 0.90 s | Going prone is slow, and that is the trade for the profile. |
| `enter` · `exit` | 1.00 s each | Long enough that mounting under fire is a real decision. |
| `hit` | 0.20 s | |
| `die` | 0.30 s | The handover to ragdoll; the ragdoll owns everything after. |

`idle`, `locomote`, `airborne` and `man` have no timing. They are states a creature is *in*, driven
procedurally for as long as it is in them, and a duration would mean nothing.

---

## 4 · Weight and anticipation

Four conventions. They are what separates a body from a diagram, and all four are cheap.

**Anticipation is a quarter of the action.** A wind-up runs about `0.25 ×` the state's duration
before the action proper, in the opposite direction to it. A throw pulls back, a dig lifts, a
rifle settles before it fires. Without it every action starts at full speed from nothing, which is
the single loudest tell that a game is animating rather than moving.

**Follow-through is a third, and it overlaps.** Recovery runs about `0.33 ×` the duration after
the action, and the *next* state may begin during it. An action that must fully finish before
anything else can start is how a game gets input lag it cannot explain.

**Weight lives in the body, not the limb.** A heavy action moves the pelvis. A soldier swinging an
entrenching tool shifts their whole mass and the arm follows; an arm that swings alone off a
motionless torso reads as weightless whatever the timing table says. In practice this means the
hip and torso joints participate in every action state — which is also why they carry joints in
`core:soldier` rather than being welded.

**Nothing eases a planted foot.** This is not a style preference, it is arithmetic, and `Gait`
already enforces it: a foot on the ground travels backward at exactly the rate the body travels
forward, on a straight line, or it slides. Every other curve in the game may ease. That one may
not. It was got wrong once — the stance carried a foot a full stride while the body covered
`duty × stride`, and every planted foot dragged 0.32 m per step — so it is written down here as
well as commented there.

**A `hit` never interrupts locomotion.** Flinch is additive: it plays over whatever the legs are
doing. A hit that stopped a creature dead would be a stun, and a stun is a design decision nobody
has made.

---

## 5 · First person and third person are the same states

One list drives both views. A first-person camera may **hide** a state — you do not see your own
`hit` flinch from inside your own head — but it may never **re-time** one.

The reason is competitive rather than aesthetic. If a reload takes 3.4 s in your view and 3.0 s in
the view of the person shooting at you, one of you is being lied to about how long you are
vulnerable. Every timing in §3 is authoritative for both views, and for the server.

What may differ is *reach*: `weapon_view` gets a higher part budget than `weapon_world`
(`ART-BIBLE` §5) because it is on screen constantly, so a first-person model may have more parts
moving. Same states, same durations, more detail.

---

## 6 · Pack pose data — **specified here, lands at C4**

A pack supplies a pose as **joint angles**, not as a clip. Same reasoning as the locomotion
system: a clip is authored against a skeleton, and a pack may declare any skeleton it likes, so a
clip cannot survive the thing it was authored for changing.

The intended shape, for the state list above:

```json
"poses": {
  "carry":  { "upper_arm_l": -40, "forearm_l": 70, "upper_arm_r": -35, "forearm_r": 65 },
  "reload": { "forearm_l": 95, "torso": 8 }
}
```

Angles in degrees, keyed by part name, in the joint's own units and clamped to its declared
limits exactly as `rest` is. A pose names only the joints it moves; everything else keeps doing
what the locomotion driver says, which is what lets a soldier reload while walking without the
two fighting.

**None of this is in `FORMAT-SPEC` yet and no code reads it.** It is written here because the
checklist asks this document for a pose-data format and because deciding it now is free, whereas
deciding it in the middle of C4 is not. The field gets added to `FORMAT-SPEC` §7, and the
validator gets a rule for it, at C4 — when there is a verb to play a pose *for*. A format nobody
can use is a format nobody has tested.

---

## 7 · What the validator can enforce, and when

| Rule | Status |
|---|---|
| An `anim` key must be a state in §2 | **enforceable now** — §2 is the list that was missing |
| A timing must be within ×0.5–×2.0 of its core default | enforceable now, once §3's defaults are core data |
| A state must be live rather than reserved | enforceable now, and the message should name the milestone |
| A `poses` block is well-formed and inside joint limits | C4, with the format |

The first three are what this document unblocks in `AssetValidator.DORMANT`. Wiring them is not
part of writing it down: no shipped asset has an `anim` block at all today, so the rules would
pass trivially on every piece of content in the game — and a rule that cannot fail is the same
problem as a rule that does not run, wearing a better hat. They go in with the first weapon.
