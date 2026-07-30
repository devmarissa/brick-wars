//! BRICKFIELD — native physics sandbox (Bevy + Rapier)
//! Blocky military sandbox: destructible fort + vehicles + terrain + a soldier who shoots.
//! WASD move · Space jump · Shift sprint · Left-click FIRE · V first-person · R-drag look · wheel zoom

use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};
use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::pbr::{CascadeShadowConfigBuilder, DistanceFog, FogFalloff};
use bevy::prelude::*;
use bevy::window::{CursorGrabMode, PrimaryWindow};
use bevy_rapier3d::prelude::*;
use std::collections::{HashMap, HashSet};

const BW: f32 = 4.0;
const BH: f32 = 1.2;
const BL: f32 = 2.0;
const FORT_COLORS: [u32; 8] = [
    0xb3a06a, 0xc2b280, 0x556b2f, 0x6b7a3a, 0x8a8577, 0x6e7364, 0x4b5043, 0xa1936a,
];
const OLV: u32 = 0x4a5320;
const DOLV: u32 = 0x3b4019;
const GUN: u32 = 0x24281d;
const TAN: u32 = 0xb3a06a;
const GRY: u32 = 0x8a8577;
const BLU: u32 = 0x5a6a72;
const GRN: u32 = 0x6b7a3a;
const LGY: u32 = 0x9a9a8a;
const BLK: u32 = 0x1a1d17;
const SKIN: u32 = 0xcaa472;
const PACK: u32 = 0x6b5f45;

#[derive(Component)]
struct Brick;
#[derive(Component)]
struct HudText;
#[derive(Component)]
struct PickR(f32);
#[derive(Component)]
struct Vehicle { parts: Vec<Part>, extent: f32 }
#[derive(Component)]
struct Player;
#[derive(Component)]
struct VertVel(f32);
#[derive(Component)]
struct Knock(Vec3);
#[derive(Component, Default)]
struct Settle(f32); // seconds this brick has been nearly still (see settle_governor)

const GRAV_SCALE: f32 = 2.6; // heavier fall for bricks/vehicles -> less floaty
#[derive(Component)]
struct Projectile { ttl: f32 }
#[derive(Component)]
struct Drivable { max_speed: f32, drive: f32, turn: f32, grip: f32 }

#[derive(Clone, Copy)]
struct Blast { point: Vec3, radius: f32, power: f32 }

#[derive(Clone)]
struct Part { p: Vec3, s: Vec3, c: u32, r: Quat }
fn pt(x: f32, y: f32, z: f32, sx: f32, sy: f32, sz: f32, c: u32) -> Part {
    Part { p: Vec3::new(x, y, z), s: Vec3::new(sx, sy, sz), c, r: Quat::IDENTITY }
}
fn ptr(x: f32, y: f32, z: f32, sx: f32, sy: f32, sz: f32, c: u32, rotz: f32) -> Part {
    Part { p: Vec3::new(x, y, z), s: Vec3::new(sx, sy, sz), c, r: Quat::from_rotation_z(rotz) }
}

#[derive(Resource)]
struct GameAssets { cube: Handle<Mesh>, pal: HashMap<u32, Handle<StandardMaterial>> }
#[derive(Resource, Default)]
struct BlastQueue(Vec<Blast>);
#[derive(Resource, Default)]
struct FirstPerson(bool);
#[derive(Resource, Default)]
struct Driving(Option<Entity>);
#[derive(Resource)]
struct Orbit { yaw: f32, pitch: f32, dist: f32, target: Vec3 }
impl Default for Orbit {
    fn default() -> Self { Orbit { yaw: 0.5, pitch: 0.6, dist: 46.0, target: Vec3::new(0.0, 3.0, 10.0) } }
}
#[derive(Resource)]
struct AutoTest { timer: Timer, fired: bool, on: bool }
#[derive(Resource)]
struct TestMode(bool); // cached BRICKFIELD_TEST — env::var is a syscall, never call it per-frame

fn col(hex: u32) -> Color { Color::srgb_u8((hex >> 16) as u8, (hex >> 8) as u8, hex as u8) }

// aim direction from the orbit yaw/pitch (the view direction shared by TP camera and FP eyes)
fn aim_dir(yaw: f32, pitch: f32) -> Vec3 {
    -Vec3::new(pitch.sin() * yaw.sin(), pitch.cos(), pitch.sin() * yaw.cos()).normalize()
}

fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window { title: "BRICKFIELD - physics sandbox".into(), ..default() }),
            ..default()
        }))
        .add_plugins(RapierPhysicsPlugin::<NoUserData>::default())
        .add_plugins(FrameTimeDiagnosticsPlugin)
        .insert_resource(ClearColor(col(0x9fa9a0)))
        .insert_resource(Orbit::default())
        .insert_resource(FirstPerson(std::env::var("BRICKFIELD_FP").is_ok()))
        .insert_resource(Driving::default())
        .insert_resource(BlastQueue::default())
        .insert_resource(AmbientLight { color: Color::WHITE, brightness: 350.0 })
        .insert_resource(AutoTest { timer: Timer::from_seconds(3.0, TimerMode::Once), fired: false, on: std::env::var("BRICKFIELD_TEST").is_ok() })
        .insert_resource(TestMode(std::env::var("BRICKFIELD_TEST").is_ok()))
        .add_systems(Startup, setup)
        .add_systems(Update, (player_move, fp_toggle, enter_exit, drive, orbit_camera, fire, projectiles, apply_blasts,
            settle_governor.after(apply_blasts),
            player_visibility.after(fp_toggle).after(enter_exit).after(drive),
            cursor_grab.after(fp_toggle).after(drive), auto_test, hud))
        .run();
}

fn spawn_brick(commands: &mut Commands, ga: &GameAssets, pos: Vec3, rot: Quat, size: Vec3, color: u32, linvel: Vec3, asleep: bool) {
    let m = ga.pal[&color].clone();
    let cube = ga.cube.clone();
    commands
        .spawn((
            Brick, PickR(size.max_element() * 0.6),
            RigidBody::Dynamic,
            Collider::cuboid(size.x / 2.0, size.y / 2.0, size.z / 2.0),
            ColliderMassProperties::Density(1.0),
            Velocity { linvel, angvel: Vec3::ZERO },
            Sleeping { sleeping: asleep, ..default() },
            Settle::default(),
            Friction::coefficient(0.8),
            // light damping so debris stops tumbling and can be put back to sleep quickly
            Damping { linear_damping: 0.08, angular_damping: 0.8 },
            GravityScale(GRAV_SCALE),
            Transform { translation: pos, rotation: rot, scale: Vec3::ONE },
            Visibility::default(),
        ))
        .with_children(|cb| {
            cb.spawn((Mesh3d(cube), MeshMaterial3d(m), Transform { scale: size, ..default() }));
        });
}

