# BRICK WARS — The Earth

*The terrain representation, and why it stops being a grid of chunky rectangles.*

The earth is the gameplay (`VISION.md` pillar 2), so it gets the most careful spec in the
project. This replaces the prototype's 2.5 m × 0.8 m block grid entirely — that grid made
a single terrain cell wider and taller than a soldier, which is why it read as chunky.

Read with `MATERIAL-SPEC.md`. Soil type *is* material; there is no separate soil system.

---

## 1 · The representation

**A column-span field at 0.5 m, with continuous height.**

- **Plan grid: 0.5 m cells** (5 modules). Down from 2.5 m — twenty-five times the
  resolution in plan. A soldier is 3.6 cells tall and about 1.2 cells wide, so terrain
  detail is now finer than the thing standing on it, which is the whole point.
- **Height is continuous**, not stepped. This is what actually kills the chunkiness — the
  old 0.8 m steps were more of the problem than the cell width was.
- Each cell is a **column** holding an ordered list of **spans**: `{bottom, top, material,
  disturbed}`. A typical column has exactly one span, bedrock to surface. Tunnels, caves
  and dugouts are what happens when a span splits in two.

**The trick that makes 0.5 m affordable: heights are stored as integer centimetres**,
`i16` relative to the chunk's base height (±327 m of range, which is more than any map
needs). One centimetre is invisible — it looks perfectly continuous — but the arithmetic
is exact. That buys three things at once:

1. **Determinism.** Slumping and collapse are integer operations, so every client computes
   the same result from the same inputs. §5 explains why that's worth a lot.
2. **Memory.** 2 bytes of height + 1 byte of material = 3 bytes per column. An 800 m
   square playable area is 1600 × 1600 = 2.56 M columns ≈ **7.7 MB**. Multi-span columns
   live in a sparse side table and are rare.
3. **Grid consistency.** 1 cm = 0.1 module, so the earth sits on the same integer system
   as everything else (`FORMAT-SPEC` §3) rather than being a special case.

**Chunks**: 32 × 32 cells = 16 m. Meshing, collision and dirty-tracking are all per chunk.

**Playable deformable area: 400–800 m per side.** Beyond it, static backdrop terrain that
nobody digs. This is a real constraint and it's worth stating rather than discovering: at
0.5 m we are buying detail with area, and a Great War sector is a few hundred metres deep
anyway.

## 2 · Meshing — organic ground *and* vertical trench walls

The obvious risk with a smooth surface is losing the crisp vertical trench wall, which
would be a terrible trade. So meshing is **slope-dependent**:

- Where the gradient between neighbouring columns is **below the cliff threshold (60°)**,
  triangulate smoothly between column centres with smoothed normals. Open ground, crater
  bowls, spoil heaps and shell-churned mud all come out genuinely curved.
- Where it **exceeds** the threshold, break the surface: emit the upper column's top edge
  and a **vertical skirt** down to its lower neighbour, with flat normals. Trench walls,
  parapets, cut faces and dugout entrances stay sharp and readable.

So the same field produces rolling organic ground and a knife-edge trench, decided by the
terrain itself rather than by an authoring mode. Dig a trench and it has vertical walls
because you cut it steeply; shell that trench and the walls slump past 60° and it becomes
an organic churned bowl. **The transition between those two states is the game.**

Colour comes from the span's material (`MATERIAL-SPEC` §2) plus per-vertex `SHADES`
variation (`ART-BIBLE` §3), so the ground gets the same non-uniform, hand-mixed look as
brickwork without textures and without a grid.

**Collision**: a Jolt heightfield collider per chunk, rebuilt with the mesh. Voids and
tunnel roofs get box colliders derived from the span boundaries — cheap, because there are
few of them.

## 3 · Angle of repose — "earth is packed"

The behaviour you described. Every granular material carries an `angle_of_repose`
(`MATERIAL-SPEC` §5); the earth continuously tries to obey it.

- Cut a face **shallower** than the repose angle and it stands indefinitely.
- Cut it **steeper** and it slumps until it doesn't — over a second or two, spreading to
  its neighbours, which is what makes it look like real earth settling rather than a
  scripted animation.

Sand slumps at 30° and is nearly useless to build with. Loam holds 38° — about 39 cm of
step per cell. Clay holds 55°, hardpack 60°, chalk 65°, which is why Great War tunnelling
happened in chalk and why a clay trench can have near-vertical walls with only light
revetment.

**How it runs**: an event-driven **settle queue**. When a cell changes, it and its eight
neighbours are pushed on. Each tick, pop up to 512 cells; for each, compare against
neighbours, and where the step exceeds `tan(repose) × distance`, move half the excess
downhill, mark both dirty and re-push their neighbours. Bounded work per frame, no spikes,
and it propagates outward the way a real slump does.

**Shoring.** Revetment — timber, wattle, sandbag facing, corrugated sheet — sets a local
repose override on the cells it covers, letting a wall stand steeper than the soil ever
would. Remove or burn the shoring and the override lifts, the queue wakes, and the wall
comes down. That's a genuine loop: trenches need maintenance, and destroying revetment is
worth doing.

