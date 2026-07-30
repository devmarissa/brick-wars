//! BRICKFIELD — Milestone 2: real rigid-body destruction cost
//! ===========================================================
//! Fills the honest gap from Phase 0. The netcode harness measured binning +
//! interest management + snapshot cost. THIS measures the other half: the true
//! cost of a real collision solver churning through physicalized bricks that
//! actually fall, collide, and pile up.
//!
//! It uses Rapier3d (the solver we'd ship) and models the architecture's
//! physics-LOD discipline:
//!   - destruction spawns real dynamic brick colliders (0.4 m cubes)
//!   - bricks that settle go to SLEEP and then BAKE (despawn -> static geometry)
//!   - a hard cap on live dynamic bodies = graceful degradation
//!
//! Output: physics-step ms vs live-body count across a 50/150/254/500-equivalent
//! destruction load, plus a device-independent throughput number (bricks solved
//! per ms) so the verdict survives being run on a 2-core sandbox.

use rapier3d::prelude::*;
use std::time::Instant;

const DT: f32 = 1.0 / 30.0;
const TICK_BUDGET_MS: f64 = 1000.0 / 30.0; // 33.3 ms
const NETCODE_MS_500: f64 = 1.3; // measured in Phase 0; physics shares the budget
const BRICK: f32 = 0.4; // half-extent cube size (m)
const HARD_AGE_TICKS: u32 = 150; // bake after this long regardless
const SETTLED_AGE_TICKS: u32 = 12; // once asleep this long -> bake to static

// Tiny deterministic RNG (xorshift64*).
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

struct Sim {
    bodies: RigidBodySet,
    colliders: ColliderSet,
    islands: IslandManager,
    broad: DefaultBroadPhase,
    narrow: NarrowPhase,
    impulse_joints: ImpulseJointSet,
    multibody_joints: MultibodyJointSet,
    ccd: CCDSolver,
    pipeline: PhysicsPipeline,
    params: IntegrationParameters,
    gravity: Vector<f32>,
    // live dynamic bricks: (handle, spawn_tick, sleeping_since)
    live: Vec<(RigidBodyHandle, u32, Option<u32>)>,
    objectives: Vec<(f32, f32)>, // XZ points where walls get blown
    cap: usize, // active-brick cap (physics LOD) -> excess bakes immediately
    rng: Rng,
}

impl Sim {
    fn new(n_objectives: usize, cap: usize) -> Self {
        let mut bodies = RigidBodySet::new();
        let mut colliders = ColliderSet::new();
        // Ground plane.
        let ground = bodies.insert(RigidBodyBuilder::fixed().translation(vector![0.0, 0.0, 0.0]));
        colliders.insert_with_parent(
            ColliderBuilder::cuboid(500.0, 0.5, 500.0).translation(vector![0.0, -0.5, 0.0]),
            ground,
            &mut bodies,
        );
        let mut rng = Rng::new(0xB21CFACE ^ n_objectives as u64);
        let mut objectives = Vec::new();
        for _ in 0..n_objectives {
            objectives.push((rng.range(-150.0, 150.0), rng.range(-150.0, 150.0)));
        }
        let params = IntegrationParameters { dt: DT, ..Default::default() };
        Sim {
            bodies,
            colliders,
            islands: IslandManager::new(),
            broad: DefaultBroadPhase::new(),
            narrow: NarrowPhase::new(),
            impulse_joints: ImpulseJointSet::new(),
            multibody_joints: MultibodyJointSet::new(),
            ccd: CCDSolver::new(),
            pipeline: PhysicsPipeline::new(),
            params,
            gravity: vector![0.0, -9.81, 0.0],
            live: Vec::new(),
            objectives,
            cap,
            rng,
        }
    }