fn spawn_projectile(commands: &mut Commands, ga: &GameAssets, pos: Vec3, vel: Vec3) {
    let m = ga.pal[&GUN].clone();
    let cube = ga.cube.clone();
    commands
        .spawn((
            Projectile { ttl: 4.0 },
            RigidBody::Dynamic,
            Collider::ball(0.35),
            Ccd::enabled(),
            GravityScale(0.35),
            Velocity { linvel: vel, angvel: Vec3::ZERO },
            ActiveEvents::COLLISION_EVENTS,
            ActiveCollisionTypes::all(), // emit events vs static/kinematic/sleeping too, not just dynamic-dynamic
            Transform::from_translation(pos),
            Visibility::default(),
        ))
        .with_children(|cb| {
            cb.spawn((Mesh3d(cube), MeshMaterial3d(m), Transform { scale: Vec3::splat(0.7), ..default() }));
        });
}

fn body_box(cb: &mut ChildBuilder, cube: &Handle<Mesh>, pal: &HashMap<u32, Handle<StandardMaterial>>, p: Vec3, s: Vec3, c: u32) {
    cb.spawn((Mesh3d(cube.clone()), MeshMaterial3d(pal[&c].clone()), Transform { translation: p, scale: s, ..default() }));
}

// static, non-destructible terrain (elevation, ramps, berms) — one collider, near-free to drive over
fn spawn_fixed_block(commands: &mut Commands, ga: &GameAssets, pos: Vec3, size: Vec3, rot: Quat, color: u32) {
    let m = ga.pal[&color].clone();
    let cube = ga.cube.clone();
    commands.spawn((RigidBody::Fixed, Collider::cuboid(size.x / 2.0, size.y / 2.0, size.z / 2.0),
        Transform { translation: pos, rotation: rot, scale: Vec3::ONE }, Visibility::default()))
        .with_children(|cb| { cb.spawn((Mesh3d(cube), MeshMaterial3d(m), Transform { scale: size, ..default() })); });
}

// a destructible building: perimeter walls (front/back full, sides inset to avoid corner overlap),
// a doorway + windows, and a flat brick roof that collapses when the walls go. All bricks start asleep.
fn spawn_building(commands: &mut Commands, ga: &GameAssets, origin: Vec3, nx: i32, nz: i32, rows: i32, wall_c: u32, roof_c: u32) {
    let bw = 3.0f32; let bh = 1.6f32; let bt = 1.4f32;
    let half_x = nx as f32 * bw / 2.0;
    let half_z = nz as f32 * bw / 2.0;
    let door_i = nx / 2;
    for row in 0..rows {
        let y = origin.y + bh * 0.5 + row as f32 * bh;
        // front (z-) and back (z+) walls — span the full X, so corners are always closed
        for i in 0..nx {
            let x = origin.x + (i as f32 - (nx as f32 - 1.0) / 2.0) * bw;
            for zs in [-1.0f32, 1.0] {
                let z = origin.z + zs * (half_z - bt * 0.5);
                let is_door = zs < 0.0 && row < 2 && i == door_i;
                let is_window = rows >= 3 && row == rows / 2 && i % 2 == 1;
                if is_door || is_window { continue; }
                spawn_brick(commands, ga, Vec3::new(x, y, z), Quat::IDENTITY, Vec3::new(bw, bh, bt), wall_c, Vec3::ZERO, true);
            }
        }
        // side walls — interior slots only (ends skipped; corners are covered by front/back)
        for j in 1..(nz - 1).max(1) {
            let z = origin.z + (j as f32 - (nz as f32 - 1.0) / 2.0) * bw;
            for xs in [-1.0f32, 1.0] {
                let x = origin.x + xs * (half_x - bt * 0.5);
                let is_window = rows >= 3 && row == rows / 2 && j % 2 == 0;
                if is_window { continue; }
                spawn_brick(commands, ga, Vec3::new(x, y, z), Quat::IDENTITY, Vec3::new(bt, bh, bw), wall_c, Vec3::ZERO, true);
            }
        }
    }
    // flat roof resting on the walls
    let ry = origin.y + rows as f32 * bh + 0.4;
    for i in 0..nx {
        for j in 0..nz {
            let x = origin.x + (i as f32 - (nx as f32 - 1.0) / 2.0) * bw;
            let z = origin.z + (j as f32 - (nz as f32 - 1.0) / 2.0) * bw;
            spawn_brick(commands, ga, Vec3::new(x, ry, z), Quat::IDENTITY, Vec3::new(bw, 0.8, bw), roof_c, Vec3::ZERO, true);
        }
    }
}

// a blocky brick tree: stacked trunk + a chunky green canopy. Bursts apart when hit.
fn spawn_tree(commands: &mut Commands, ga: &GameAssets, base: Vec3) {
    let trunk = 0x6d4a2f; let (leaf1, leaf2) = (0x556b2f, 0x6b7a3a);
    let th = 1.5f32;
    for k in 0..3 {
        let y = base.y + th * 0.5 + k as f32 * th;
        spawn_brick(commands, ga, Vec3::new(base.x, y, base.z), Quat::IDENTITY, Vec3::new(1.1, th, 1.1), trunk, Vec3::ZERO, true);
    }
    let cy = base.y + 3.0 * th + 1.0;
    let canopy = [(0.0, 0.0, 0.0), (2.0, 0.2, 0.0), (-2.0, 0.2, 0.0), (0.0, 0.2, 2.0), (0.0, 0.2, -2.0), (0.0, 1.7, 0.0)];
    for (i, &(dx, dy, dz)) in canopy.iter().enumerate() {
        let c = if i % 2 == 0 { leaf1 } else { leaf2 };
        spawn_brick(commands, ga, Vec3::new(base.x + dx, cy + dy, base.z + dz), Quat::IDENTITY, Vec3::splat(2.2), c, Vec3::ZERO, true);
    }
}

