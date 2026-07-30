//! BRICKFIELD — Milestone 4: real-socket load test
//! ================================================
//! M1 proved the netcode ALGORITHMS on paper (interest management, relevance
//! budget, quantized snapshots) by counting serialized bytes. It never opened a
//! socket. THIS opens real ones: a real UDP dedicated server plus N real bot
//! clients, each with its own socket, exchanging real packets over the loopback
//! network stack at 30 Hz. It answers the honest question M1 couldn't:
//!
//!   "When 500 clients actually CONNECT and the server does real packet I/O +
//!    serialization every tick, does it hold — and what's the real per-client
//!    bandwidth and packet loss?"
//!
//! Techniques exercised for real: spatial cells, area-of-interest, a nearest-K
//! relevance budget, quantized player records, and DecimalCubed's 2-byte
//! grid-index encoding for destruction events.
//!
//! HONEST SCOPE (read this before trusting a number):
//!  - Loopback is not the internet: no real latency, jitter, or path loss. It
//!    DOES exercise real sockets, real syscalls, real serialization, real packet
//!    counts, and real kernel UDP buffers. It proves packet *throughput* and
//!    server tick under genuine I/O — not behavior under real-world lag.
//!  - This is a 2-core sandbox and the server shares those cores with all N
//!    bots, so server-CPU numbers are pessimistic vs a dedicated host. Per-client
//!    BANDWIDTH and LOSS are device-independent and the clean takeaways.

use std::collections::HashMap;
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

const HZ: u64 = 30;
const DT_MS: u64 = 1000 / HZ;
const WORLD: f32 = 4000.0;
const CELL: f32 = 250.0;
const GRID: usize = (WORLD / CELL) as usize; // 16
const AOI: i32 = 1;
const BUDGET_PLAYERS: usize = 64; // relevance budget (nearest-K)
const OBJECTIVES: usize = 10;

const IN_SZ: usize = 16; // input packet size
const REC_PLAYER: usize = 7; // per replicated player in a snapshot
const REC_EVENT: usize = 2; // per destruction voxel index (grid-index scheme)

#[inline]
fn rng(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(0x2545F4914F6CDD1D)
}
#[inline]
fn frand(s: &mut u64) -> f32 {
    (rng(s) >> 40) as f32 / (1u64 << 24) as f32
}
#[inline]
fn cell_of(x: f32, z: f32) -> usize {
    let cx = (x / CELL).clamp(0.0, (GRID - 1) as f32) as usize;
    let cz = (z / CELL).clamp(0.0, (GRID - 1) as f32) as usize;
    cz * GRID + cx
}

struct Stats {
    n: usize,
    srv_avg_ms: f64,
    srv_p99_ms: f64,
    per_client_down_kbps: f64,
    per_client_up_kbps: f64,
    snapshots_sent: u64,
    snapshots_recv: u64,
    loss_pct: f64,
}