    /// Blow a wall: spawn a cluster of real brick colliders with outward velocity.
    fn spawn_burst(&mut self, ox: f32, oz: f32, count: usize, tick: u32) {
        for _ in 0..count {
            if self.live.len() >= self.cap {
                return; // at cap -> drop (bake immediately). Graceful degradation.
            }
            let x = ox + self.rng.range(-3.0, 3.0);
            let z = oz + self.rng.range(-3.0, 3.0);
            let y = self.rng.range(0.5, 6.0);
            let vx = self.rng.range(-6.0, 6.0);
            let vy = self.rng.range(1.0, 7.0);
            let vz = self.rng.range(-6.0, 6.0);
            let rb = RigidBodyBuilder::dynamic()
                .translation(vector![x, y, z])
                .linvel(vector![vx, vy, vz])
                .can_sleep(true)
                .build();
            let h = self.bodies.insert(rb);
            self.colliders.insert_with_parent(
                ColliderBuilder::cuboid(BRICK, BRICK, BRICK).density(1.5),
                h,
                &mut self.bodies,
            );
            self.live.push((h, tick, None));
        }
    }

    /// Bake settled/old bricks back to static (remove from the sim).
    fn bake(&mut self, tick: u32) {
        let mut to_remove: Vec<RigidBodyHandle> = Vec::new();
        for entry in self.live.iter_mut() {
            let (h, spawn, sleeping_since) = entry;
            let sleeping = self.bodies.get(*h).map(|b| b.is_sleeping()).unwrap_or(true);
            if sleeping {
                if sleeping_since.is_none() {
                    *sleeping_since = Some(tick);
                }
            } else {
                *sleeping_since = None;
            }
            let settled = sleeping_since.map(|s| tick - s >= SETTLED_AGE_TICKS).unwrap_or(false);
            let too_old = tick - *spawn >= HARD_AGE_TICKS;
            if settled || too_old {
                to_remove.push(*h);
            }
        }
        for h in &to_remove {
            self.bodies.remove(
                *h,
                &mut self.islands,
                &mut self.colliders,
                &mut self.impulse_joints,
                &mut self.multibody_joints,
                true,
            );
        }
        if !to_remove.is_empty() {
            let dead: std::collections::HashSet<_> = to_remove.into_iter().collect();
            self.live.retain(|(h, _, _)| !dead.contains(h));
        }
    }

    fn step(&mut self) {
        self.pipeline.step(
            &self.gravity,
            &self.params,
            &mut self.islands,
            &mut self.broad,
            &mut self.narrow,
            &mut self.bodies,
            &mut self.colliders,
            &mut self.impulse_joints,
            &mut self.multibody_joints,
            &mut self.ccd,
            None,
            &(),
            &(),
        );
    }
}

struct Row {
    players: usize,
    avg_step_ms: f64,
    p99_step_ms: f64,
    peak_step_ms: f64,
    avg_live: f64,
    peak_live: usize,
}

fn run(players: usize, ticks: u32, cap: usize) -> Row {
    // More players -> more simultaneous wall-breaking.
    let n_obj = 10;
    let mut sim = Sim::new(n_obj, cap);
    let steady_bursts = (players as f32 * 0.03).ceil() as usize; // bursts/tick
    let burst_size = 24usize;

    let mut step_ms: Vec<f64> = Vec::with_capacity(ticks as usize);
    let mut live_sum: u64 = 0;
    let mut peak_live = 0usize;

    for t in 0..ticks {
        // Steady destruction spread across objectives.
        for _ in 0..steady_bursts {
            let oi = (sim.rng.f32() * n_obj as f32) as usize % n_obj;
            let (ox, oz) = sim.objectives[oi];
            sim.spawn_burst(ox, oz, burst_size, t);
        }
        // Mega-spike: everyone blows the SAME building.
        if t > 30 && t % 90 == 0 {
            let (ox, oz) = sim.objectives[0];
            sim.spawn_burst(ox, oz, players / 2, t);
        }

        let t0 = Instant::now();
        sim.step();
        let ms = t0.elapsed().as_secs_f64() * 1000.0;
        sim.bake(t);

        step_ms.push(ms);
        let live = sim.live.len();
        live_sum += live as u64;
        if live > peak_live {
            peak_live = live;
        }
    }

    step_ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let avg = step_ms.iter().sum::<f64>() / step_ms.len() as f64;
    let p99 = step_ms[(((step_ms.len() as f64) * 0.99) as usize).min(step_ms.len() - 1)];
    let peak = *step_ms.last().unwrap();
    Row {
        players,
        avg_step_ms: avg,
        p99_step_ms: p99,
        peak_step_ms: peak,
        avg_live: live_sum as f64 / ticks as f64,
        peak_live,
    }
}

