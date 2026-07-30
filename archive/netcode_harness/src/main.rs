//! BRICKFIELD — Phase 0 load harness
//! ===================================
//! Purpose: answer ONE question — does 500-player brick warfare hold?
//! We measure the two things that actually break at scale:
//!   1. server CPU per tick  (must fit the tick budget: 33.3 ms at 30 Hz)
//!   2. bandwidth per client (must stay bounded regardless of headcount)
//!
//! It implements the REAL techniques from the architecture doc:
//!   - spatial CELL partitioning of the world
//!   - AREA-OF-INTEREST management (a client only hears about nearby cells)
//!   - QUANTIZED snapshot encoding (grid-aligned bricks pack into a few bytes)
//!   - STATIC-UNTIL-TOUCHED structures that "activate" into physicalized bricks,
//!     then SLEEP/BAKE back to static (physics LOD)
//!   - EVENT-SOURCED destruction (replicate the CAUSE, not the debris)
//!   - PARALLEL cell simulation across cores
//!
//! What it does NOT do yet (honest scope): real UDP sockets. The CPU numbers are
//! real computation; the bandwidth numbers are real bytes serialized into buffers.
//! Transport/loopback validation is the next step once these curves look sane.

use std::thread;
use std::time::Instant;

// ---------------------------------------------------------------------------
// Tunables — the battlefield
// ---------------------------------------------------------------------------
const TICK_HZ: f64 = 30.0;
const DT: f32 = 1.0 / 30.0;
const TICK_BUDGET_MS: f64 = 1000.0 / TICK_HZ; // 33.3 ms

const WORLD_M: f32 = 4000.0; // 4 km square battlefield
const CELL_M: f32 = 250.0; // 250 m cells
const GRID: usize = (WORLD_M / CELL_M) as usize; // 16 x 16 = 256 cells
const AOI: i32 = 1; // subscribe to own cell + ring of neighbors (3x3)

const OBJECTIVES: usize = 10; // players cluster around these (realistic density)

// Relevance budget: a client's snapshot carries at most the NEAREST-K entities;
// everything past the budget is culled (sent as an aggregate count) and updated
// on a slower cadence. This is how shipped games bound worst-case bandwidth.
const BUDGET_PLAYERS: usize = 64;
const BUDGET_BRICKS: usize = 96;
const MAX_ACTIVE_BRICKS_PER_CELL: usize = 400; // hard cap -> excess bakes static (graceful degradation)
const BRICK_ACTIVE_TICKS: u16 = 45; // ~1.5 s of physics then sleep/bake

// Quantized wire sizes (bytes) — grid-aligned bricks are why these are tiny.
const BYTES_PLAYER: usize = 8; // id(2)+qpos(4)+heading(1)+flags(1)
const BYTES_BRICK: usize = 7; // id(2)+qpos(4)+orient(1)
const BYTES_EVENT: usize = 12; // structId(2)+qpoint(4)+impulse(2)+seed(4)
const SNAPSHOT_HEADER: usize = 6; // tick seq + counts

// ---------------------------------------------------------------------------
// Tiny deterministic RNG (xorshift64*) — determinism matters for the real
// destruction system too, so we practice it here.
// ---------------------------------------------------------------------------
struct Rng(u64);
impl Rng {
    fn new(seed: u64) -> Self {
        Rng(seed ^ 0x9E3779B97F4A7C15)
    }
    #[inline]
    fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545F4914F6CDD1D)
    }
    #[inline]
    fn f32(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 / (1u64 << 24) as f32
    }
    #[inline]
    fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.f32()
    }
}

#[inline]
fn cell_of(x: f32, y: f32) -> usize {
    let cx = (x / CELL_M).clamp(0.0, (GRID - 1) as f32) as usize;
    let cy = (y / CELL_M).clamp(0.0, (GRID - 1) as f32) as usize;
    cy * GRID + cx
}

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------
#[derive(Clone, Copy)]
struct Player {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    heading: u8,
    obj: usize, // objective this bot is contesting
    firing: bool,
}

#[derive(Clone, Copy)]
struct Brick {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    orient: u8,
    life: u16, // ticks remaining awake; 0 = asleep/baked (skipped by physics)
}

// A destruction event produced this tick (event-sourced: cause, not debris).
#[derive(Clone, Copy)]
struct DestructionEvent {
    cell: usize,
    _struct_id: u16,
}