fn setup(mut commands: Commands, mut meshes: ResMut<Assets<Mesh>>, mut mats: ResMut<Assets<StandardMaterial>>) {
    commands.spawn((Camera3d::default(),
        // distance fog: atmosphere + softly blends the far field into the sky color
        DistanceFog { color: col(0x9fa9a0), falloff: FogFalloff::Linear { start: 150.0, end: 420.0 }, ..default() },
        Transform::from_xyz(0.0, 20.0, 40.0).looking_at(Vec3::new(0.0, 3.0, 10.0), Vec3::Y)));
    commands.spawn((DirectionalLight { illuminance: 11000.0, shadows_enabled: true, ..default() },
        // 2 cascades to 170m instead of the default 4-to-the-horizon: with ~1700 shadow casters,
        // every cascade re-renders the whole brick world — this halves shadow cost outright
        CascadeShadowConfigBuilder { num_cascades: 2, maximum_distance: 170.0, ..default() }.build(),
        Transform::from_xyz(50.0, 90.0, 40.0).looking_at(Vec3::ZERO, Vec3::Y)));

    let cube = meshes.add(Cuboid::new(1.0, 1.0, 1.0));
    let mut all: Vec<u32> = FORT_COLORS.to_vec();
    all.extend_from_slice(&[OLV, DOLV, GUN, TAN, GRY, BLU, GRN, LGY, BLK, SKIN, PACK, 0x6b5f45, 0x766a4d,
        0x6d4a2f, 0x8a4b3c, 0x9a7b52, 0x707c62]);
    let mut pal: HashMap<u32, Handle<StandardMaterial>> = HashMap::new();
    for &c in &all {
        pal.entry(c).or_insert_with(|| mats.add(StandardMaterial { base_color: col(c), perceptual_roughness: 0.9, ..default() }));
    }
    let ga = GameAssets { cube: cube.clone(), pal: pal.clone() };

    // ground — collider on an UNSCALED entity; visual scale on a child (scaling the entity would scale the collider)
    commands.spawn((RigidBody::Fixed, Collider::cuboid(300.0, 2.0, 300.0), Transform::from_xyz(0.0, -2.0, 0.0), Visibility::default()))
        .with_children(|cb| {
            cb.spawn((Mesh3d(cube.clone()), MeshMaterial3d(pal[&0x6b5f45].clone()),
                Transform { scale: Vec3::new(600.0, 4.0, 600.0), ..default() }));
        });

    // fort
    let rows = 6; let len = 13i32; let wall_half = len as f32 * BW / 2.0;
    let walls = [(0.0, -wall_half, 0.0, false), (0.0, wall_half, 0.0, true),
                 (-wall_half, 0.0, std::f32::consts::FRAC_PI_2, false), (wall_half, 0.0, std::f32::consts::FRAC_PI_2, true)];
    let mut ci = 0usize;
    for &(ox, oz, rot, gap) in &walls {
        for r in 0..rows {
            let y = BH / 2.0 + r as f32 * BH; let off = if r % 2 == 1 { BW / 2.0 } else { 0.0 };
            for i in 0..len {
                let along = (i as f32 - (len as f32 - 1.0) / 2.0) * BW + off;
                if gap && along.abs() < BW * 1.5 { continue; }
                let (x, z) = if rot == 0.0 { (ox + along, oz) } else { (ox, oz + along) };
                let c = FORT_COLORS[ci % FORT_COLORS.len()]; ci += 1;
                spawn_brick(&mut commands, &ga, Vec3::new(x, y, z), Quat::from_rotation_y(rot), Vec3::new(BW, BH, BL), c, Vec3::ZERO, true);
            }
        }
    }

    // vehicles
    let tank = vec![pt(0.0,-0.4,0.0,8.0,2.0,4.2,OLV),pt(0.0,-1.3,2.5,8.4,1.4,1.1,GUN),pt(0.0,-1.3,-2.5,8.4,1.4,1.1,GUN),
        pt(0.0,0.5,2.6,8.4,0.6,0.4,DOLV),pt(0.0,0.5,-2.6,8.4,0.6,0.4,DOLV),pt(-0.5,1.2,0.0,4.2,1.6,3.2,DOLV),
        pt(-0.5,2.2,0.0,1.4,0.5,1.4,OLV),pt(3.8,1.2,0.0,6.0,0.55,0.55,GUN),pt(1.6,2.3,0.8,1.6,0.35,0.35,BLK),
        pt(3.9,-0.2,0.0,1.2,1.4,4.0,DOLV),                                   // glacis / front plate
        pt(-3.4,0.9,1.1,1.0,1.2,1.0,PACK),pt(-3.4,0.9,-1.1,1.0,1.2,1.0,PACK),// stowage bins
        pt(-1.6,2.7,1.2,0.1,2.0,0.1,BLK),                                    // antenna
        pt(-4.0,0.1,1.6,0.35,0.35,1.3,GUN),                                  // exhaust
        pt(4.0,-0.2,1.5,0.4,0.45,0.25,LGY),pt(4.0,-0.2,-1.5,0.4,0.45,0.25,LGY)]; // headlights
    let jeep = vec![pt(0.0,-0.3,0.0,6.0,1.1,3.0,TAN),pt(1.6,0.2,0.0,2.6,0.8,2.8,TAN),pt(-0.9,0.8,0.0,2.6,1.2,2.8,DOLV),
        pt(-2.6,0.4,0.0,0.5,1.2,2.8,GUN),pt(2.0,-1.0,1.6,1.4,1.4,0.7,BLK),pt(2.0,-1.0,-1.6,1.4,1.4,0.7,BLK),
        pt(-2.0,-1.0,1.6,1.4,1.4,0.7,BLK),pt(-2.0,-1.0,-1.6,1.4,1.4,0.7,BLK),
        pt(0.4,1.35,0.0,0.12,1.0,2.7,GUN),                                   // windshield frame
        pt(-0.9,1.95,1.25,0.14,1.0,0.14,GUN),pt(-0.9,1.95,-1.25,0.14,1.0,0.14,GUN),pt(-0.9,2.45,0.0,0.14,0.14,2.7,GUN), // roll bar
        pt(3.05,0.05,1.0,0.3,0.4,0.25,LGY),pt(3.05,0.05,-1.0,0.3,0.4,0.25,LGY), // headlights
        pt(-2.95,0.6,0.0,0.35,1.5,1.5,BLK),                                  // spare tyre
        pt(2.3,-0.2,0.0,0.15,0.6,3.0,GUN)];                                  // grille
    let plane = vec![pt(0.0,0.0,0.0,9.0,1.4,1.4,GRY),pt(0.5,0.15,0.0,2.8,0.35,11.0,LGY),pt(-3.7,1.1,0.0,1.3,2.1,0.35,GRY),
        pt(-3.7,0.2,0.0,1.6,0.35,4.6,LGY),pt(1.5,0.85,0.0,1.8,0.9,1.2,BLU),pt(4.7,0.0,0.0,0.5,3.4,0.5,BLK),pt(4.35,0.0,0.0,0.9,1.3,1.3,GUN)];
    let boat = vec![pt(0.0,-0.3,0.0,11.0,1.8,4.2,BLU),pt(5.6,0.3,0.0,1.8,1.1,2.6,BLU),pt(-1.8,1.1,0.0,3.4,1.6,3.0,GRY),
        pt(-1.8,2.2,0.0,0.5,1.0,0.5,BLK),pt(3.0,0.7,1.5,3.0,0.5,0.4,DOLV),pt(3.0,0.7,-1.5,3.0,0.5,0.4,DOLV)];
    let turret = vec![pt(0.0,-1.1,0.0,3.4,1.6,3.4,GRY),pt(0.0,0.3,0.0,2.4,1.2,2.4,DOLV),pt(1.9,0.7,0.55,4.2,0.4,0.4,GUN),
        pt(1.9,0.7,-0.55,4.2,0.4,0.4,GUN),pt(-0.6,0.9,0.0,1.6,1.0,1.8,OLV)];
    let aa = vec![pt(0.0,-1.9,0.0,3.4,1.0,3.4,DOLV),pt(0.0,-1.0,0.0,2.4,0.8,2.4,GRN),pt(-0.7,0.2,0.0,1.4,1.3,1.8,GUN),
        ptr(1.8,0.9,0.5,5.2,0.35,0.35,GUN,0.55),ptr(1.8,0.9,-0.5,5.2,0.35,0.35,GUN,0.55),ptr(1.8,1.7,0.5,5.2,0.35,0.35,GUN,0.55),ptr(1.8,1.7,-0.5,5.2,0.35,0.35,GUN,0.55)];
    let arty = vec![pt(0.0,-0.6,0.0,5.0,1.5,3.0,GRN),pt(0.0,-1.5,1.7,2.8,2.8,0.5,BLK),pt(0.0,-1.5,-1.7,2.8,2.8,0.5,BLK),
        ptr(1.8,1.3,0.0,9.5,0.75,0.75,DOLV,0.42),pt(-3.4,-0.8,0.0,4.5,0.45,0.45,GUN),pt(0.6,0.6,0.0,2.0,1.2,2.4,DOLV)];

    // ── hand-fitted compound hitboxes (1–4 boxes per vehicle; Part.c unused, Part.s is FULL size) ──
    // A single AABB inflated by long thin parts (barrels/wings) made you collide with empty air;
    // per-part colliders were too slow on impact. A few fitted boxes are both correct and cheap.
    let tank_hit = vec![pt(0.0,-0.7,0.0, 8.4,2.6,6.1, 0),      // hull + tracks + glacis
        pt(-0.5,1.2,0.0, 4.2,1.6,3.2, 0),                       // turret
        pt(3.8,1.2,0.0, 5.6,0.6,0.6, 0)];                       // main gun barrel
    let jeep_hit = vec![pt(0.0,-0.5,0.0, 6.0,2.4,3.4, 0),      // chassis + wheels
        pt(-0.9,0.9,0.0, 2.6,1.4,2.8, 0)];                      // cab / roll cage
    let plane_hit = vec![pt(0.0,0.0,0.0, 9.0,1.4,1.4, 0),      // fuselage
        pt(0.5,0.15,0.0, 2.8,0.4,11.0, 0),                      // wings (thin!)
        pt(-3.7,0.7,0.0, 1.6,2.9,4.6, 0)];                      // tail assembly
    let boat_hit = vec![pt(0.0,-0.3,0.0, 11.0,1.8,4.2, 0),     // hull
        pt(5.6,0.3,0.0, 1.8,1.1,2.6, 0),                        // bow
        pt(-1.8,1.1,0.0, 3.4,1.6,3.0, 0)];                      // cabin
    let turret_hit = vec![pt(0.0,-1.1,0.0, 3.4,1.6,3.4, 0),    // base
        pt(0.0,0.35,0.0, 2.6,1.3,2.6, 0),                       // housing
        pt(1.9,0.7,0.0, 4.2,0.4,1.5, 0)];                       // twin barrels
    let aa_hit = vec![pt(0.0,-1.5,0.0, 3.4,1.8,3.4, 0),        // base + pedestal
        pt(-0.7,0.2,0.0, 1.4,1.3,1.8, 0),                       // cradle
        ptr(1.8,1.3,0.0, 4.8,1.1,1.7, 0, 0.55)];                // elevated barrel cluster
    let arty_hit = vec![pt(0.0,-0.6,0.0, 5.0,1.5,3.0, 0),      // carriage
        pt(0.0,-1.5,0.0, 2.8,2.8,3.9, 0),                       // wheels + axle
        ptr(1.8,1.3,0.0, 8.0,0.8,0.8, 0, 0.42),                 // gun tube
        pt(-3.4,-0.8,0.0, 4.5,0.5,0.5, 0)];                     // trail

    // (rigidbody, pos, yaw, parts, hitboxes, drive-tuning) — Some(..) means drivable
    let pool: Vec<(RigidBody, Vec3, f32, Vec<Part>, Vec<Part>, Option<Drivable>)> = vec![
        (RigidBody::Dynamic, Vec3::new(42.0,2.7,-8.0), 0.3, tank, tank_hit, Some(Drivable { max_speed: 15.0, drive: 4200.0, turn: 5200.0, grip: 9.0 })),
        (RigidBody::Dynamic, Vec3::new(14.0,2.0,20.0), -0.6, jeep, jeep_hit, Some(Drivable { max_speed: 24.0, drive: 2400.0, turn: 2000.0, grip: 6.0 })),
        (RigidBody::Dynamic, Vec3::new(-48.0,1.8,6.0), 1.2, plane, plane_hit, None),
        (RigidBody::Dynamic, Vec3::new(46.0,2.2,44.0), 0.8, boat, boat_hit, None),
        (RigidBody::Fixed, Vec3::new(-14.0,2.2,14.0), 0.0, turret, turret_hit, None),
        (RigidBody::Dynamic, Vec3::new(-40.0,2.6,40.0), 0.6, aa, aa_hit, None),
        (RigidBody::Dynamic, Vec3::new(-6.0,3.0,-46.0), 0.1, arty, arty_hit, None),
    ];
    for (body, pos, yaw, parts, hitboxes, drivable) in pool {
        let extent = parts.iter().map(|p| p.p.length() + p.s.max_element() * 0.5).fold(0.0f32, f32::max);
        let cube2 = cube.clone(); let pal2 = pal.clone(); let parts2 = parts.clone();
        // drivables run low-friction colliders + code-side traction (see drive()); props stay grippy
        let friction = if drivable.is_some() {
            Friction { coefficient: 0.3, combine_rule: CoefficientCombineRule::Min }
        } else { Friction::coefficient(0.8) };
        let mut ec = commands.spawn((Vehicle { parts, extent }, PickR(extent), body,
            Velocity::zero(), Sleeping { sleeping: true, ..default() }, GravityScale(GRAV_SCALE),
            Transform::from_translation(pos).with_rotation(Quat::from_rotation_y(yaw)), Visibility::default()));
        ec.with_children(|cb| {
            // visuals: one mesh per part (no per-part collider)
            for part in &parts2 {
                let m = pal2[&part.c].clone();
                cb.spawn((Mesh3d(cube2.clone()), MeshMaterial3d(m),
                    Transform { translation: part.p, rotation: part.r, scale: part.s }));
            }
            // compound collision hull: a few fitted boxes, each carrying its share of the mass
            for hbx in &hitboxes {
                cb.spawn((Collider::cuboid(hbx.s.x * 0.5, hbx.s.y * 0.5, hbx.s.z * 0.5),
                    ColliderMassProperties::Density(1.2), friction,
                    Transform { translation: hbx.p, rotation: hbx.r, ..default() }));
            }
        });
        if let Some(d) = drivable {
            ec.insert((d, ExternalForce::default(), Damping { linear_damping: 0.5, angular_damping: 4.0 }));
        }
    }

    // ── varying terrain elevation (static, non-destructible so it stays cheap to drive over) ──
    // a stepped mesa on the west side...
    spawn_fixed_block(&mut commands, &ga, Vec3::new(-74.0, 3.0, -38.0), Vec3::new(38.0, 6.0, 34.0), Quat::IDENTITY, 0x6b7a3a);
    spawn_fixed_block(&mut commands, &ga, Vec3::new(-74.0, 7.0, -38.0), Vec3::new(22.0, 3.0, 20.0), Quat::IDENTITY, 0x556b2f);
    // ...with a ramp up its east face
    spawn_fixed_block(&mut commands, &ga, Vec3::new(-49.0, 2.6, -38.0), Vec3::new(24.0, 1.6, 12.0), Quat::from_rotation_z(-0.26), 0x8a8577);
    // low berms for cover and gentle elevation
    spawn_fixed_block(&mut commands, &ga, Vec3::new(28.0, 1.0, -20.0), Vec3::new(22.0, 2.0, 6.0), Quat::IDENTITY, 0x6b5f45);
    spawn_fixed_block(&mut commands, &ga, Vec3::new(-24.0, 1.2, 34.0), Vec3::new(6.0, 2.4, 20.0), Quat::IDENTITY, 0x6b5f45);
    // a raised plateau to the north-east (a building sits on top)
    spawn_fixed_block(&mut commands, &ga, Vec3::new(66.0, 1.6, -8.0), Vec3::new(26.0, 3.2, 22.0), Quat::IDENTITY, 0x707c62);

    // ── destructible buildings (chunky bricks, asleep until disturbed) ──
    spawn_building(&mut commands, &ga, Vec3::new(52.0, 0.0, -32.0), 4, 4, 3, 0x8a4b3c, DOLV);
    spawn_building(&mut commands, &ga, Vec3::new(30.0, 0.0, 56.0), 5, 3, 2, 0x9a7b52, DOLV);
    spawn_building(&mut commands, &ga, Vec3::new(-58.0, 0.0, 54.0), 3, 4, 3, GRY, DOLV);
    spawn_building(&mut commands, &ga, Vec3::new(66.0, 3.2, -8.0), 4, 4, 4, 0x8a4b3c, DOLV); // two-storey, on the plateau

    // ── brick trees scattered around the field ──
    for &(tx, tz) in &[(-30.0, -52.0), (22.0, -58.0), (-64.0, 8.0), (78.0, 22.0), (-40.0, -6.0),
        (12.0, -40.0), (-18.0, 62.0), (48.0, 62.0), (-72.0, 34.0), (84.0, -30.0), (-8.0, 44.0), (38.0, -50.0)] {
        spawn_tree(&mut commands, &ga, Vec3::new(tx, 0.0, tz));
    }

    // ── crates as low cover ──
    for &(cx, cz) in &[(40.0, -28.0), (42.0, -28.0), (41.0, -26.2), (-20.0, 20.0), (-20.0, 22.0), (18.0, 46.0)] {
        spawn_brick(&mut commands, &ga, Vec3::new(cx, 1.1, cz), Quat::IDENTITY, Vec3::splat(2.2), 0x9a7b52, Vec3::ZERO, true);
    }

    // ── diggable trench field to the north ──
    let terr_cols = [0x6b5f45u32, 0x766a4d, 0x556b2f, 0x6b7a3a, 0x8a8577];
    let step = 5.0f32; let tsize = Vec3::new(4.85, 1.5, 4.85);
    let (gx, gz, cz0) = (10i32, 8i32, 68.0f32);
    for ix in 0..gx {
        for iz in 0..gz {
            let x = (ix as f32 - (gx as f32 - 1.0) / 2.0) * step;
            let z = cz0 + (iz as f32 - (gz as f32 - 1.0) / 2.0) * step;
            for layer in 0..2 {
                let y = tsize.y / 2.0 + layer as f32 * tsize.y;
                let c = terr_cols[((ix + iz + layer) as usize) % terr_cols.len()];
                spawn_brick(&mut commands, &ga, Vec3::new(x, y, z), Quat::IDENTITY, tsize, c, Vec3::ZERO, true);
            }
        }
    }

    // player — Unturned-style soldier on a kinematic controller
    let cube3 = cube.clone(); let pal3 = pal.clone();
    commands.spawn((
        Player, VertVel(0.0), Knock(Vec3::ZERO),
        RigidBody::KinematicPositionBased,
        Collider::capsule_y(1.0, 0.6),
        KinematicCharacterController { offset: CharacterLength::Absolute(0.05), up: Vec3::Y, snap_to_ground: Some(CharacterLength::Absolute(0.5)), ..default() },
        Transform::from_xyz(0.0, 4.0, 6.0),
        Visibility::default(),
    ))
    .with_children(|cb| {
        body_box(cb, &cube3, &pal3, Vec3::new(0.42,-1.45,0.1), Vec3::new(0.72,0.5,1.15), BLK);
        body_box(cb, &cube3, &pal3, Vec3::new(-0.42,-1.45,0.1), Vec3::new(0.72,0.5,1.15), BLK);
        body_box(cb, &cube3, &pal3, Vec3::new(0.42,-0.75,0.0), Vec3::new(0.78,1.3,0.85), DOLV);
        body_box(cb, &cube3, &pal3, Vec3::new(-0.42,-0.75,0.0), Vec3::new(0.78,1.3,0.85), DOLV);
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,0.2,0.0), Vec3::new(1.6,1.5,0.95), GRN);
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,0.15,0.5), Vec3::new(1.5,1.15,0.35), GUN);
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,0.25,-0.6), Vec3::new(1.15,1.25,0.55), PACK);
        body_box(cb, &cube3, &pal3, Vec3::new(1.02,0.15,0.0), Vec3::new(0.5,1.35,0.7), OLV);
        body_box(cb, &cube3, &pal3, Vec3::new(-1.02,0.15,0.0), Vec3::new(0.5,1.35,0.7), OLV);
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,1.2,0.05), Vec3::new(0.8,0.8,0.8), SKIN);
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,1.62,0.0), Vec3::new(1.0,0.5,1.02), OLV);
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,1.45,0.55), Vec3::new(1.0,0.18,0.3), OLV);
        // collar, knee pads, and a rifle held across the chest
        body_box(cb, &cube3, &pal3, Vec3::new(0.0,0.98,0.0), Vec3::new(0.95,0.3,0.7), DOLV);
        body_box(cb, &cube3, &pal3, Vec3::new(0.42,-1.05,0.5), Vec3::new(0.5,0.35,0.32), GUN);
        body_box(cb, &cube3, &pal3, Vec3::new(-0.42,-1.05,0.5), Vec3::new(0.5,0.35,0.32), GUN);
        body_box(cb, &cube3, &pal3, Vec3::new(0.7,0.05,0.85), Vec3::new(0.22,0.32,1.5), GUN);
        body_box(cb, &cube3, &pal3, Vec3::new(0.7,0.12,1.75), Vec3::new(0.1,0.1,0.5), BLK);
        body_box(cb, &cube3, &pal3, Vec3::new(0.7,-0.28,1.0), Vec3::new(0.18,0.5,0.22), BLK);
    });

    commands.insert_resource(ga);

    // HUD + crosshair
    commands.spawn((Text::new(""), TextFont { font_size: 16.0, ..default() },
        TextColor(Color::srgb(0.92, 0.96, 1.0)),
        Node { position_type: PositionType::Absolute, top: Val::Px(12.0), left: Val::Px(14.0), ..default() }, HudText));
    commands.spawn((Text::new("+"), TextFont { font_size: 26.0, ..default() },
        TextColor(Color::srgba(1.0, 1.0, 1.0, 0.85)),
        Node { position_type: PositionType::Absolute, top: Val::Percent(48.5), left: Val::Percent(49.3), ..default() }));
}

