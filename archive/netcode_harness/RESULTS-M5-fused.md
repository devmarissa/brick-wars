# BRICKFIELD — Milestone 5 Results: the fused server

**What this is:** every prior milestone proved one layer alone. This fuses them into ONE running dedicated server and stress-tests the whole thing: real UDP (M4) + interest management & relevance budget (M1) + real Rapier destruction (M2) + cell-sharded physics across cores (M3). 500 real socket clients connect and hammer it with movement + destruction; the server spawns real bricks into per-cell physics shards, steps them across cores, bakes settled rubble, and streams interest-managed snapshots carrying player *and* live-brick state back over the wire.

**Setup:** 2-core sandbox — the server shares those two cores with all 500 bot threads *and* the physics workers. Loopback. ~5% of clients trigger destruction each tick.

## Fused sweep (default per-cell cap 260)

| clients | srv avg (ms) | srv p99 (ms) | phys avg (ms) | down/client (kbit/s) | up/client | loss | peak live bricks | hot cells |
|--------:|------------:|------------:|--------------:|---------------------:|----------:|-----:|-----------------:|----------:|
| 50      | 16.8 | 32.0 | 16.3 | 132 | 3.8 | 0.00% | 2,888 | 20 |
| 150     | 17.6 | 26.3 | 16.6 | 168 | 3.9 | 0.00% | 3,818 | 22 |
| 254     | 23.9 | 42.1 | 22.3 | 185 | 3.8 | 0.00% | 5,264 | 31 |
| **500** | **27.9** | **44.1** | **24.9** | **214** | **1.9** | **0.00%** | **4,652** | **34** |

**The whole thesis is running as one server:** 500 real clients, real packets, real rigid-body destruction (4,652 live bricks across 34 hot cells at peak), sharded across cores, interest-managed. **Zero packet loss.** Per-client bandwidth ~214 kbit/s down even while streaming live brick state — still fits any home connection.

The combined tick went **over the 33 ms budget** at 254 and 500 clients — and the breakdown says exactly why: ~25 of those 44 ms are *physics*. That's the M2 finding again — the governor is active-brick count, not player count — landing inside the integrated system, on a box where the server is fighting 500 bots and the physics workers for two cores.

## The lever (tighten the per-cell active-brick cap), 500 clients

| per-cell cap | srv p99 (ms) | physics (ms) | peak live bricks | down/client | loss | in budget? |
|-------------:|------------:|-------------:|-----------------:|------------:|-----:|:----------:|
| 260 (default)| 44.1 | 24.9 | 4,652 | 214 | 0.00% | no |
| **120**      | **20.0** | 9.4 | 2,724 | 220 | 0.00% | **YES** |
| **80**       | **17.3** | 5.8 | 2,016 | 214 | 0.00% | **YES** |

Tightening the cap brings the fused 500-client server **comfortably into budget on this 2-core box** — same clients, same zero loss, same bandwidth. The active-brick cap is the single master dial: it trades destruction spectacle for headroom and degrades gracefully (excess rubble just bakes to static sooner). This is precisely the M2 prediction, now demonstrated in the fully integrated server.

## Verdict

The fused server works. All four proven layers run together as one process under real load: **500 real clients, 0% packet loss, ~214 kbit/s/client, live sharded destruction, interest-managed** — and it holds tick budget once the active-brick cap is tuned to the hardware (and on this box the *only* pressure is physics on two shared cores; a dedicated many-core host plus the M3 sharding lifts the cap way up). There is no longer any layer of the core scaling thesis that hasn't been run, together, with real code.

## Two dials, restated (this is the whole performance model)

1. **Per-cell active-brick cap** (physics LOD) — trades destruction fidelity for tick headroom. Demonstrated: 260→over, 120→in budget, 80→lots of headroom.
2. **Cores** — cell-sharding scales the number of simultaneous hot cells ~linearly (M3, 97%). More cores = a higher cap at the same tick rate.

Between them, "500 players + brick destruction at 30 Hz" is a tuning exercise on known hardware, not an open research question.

## Remaining honest gaps (unchanged, and now the actual frontier)

- **Real-internet latency, jitter, loss** — loopback doesn't have them. Needs client-side **prediction + server reconciliation** and a WAN emulator (netem) to prove it *feels* right at 60–120 ms ping. This is the next real netcode work.
- **A human playtest** — the final truth.
- Everything below those two is now de-risked with running code.
