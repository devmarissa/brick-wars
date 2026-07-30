# BRICKFIELD — Phase 0 Harness Results

**The question:** does 500-player brick warfare hold on one machine?
**The answer from this experiment:** yes on both walls — with the right techniques. And the harness caught the real failure mode along the way.

Run: 4 km² map, 250 m cells (16×16 = 256), 3×3 area-of-interest, 30 Hz tick (33.3 ms budget), 2 worker threads, 600 ticks (~20 s) per player count, bots clustered on 10 objectives, periodic "everyone blows the same central building" stress spikes.

## Scaling table (with relevance budget on)

| players | avg tick (ms) | p99 tick (ms) | avg client (kbit/s) | worst-case client* (kbit/s) | server up (Mbit/s) |
|--------:|-------------:|-------------:|-------------------:|---------------------------:|-------------------:|
| 50      | 0.15 | 0.34 | 169 | 254  | 8   |
| 150     | 0.22 | 0.50 | 203 | 221  | 30  |
| 254     | 0.33 | 0.64 | 241 | 286  | 61  |
| **500** | **0.58** | **1.29** | **277** | **1046** | **139** |

\* worst-case = a client standing at the objective during the "everyone blows the same building" spike.

## Verdict @ 500 players

- **CPU:** p99 tick **1.29 ms** vs a **33.3 ms** budget → **PASS.** ~25× headroom on the netcode cost, single machine, no server meshing needed yet.
- **Bandwidth:** worst-case client **1.05 Mbit/s** down (avg **277 kbit/s**) → **PASS.** Fits a phone tether. Console/PC never blink.
- **vs naive broadcast** (no interest management, everyone hears everyone): **~0.48 Gbit/s** of server upload — the O(n²) wall interest management + the budget keep us off of.

## The finding the harness earned its keep on

The **first** run — interest management but *no relevance budget* — passed on CPU but **failed on bandwidth**: worst-case client hit **3.3 Mbit/s** when 80+ bots piled onto one point. That's the classic "everyone in one room" problem, and it proved the real enemy at 500 isn't headcount, it's **local density**.

Adding a **nearest-K relevance budget** (each snapshot carries at most the closest 64 players + 96 bricks; the rest are culled and updated on a slower cadence) bounded the worst case to **1.05 Mbit/s** and 500 passed. The cost is a fidelity tradeoff — distant entities update slower — which is exactly the deal every large-scale shooter makes, and it's invisible to a player because you can't meaningfully track 500 enemies at once anyway.

Peak simultaneously-physicalized bricks at 500p reached **~9,000**, kept bounded by the per-cell active cap (excess bakes to static). The static-until-touched + sleep/bake model means the vast majority of the map costs nothing at any instant.

## Honest scope / caveats

- **CPU measured here is the *netcode* cost** — cell binning, interest management, quantized snapshot encoding — which is the part that scales with *player count*. A full rigid-body **collision solver** (Jolt/Rapier) is heavier per active brick, but it's bounded by the static-until-touched model + the per-cell active-brick cap, and it parallelizes across cells and cores. That's the next thing to bolt on and measure for real.
- **No real sockets yet.** CPU numbers are real computation; bandwidth numbers are real serialized byte counts. The next milestone is **UDP loopback** (GameNetworkingSockets) so we measure actual packet overhead, loss, and reconciliation — not just idealized payload size.
- **2-core box** here. The whole point of cell partitioning is that CPU scales across cores; on a real 32–64-core server host the ceiling is far higher. We validate that curve on a bigger machine.
- **Determinism** is stubbed (fixed-seed RNG). Production destruction has to be deterministic across platforms (fixed-point or carefully constrained float) so clients reproduce collapses from the event alone — that's its own de-risking task.

## What this buys us

We now have a **number and a failure mode**, not a vibe. 500 holds on one machine for the netcode layer, the real wall is local crowd density (solved with a relevance budget), and the next experiments are clear: real physics solver, real UDP, and the bigger-core scaling curve. This is the go signal to keep building — and if a later experiment says the honest ceiling is 350 instead of 500, that's still a bigger battle than BattleBit shipped at 254.