fn player_move(
    time: Res<Time>, keys: Res<ButtonInput<KeyCode>>, mut orbit: ResMut<Orbit>, driving: Res<Driving>,
    mut q: Query<(&mut KinematicCharacterController, Option<&KinematicCharacterControllerOutput>, &mut VertVel, &mut Knock, &mut Transform), With<Player>>,
) {
    if driving.0.is_some() { return; }
    let dt = time.delta_secs().min(0.033);
    let Ok((mut kcc, out, mut vv, mut knock, mut tf)) = q.get_single_mut() else { return };
    let grounded = out.map(|o| o.grounded).unwrap_or(false);
    let yaw = orbit.yaw;
    let fwd = Vec3::new(-yaw.sin(), 0.0, -yaw.cos());
    let right = Vec3::new(yaw.cos(), 0.0, -yaw.sin());
    let mut dir = Vec3::ZERO;
    if keys.pressed(KeyCode::KeyW) { dir += fwd; }
    if keys.pressed(KeyCode::KeyS) { dir -= fwd; }
    if keys.pressed(KeyCode::KeyD) { dir += right; }
    if keys.pressed(KeyCode::KeyA) { dir -= right; }
    let speed = if keys.pressed(KeyCode::ShiftLeft) { 22.0 } else { 12.0 };
    let horiz = if dir.length_squared() > 0.0 { dir.normalize() * speed } else { Vec3::ZERO };
    if grounded && knock.0.y <= 0.1 { vv.0 = -2.0; if keys.just_pressed(KeyCode::Space) { vv.0 = 18.0; } } else { vv.0 -= 55.0 * dt; }
    // explosion knockback (decaying velocity added to movement) — kinematic bodies ignore impulses, so we apply it here
    let motion = Vec3::new(horiz.x, vv.0, horiz.z) + knock.0;
    kcc.translation = Some(motion * dt);
    knock.0 *= (1.0 - 5.0 * dt).max(0.0);
    if horiz.length_squared() > 0.1 {
        // the soldier is modelled with his FRONT on +Z (look_at aims -Z), so look AWAY from the
        // movement direction — that puts his face toward where he's going, backpack behind.
        let t = tf.translation - Vec3::new(horiz.x, 0.0, horiz.z);
        let y = tf.translation.y;
        tf.look_at(Vec3::new(t.x, y, t.z), Vec3::Y);
    }
    orbit.target = tf.translation + Vec3::new(0.0, 1.5, 0.0);
}