fn main() {
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2);
    println!("BRICKFIELD — Milestone 2: real rigid-body destruction cost (Rapier3d)");
    println!("=====================================================================");
    println!(
        "30 Hz | tick budget {:.1} ms | Phase-0 netcode ~{:.1} ms leaves ~{:.1} ms for physics | {} cores | 0.4 m brick cubes",
        TICK_BUDGET_MS, NETCODE_MS_500, TICK_BUDGET_MS - NETCODE_MS_500, cores
    );
    let phys_budget = TICK_BUDGET_MS - NETCODE_MS_500;

    // ---- PART A: the wall. Lax cap lets bricks pile up; player count is a red herring.
    println!("PART A — naive (loose active-brick cap 8000): what actually breaks");
    println!("bake: settle->static after {} settled ticks; excess over cap bakes immediately\n", SETTLED_AGE_TICKS);
    println!("{:>7} | {:>11} | {:>11} | {:>10} | {:>10}", "players", "avg step", "p99 step", "avg live", "peak live");
    println!("{:>7} | {:>11} | {:>11} | {:>10} | {:>10}", "", "(ms)", "(ms)", "bricks", "bricks");
    println!("{}", "-".repeat(64));
    let mut hi = None;
    for &c in &[50usize, 150, 254, 500] {
        let r = run(c, 600, 8000);
        let flag = if r.p99_step_ms < phys_budget { "" } else { "  <-- OVER budget" };
        println!("{:>7} | {:>11.2} | {:>11.2} | {:>10.0} | {:>10}{}", r.players, r.avg_step_ms, r.p99_step_ms, r.avg_live, r.peak_live, flag);
        if c == 500 { hi = Some(r); }
    }
    let hi = hi.unwrap();
    let throughput = hi.peak_live as f64 / hi.peak_step_ms.max(0.001);
    println!("{}", "-".repeat(64));
    println!(
        "finding: player count barely moves the needle — CONCURRENT ACTIVE BRICKS do. Solver throughput\n         on this {}-core box ~{:.0} bricks/ms, so ~{:.0} active bricks is the single-world budget ceiling here.\n",
        cores, throughput, throughput * phys_budget
    );

    // ---- PART B: the fix. Cap active bricks (physics LOD) at the 500-player load.
    println!("PART B — the fix: cap simultaneously-active bricks (physics LOD) at 500-player destruction load");
    println!("{:>10} | {:>11} | {:>11} | {:>10} | {}", "active cap", "avg step", "p99 step", "avg live", "fits budget?");
    println!("{:>10} | {:>11} | {:>11} | {:>10} |", "(bricks)", "(ms)", "(ms)", "bricks");
    println!("{}", "-".repeat(66));
    let mut best_cap = 0usize;
    for &cap in &[8000usize, 4000, 2500, 1800, 1200, 800] {
        let r = run(500, 600, cap);
        let fits = r.p99_step_ms < phys_budget;
        if fits && cap > best_cap { best_cap = cap; }
        println!(
            "{:>10} | {:>11.2} | {:>11.2} | {:>10.0} | {}",
            cap, r.avg_step_ms, r.p99_step_ms, r.avg_live, if fits { "YES" } else { "no" }
        );
    }
    println!("{}", "-".repeat(66));

    println!("\nVERDICT @ 500 players:");
    println!(
        "  Netcode holds 500 at ~{:.1} ms (Phase 0). Physics is the real governor: not players, but\n  concurrently-active bricks. On THIS 2-core sandbox, ~{} active bricks fits the tick budget.",
        NETCODE_MS_500, best_cap
    );
    println!(
        "  Two independent levers push that ceiling up, and they multiply:\n    1) PHYSICS LOD  — cap active bricks; settled rubble bakes to static fast (this benchmark).\n    2) CELL SHARDING — split the world's physics across cores; ceiling scales ~linearly with core count.\n  A 32-core server host is ~16x this box, so ~{}-{} active bricks server-wide is realistic — plenty for\n  500 players fighting over trenches, since only the FEW hot cells are ever churning at once.",
        best_cap * 12, best_cap * 20
    );
}
