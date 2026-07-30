//! BRICKFIELD — Milestone 5: the fused server (the real spine)
//! ===========================================================
//! Every prior milestone proved one layer in isolation. This fuses them into ONE
//! running dedicated server and stress-tests the whole thing at once:
//!
//!   real UDP (M4) + interest management & relevance budget (M1)
//!   + real Rapier destruction (M2) + cell-sharded physics across cores (M3)
//!
//! Flow per tick, in one process:
//!   1. drain real input packets from N real client sockets
//!   2. destruction triggers spawn real rigid-body bricks into per-cell physics
//!      SHARDS (one Rapier world per hot cell), capped per cell (physics LOD)
//!   3. step all shards in PARALLEL across worker threads
//!   4. bake settled rubble back to static; drop it from the sim
//!   5. build each client an interest-managed snapshot carrying nearby players
//!      AND live brick state, and send it over the wire
//!
//! Then 500 bots connect and hammer it with movement + destruction while we
//! measure the COMBINED server tick (netcode + physics), real per-client
//! bandwidth, packet loss, and how many bricks are live at once.
//!
//! HONEST SCOPE: loopback (not real-internet latency/jitter), and a 2-core box
//! where the server shares cores with all 500 bots AND the physics workers — so
//! the CPU number here is a worst case. Bandwidth + loss are the clean metrics;
//! the CPU story is "even in that cramped setup, do the M2/M3 caps hold it?"

use rapier3d::prelude::*;
use std::collections::HashMap;
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

const HZ: u64 = 30;
const DT_MS: u64 = 1000 / HZ;
const DT: f32 = 1.0 / 30.0;
const WORLD: f32 = 4000.0;
const CELL: f32 = 250.0;
const GRID: usize = (WORLD / CELL) as usize;
const AOI: i32 = 1;
const BUDGET_PLAYERS: usize = 64;
const BUDGET_BRICKS: usize = 90; // per-snapshot live-brick relevance budget
const OBJECTIVES: usize = 10;
const IN_SZ: usize = 16;
use std::sync::atomic::AtomicUsize;
static CAP: AtomicUsize = AtomicUsize::new(260); // per-cell active-brick cap (physics LOD, M2); tunable at runtime
const SPAWN_PER_TRIGGER: usize = 12;
const BRICK: f32 = 0.4;
const SETTLE_TICKS: u32 = 12;

#[inline]
fn rng(s: &mut u64) -> u64 { let mut x=*s; x^=x>>12; x^=x<<25; x^=x>>27; *s=x; x.wrapping_mul(0x2545F4914F6CDD1D) }
#[inline]
fn frand(s: &mut u64) -> f32 { (rng(s)>>40) as f32 / (1u64<<24) as f32 }
#[inline]
fn cell_of(x: f32, z: f32) -> usize {
    let cx=(x/CELL).clamp(0.0,(GRID-1) as f32) as usize;
    let cz=(z/CELL).clamp(0.0,(GRID-1) as f32) as usize;
    cz*GRID+cx
}

