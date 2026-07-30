# BRICKFIELD — native

The physics sandbox as a **real cross-platform native app** (macOS / Windows / Linux), built on **Bevy** (engine + rendering) and **Rapier** (the same physics engine we validated in the server harness, milestones M2–M5). No browser.

## Run it on your Mac

You need the Rust toolchain once:

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Then, from this folder:

```
cargo run --release
```

The first build downloads and compiles Bevy (a few minutes). After that it's instant. A window opens with the brick fort.

## Controls

- **Left-click** — detonate at the point under the cursor (bricks in range fly; bricks above lose support and fall)
- **Right-drag** — orbit the camera
- **Mouse wheel** — zoom
- **WASD** — pan across the field

## What's real here

Every brick is a genuine Rapier rigid body. They start asleep so the walls stand crisp and cost nothing until something disturbs them; hit them and it's real momentum, real collapse — no scripted animation. The HUD shows how many bricks are actively simulating (the M2 "active-brick" governor, live).

## Status / next

This is the native foundation: ground, destructible brick fort, orbit camera, real explosions. Coming next, ported from the browser prototype:

- the breakable multi-part vehicle (chassis + wheels on real axles + armor panels on breakable joints)
- wiring the client to the real UDP server (M1/M4) so this becomes the actual networked game client
- the data-driven brick/vehicle content format (which doubles as the mod format)

Build note: on Linux you need a few dev libraries (`libasound2-dev libudev-dev libwayland-dev libxkbcommon-dev`); macOS and Windows need nothing beyond Rust.
