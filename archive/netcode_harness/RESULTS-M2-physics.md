# BRICKFIELD — Milestone 2 Results: real rigid-body destruction cost

**The question:** the Phase 0 netcode harness measured binning + interest management + snapshot cost. What does a *real* collision solver add — the actual cost of bricks that fall, collide, and pile up?

**Tool:** Rapier3d (the solver we'd ship), 0.4 m brick cubes, real colliders, real contacts, auto-sleep, with settled rubble baking to static. Same 50/150/254/500 destruction-load sweep, 600 ticks each, on this 2-core sandbox. Budget: 33.3 ms tick, minus ~1.3 ms netcode = ~32 ms for physics.

## The finding (this is the important one)

**Player count is almost a red herring. The governor is the number of *simultaneously-active* bricks.**

### Part A — the wall (loose cap, bricks allowed to pile up)

| players | avg step (ms) | p99 step (ms) | avg live bricks | peak live |
|--------:|-------------:|-------------:|----------------:|----------:|
| 50      | 47.9 | 62.1  | 6,334 | 7,249 | ❌ over |
| 150     | 57.6 | 80.7  | 7,522 | 8,000 | ❌ over |
| 254     | 56.4 | 80.1  | 7,689 | 8,000 | ❌ over |
| 500     | 51.6 | 104.5 | 7,817 | 8,000 | ❌ over |

Even **50 players** blows the 32 ms budget — because with a lax cap the piles grow to 6–8k live bodies and never settle (constant contact jitter in a big pile keeps them awake). Notice avg step time is roughly flat from 50→500: it's tracking *live brick count*, which saturates the cap either way, **not** player count. Solver throughput on this box measured ~**76 colliding bricks/ms**, so ~**2,400 active bricks** is the single-world budget ceiling here.

### Part B — the fix (cap active bricks = physics LOD), at the full 500-player load

| active cap | avg step (ms) | p99 step (ms) | fits ~32 ms budget? |
|-----------:|-------------:|-------------:|:-------------------:|
| 8,000 | 51.2 | 105.9 | no |
| 4,000 | 20.9 | 43.4  | no |
| **2,500** | **12.0** | **22.0** | **YES** |
| 1,800 | 8.0  | 12.9 | YES (lots of headroom) |
| 1,200 | 4.5  | 6.5  | YES |
| 800   | 2.3  | 3.0  | YES |

Cap the simultaneously-active bricks and 500-player destruction load fits comfortably — **~2,500 active bricks at p99 22 ms** on a 2-core box, and huge headroom below that.

## Verdict @ 500 players

- **Netcode:** holds 500 at ~1.3 ms/tick (Phase 0). Not the bottleneck.
- **Physics:** the real governor — and it's bounded by *active-brick count*, not headcount. ~2,500 active bricks fits the budget on this 2-core sandbox.
- **Two levers, and they multiply:**
  1. **Physics LOD** — cap active bricks; settled rubble bakes to static fast. (Demonstrated here.)
  2. **Cell-sharded physics** — split the world's physics across cores; the ceiling scales ~linearly with core count.

A 32-core server host is ~16× this box, so **~30,000–50,000 active bricks server-wide** is realistic — far more than 500 players fighting over trenches will ever churn at once, because only the *few hot cells* are simulating at any instant while the rest of the map sits baked and static.

## What this changes about the design

The whole feel of BRICKFIELD now rests on one tunable: the **active-brick budget** per cell. That's a *good* place for the design to live — it's a single dial that trades destruction spectacle against headroom, it degrades gracefully (excess rubble just bakes sooner), and it's exactly the knob Teardown/BeamNG-class games ship with. It also means the art direction ("chunky bricks, not fine gravel") is doing real work: bigger bricks = fewer bodies per collapse = more collapses on screen at once.

## Honest remaining gaps (Milestone 3 candidates)

- **Real UDP transport** (GameNetworkingSockets loopback) — measure actual packet overhead, loss, and client-side reconciliation, not idealized payload bytes.
- **Cross-platform deterministic destruction** — so clients reproduce a collapse from the event alone (fixed-point or constrained float).
- **The sharded multi-world physics** actually implemented across cores, measured on a real many-core host to confirm the ~linear scaling assumption.
- **Structural integrity** (do walls hold their shape until hit, and collapse believably?) — gameplay-facing, builds on the cap model.
