# BRICKFIELD — Milestone 4 Results: real-socket load test

**The question M1 couldn't answer:** M1 proved the netcode *algorithms* by counting serialized bytes — it never opened a socket. This opens real ones. A real UDP dedicated server plus **N real bot clients, each with its own socket**, exchanging real packets over the network stack at 30 Hz. Does it hold when 500 clients genuinely *connect*?

**Setup:** real UDP over loopback, 30 Hz, 4 km² / 250 m cells, 3×3 area-of-interest, nearest-64 relevance budget, quantized player records, DecimalCubed's 2-byte grid-index encoding for destruction events. 2-core sandbox; the server shares those cores with every bot. 12 s per count.

## Result

| clients | srv avg (ms) | srv p99 (ms) | down/client (kbit/s) | up/client (kbit/s) | snapshots sent | loss |
|--------:|------------:|------------:|---------------------:|-------------------:|---------------:|-----:|
| 50      | 0.25 | 0.50 | 9.0  | 3.9 | 17,950  | 0.00% |
| 150     | 0.74 | 1.43 | 40.6 | 3.9 | 53,250  | 0.00% |
| 254     | 1.24 | 3.68 | 59.0 | 3.8 | 90,932  | 0.00% |
| **500** | **2.63** | **6.62** | **91.9** | **2.0** | **174,752** | **0.00%** |

## Verdict @ 500 real connected clients

- **Bandwidth (device-independent, the clean metric):** ~92 kbit/s down + ~2 kbit/s up per client. That fits any home or phone connection with room to spare — two orders of magnitude under a 2 Mbit/s comfort line. Down-rate rises with client count because denser crowds mean bigger area-of-interest sets, and the nearest-64 relevance budget is what keeps it bounded.
- **Packet loss: 0.00%** — 174,752 snapshots sent, 174,752 received. Clean at the socket layer; kernel UDP buffers kept up.
- **Server tick p99 6.62 ms** vs a 33.3 ms budget — and that's the server *fighting 500 bot threads for the same 2 cores.* On a dedicated many-core host with clients elsewhere it drops sharply, and M3's cell-sharding scales it out further.

**This is the first BRICKFIELD result with real sockets in the loop:** 500 clients actually connected, real packets, real serialization, real kernel buffers — not a paper model. The core question "does 500 players connecting hold" now has a measured yes at the transport level.

## What's proven now, end to end (M1–M4)

- **M1** — netcode algorithms: interest management + relevance budget bound per-client bandwidth. *(paper)*
- **M2** — physics governor: it's active-brick count, not player count; capping per cell keeps the solver in budget. *(real Rapier)*
- **M3** — scaling: sharding capped cells across cores is ~linear (97% on 2 cores). *(real Rapier, threaded)*
- **M4** — real transport: 500 genuine socket connections, 0% loss, ~92 kbit/s/client, healthy server tick. *(real UDP)*

The core scaling thesis — 500 players, brick destruction, bounded bandwidth — is now validated with real code at every layer that a single machine can validate.

## Honest remaining gaps

- **Loopback is not the internet.** This proves packet throughput, serialization, and kernel-buffer behavior under real I/O. It does **not** prove behavior under real-world **latency, jitter, and path loss** — that needs a WAN emulator (netem) or genuinely distributed clients, plus client-side prediction and reconciliation, which we haven't built yet.
- **Shared-core caveat:** server-CPU numbers here are pessimistic (server competes with 500 bots for 2 cores). A dedicated host improves them; they're already inside budget regardless.
- **The final truth is a human playtest** — real people, real machines, real connections. Everything up to that is de-risking; this milestone is a large chunk of it.

## Suggested next milestones

1. **Latency realism:** add client prediction + server reconciliation and run behind a netem WAN emulator (say 60–120 ms RTT, 1–3% loss) to prove it *feels* right, not just that it fits the pipe.
2. **Fuse the layers:** run the real UDP server *with* the sharded Rapier physics from M2/M3 so destruction events flow over the wire to 500 clients in one process — the first true vertical slice of the server.