**Wet ground** multiplies effective repose downward. Rain, a broken water table, or heavy
shelling turns loam into `mud` at 15°, at which point trench walls simply will not stand.
That is the Great War in one number, and it costs nothing to have.

## 4 · Digging, spoil, and conservation of volume

> **Material removed has to go somewhere.** Digging is not deletion.

- Excavating produces **spoil** — carried on the tool, then deposited. Cutting a trench
  raises a parapet from its own spoil, automatically, because the volume has nowhere else
  to be. Craters get raised lips because the blast threw the material outward.
- Blast conserves about 70% of displaced volume onto the rim; the rest goes airborne as
  dust and debris and disperses. Full conservation makes craters look wrong — a real
  crater loses material to the air.
- **Spoil is weaker than undug ground.** Rather than doubling the material list, each span
  carries a `disturbed` flag: repose −15°, cohesion ×0.4, support ×0.6. One bit, and a
  parapet of loose spoil now behaves noticeably worse than the same shape cut from
  virgin clay. Tamping it down over time is a possible later mechanic.

Conservation of volume is what makes the earth feel like a substance instead of a subtract
brush, and it's the difference between digging feeling like work and feeling like cheating.

## 5 · The event log

Every modification is a serialised event, from day one, because this is simultaneously the
netcode foundation, the replay system and the late-join path:

```
{ tick, actor, cell, span, op, delta_cm, material }
op ∈ carve · deposit · split · collapse · shore · unshore
```

About 10 bytes packed. Digging is bursty but small; a busy 100v100 battle is a few
kilobytes a second.

**Slumping is never replicated.** Because heights are integers and the settle queue runs in
a fixed order, every client derives identical slumping from the same event stream. The
server sends the dig; the collapse happens everywhere by itself. Given how much of this
game is earth moving, that is a very large saving on the wire — it's the single biggest
reason for the integer-centimetre decision in §1.

Drift is caught rather than assumed: each chunk carries a rolling hash, reconciled
periodically, and a mismatched chunk is re-snapshotted.

**Late join** = chunk snapshot (run-length encoded heights and materials) + events since.

## 6 · Tunnels, sapping and mining

Spans are what make this possible, and sapping is core to the vision in every era.

- Digging **into a face** rather than downward splits a span and opens a void.
- **Max 4 spans per column**, enforced at runtime and by the validator. This prevents
  pathological swiss cheese and keeps the sparse table small.
- **Roof support**: for each void, the unsupported horizontal span is measured against what
  the roof material's `support_vertical` can carry given the overburden above it. Exceed it
  and the roof comes down. Chalk tunnels a long way unaided; sand does not tunnel at all.
- **Props** — `timber` placed inside the tunnel — provide local support and extend the safe
  span. Burn them or blast them and the support goes with them (`MATERIAL-SPEC` §6).
- **Collapse** drops the material above and **subsides the surface** by the void volume.
  Subsidence is visible from above, which makes spotting an enemy mine and counter-mining
  a real thing a player can do with their eyes rather than a UI element.

## 7 · The earth and everything standing on it

- Structures rest on the heightfield. Remove the ground under a foundation and the
  structure loses support, and the structural integrity system (`MATERIAL-SPEC` §2)
  takes it from there. **Undermining a wall is not a special case — it's the same code as
  shooting out its base.**
- Vehicles interact with slope, `friction` per material, and `disturbed` ground: fresh
  spoil and mud bog wheels in a way hardpack does not.
- Foot planting (`RIG-SPEC` §4) raycasts against the live field, which is exactly why we
  can't ship canned locomotion clips — and why 0.5 m resolution matters for how feet read
  on a crater lip.

## 8 · Water

A per-map water level, with optional per-region overrides. Dig below it and the void fills;
filled ground becomes `mud`, with everything that implies for repose and movement. Pumping,
duckboards and drainage are pack-level answers to a core-level problem.

Full water simulation is explicitly **not** in scope. A level, a fill rule and a wetness
multiplier get 90% of the feel for 5% of the work.

## 9 · Performance budgets

Written down now so they're targets rather than surprises:

| Budget | Value |
|---|---|
| Cell size | 0.5 m |
| Height quantisation | 1 cm (`i16` per column, chunk-relative) |
| Chunk | 32 × 32 cells (16 m) |
| Playable deformable area | 400–800 m per side |
| Remesh | ≤ 8 chunks per frame |
| Settle queue | ≤ 512 cells per frame |
| Max spans per column | 4 |
| Memory, 800 m square | ~8 MB base field |

Render LOD (half and quarter resolution meshes at distance) is render-only. **Deformation
is full resolution everywhere in the playable area** — a mine going off out of view has to
be real, or the whole premise breaks.

## 10 · What this changes from the prototype

`earth.gd` moves from harvest to **rebuild** (`BUILD-ORDER` §1b). Cell size, height
representation, meshing and collision all change, so there isn't much left to port. What
survives is the **design lineage** — column rebuild, carve, crater lips, spoil, and the
event log — which is worth a great deal even though none of the code comes with it. Those
concepts were right; they were just expressed on a grid five times too coarse.

The C3 milestone is rewritten accordingly.
