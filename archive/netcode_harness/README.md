# brickfield-harness

Phase 0 load harness for **BRICKFIELD** — a 500-player, cross-platform, destructible brick-warfare sandbox.

Its only job: answer **"does 500-player brick warfare hold on one machine?"** by measuring the two things that actually break at scale — server CPU per tick and bandwidth per client — under the real large-scale-netcode techniques.

## What it models (the real techniques)

- **Spatial cell partitioning** of a 4 km² battlefield (250 m cells).
- **Area-of-interest management** — a client only hears about its 3×3 cell neighborhood.
- **Relevance budget** — each snapshot carries only the nearest-K entities; the rest are culled (this is what bounds worst-case bandwidth under crowding).
- **Quantized snapshots** — grid-aligned bricks pack into ~7 bytes each.
- **Static-until-touched** structures that activate into physicalized bricks, then **sleep/bake** back to static (physics LOD), with a per-cell active-brick cap for graceful degradation.
- **Event-sourced destruction** — replicate the *cause* (an impulse event), not the debris.
- **Parallel** cell/brick simulation across cores.

## Run

```
cargo run --release
```

Sweeps 50 / 150 / 254 / 500 players, prints a scaling table and a pass/fail verdict at 500. See `RESULTS.md` for the interpreted output.

## Not yet (deliberate Phase 0 scope)

Real UDP sockets, a full rigid-body collision solver, and cross-platform deterministic destruction. Those are the next milestones — this harness exists to prove the scaling shape is sound *before* we build any of that. Zero external dependencies by design (std only), so it builds anywhere Rust does.