fn fp_toggle(keys: Res<ButtonInput<KeyCode>>, mut fp: ResMut<FirstPerson>) {
    if keys.just_pressed(KeyCode::KeyV) { fp.0 = !fp.0; }
}

fn enter_exit(
    keys: Res<ButtonInput<KeyCode>>, mut driving: ResMut<Driving>,
    mut q_player: Query<&mut Transform, With<Player>>,
    q_veh: Query<(Entity, &Transform), (With<Drivable>, Without<Player>)>,
) {
    if !keys.just_pressed(KeyCode::KeyE) { return; }
    let Ok(mut ptf) = q_player.get_single_mut() else { return };
    if let Some(v) = driving.0 {
        driving.0 = None;
        if let Ok((_, vtf)) = q_veh.get(v) {
            let side = vtf.rotation * Vec3::Z; // step out beside the vehicle
            ptf.translation = vtf.translation + side * 4.0 + Vec3::Y;
        }
    } else {
        let mut best: Option<Entity> = None; let mut bd = 12.0f32;
        for (e, t) in q_veh.iter() {
            let d = t.translation.distance(ptf.translation);
            if d < bd { bd = d; best = Some(e); }
        }
        if let Some(e) = best { driving.0 = Some(e); }
    }
}

fn player_visibility(fp: Res<FirstPerson>, driving: Res<Driving>, mut q: Query<&mut Visibility, With<Player>>) {
    let hide = fp.0 || driving.0.is_some();
    if let Ok(mut v) = q.get_single_mut() {
        let want = if hide { Visibility::Hidden } else { Visibility::Inherited };
        if *v != want { *v = want; } // write only on change — a blind write re-extracts the whole hierarchy every frame
    }
}