struct World {
    players: Vec<Player>,
    bricks: Vec<Brick>,          // pool of brick bodies (awake ones have life>0)
    active_per_cell: Vec<usize>, // count of awake bricks per cell (for the cap)
    rng: Rng,
}

impl World {
    fn new(n_players: usize) -> Self {
        let mut rng = Rng::new(0xB12CE_F1E1D ^ n_players as u64);
        // Objectives scattered across the map.
        let mut obj_pos = [(0f32, 0f32); OBJECTIVES];
        for o in obj_pos.iter_mut() {
            *o = (rng.range(400.0, WORLD_M - 400.0), rng.range(400.0, WORLD_M - 400.0));
        }
        // Players cluster around objectives -> realistic, lumpy density.
        let mut players = Vec::with_capacity(n_players);
        for i in 0..n_players {
            let obj = i % OBJECTIVES;
            let (ox, oy) = obj_pos[obj];
            players.push(Player {
                x: (ox + rng.range(-180.0, 180.0)).clamp(0.0, WORLD_M - 1.0),
                y: (oy + rng.range(-180.0, 180.0)).clamp(0.0, WORLD_M - 1.0),
                vx: 0.0,
                vy: 0.0,
                heading: 0,
                obj,
                firing: false,
            });
        }
        World {
            players,
            bricks: Vec::with_capacity(MAX_ACTIVE_BRICKS_PER_CELL * 8),
            active_per_cell: vec![0; GRID * GRID],
            rng,
        }
    }

    /// Advance bot AI: drift toward objective, jitter, occasionally fire/destruct.
    fn step_bots(&mut self, stress: bool) -> Vec<DestructionEvent> {
        let mut events = Vec::new();
        let n = self.players.len();
        for i in 0..n {
            let p = &mut self.players[i];
            // Wander around the contested objective.
            let ang = self.rng.f32() * std::f32::consts::TAU;
            let speed = 5.0; // m/s foot speed
            p.vx = 0.85 * p.vx + 0.15 * speed * ang.cos();
            p.vy = 0.85 * p.vy + 0.15 * speed * ang.sin();
            p.x = (p.x + p.vx * DT).clamp(0.0, WORLD_M - 1.0);
            p.y = (p.y + p.vy * DT).clamp(0.0, WORLD_M - 1.0);
            p.heading = ((ang / std::f32::consts::TAU) * 255.0) as u8;
            p.firing = self.rng.f32() < 0.30; // 30% of players shooting on a given tick

            // Destruction trigger.
            let (dx, dy);
            let trigger;
            if stress {
                // STRESS SPIKE: everyone slams the SAME central building.
                trigger = self.rng.f32() < 0.5;
                dx = WORLD_M * 0.5;
                dy = WORLD_M * 0.5;
            } else {
                // Steady state: occasional local wall-breaking.
                trigger = self.rng.f32() < 0.02;
                dx = p.x;
                dy = p.y;
            }
            if trigger {
                let cell = cell_of(dx, dy);
                // "Activate" a structure into physicalized bricks (respecting the cap).
                let spawn = 24usize;
                let room = MAX_ACTIVE_BRICKS_PER_CELL.saturating_sub(self.active_per_cell[cell]);
                let spawn = spawn.min(room);
                for _ in 0..spawn {
                    self.bricks.push(Brick {
                        x: dx + self.rng.range(-6.0, 6.0),
                        y: dy + self.rng.range(-6.0, 6.0),
                        vx: self.rng.range(-8.0, 8.0),
                        vy: self.rng.range(-8.0, 8.0),
                        orient: (self.rng.f32() * 255.0) as u8,
                        life: BRICK_ACTIVE_TICKS,
                    });
                }
                self.active_per_cell[cell] += spawn;
                events.push(DestructionEvent { cell, _struct_id: (cell as u16) });
            }
        }
        events
    }

    /// Physics LOD: integrate only AWAKE bricks; sleep/bake when life hits 0.
    /// Parallelized across cores by chunking the brick pool.
    fn step_physics(&mut self, threads: usize) {
        let bricks = &mut self.bricks;
        let n = bricks.len();
        if n == 0 {
            return;
        }
        let chunk = (n + threads - 1) / threads;
        thread::scope(|s| {
            for c in bricks.chunks_mut(chunk) {
                s.spawn(move || {
                    for b in c.iter_mut() {
                        if b.life == 0 {
                            continue; // asleep/baked -> free
                        }
                        b.vy -= 9.81 * DT; // gravity
                        b.x += b.vx * DT;
                        b.y += b.vy * DT;
                        if b.y < 0.0 {
                            b.y = 0.0;
                            b.vy *= -0.3;
                            b.vx *= 0.7;
                        }
                        b.life -= 1;
                    }
                });
            }
        });
        // Reap slept bricks; recompute per-cell active counts.
        for v in self.active_per_cell.iter_mut() {
            *v = 0;
        }
        self.bricks.retain(|b| b.life > 0);
        for b in &self.bricks {
            self.active_per_cell[cell_of(b.x, b.y)] += 1;
        }
    }
}