/// One hot cell = one independent Rapier world.
struct Shard {
    cell: usize,
    bodies: RigidBodySet,
    colliders: ColliderSet,
    islands: IslandManager,
    broad: DefaultBroadPhase,
    narrow: NarrowPhase,
    ij: ImpulseJointSet,
    mj: MultibodyJointSet,
    ccd: CCDSolver,
    pipeline: PhysicsPipeline,
    params: IntegrationParameters,
    gravity: Vector<f32>,
    live: Vec<(RigidBodyHandle, u32, Option<u32>)>, // handle, spawn_tick, sleeping_since
    cx: f32,
    cz: f32,
}
impl Shard {
    fn new(cell: usize) -> Self {
        let mut bodies = RigidBodySet::new();
        let mut colliders = ColliderSet::new();
        let ground = bodies.insert(RigidBodyBuilder::fixed());
        colliders.insert_with_parent(ColliderBuilder::cuboid(CELL, 0.5, CELL).translation(vector![0.0,-0.5,0.0]), ground, &mut bodies);
        let cxi = (cell % GRID) as f32 * CELL + CELL/2.0;
        let czi = (cell / GRID) as f32 * CELL + CELL/2.0;
        Shard {
            cell, bodies, colliders,
            islands: IslandManager::new(), broad: DefaultBroadPhase::new(), narrow: NarrowPhase::new(),
            ij: ImpulseJointSet::new(), mj: MultibodyJointSet::new(), ccd: CCDSolver::new(),
            pipeline: PhysicsPipeline::new(), params: IntegrationParameters { dt: DT, ..Default::default() },
            gravity: vector![0.0,-30.0,0.0], live: Vec::new(), cx: cxi, cz: czi,
        }
    }
    fn spawn(&mut self, n: usize, tick: u32, seed: &mut u64) {
        for _ in 0..n {
            if self.live.len() >= CAP.load(Ordering::Relaxed) { return; }
            let x=(frand(seed)-0.5)*10.0; let z=(frand(seed)-0.5)*10.0; let y=frand(seed)*8.0+0.5;
            let rb=RigidBodyBuilder::dynamic().translation(vector![x,y,z])
                .linvel(vector![(frand(seed)-0.5)*10.0,frand(seed)*6.0,(frand(seed)-0.5)*10.0]).build();
            let h=self.bodies.insert(rb);
            self.colliders.insert_with_parent(ColliderBuilder::cuboid(BRICK,BRICK,BRICK).density(1.5),h,&mut self.bodies);
            self.live.push((h,tick,None));
        }
    }
    fn step(&mut self) {
        if self.live.is_empty() { return; }
        self.pipeline.step(&self.gravity,&self.params,&mut self.islands,&mut self.broad,&mut self.narrow,
            &mut self.bodies,&mut self.colliders,&mut self.ij,&mut self.mj,&mut self.ccd,None,&(),&());
    }
    fn bake(&mut self, tick: u32) {
        let mut rm: Vec<RigidBodyHandle>=Vec::new();
        for e in self.live.iter_mut() {
            let (h,spawn,since)=e;
            let sleeping=self.bodies.get(*h).map(|b| b.is_sleeping()).unwrap_or(true);
            if sleeping { if since.is_none(){*since=Some(tick);} } else { *since=None; }
            let settled=since.map(|s| tick-s>=SETTLE_TICKS).unwrap_or(false);
            if settled || tick-*spawn>=150 { rm.push(*h); }
        }
        for h in &rm { self.bodies.remove(*h,&mut self.islands,&mut self.colliders,&mut self.ij,&mut self.mj,true); }
        if !rm.is_empty(){ let d:std::collections::HashSet<_>=rm.into_iter().collect(); self.live.retain(|(h,_,_)| !d.contains(h)); }
    }
    /// world-space quantized brick positions for snapshotting (capped)
    fn snapshot_positions(&self, cap: usize) -> Vec<[i16;3]> {
        let mut v=Vec::with_capacity(self.live.len().min(cap));
        for (h,_,_) in self.live.iter().take(cap) {
            if let Some(b)=self.bodies.get(*h) {
                let t=b.translation();
                v.push([ (self.cx+t.x) as i16, (t.y) as i16, (self.cz+t.z) as i16 ]);
            }
        }
        v
    }
}

struct Stats {
    n: usize,
    srv_avg_ms: f64,
    srv_p99_ms: f64,
    phys_avg_ms: f64,
    down_kbps: f64,
    up_kbps: f64,
    loss_pct: f64,
    peak_active: usize,
    peak_hot: usize,
}