fn drive(
    time: Res<Time>, keys: Res<ButtonInput<KeyCode>>, driving: Res<Driving>, testmode: Res<TestMode>,
    mut orbit: ResMut<Orbit>, mut fp: ResMut<FirstPerson>,
    mut q: Query<(Entity, &Transform, &mut Velocity, &mut ExternalForce, &mut Sleeping, &Drivable)>,
) {
    let dt = time.delta_secs().min(0.05);
    for (e, tf, mut vel, mut force, mut sleep, d) in q.iter_mut() {
        if Some(e) != driving.0 {
            if force.force != Vec3::ZERO || force.torque != Vec3::ZERO {
                force.force = Vec3::ZERO; force.torque = Vec3::ZERO;
            }
            continue;
        }
        if sleep.sleeping { sleep.sleeping = false; } // write only on change (a blind write = rapier writeback every frame)
        if fp.0 { fp.0 = false; }
        let mut fwd = tf.rotation * Vec3::X; fwd.y = 0.0;
        let fwd = fwd.normalize_or_zero();
        let test = testmode.0;
        let throttle = if test { 1.0 } else if keys.pressed(KeyCode::KeyW) { 1.0 } else if keys.pressed(KeyCode::KeyS) { -1.0 } else { 0.0 };
        let steer = if test { 0.4 } else if keys.pressed(KeyCode::KeyA) { 1.0 } else if keys.pressed(KeyCode::KeyD) { -1.0 } else { 0.0 }; // A=left, D=right
        if test { eprintln!("TANK_POS {:.1},{:.1},{:.1}", tf.translation.x, tf.translation.y, tf.translation.z); }
        let fs = vel.linvel.dot(fwd);
        force.force = if throttle > 0.0 && fs < d.max_speed { fwd * d.drive }
            else if throttle < 0.0 && fs > -d.max_speed * 0.4 { -fwd * d.drive }
            else { Vec3::ZERO };
        // tanks can neutral-steer (0.45 floor); turn authority grows with forward speed
        let target_turn = steer * 1.5 * (fs.abs().min(6.0) / 6.0 * 0.55 + 0.45);
        force.torque = Vec3::Y * (target_turn - vel.angvel.y) * d.turn;
        // TRACTION: bleed sideways velocity so tyres/tracks grip — dt-scaled (framerate-independent)
        let lat = Vec3::new(-fwd.z, 0.0, fwd.x);
        let lat_speed = vel.linvel.dot(lat);
        let grip = 1.0 - (-d.grip * dt).exp();
        vel.linvel -= lat * lat_speed * grip;
        // engine braking when coasting (colliders are low-friction, so stop via the drivetrain)
        if throttle == 0.0 {
            let brake = 1.0 - (-3.0 * dt).exp();
            vel.linvel -= fwd * fs * brake;
        }
        orbit.target = tf.translation + Vec3::Y * 2.5;
    }
}