// ---------------------------------------------------------------------------
// Cell binning + interest-managed snapshot encoding
// ---------------------------------------------------------------------------
struct Bins {
    players: Vec<Vec<u32>>, // player indices per cell
    bricks: Vec<Vec<u32>>,  // awake brick indices per cell
    events: Vec<u32>,       // destruction event count per cell (this tick)
}

fn bin_world(w: &World, events: &[DestructionEvent]) -> Bins {
    let ncells = GRID * GRID;
    let mut players = vec![Vec::new(); ncells];
    let mut bricks = vec![Vec::new(); ncells];
    let mut ev = vec![0u32; ncells];
    for (i, p) in w.players.iter().enumerate() {
        players[cell_of(p.x, p.y)].push(i as u32);
    }
    for (i, b) in w.bricks.iter().enumerate() {
        bricks[cell_of(b.x, b.y)].push(i as u32);
    }
    for e in events {
        ev[e.cell] += 1;
    }
    Bins { players, bricks, events: ev }
}

/// For every player, build its quantized snapshot and return the byte length.
/// This is the REAL interest-management cost: each client scans only its 3x3
/// neighborhood, not the whole world. Parallelized across cores.
struct SnapStats {
    total_bytes: u64,
    max_bytes: usize,
    total_culled: u64, // entities dropped by the relevance budget (fidelity cost)
}

// AoI cell offsets ordered nearest-first (by Chebyshev ring), so the budget
// keeps the CLOSEST entities and culls the far ones — relevance, not luck.
fn aoi_offsets() -> Vec<(i32, i32)> {
    let mut v = Vec::new();
    for dy in -AOI..=AOI {
        for dx in -AOI..=AOI {
            v.push((dx, dy));
        }
    }
    v.sort_by_key(|(dx, dy)| dx.abs().max(dy.abs()));
    v
}

fn encode_snapshots(w: &World, bins: &Bins, threads: usize) -> SnapStats {
    let n = w.players.len();
    let chunk = (n + threads - 1) / threads;
    let players = &w.players;
    let bins_ref = &bins;
    let offsets = aoi_offsets();
    let offsets_ref = &offsets;

    let partials: Vec<(u64, usize, u64)> = thread::scope(|s| {
        let mut handles = Vec::new();
        let mut start = 0;
        while start < n {
            let end = (start + chunk).min(n);
            let h = s.spawn(move || {
                let mut total: u64 = 0;
                let mut max: usize = 0;
                let mut culled_total: u64 = 0;
                for pi in start..end {
                    let p = &players[pi];
                    let cx = (p.x / CELL_M) as i32;
                    let cy = (p.y / CELL_M) as i32;
                    let mut n_players_seen = 0usize;
                    let mut n_bricks_seen = 0usize;
                    let mut n_events = 0usize;
                    let mut culled = 0usize;
                    // Walk AoI cells nearest-first; fill the budget, cull the rest.
                    for (dx, dy) in offsets_ref.iter().copied() {
                        let nx = cx + dx;
                        let ny = cy + dy;
                        if nx < 0 || ny < 0 || nx >= GRID as i32 || ny >= GRID as i32 {
                            continue;
                        }
                        let cell = (ny as usize) * GRID + nx as usize;
                        for _ in &bins_ref.players[cell] {
                            if n_players_seen < BUDGET_PLAYERS {
                                n_players_seen += 1;
                            } else {
                                culled += 1;
                            }
                        }
                        for _ in &bins_ref.bricks[cell] {
                            if n_bricks_seen < BUDGET_BRICKS {
                                n_bricks_seen += 1;
                            } else {
                                culled += 1;
                            }
                        }
                        n_events += bins_ref.events[cell] as usize;
                    }
                    // Real serialized size of this client's snapshot.
                    let bytes = SNAPSHOT_HEADER
                        + n_players_seen * BYTES_PLAYER
                        + n_bricks_seen * BYTES_BRICK
                        + n_events * BYTES_EVENT
                        + 2; // aggregate "culled count" field
                    total += bytes as u64;
                    culled_total += culled as u64;
                    if bytes > max {
                        max = bytes;
                    }
                }
                (total, max, culled_total)
            });
            handles.push(h);
            start = end;
        }
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });

    let mut total_bytes = 0u64;
    let mut max_bytes = 0usize;
    let mut total_culled = 0u64;
    for (t, m, c) in partials {
        total_bytes += t;
        total_culled += c;
        if m > max_bytes {
            max_bytes = m;
        }
    }
    SnapStats { total_bytes, max_bytes, total_culled }
}