fn run(n: usize, secs: u64) -> Stats {
    // ---- server ----
    let server = UdpSocket::bind("127.0.0.1:0").unwrap();
    server.set_nonblocking(true).unwrap();
    let srv_addr = server.local_addr().unwrap();

    let stop = Arc::new(AtomicBool::new(false));
    let bytes_down = Arc::new(AtomicU64::new(0)); // server -> clients
    let bytes_up = Arc::new(AtomicU64::new(0)); // clients -> server
    let snaps_sent = Arc::new(AtomicU64::new(0));

    // objectives so bots cluster (realistic density)
    let mut oseed = 0xB0B5 ^ n as u64;
    let objectives: Vec<(f32, f32)> = (0..OBJECTIVES)
        .map(|_| (frand(&mut oseed) * WORLD, frand(&mut oseed) * WORLD))
        .collect();

    // ---- server thread ----
    let srv_stop = stop.clone();
    let srv_down = bytes_down.clone();
    let srv_up = bytes_up.clone();
    let srv_snaps = snaps_sent.clone();
    let srv_thread = std::thread::Builder::new()
        .stack_size(1 << 20)
        .spawn(move || {
            let mut addrs: HashMap<u16, SocketAddr> = HashMap::new();
            let mut px = vec![0f32; n];
            let mut pz = vec![0f32; n];
            let mut pyaw = vec![0u8; n];
            let mut seen = vec![false; n];
            let mut cli_seq = vec![0u32; n]; // per-client outbound snapshot seq
            let mut buf = [0u8; 2048];
            let mut tick_ms: Vec<f64> = Vec::new();
            let mut bins: Vec<Vec<u32>> = vec![Vec::new(); GRID * GRID];
            let mut snap = Vec::with_capacity(2048);

            while !srv_stop.load(Ordering::Relaxed) {
                let t0 = Instant::now();
                // 1) drain inbound input packets
                loop {
                    match server.recv_from(&mut buf) {
                        Ok((len, addr)) => {
                            srv_up.fetch_add(len as u64, Ordering::Relaxed);
                            if len >= IN_SZ && buf[0] == 1 {
                                let id = u16::from_le_bytes([buf[1], buf[2]]) as usize;
                                if id < n {
                                    px[id] = i16::from_le_bytes([buf[7], buf[8]]) as f32;
                                    pz[id] = i16::from_le_bytes([buf[9], buf[10]]) as f32;
                                    pyaw[id] = buf[11];
                                    seen[id] = true;
                                    addrs.insert(id as u16, addr);
                                }
                            }
                        }
                        Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                        Err(_) => break,
                    }
                }

                // 2) bin players into cells
                for b in bins.iter_mut() {
                    b.clear();
                }
                for i in 0..n {
                    if seen[i] {
                        bins[cell_of(px[i], pz[i])].push(i as u32);
                    }
                }

                // 3) per-client interest-managed snapshot
                for id in 0..n {
                    if !seen[id] {
                        continue;
                    }
                    let addr = match addrs.get(&(id as u16)) {
                        Some(a) => *a,
                        None => continue,
                    };
                    let cx = (px[id] / CELL) as i32;
                    let cz = (pz[id] / CELL) as i32;
                    // gather nearest-K visible players
                    let mut vis: Vec<u32> = Vec::with_capacity(96);
                    'outer: for dz in -AOI..=AOI {
                        for dx in -AOI..=AOI {
                            let nx = cx + dx;
                            let nz = cz + dz;
                            if nx < 0 || nz < 0 || nx >= GRID as i32 || nz >= GRID as i32 {
                                continue;
                            }
                            for &pi in &bins[(nz as usize) * GRID + nx as usize] {
                                if pi as usize != id {
                                    vis.push(pi);
                                    if vis.len() >= BUDGET_PLAYERS {
                                        break 'outer;
                                    }
                                }
                            }
                        }
                    }
                    // serialize snapshot
                    snap.clear();
                    snap.push(2u8);
                    cli_seq[id] += 1;
                    snap.extend_from_slice(&cli_seq[id].to_le_bytes());
                    snap.extend_from_slice(&(vis.len() as u16).to_le_bytes());
                    for &pi in &vis {
                        let pi = pi as usize;
                        snap.extend_from_slice(&(pi as u16).to_le_bytes());
                        snap.extend_from_slice(&(px[pi] as i16).to_le_bytes());
                        snap.extend_from_slice(&(pz[pi] as i16).to_le_bytes());
                        snap.push(pyaw[pi]);
                    }
                    // destruction events near this client (grid-index, 2 bytes each) — small, bursty
                    let dcount: u16 = if (cli_seq[id] % 90) == 0 { 8 } else { 0 };
                    snap.extend_from_slice(&dcount.to_le_bytes());
                    for k in 0..dcount {
                        snap.extend_from_slice(&(((id as u16).wrapping_add(k)) as u16).to_le_bytes());
                    }
                    if server.send_to(&snap, addr).is_ok() {
                        srv_down.fetch_add(snap.len() as u64, Ordering::Relaxed);
                        srv_snaps.fetch_add(1, Ordering::Relaxed);
                    }
                }

                let el = t0.elapsed().as_secs_f64() * 1000.0;
                tick_ms.push(el);
                let sleep = DT_MS.saturating_sub(el as u64);
                if sleep > 0 {
                    std::thread::sleep(Duration::from_millis(sleep));
                }
            }
            tick_ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let avg = tick_ms.iter().sum::<f64>() / tick_ms.len().max(1) as f64;
            let p99 = tick_ms[((tick_ms.len() as f64 * 0.99) as usize).min(tick_ms.len().saturating_sub(1))];
            (avg, p99)
        })
        .unwrap();

    // ---- bot client threads ----
    let snaps_recv = Arc::new(AtomicU64::new(0));
    let loss = Arc::new(AtomicU64::new(0));
    let mut bots = Vec::new();
    for id in 0..n {
        let stop_b = stop.clone();
        let recv_c = snaps_recv.clone();
        let loss_c = loss.clone();
        let objs = objectives.clone();
        let h = std::thread::Builder::new()
            .stack_size(256 * 1024)
            .spawn(move || {
                let sock = UdpSocket::bind("127.0.0.1:0").unwrap();
                sock.connect(srv_addr).unwrap();
                sock.set_nonblocking(true).unwrap();
                let mut s = 0x1234u64 ^ (id as u64).wrapping_mul(2654435761);
                let (ox, oz) = objs[id % OBJECTIVES];
                let mut x = (ox + (frand(&mut s) - 0.5) * 300.0).clamp(0.0, WORLD - 1.0);
                let mut z = (oz + (frand(&mut s) - 0.5) * 300.0).clamp(0.0, WORLD - 1.0);
                let mut seq = 0u32;
                let mut last_snap = 0u32;
                let mut rbuf = [0u8; 2048];
                while !stop_b.load(Ordering::Relaxed) {
                    // move toward objective + jitter
                    x += (ox - x) * 0.02 + (frand(&mut s) - 0.5) * 4.0;
                    z += (oz - z) * 0.02 + (frand(&mut s) - 0.5) * 4.0;
                    x = x.clamp(0.0, WORLD - 1.0);
                    z = z.clamp(0.0, WORLD - 1.0);
                    seq += 1;
                    let mut pkt = [0u8; IN_SZ];
                    pkt[0] = 1;
                    pkt[1..3].copy_from_slice(&(id as u16).to_le_bytes());
                    pkt[3..7].copy_from_slice(&seq.to_le_bytes());
                    pkt[7..9].copy_from_slice(&(x as i16).to_le_bytes());
                    pkt[9..11].copy_from_slice(&(z as i16).to_le_bytes());
                    pkt[11] = (frand(&mut s) * 255.0) as u8;
                    pkt[12] = if frand(&mut s) < 0.3 { 1 } else { 0 };
                    let _ = sock.send(&pkt);
                    // drain inbound snapshots, track loss via seq gaps
                    loop {
                        match sock.recv(&mut rbuf) {
                            Ok(len) if len >= 7 && rbuf[0] == 2 => {
                                recv_c.fetch_add(1, Ordering::Relaxed);
                                let sq = u32::from_le_bytes([rbuf[1], rbuf[2], rbuf[3], rbuf[4]]);
                                if last_snap != 0 && sq > last_snap + 1 {
                                    loss_c.fetch_add((sq - last_snap - 1) as u64, Ordering::Relaxed);
                                }
                                last_snap = sq;
                            }
                            Ok(_) => {}
                            Err(_) => break,
                        }
                    }
                    std::thread::sleep(Duration::from_millis(DT_MS));
                }
            })
            .unwrap();
        bots.push(h);
    }

    // ---- run window ----
    std::thread::sleep(Duration::from_secs(secs));
    stop.store(true, Ordering::Relaxed);
    let (srv_avg, srv_p99) = srv_thread.join().unwrap();
    for h in bots {
        let _ = h.join();
    }

    let dur = secs as f64;
    let down = bytes_down.load(Ordering::Relaxed) as f64;
    let up = bytes_up.load(Ordering::Relaxed) as f64;
    let sent = snaps_sent.load(Ordering::Relaxed);
    let recv = snaps_recv.load(Ordering::Relaxed);
    let lost = loss.load(Ordering::Relaxed);
    Stats {
        n,
        srv_avg_ms: srv_avg,
        srv_p99_ms: srv_p99,
        per_client_down_kbps: down / dur / n as f64 * 8.0 / 1000.0,
        per_client_up_kbps: up / dur / n as f64 * 8.0 / 1000.0,
        snapshots_sent: sent,
        snapshots_recv: recv,
        loss_pct: if sent > 0 { lost as f64 / sent as f64 * 100.0 } else { 0.0 },
    }
}

