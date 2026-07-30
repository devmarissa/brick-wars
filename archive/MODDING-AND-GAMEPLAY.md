# BRICKFIELD — Modding & the Gameplay Layer

*How we handle modding, and why it's the same decision as how we build vehicles, combat, and content.*

The big realization up front: **in BRICKFIELD, modding isn't a feature bolted onto the game — the game's native content format *is* the mod format.** Everything is already grid-aligned bricks + joints + a bit of script. A player who welds a tank together in the editor has, mechanically, authored a mod. That's the Roblox / Trailmakers / Besiege loop, and it's the single biggest reason this aesthetic was the right call. So the modding architecture and the gameplay architecture are one design, described below.

## The three tiers of moddability

We deliberately separate mods into tiers by *power* and *portability*, because the PC-vs-console constraint runs right through the middle.

### Tier 1 — Data-defined content (portable, console-safe)
Bricks, vehicles, weapons, structures, and maps are all declarative **data**, not code. A vehicle is a brick assembly + a stats block + a list of which automatic systems apply to it (suspension, buoyancy, thrust). A weapon is fire rate + projectile type + damage falloff. A map is a brick/voxel field + spawn/objective metadata.

Because it's pure data the engine validates, **Tier 1 ships to console** — it's the Minecraft "data pack" / Bedrock marketplace tier. And because our native creations are *already* grid-aligned brick data, user-built content and "official" content are the same format. This is the tier most players live in, and it's the tier that makes the game feel infinite without any untrusted code running anywhere.

### Tier 2 — Sandboxed scripting (portable-ish, curated for console)
For behavior beyond data — a custom vehicle system, a new game mode's rules, a gadget — we expose a **sandboxed scripting VM**. The natural pick is **Luau** (Roblox's typed, sandboxed Lua fork): it was purpose-built to run *untrusted user code at massive scale*, which is exactly our threat model, and it fits the classic-Roblox lineage of the whole project. (WASM is the alternative if we want language flexibility.)

Hard rules for Tier 2, all of which tie back to the tech we've already measured:
- **No filesystem, no network, no native calls** from user scripts — sandbox only.
- **Per-tick instruction budget.** A mod script gets a bounded slice of the tick. This is the same discipline as our 30 Hz tick budget: a badly-written mod can be *slow* but it can never stall the server, because it's cut off at its budget and its entities degrade gracefully (just like over-cap bricks bake to static).
- **Runs server-authoritative**, with cosmetic/predicted copies on clients — mods obey the same authority model as everything else, so they can't trivially cheat.
- **Determinism-friendly**, which dovetails with the destruction-determinism work: scripted effects reproduce from events, not per-object sync.

Tier 2 is portable in principle, but for **console** we promote only a *curated, reviewed* subset (data + sandboxed scripts that pass cert-compliance checks) — the same line Bethesda drew for console mods. On PC, Tier 2 is open.

### Tier 3 — Native / total-conversion mods (PC-only)
Full native code, engine-level mods, total conversions, dedicated-server plugins. This is the Garry's Mod tier. **PC only, never console** (platform cert forbids unsigned native code), and clearly labeled as such. Distributed outside the curated channel, community-run servers, run-at-your-own-risk. This is where the truly wild longevity comes from years down the line.

## Distribution

Steam Workshop for PC across all three tiers. A **curated console channel** carries the Tier-1 (and vetted Tier-2) subset, gated by automated + human review for cert compliance. One content format, three trust levels, two storefronts. Players never see the plumbing — they see "install mod."

## Why this is also the gameplay architecture

Read the tiers again as a *build plan* and they describe the base game:

- **Vehicles** = a brick assembly (Tier-1 data) + automatic **systems** that run over it. Fezezen's auto-suspension is exactly this: a system script that inspects the brick layout and rigs suspension without the player wiring constraints by hand. Thrust, buoyancy, tank tracks, aircraft lift — each is a system that operates on tagged brick data. Build the system library once; every user vehicle (official or modded) gets it for free.
- **Combat** = weapons as Tier-1 data (fire rate, projectile, spread, damage) + **server-authoritative hit resolution** (which we already have the authority model for) + destruction events (which we've already measured). A modded gun is just a new data row flowing through the same replication.
- **Physics of it all** = already handled. A modded vehicle is just more bricks; it flows through the quantized snapshot system (M1) and the capped, sharded destruction solver (M2/M3) with zero special-casing. *This is the payoff of doing the scaling work first* — content and mods don't need new netcode, because they're made of the primitives we already proved.

## The networking implication, stated plainly

Nothing a mod adds is exempt from the rules we've measured. Content mods (bricks/vehicles/weapons) ride the existing interest-managed, quantized replication — a modded tank replicates exactly like a stock one. Script mods run server-authoritative inside an instruction budget, so they can't break the tick or out-authority the server. This is what lets us promise "moddable *and* 500 players *and* console" instead of picking two — the mod system inherits the scaling guarantees rather than threatening them.

## Proposed next milestone (the gameplay bridge)

Everything above is buildable headless — no Unreal client needed yet — as the natural next step:

1. **A data-driven entity schema** — declarative brick-assembly + stats format for vehicles/weapons/structures (this *is* the Tier-1 mod format; we design it once).
2. **A systems library over brick data** — auto-suspension first (the signature feature), then thrust/buoyancy, running server-side over assemblies.
3. **A headless gameplay sim** — soldiers moving/shooting, a drivable vehicle with real suspension, server-authoritative hit resolution and destruction — all flowing through the M1–M3 netcode and physics we've already proven.

That gives us a *playable-by-bots* base game loop with the mod format baked in from the first line, before we spend a dollar of client/engine effort. Then the Unreal client is "just" rendering + input on top of a proven, moddable simulation.