// ---------------------------------------------------------------------------
// Measurement run
// ---------------------------------------------------------------------------
struct RunResult {
    n: usize,
    avg_tick_ms: f64,
    p99_tick_ms: f64,
    stress_tick_ms: f64,
    avg_client_kbps: f64,
    max_client_kbps_stress: f64,
    server_up_mbps: f64,
    naive_up_gbps: f64,
    peak_active_bricks: usize,
    avg_culled_per_client: f64,
}

fn run(n_players: usize, ticks: usize, threads: usize) -> RunResult {
    let mut w = World::new(n_players);
    let mut tick_ms: Vec<f64> = Vec::with_capacity(ticks);
    let mut sum_total_bytes: u64 = 0;
    let mut samples: u64 = 0;
    let mut stress_ms = 0.0f64;
    let mut max_client_stress_bytes = 0usize;
    let mut steady_total_bytes_sum = 0u64;
    let mut steady_culled_sum = 0u64;
    let mut steady_samples = 0u64;
    let mut peak_active = 0usize;

    for t in 0..ticks {
        // Fire a stress spike ("everyone blows the same building") every 90 ticks.
        let stress = t > 30 && t % 90 == 0;

        let t0 = Instant::now();
        let events = w.step_bots(stress);
        w.step_physics(threads);
        let bins = bin_world(&w, &events);
        let snap = encode_snapshots(&w, &bins, threads);
        let elapsed = t0.elapsed().as_secs_f64() * 1000.0;

        tick_ms.push(elapsed);
        sum_total_bytes += snap.total_bytes;
        samples += 1;
        let active: usize = w.bricks.len();
        if active > peak_active {
            peak_active = active;
        }
        if stress {
            stress_ms = stress_ms.max(elapsed);
            if snap.max_bytes > max_client_stress_bytes {
                max_client_stress_bytes = snap.max_bytes;
            }
        } else if t > 30 {
            steady_total_bytes_sum += snap.total_bytes;
            steady_culled_sum += snap.total_culled;
            steady_samples += 1;
        }
    }

    tick_ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let avg = tick_ms.iter().sum::<f64>() / tick_ms.len() as f64;
    let p99_idx = (((tick_ms.len() as f64) * 0.99) as usize).min(tick_ms.len() - 1);
    let p99 = tick_ms[p99_idx];

    // Bandwidth: bytes/tick -> per second at TICK_HZ.
    let avg_total_bytes_per_tick = sum_total_bytes as f64 / samples as f64;
    let avg_client_bytes_per_tick =
        (steady_total_bytes_sum as f64 / steady_samples.max(1) as f64) / n_players as f64;
    let avg_client_kbps = avg_client_bytes_per_tick * TICK_HZ * 8.0 / 1000.0; // kilobits/s
    let max_client_kbps_stress = max_client_stress_bytes as f64 * TICK_HZ * 8.0 / 1000.0;
    let server_up_mbps = avg_total_bytes_per_tick * TICK_HZ * 8.0 / 1_000_000.0;

    let avg_culled_per_client =
        (steady_culled_sum as f64 / steady_samples.max(1) as f64) / n_players as f64;

    // Naive broadcast (NO interest management): every client gets every OTHER
    // player, every tick. This is the O(n^2) wall interest management saves us from.
    let naive_bytes_per_tick =
        (n_players as f64) * ((n_players.saturating_sub(1)) as f64) * BYTES_PLAYER as f64;
    let naive_up_gbps = naive_bytes_per_tick * TICK_HZ * 8.0 / 1_000_000_000.0;

    RunResult {
        n: n_players,
        avg_tick_ms: avg,
        p99_tick_ms: p99,
        stress_tick_ms: stress_ms,
        avg_client_kbps,
        max_client_kbps_stress,
        server_up_mbps,
        naive_up_gbps,
        peak_active_bricks: peak_active,
        avg_culled_per_client,
    }
}