fn orbit_camera(
    mut orbit: ResMut<Orbit>, fp: Res<FirstPerson>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut motion: EventReader<MouseMotion>, mut wheel: EventReader<MouseWheel>,
    mut cam: Query<&mut Transform, With<Camera3d>>,
    player: Query<&Transform, (With<Player>, Without<Camera3d>)>,
) {
    if fp.0 {
        // first person: locked-cursor free look, no button held. Wider pitch range so you can
        // look up at planes and down your own sights (pitch is measured from straight-up).
        for ev in motion.read() {
            orbit.yaw -= ev.delta.x * 0.0035;
            orbit.pitch = (orbit.pitch - ev.delta.y * 0.0035).clamp(0.15, 2.95);
        }
    } else if buttons.pressed(MouseButton::Right) {
        for ev in motion.read() {
            orbit.yaw -= ev.delta.x * 0.005;
            orbit.pitch = (orbit.pitch - ev.delta.y * 0.005).clamp(0.15, 1.5);
        }
    } else { motion.clear(); }
    for ev in wheel.read() { orbit.dist = (orbit.dist - ev.y * 3.0).clamp(8.0, 120.0); }

    let Ok(mut t) = cam.get_single_mut() else { return };
    if fp.0 {
        if let Ok(p) = player.get_single() {
            let eye = p.translation + Vec3::new(0.0, 1.35, 0.0);
            let dir = aim_dir(orbit.yaw, orbit.pitch);
            *t = Transform::from_translation(eye).looking_at(eye + dir, Vec3::Y);
        }
    } else {
        // re-clamp pitch to the orbit range in case we just left first person looking down
        if orbit.pitch > 1.5 { orbit.pitch = 1.5; }
        let (yaw, pitch, dist, target) = (orbit.yaw, orbit.pitch, orbit.dist, orbit.target);
        let pos = target + Vec3::new(dist * pitch.sin() * yaw.sin(), dist * pitch.cos(), dist * pitch.sin() * yaw.cos());
        *t = Transform::from_translation(pos).looking_at(target, Vec3::Y);
    }
}

// lock + hide the cursor while in first person (raw MouseMotion keeps flowing while locked);
// restore the normal cursor for third person / driving.
fn cursor_grab(fp: Res<FirstPerson>, mut windows: Query<&mut Window, With<PrimaryWindow>>) {
    if !fp.is_changed() { return; }
    let Ok(mut w) = windows.get_single_mut() else { return };
    if fp.0 {
        w.cursor_options.grab_mode = CursorGrabMode::Locked;
        w.cursor_options.visible = false;
    } else {
        w.cursor_options.grab_mode = CursorGrabMode::None;
        w.cursor_options.visible = true;
    }
}

fn fire(
    buttons: Res<ButtonInput<MouseButton>>, ga: Res<GameAssets>, driving: Res<Driving>, mut commands: Commands,
    player: Query<&Transform, With<Player>>, cam: Query<&GlobalTransform, With<Camera3d>>,
) {
    if driving.0.is_some() { return; }
    if !buttons.just_pressed(MouseButton::Left) { return; }
    let Ok(pt) = player.get_single() else { return };
    let Ok(ct) = cam.get_single() else { return };
    let dir = ct.forward().as_vec3();
    let origin = pt.translation + Vec3::new(0.0, 1.3, 0.0) + dir * 1.8;
    spawn_projectile(&mut commands, &ga, origin, dir * 75.0);
}

fn projectiles(
    time: Res<Time>, mut commands: Commands, mut queue: ResMut<BlastQueue>, testmode: Res<TestMode>,
    mut ev: EventReader<CollisionEvent>, mut q: Query<(Entity, &Transform, &mut Projectile)>,
) {
    let dt = time.delta_secs();
    if testmode.0 {
        for (_, t, _) in q.iter() { eprintln!("PROJ_POS {:.1},{:.1},{:.1}", t.translation.x, t.translation.y, t.translation.z); }
    }
    let map: HashMap<Entity, Vec3> = q.iter().map(|(e, t, _)| (e, t.translation)).collect();
    let mut dead: HashSet<Entity> = HashSet::new();
    for e in ev.read() {
        if let CollisionEvent::Started(a, b, _) = e {
            for c in [*a, *b] {
                if let Some(pos) = map.get(&c) {
                    if dead.insert(c) {
                        queue.0.push(Blast { point: *pos, radius: 8.0, power: 42.0 });
                        eprintln!("PROJECTILE_IMPACT at {:.1},{:.1},{:.1}", pos.x, pos.y, pos.z);
                    }
                }
            }
        }
    }
    for (e, _, mut p) in q.iter_mut() {
        p.ttl -= dt;
        if p.ttl <= 0.0 { dead.insert(e); }
    }
    for e in dead {
        if let Some(ec) = commands.get_entity(e) { ec.despawn_recursive(); }
    }
}