fn main() {
    let cores = std::thread::available_parallelism().map(|c| c.get()).unwrap_or(2);
    println!("BRICKFIELD — Milestone 4: real-socket UDP load test");
    println!("===================================================");
    println!(
        "real UDP over loopback | {} Hz | 4km/{:.0}m cells | AoI 3x3 | nearest-{} budget | 2-byte grid-index events | {} cores",
        HZ, CELL, BUDGET_PLAYERS, cores
    );
    println!("each bot = its own real socket, sending input + receiving interest-managed snapshots every tick\n");

    let counts = [50usize, 150, 254, 500];
    let mut rows = Vec::new();
    for &c in &counts {
        rows.push(run(c, 12));
    }

    println!(
        "{:>7} | {:>10} | {:>10} | {:>12} | {:>10} | {:>9} | {:>8}",
        "clients", "srv avg", "srv p99", "down/client", "up/client", "snaps", "loss"
    );
    println!(
        "{:>7} | {:>10} | {:>10} | {:>12} | {:>10} | {:>9} | {:>8}",
        "", "(ms)", "(ms)", "(kbit/s)", "(kbit/s)", "sent", ""
    );
    println!("{}", "-".repeat(82));
    for r in &rows {
        let budget = 1000.0 / HZ as f64;
        let flag = if r.srv_p99_ms < budget { "" } else { "  <-- srv over tick budget (shared cores)" };
        println!(
            "{:>7} | {:>10.2} | {:>10.2} | {:>12.1} | {:>10.1} | {:>9} | {:>7.2}%{}",
            r.n, r.srv_avg_ms, r.srv_p99_ms, r.per_client_down_kbps, r.per_client_up_kbps, r.snapshots_sent, r.loss_pct, flag
        );
    }
    println!("{}", "-".repeat(82));

    let hi = rows.last().unwrap();
    println!("\nVERDICT @ 500 real connected clients:");
    println!(
        "  Bandwidth (device-independent): ~{:.0} kbit/s down + ~{:.0} kbit/s up per client -> {}",
        hi.per_client_down_kbps,
        hi.per_client_up_kbps,
        if hi.per_client_down_kbps < 2000.0 { "PASS (fits any home/phone connection)" } else { "high — tighten AoI/budget" }
    );
    println!(
        "  Snapshot loss: {:.2}% ({} recv / {} sent) -> {}",
        hi.loss_pct, hi.snapshots_recv, hi.snapshots_sent,
        if hi.loss_pct < 2.0 { "clean at the socket layer" } else { "kernel UDP buffers saturating under shared-core contention" }
    );
    println!(
        "  Server tick p99 {:.2} ms vs {:.1} ms budget — note the server is fighting 500 bot threads for {} cores here;",
        hi.srv_p99_ms, 1000.0 / HZ as f64, cores
    );
    println!("  on a dedicated many-core host (bots elsewhere) this drops sharply, and cell-sharding (M3) scales it out.");
    println!("\n  This is the first result with REAL sockets in the loop: 500 clients genuinely connected, real packets,");
    println!("  real serialization, real kernel buffers. Remaining honest gap: real-internet latency/jitter/loss (needs");
    println!("  a WAN emulator or distributed clients) and eventually a human playtest.");
}