fn run(n: usize, secs: u64) -> Stats {
    let server = UdpSocket::bind("127.0.0.1:0").unwrap();
    server.set_nonblocking(true).unwrap();
    let srv_addr = server.local_addr().unwrap();
    let stop = Arc::new(AtomicBool::new(false));
    let bytes_down = Arc::new(AtomicU64::new(0));
    let bytes_up = Arc::new(AtomicU64::new(0));
    let snaps_sent = Arc::new(AtomicU64::new(0));

    let mut oseed = 0xB0B5 ^ n as u64;
    let objectives: Vec<(f32,f32)> = (0..OBJECTIVES).map(|_| (frand(&mut oseed)*WORLD, frand(&mut oseed)*WORLD)).collect();

    // ---- fused server thread ----
    let srv_stop=stop.clone(); let srv_down=bytes_down.clone(); let srv_up=bytes_up.clone(); let srv_snaps=snaps_sent.clone();
    let workers = std::thread::available_parallelism().map(|c| c.get()).unwrap_or(2);
    let srv = std::thread::Builder::new().stack_size(4<<20).spawn(move || {
        let mut addrs: HashMap<u16,SocketAddr>=HashMap::new();
        let mut px=vec![0f32;n]; let mut pz=vec![0f32;n]; let mut pyaw=vec![0u8;n]; let mut seen=vec![false;n];
        let mut cli_seq=vec![0u32;n];
        let mut buf=[0u8;2048];
        let mut shards: Vec<Shard>=Vec::new();
        let mut cell_idx: HashMap<usize,usize>=HashMap::new();
        let mut bins: Vec<Vec<u32>>=vec![Vec::new(); GRID*GRID];
        let mut sseed=0xDEADBEEFu64 ^ n as u64;
        let mut tick_ms:Vec<f64>=Vec::new();
        let mut phys_ms:Vec<f64>=Vec::new();
        let mut peak_active=0usize; let mut peak_hot=0usize;
        let mut tick=0u32;
        let mut snap=Vec::with_capacity(4096);

        while !srv_stop.load(Ordering::Relaxed) {
            tick+=1;
            let t0=Instant::now();
            // 1) drain inbound; collect destruction triggers
            let mut triggers:Vec<usize>=Vec::new();
            loop {
                match server.recv_from(&mut buf) {
                    Ok((len,addr)) => {
                        srv_up.fetch_add(len as u64,Ordering::Relaxed);
                        if len>=IN_SZ && buf[0]==1 {
                            let id=u16::from_le_bytes([buf[1],buf[2]]) as usize;
                            if id<n {
                                px[id]=i16::from_le_bytes([buf[7],buf[8]]) as f32;
                                pz[id]=i16::from_le_bytes([buf[9],buf[10]]) as f32;
                                pyaw[id]=buf[11]; seen[id]=true; addrs.insert(id as u16,addr);
                                if buf[12]&0x02!=0 { triggers.push(cell_of(px[id],pz[id])); }
                            }
                        }
                    }
                    Err(ref e) if e.kind()==std::io::ErrorKind::WouldBlock => break,
                    Err(_) => break,
                }
            }
            // 2) apply destruction -> spawn bricks into per-cell shards
            for c in triggers {
                let idx=*cell_idx.entry(c).or_insert_with(|| { shards.push(Shard::new(c)); shards.len()-1 });
                shards[idx].spawn(SPAWN_PER_TRIGGER, tick, &mut sseed);
            }
            // 3) step shards in PARALLEL across cores
            let p0=Instant::now();
            let chunk=(shards.len()+workers-1)/workers.max(1);
            if chunk>0 {
                std::thread::scope(|s| {
                    for grp in shards.chunks_mut(chunk) {
                        s.spawn(move || { for sh in grp.iter_mut(){ sh.step(); } });
                    }
                });
            }
            // 4) bake settled rubble
            for sh in shards.iter_mut(){ sh.bake(tick); }
            let phys_el=p0.elapsed().as_secs_f64()*1000.0;

            // brick positions per hot cell for snapshotting
            let mut brick_snap:HashMap<usize,Vec<[i16;3]>>=HashMap::new();
            let mut active_now=0usize; let mut hot_now=0usize;
            for sh in &shards { if !sh.live.is_empty(){ hot_now+=1; active_now+=sh.live.len(); brick_snap.insert(sh.cell, sh.snapshot_positions(BUDGET_BRICKS)); } }
            if active_now>peak_active{peak_active=active_now;} if hot_now>peak_hot{peak_hot=hot_now;}

            // 5) bin players + build interest-managed snapshots (players + bricks)
            for b in bins.iter_mut(){ b.clear(); }
            for i in 0..n { if seen[i] { bins[cell_of(px[i],pz[i])].push(i as u32); } }
            for id in 0..n {
                if !seen[id] { continue; }
                let addr=match addrs.get(&(id as u16)){Some(a)=>*a,None=>continue};
                let cx=(px[id]/CELL) as i32; let cz=(pz[id]/CELL) as i32;
                let mut vis:Vec<u32>=Vec::with_capacity(96);
                let mut bricks:Vec<[i16;3]>=Vec::new();
                'o: for dz in -AOI..=AOI { for dx in -AOI..=AOI {
                    let nx=cx+dx; let nz=cz+dz;
                    if nx<0||nz<0||nx>=GRID as i32||nz>=GRID as i32 {continue;}
                    let c=(nz as usize)*GRID+nx as usize;
                    for &pi in &bins[c] { if pi as usize!=id { vis.push(pi); if vis.len()>=BUDGET_PLAYERS{break 'o;} } }
                    if let Some(bs)=brick_snap.get(&c) { for b in bs { if bricks.len()<BUDGET_BRICKS { bricks.push(*b);} } }
                }}
                snap.clear(); snap.push(2u8);
                cli_seq[id]+=1; snap.extend_from_slice(&cli_seq[id].to_le_bytes());
                snap.extend_from_slice(&(vis.len() as u16).to_le_bytes());
                for &pi in &vis { let pi=pi as usize;
                    snap.extend_from_slice(&(pi as u16).to_le_bytes());
                    snap.extend_from_slice(&(px[pi] as i16).to_le_bytes());
                    snap.extend_from_slice(&(pz[pi] as i16).to_le_bytes());
                    snap.push(pyaw[pi]); }
                snap.extend_from_slice(&(bricks.len() as u16).to_le_bytes());
                for b in &bricks { snap.extend_from_slice(&b[0].to_le_bytes()); snap.extend_from_slice(&b[1].to_le_bytes()); snap.extend_from_slice(&b[2].to_le_bytes()); }
                if server.send_to(&snap,addr).is_ok() { srv_down.fetch_add(snap.len() as u64,Ordering::Relaxed); srv_snaps.fetch_add(1,Ordering::Relaxed); }
            }

            let el=t0.elapsed().as_secs_f64()*1000.0;
            tick_ms.push(el); phys_ms.push(phys_el);
            let sl=DT_MS.saturating_sub(el as u64);
            if sl>0 { std::thread::sleep(Duration::from_millis(sl)); }
        }
        tick_ms.sort_by(|a,b| a.partial_cmp(b).unwrap());
        let avg=tick_ms.iter().sum::<f64>()/tick_ms.len().max(1) as f64;
        let p99=tick_ms[((tick_ms.len() as f64*0.99) as usize).min(tick_ms.len().saturating_sub(1))];
        let pavg=phys_ms.iter().sum::<f64>()/phys_ms.len().max(1) as f64;
        (avg,p99,pavg,peak_active,peak_hot)
    }).unwrap();

    // ---- bots ----
    let snaps_recv=Arc::new(AtomicU64::new(0)); let loss=Arc::new(AtomicU64::new(0));
    let mut bots=Vec::new();
    for id in 0..n {
        let stop_b=stop.clone(); let recv_c=snaps_recv.clone(); let loss_c=loss.clone(); let objs=objectives.clone();
        let h=std::thread::Builder::new().stack_size(256*1024).spawn(move || {
            let sock=UdpSocket::bind("127.0.0.1:0").unwrap(); sock.connect(srv_addr).unwrap(); sock.set_nonblocking(true).unwrap();
            let mut s=0x1234u64 ^ (id as u64).wrapping_mul(2654435761);
            let (ox,oz)=objs[id%OBJECTIVES];
            let mut x=(ox+(frand(&mut s)-0.5)*300.0).clamp(0.0,WORLD-1.0);
            let mut z=(oz+(frand(&mut s)-0.5)*300.0).clamp(0.0,WORLD-1.0);
            let mut seq=0u32; let mut last=0u32; let mut rbuf=[0u8;4096];
            while !stop_b.load(Ordering::Relaxed) {
                x+=(ox-x)*0.02+(frand(&mut s)-0.5)*4.0; z+=(oz-z)*0.02+(frand(&mut s)-0.5)*4.0;
                x=x.clamp(0.0,WORLD-1.0); z=z.clamp(0.0,WORLD-1.0); seq+=1;
                let mut pkt=[0u8;IN_SZ]; pkt[0]=1;
                pkt[1..3].copy_from_slice(&(id as u16).to_le_bytes());
                pkt[3..7].copy_from_slice(&seq.to_le_bytes());
                pkt[7..9].copy_from_slice(&(x as i16).to_le_bytes());
                pkt[9..11].copy_from_slice(&(z as i16).to_le_bytes());
                pkt[11]=(frand(&mut s)*255.0) as u8;
                pkt[12]=if frand(&mut s)<0.05 {0x02} else {0}; // ~5%/tick trigger destruction
                let _=sock.send(&pkt);
                loop { match sock.recv(&mut rbuf) {
                    Ok(len) if len>=7 && rbuf[0]==2 => { recv_c.fetch_add(1,Ordering::Relaxed);
                        let sq=u32::from_le_bytes([rbuf[1],rbuf[2],rbuf[3],rbuf[4]]);
                        if last!=0 && sq>last+1 { loss_c.fetch_add((sq-last-1) as u64,Ordering::Relaxed); } last=sq; }
                    Ok(_)=>{}, Err(_)=>break,
                }}
                std::thread::sleep(Duration::from_millis(DT_MS));
            }
        }).unwrap();
        bots.push(h);
    }

    std::thread::sleep(Duration::from_secs(secs));
    stop.store(true,Ordering::Relaxed);
    let (savg,sp99,pavg,peak_active,peak_hot)=srv.join().unwrap();
    for h in bots { let _=h.join(); }

    let dur=secs as f64;
    let down=bytes_down.load(Ordering::Relaxed) as f64; let up=bytes_up.load(Ordering::Relaxed) as f64;
    let sent=snaps_sent.load(Ordering::Relaxed); let lost=loss.load(Ordering::Relaxed);
    Stats { n, srv_avg_ms:savg, srv_p99_ms:sp99, phys_avg_ms:pavg,
        down_kbps: down/dur/n as f64*8.0/1000.0, up_kbps: up/dur/n as f64*8.0/1000.0,
        loss_pct: if sent>0 {lost as f64/sent as f64*100.0} else {0.0}, peak_active, peak_hot }
}

fn main() {
    let cores=std::thread::available_parallelism().map(|c| c.get()).unwrap_or(2);
    println!("BRICKFIELD — Milestone 5: the FUSED server (UDP + sharded Rapier physics)");
    println!("========================================================================");
    println!("real UDP + interest mgmt (M1) + real destruction (M2) + cell-sharding (M3) + real sockets (M4), one process");
    // optional: `fused <cap>` runs a single 500-client test at that per-cell cap (to demo the LOD lever)
    let args:Vec<String>=std::env::args().collect();
    let single_cap:Option<usize>=args.get(1).and_then(|s| s.parse().ok());
    if let Some(cap)=single_cap {
        CAP.store(cap,Ordering::Relaxed);
        println!("{} Hz | per-cell active cap {} (TIGHTENED) | 500 clients | {} cores\n", HZ, cap, cores);
        let r=run(500,12);
        let budget=1000.0/HZ as f64;
        println!("500 clients @ cap {}: srv p99 {:.2} ms ({:.2} ms physics) | peak {} live bricks / {} hot cells | down {:.0} kbit/s | loss {:.2}% -> {}",
            cap, r.srv_p99_ms, r.phys_avg_ms, r.peak_active, r.peak_hot, r.down_kbps, r.loss_pct,
            if r.srv_p99_ms<budget {"IN BUDGET"} else {"still over"});
        return;
    }

    println!("{} Hz | per-cell active cap {} (physics LOD) | ~5%/tick of clients trigger destruction | {} cores (shared w/ bots+physics)\n", HZ, CAP.load(Ordering::Relaxed), cores);

    let counts=[50usize,150,254,500];
    let mut rows=Vec::new();
    for &c in &counts { rows.push(run(c,12)); }

    println!("{:>7} | {:>9} | {:>9} | {:>9} | {:>11} | {:>9} | {:>7} | {:>9} | {:>6}",
        "clients","srv avg","srv p99","phys avg","down/client","up/cli","loss","peak live","hot");
    println!("{:>7} | {:>9} | {:>9} | {:>9} | {:>11} | {:>9} | {:>7} | {:>9} | {:>6}",
        "","(ms)","(ms)","(ms)","(kbit/s)","(kbit/s)","","bricks","cells");
    println!("{}","-".repeat(94));
    for r in &rows {
        let budget=1000.0/HZ as f64;
        let flag=if r.srv_p99_ms<budget {""} else {"  <-- over budget (shared cores)"};
        println!("{:>7} | {:>9.2} | {:>9.2} | {:>9.2} | {:>11.1} | {:>9.1} | {:>6.2}% | {:>9} | {:>6}{}",
            r.n,r.srv_avg_ms,r.srv_p99_ms,r.phys_avg_ms,r.down_kbps,r.up_kbps,r.loss_pct,r.peak_active,r.peak_hot,flag);
    }
    println!("{}","-".repeat(94));

    let hi=rows.last().unwrap();
    let budget=1000.0/HZ as f64;
    println!("\nVERDICT @ 500 clients, fused server under destruction load:");
    println!("  Peak {} live bricks across {} hot cells, all flowing to clients over real UDP.", hi.peak_active, hi.peak_hot);
    println!("  Bandwidth: ~{:.0} kbit/s down + ~{:.0} kbit/s up per client -> {}", hi.down_kbps, hi.up_kbps,
        if hi.down_kbps<2000.0 {"PASS (fits any connection even with live brick state)"} else {"high"});
    println!("  Loss: {:.2}% -> {}", hi.loss_pct, if hi.loss_pct<2.0 {"clean"} else {"buffers saturating under shared-core stress"});
    println!("  Combined tick p99 {:.2} ms vs {:.1} ms budget ({} of it physics) -> {}", hi.srv_p99_ms, budget, format!("{:.2} ms", hi.phys_avg_ms),
        if hi.srv_p99_ms<budget {"IN BUDGET even on 2 shared cores"} else {"over on this 2-core box — the M2 cap + M3 sharding are the levers; a dedicated many-core host clears it"});
    println!("\n  This is the whole thesis running as ONE server: real clients, real packets, real physics, sharded, interest-managed.");
    println!("  Remaining gap is unchanged: real-internet latency/jitter + prediction/reconciliation, then a human playtest.");
}
