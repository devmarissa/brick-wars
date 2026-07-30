# BRICKFIELD — The Road to 500

*Technical architecture & de-risking plan for a 500-player, cross-platform (PC + console), destructible brick-warfare sandbox.*

**Status:** Draft v0.1 — architecture direction, not yet validated. The whole point of this doc is to define the ONE experiment that tells us whether 500 is real.

---

## 0. The thesis, stated honestly

We want 500 concurrent players in one battle, with destructible brick terrain, on PC and console, moddable, on Steam. That specific combination is at the frontier of what shipped games do. But it is **not** unprecedented, and the closest proof point is directly on our side:

**BattleBit Remastered** — a deliberately low-poly FPS with *total destruction* — shipped **254-player** battles, was built by a **team of ~4**, topped the Steam charts, and made a fortune. It is almost exactly this pitch, proven, at roughly half our target headcount. ([TechRadar](https://www.techradar.com/news/fps-made-by-four-people-tops-steam-charts-with-massive-254-player-battles), [Wikipedia](https://en.wikipedia.org/wiki/BattleBit_Remastered))

That reframes our problem. We are not trying to leap from 0 to a number nobody has hit. We are trying to roughly **2× the proven ceiling** of a game that used our exact aesthetic strategy. That is hard but it is a *scaling* problem, not a *miracle* problem.

The cautionary tale at the far end: **Star Citizen** reached ~1,000 players in one shard via "server meshing" — after **~$750M and 11+ years**. ([PC Gamer](https://www.pcgamer.com/games/11-years-and-usd750-million-later-star-citizen-now-has-a-new-star-system-and-mmo-scale-server-sizes/)) That's the price of *fully distributed authoritative physics at MMO scale*. Our job is to reach 500 **without** paying that bill — by cheating the physics the way BattleBit did, not by out-engineering CIG.

---

## 1. The art-simplicity question, answered

Your intuition — "simple art should lower the physics replication cost" — is **half right, and the useful half is exploitable.**

**The half that's wrong:** replication cost has nothing to do with polygon count. The network doesn't send triangles; it sends *state* — positions, velocities, events. A blocky wall and a photoreal wall cost the same to replicate if both are simulated as independent moving bodies. So "the art is simple" does not, by itself, buy us anything on the wire.

**The half that's right, and where the real leverage is:** brick geometry is **uniform, grid-aligned, and quantizable**, and *that* slashes cost in three places the art style directly enables:

1. **State compression.** A brick's transform can be quantized to integer grid coordinates + a handful of orientation bits — a few bytes instead of a full float transform. Photoreal irregular meshes can't do this cleanly; identical bricks can.
2. **Deterministic destruction.** Identical, regular bricks make a collapse *reproducible from a seed*. We send the trigger ("this wall took impulse X at point Y"), and every client computes the same rubble locally. Irregular meshes make determinism far harder. **This is the single biggest bandwidth win available to us, and the art style is what unlocks it.**
3. **Chunking & baking.** Grid-aligned bricks aggregate into chunks trivially (think Minecraft), so settled destruction bakes into cheap static geometry instead of thousands of live bodies.

So: the art doesn't lower replication cost *directly*, but it lets us build a **quantized, deterministic, chunkable** destruction system that a realistic-art game couldn't. We should lean into blocky-and-grid-aligned as an **engineering requirement**, not just a look.

---

## 2. How we "cheat" to 500 — the legitimate toolkit

Every large-scale game reaches its numbers by *not* simulating what it can pretend to simulate. These aren't hacks; they're the actual discipline. Ranked by how much headroom each buys us:

1. **Interest management (Area of Interest).** Non-negotiable. Each client only receives entities near it / in view. Turns bandwidth from O(n²) (everyone knows everyone) into O(n·k) (everyone knows their ~k neighbors). This alone is what makes 500 *thinkable*.
2. **Deterministic, event-sourced destruction.** Replicate the *cause* (impulse events), not the *debris* (per-brick transforms). Clients reproduce collapses locally and reconcile. Enabled by the brick uniformity above.
3. **Static-until-touched.** A wall is ONE sleeping static body until something hits it, then it "activates" into chunks. Sleeping bodies cost ~nothing on CPU and nothing on the wire. At any instant only a small fraction of the map is actually simulating.
4. **Cosmetic client-only debris.** Small fragments, splinters, dust — pure visual effects that **never replicate**. Only *gameplay-relevant* state ("is there now a hole in this wall? is the bridge down? is this trench dug?") is authoritative and synced.
5. **Physics LOD by distance.** Full rigid-body sim only near active players. Distant destruction freezes, merges, and bakes to static. Far rubble is a texture, not a simulation.
6. **Aggregate bodies for vehicles.** A tank is ONE rigid body with cosmetic sub-parts + a *scripted* suspension approximation (exactly what Fezezen's auto-suspension does — it's a script, not 12 real constraints). Not 200 welded bricks.
7. **Chunked/voxel terrain for the "dig a trench" fantasy.** Destructible ground is a chunked heightfield/voxel grid. Digging = a small delta edit to a chunk, delta-compressed and replicated cheaply. This is how Pordier-style trench-building stays affordable.
8. **Tiered tickrates.** Nearby combatants update fast; distant entities and settling destruction update slow.
9. **Time dilation as a safety valve.** If a cell overloads, slow its local time (EVE-style) instead of crashing. Graceful degradation beats a server meltdown.

**The mental model:** the server is authoritative over *game truth* (who's where, what's destroyed as a gameplay fact, who shot whom) — **not** over every physical fragment. Fragments are mostly cosmetic and client-side. That division is the whole trick.

---

## 3. Where the load actually comes from

A useful surprise: at 500 players, the dominant baseline cost is usually **the players themselves** (movement + fire state, interest-managed), not static-until-hit terrain. Destruction is spiky, not constant. That means the core scaling battle is really:

- **Player-state replication** at 500 → solved by interest management + snapshot compression. Well-understood; BattleBit-tier.
- **Destruction spikes** when a building comes down near a crowd → solved by determinism + cosmetic debris + chunk baking. This is our novel risk area and the thing the harness must stress hardest.

---

## 4. Server architecture

Authoritative dedicated server, designed for horizontal scale from day one but proven incrementally:

- **Single-process, multi-threaded first.** One battle = one server process, world carved into spatial **cells**, each cell's physics on its own worker thread. Get 500 working here before touching multi-machine.
- **Cell-based authority.** Each cell owns its entities/destruction. Players near a cell boundary subscribe to both. This is "server meshing lite" — the same idea as Star Citizen but confined to one machine's cores, which is where 99% of the value is for a single-battlefield game and where almost none of the $750M pain lives.
- **Interest manager** sits between the sim and the network: computes each client's subscription set every tick.
- **Event-sourced destruction log** per cell: append-only impulse events, delta-synced, replayable for late-joiners and reconnects.
- **Graceful degradation:** per-cell time dilation + a hard cap on simultaneously-physicalized bricks per cell (excess goes straight to baked-static).

Multi-machine meshing (500 → 1000+, multiple battlefields) is a **later** phase and explicitly out of scope for proving 500.

---

## 5. Stack decision (PC + console)

Console-from-the-start is the hard constraint, and it drives the client choice more than anything else.

**Recommended split:**

- **Client engine: Unreal Engine 5.** It's the pragmatic answer to "PC + console from day one." Reasons: proven console certification paths and dev-kit support, controller input solved, and it ships with **Chaos** — a real destruction system we can build the brick look on top of. Godot is the moddability dream but has **no official console support** (you go through third-party porting houses), and a custom Rust/C++ engine makes console cert a brutal, NDA-gated lift. Neither fits "console from the start."
- **Netcode: custom authoritative dedicated server**, most likely **Rust** (memory safety matters enormously for a long-running sim server) with **Jolt** or **Rapier** for physics. We **bypass/augment Unreal's default replication** for the 500-scale layer — Unreal's out-of-the-box networking is not built for this headcount — and keep Unreal purely for rendering, input, physics visualization, and console plumbing.
- **Transport: Valve's GameNetworkingSockets.** We're Steam-bound anyway; it gives us UDP reliability layers, encryption, and NAT traversal cross-platform, essentially for free.

**The honest tension you should know about now:** *console* and *Minecraft-level moddability* pull in opposite directions. Consoles heavily restrict user-authored code (cert, no arbitrary native mods). So realistically: **deep moddability lives on PC** (data-driven content + a sandboxed scripting layer), while **console gets curated/data-only mods.** That's the same line Minecraft itself draws. Worth accepting explicitly rather than discovering late.

---

## 6. The de-risking plan — prove 500 before building a game

We do **not** build a fun game and then add players. We build the smallest thing that answers "does 500 hold?" and nothing else.

**Phase 0 — The Load Harness (the real first build).**
A headless authoritative server + a swarm of **headless bot clients** (500 of them) that walk, shoot, and trigger destruction. No art, no real client, no rendering. Pure systems. We measure:
- server CPU per tick as bot count climbs 50 → 150 → 254 → 500,
- bandwidth per client (must stay bounded via interest management),
- tick stability under a coordinated "everyone blows up the same building" stress spike,
- where it first breaks, and why.

This is the opposite of a toy — it's the hard core with all the fun stripped out so nothing hides the truth. If 500 holds here, almost everything else is "just" game-building. If it breaks at 180, we learn that in month two for cheap.

**Phase 1 — Vertical netcode + one real client.** Attach the Unreal client to the proven server. One small map, soldier + one vehicle, shoot-a-wall-apart working end to end for a real (small) player test.

**Phase 2 — Scale the fun.** Game modes, maps, vehicles, progression — layered onto netcode we already trust.

**Phase 3 — Beyond one machine.** Multi-process meshing toward 1000+ and multiple concurrent battlefields. Only if Phases 0–2 earned it.

**Phase 4 — Moddability + Steam ship.** Data-driven content pipeline, PC scripting sandbox, Workshop.

---

## 7. Risk register (the stuff that kills projects like this)

- **The graveyard is real.** Improbable/SpatialOS sold exactly this "distributed sim at scale" dream and burned hundreds of millions; most licensees' games failed — often because gameplay-agnostic infrastructure produces tech demos, not fun. **Mitigation:** co-design netcode and gameplay together after Phase 0; never build infra in a vacuum past the harness.
- **Destruction determinism is subtle.** Floating-point divergence across CPUs/platforms can desync collapses. **Mitigation:** fixed-point or carefully-constrained deterministic destruction; server remains the tiebreaker for gameplay-relevant state.
- **Console cert + cross-play networking** add real calendar time and NDA overhead. **Mitigation:** PC-first internally, but make the client-engine choice (Unreal) that keeps console a *port*, not a *rewrite*.
- **500 may not fully hold with our first destruction model.** **Mitigation:** the harness tells us the true ceiling early; if it's 300, that's still a great game (BattleBit shipped at 254) and we tune fidelity vs. headcount deliberately.
- **Scope.** This is a multi-person, multi-year effort even done well. **Mitigation:** the phased plan makes every phase independently fundable/shippable-ish, with a real go/no-go after Phase 0.

---

## 8. Immediate next step

Build **Phase 0, the load harness** — a Rust authoritative server with cell partitioning + interest management, and a bot swarm we point at the 500 number and start pushing. That single experiment converts BRICKFIELD from "vibe" to "we have a number and we know what breaks first."

---

### Sources
- [FPS made by four people tops Steam charts with massive 254-player battles — TechRadar](https://www.techradar.com/news/fps-made-by-four-people-tops-steam-charts-with-massive-254-player-battles)
- [BattleBit Remastered — Wikipedia](https://en.wikipedia.org/wiki/BattleBit_Remastered)
- [11 years and $750 million later, Star Citizen now has MMO-scale server sizes — PC Gamer](https://www.pcgamer.com/games/11-years-and-usd750-million-later-star-citizen-now-has-a-new-star-system-and-mmo-scale-server-sizes/)