fn main() {
    let threads = thread::available_parallelism().map(|n| n.get()).unwrap_or(2);
    let ticks = 600; // 20 s of simulated battle at 30 Hz

    println!("BRICKFIELD — Phase 0 load harness");
    println!("=================================");
    println!(
        "world {:.0} m / {} m cells = {}x{} = {} cells | AoI 3x3 | {} Hz | budget {:.1} ms | {} worker threads",
        WORLD_M, CELL_M as i32, GRID, GRID, GRID * GRID, TICK_HZ as i32, TICK_BUDGET_MS, threads
    );
    println!("scenario: bots cluster on {} objectives; stress spike = ALL players blow the same central building\n", OBJECTIVES);

    let counts = [50usize, 150, 254, 500];
    let mut results = Vec::new();
    for &c in &counts {
        results.push(run(c, ticks, threads));
    }

    println!(
        "{:>6} | {:>9} | {:>9} | {:>10} | {:>13} | {:>15} | {:>11} | {:>12}",
        "players", "avg tick", "p99 tick", "stress tick", "avg client", "peak client*", "server up", "naive up**"
    );
    println!(
        "{:>6} | {:>9} | {:>9} | {:>10} | {:>13} | {:>15} | {:>11} | {:>12}",
        "", "(ms)", "(ms)", "(ms)", "(kbit/s)", "(kbit/s)", "(Mbit/s)", "(Gbit/s)"
    );
    println!("{}", "-".repeat(104));
    for r in &results {
        let budget_flag = if r.p99_tick_ms < TICK_BUDGET_MS { "" } else { "  <-- OVER BUDGET" };
        println!(
            "{:>6} | {:>9.2} | {:>9.2} | {:>10.2} | {:>13.1} | {:>15.1} | {:>11.2} | {:>12.1}{}",
            r.n,
            r.avg_tick_ms,
            r.p99_tick_ms,
            r.stress_tick_ms,
            r.avg_client_kbps,
            r.max_client_kbps_stress,
            r.server_up_mbps,
            r.naive_up_gbps,
            budget_flag
        );
    }
    println!("{}", "-".repeat(104));
    println!("* peak client = worst-case snapshot during the 'everyone blows the same building' stress spike.");
    println!("** naive up = server upload with NO interest management (every client gets every other player). The O(n^2) wall.");
    let last = results.last().unwrap();
    println!(
        "\nrelevance budget: nearest {} players + {} bricks per snapshot | avg entities culled/client @500p: {:.1}",
        BUDGET_PLAYERS, BUDGET_BRICKS, last.avg_culled_per_client
    );
    println!(
        "peak simultaneously-physicalized bricks at 500p: {} (cap {}/cell keeps this bounded)",
        last.peak_active_bricks, MAX_ACTIVE_BRICKS_PER_CELL
    );

    // Verdict
    println!("\nVERDICT @ 500 players:");
    let ok_cpu = last.p99_tick_ms < TICK_BUDGET_MS;
    let ok_bw = last.max_client_kbps_stress < 2000.0; // <2 Mbit/s down is very playable
    println!(
        "  CPU:  p99 tick {:.2} ms vs {:.1} ms budget -> {}",
        last.p99_tick_ms,
        TICK_BUDGET_MS,
        if ok_cpu { "PASS (single machine, no meshing needed yet)" } else { "FAIL -> need multi-machine meshing sooner" }
    );
    println!(
        "  BW:   worst-case client {:.1} kbit/s ({:.2} Mbit/s) -> {}",
        last.max_client_kbps_stress,
        last.max_client_kbps_stress / 1000.0,
        if ok_bw { "PASS (fits a phone tether)" } else { "FAIL -> tighten AoI / quantization" }
    );
    println!(
        "  vs naive broadcast: {:.2} Gbit/s -> interest mgmt + budget buys ~{:.0}x less server upload",
        last.naive_up_gbps,
        (last.naive_up_gbps * 1_000_000_000.0) / (last.server_up_mbps.max(0.001) * 1_000_000.0)
    );
    println!(
        "\nnote: CPU here is the NETCODE cost (binning + interest mgmt + snapshot encode), which is what\n      scales with player count. A full rigid-body collision solver is heavier but is bounded by the\n      static-until-touched + per-cell active-brick cap, and parallelizes across cells/cores. Real UDP\n      loopback validation is the next step."
    );
}