fn apply_blasts(
    mut queue: ResMut<BlastQueue>, ga: Res<GameAssets>, mut commands: Commands,
    mut bricks: Query<(&Transform, &mut Velocity, &mut Sleeping), (With<Brick>, Without<Vehicle>)>,
    vehicles: Query<(Entity, &Transform, &Vehicle)>,
    mut player: Query<(&Transform, &mut Knock), With<Player>>,
) {
    if queue.0.is_empty() { return; }
    let blasts: Vec<Blast> = queue.0.drain(..).collect();
    let mut destroyed: HashSet<Entity> = HashSet::new();
    for bl in blasts {
        let (point, radius, power) = (bl.point, bl.radius, bl.power);
        // knock the soldier if he's in the blast
        if let Ok((ptf, mut knock)) = player.get_single_mut() {
            let d = ptf.translation - point; let dist = d.length();
            let reach = radius + 3.0;
            if dist < reach {
                let f = power * (1.0 - dist / reach);
                let dir = d.normalize_or_zero();
                knock.0 += dir * f * 0.7 + Vec3::Y * f * 0.5;
            }
        }
        let mut affected = 0;
        for (tf, mut vel, mut sleep) in bricks.iter_mut() {
            let d = tf.translation - point; let dist = d.length(); let dh = Vec3::new(d.x, 0.0, d.z).length();
            if dist <= radius {
                sleep.sleeping = false;
                let f = power * (1.0 - dist / radius); let inv = 1.0 / dist.max(0.7);
                vel.linvel += Vec3::new(d.x * inv * f, (d.y.abs() * inv * 0.6 + 0.5) * f, d.z * inv * f);
                affected += 1;
            } else if dh < radius * 0.75 && d.y > 0.0 { sleep.sleeping = false; }
        }
        for (e, tf, veh) in vehicles.iter() {
            if destroyed.contains(&e) { continue; }
            let reach = radius + veh.extent;
            if (tf.translation - point).length() > reach { continue; }
            destroyed.insert(e);
            if let Some(ec) = commands.get_entity(e) { ec.despawn_recursive(); }
            for part in &veh.parts {
                let mut wp = tf.translation + tf.rotation * part.p;
                let wr = tf.rotation * part.r;
                let half_y = part.s.y * 0.5;
                if wp.y < half_y + 0.05 { wp.y = half_y + 0.05; }
                let d = wp - point; let dist = d.length().max(0.7);
                let f = power * (1.0 - (dist / reach).min(0.95));
                let linvel = d / dist * f + Vec3::new(0.0, 0.18 * f, 0.0);
                spawn_brick(&mut commands, &ga, wp, wr, part.s, part.c, linvel, false);
            }
        }
        if affected > 0 { eprintln!("BLAST at {:.1},{:.1},{:.1} affected {} bricks", point.x, point.y, point.z, affected); }
    }
}

// THE frame-budget guard: Rapier's own sleep timer is far too patient for hundreds of loose
// bricks — after a collapse they sit awake grinding the contact solver for seconds. Force-sleep
// any brick that's been nearly still for a moment; under heavy load, get aggressive. A brick in
// free fall can never qualify (gravity changes its velocity ~3 m/s per window), so nothing
// freezes mid-air; anything a mover touches is woken again by Rapier as usual.
fn settle_governor(time: Res<Time>, mut q: Query<(&mut Velocity, &mut Sleeping, &mut Settle), With<Brick>>) {
    let dt = time.delta_secs();
    let awake = q.iter().filter(|(_, s, _)| !s.sleeping).count();
    let settle_after = if awake > 220 { 0.1 } else { 0.4 }; // seconds of stillness before force-sleep
    for (mut vel, mut sleep, mut st) in q.iter_mut() {
        if sleep.sleeping { continue; }
        if vel.linvel.length_squared() < 0.6 && vel.angvel.length_squared() < 0.5 {
            st.0 += dt;
            if st.0 >= settle_after {
                st.0 = 0.0;
                vel.linvel = Vec3::ZERO; vel.angvel = Vec3::ZERO;
                sleep.sleeping = true;
            }
        } else if st.0 > 0.0 { st.0 = 0.0; }
    }
}

fn auto_test(time: Res<Time>, mut at: ResMut<AutoTest>, mut driving: ResMut<Driving>, mut queue: ResMut<BlastQueue>, drivables: Query<(Entity, &Drivable)>) {
    if at.on && !at.fired {
        at.timer.tick(time.delta());
        if at.timer.finished() {
            // deterministically pick the tank (the slowest drivable) so test output is stable
            let mut best: Option<Entity> = None; let mut bs = f32::MAX;
            for (e, d) in drivables.iter() { if d.max_speed < bs { bs = d.max_speed; best = Some(e); } }
            if let Some(e) = best { driving.0 = Some(e); eprintln!("TEST: possessed drivable"); }
            // also blow a hole in the fort's front wall to exercise blast -> collapse -> settle_governor
            queue.0.push(Blast { point: Vec3::new(0.0, 2.0, -26.0), radius: 8.0, power: 42.0 });
            at.fired = true;
        }
    }
}

fn hud(diagnostics: Res<DiagnosticsStore>, time: Res<Time>, mut acc: Local<f32>,
    bricks: Query<&Sleeping, With<Brick>>, vels: Query<&Velocity>,
    fp: Res<FirstPerson>, driving: Res<Driving>, mut text: Query<&mut Text, With<HudText>>) {
    // refresh 5x/sec — rewriting UI text every frame relayouts it every frame for no reason
    *acc += time.delta_secs();
    if *acc < 0.2 { return; }
    *acc = 0.0;
    let fps = diagnostics.get(&FrameTimeDiagnosticsPlugin::FPS).and_then(|d| d.smoothed()).unwrap_or(0.0);
    let awake = bricks.iter().filter(|s| !s.sleeping).count();
    let mode = if let Some(e) = driving.0 {
        let spd = vels.get(e).map(|v| v.linvel.length()).unwrap_or(0.0);
        format!("DRIVING {spd:.0} m/s (E to exit)")
    } else if fp.0 { "on foot - 1st person".to_string() } else { "on foot - 3rd person".to_string() };
    if let Ok(mut t) = text.get_single_mut() {
        **t = format!("BRICKFIELD - native (Bevy + Rapier)   {mode}\nawake bricks: {awake}   fps: {fps:.0}\nWASD move/drive | Space jump | Shift sprint | E enter/exit vehicle\nL-click FIRE | V first-person | R-drag look | wheel zoom");
    }
}
