extends Node3D
## BRICKFIELD: WESTERN FRONT — trench-warfare brick physics (Godot + Jolt).
## "Pordier at War, but everything is actually physical."
## Two trench networks face each other across a cratered no-man's-land. Every trench wall,
## sandbag, wire fence and ruin is a real rigid body: artillery genuinely carves the field.
##
## On foot:  WASD · Space jump · Shift sprint · 1/2/3 rifle/rocket/grenade · L-click fire ·
##           V first person · E enter vehicle · Esc release mouse
## Driving:  WASD drive · L-click fire · V cockpit view · E exit
## Plane:    hold W; past takeoff speed it lifts off and flies toward your AIM
## Turret / AA / Artillery: E to man, aim with mouse, L-click to fire

# ---------- palette (weathered, muted — mud, wood, canvas, field grey) ----------
const OLV := 0x50543a      # allied drab
const DOLV := 0x3f4230
const GUN := 0x2b2a24
const TAN := 0x8a7a58
const GRY := 0x767468
const BLU := 0x5c6660
const GRN := 0x5a5c42
const LGY := 0x8f8c7c
const BLK := 0x232019
const SKIN := 0xc4a26e
const PACK := 0x584c39
const MUD := 0x5e5240
const MUD2 := 0x6a5c47
const CLAY := 0x74604a
const WOOD := 0x6a5138
const WOOD2 := 0x584431
const SBAG := 0x9a8a68
const SBAG2 := 0x8b7c5e
const STONE := 0x7d7a70
const STONE2 := 0x6e6b62
const FGREY := 0x686d66    # enemy field grey
const FGREY2 := 0x565b55
const WIRE := 0x4a4440
const CANVAS := 0x7d7460

# ---------- feel-tuning knobs ----------
const FP_SENS := 0.0035
const ORBIT_SENS := 0.005
const SHATTER_POWER := 25.0
const LAKE_RECT := Rect2(85, -60, 30, 120)   # the river east of the battlefield (x, z, w, h)
const WATER_LEVEL := 1.4
const SHADES := [1.0, 0.92, 0.85, 1.06]      # per-brick tint variation — kills the "clean lego" look

const DRIVER_EYE := {
	"tank": Vector3(0.9, 2.35, 0), "jeep": Vector3(-0.9, 1.75, 0.8), "plane": Vector3(1.4, 1.4, 0),
	"boat": Vector3(-1.8, 2.35, 0), "turret": Vector3(-1.6, 1.7, 0), "aa": Vector3(-1.6, 1.7, 0),
	"arty": Vector3(-2.6, 1.7, 0)}

var mats := {}
var unit_box := BoxMesh.new()
var brick_pm := PhysicsMaterial.new()
var drive_pm := PhysicsMaterial.new()
var bounce_pm := PhysicsMaterial.new()

var cam: Camera3D
var player: Player
var earth: EarthField
var spoil := 8            # sandbags-worth of dirt you're carrying (dig to earn, R-click to place)
var hud: Label
var yaw := 0.0            # start facing the enemy line (-z)
var pitch := 1.45         # near the horizon — you wake up looking across no-man's-land
var dist := 46.0
var cam_target := Vector3.ZERO
var first_person := true  # this is a shooter: FP is the default, V for third person
var vehicle_fp := false
var driving: Vehicle = null
var weapon := 1
var cooldowns := {}
var capture_grace := 0.0
var blast_queue: Array = []
var scorches: Array = []
var hud_acc := 0.0

var snd_shot: AudioStreamWAV
var snd_boom: AudioStreamWAV

# ---------- first-person presentation (Pass 1 of the craft phase) ----------
var viewmodel: Node3D          # blocky arms + held weapon, child of the camera
var vm_roots := {}             # weapon id -> its viewmodel root
var vm_sway := Vector3.ZERO    # mouse-look lag
var vm_kick := 0.0             # recoil punch, decays
var vm_raise := 1.0            # 0..1 raise animation on weapon switch
var bob_phase := 0.0
var prev_weapon := 1
var ads := 0.0                 # aim-down-sights blend (rifle, hold R-click)
var vm_bolt_t := 0.0           # bolt-cycle animation timer (rifle is BOLT-ACTION now)
var vm_reload_t := 0.0         # rocket reload animation timer
var vm_throw_t := 0.0          # grenade throw swing timer
var nade_charging := false     # holding L with grenade: show the arc, release to throw
var lmb_prev := false
var cam_shake := 0.0           # explosion/cannon camera shake
var recoil_return := 0.0       # portion of recoil the camera walks back after a shot
var vm_bolt: MeshInstance3D    # the rifle's bolt handle (slides during the cycle)
var vm_bolt_base := Vector3.ZERO
var arc_mesh := ImmediateMesh.new()
var arc_mi: MeshInstance3D
const ADS_OFFSET := Vector3(-0.35, 0.095, 0.12)

var test_mode := false
var test_t := 0.0
var test_stage := 0

func _ready() -> void:
	test_mode = OS.get_environment("BRICKFIELD_TEST") != ""
	brick_pm.friction = 0.8
	drive_pm.friction = 0.3
	bounce_pm.friction = 0.6
	bounce_pm.bounce = 0.45
	_build_audio()
	_build_environment()
	_build_world()
	_build_player()
	_build_hud()
	_build_viewmodel()
	_apply_camera_mode()
	# grenade trajectory preview line
	arc_mi = MeshInstance3D.new()
	arc_mi.mesh = arc_mesh
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color(1.0, 0.95, 0.6, 0.85)
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mi.material_override = am
	arc_mi.visible = false
	add_child(arc_mi)
	_initial_sleep()
	if not test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		capture_grace = 0.3

func _initial_sleep() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for b in get_tree().get_nodes_in_group("bricks"):
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.sleeping = true
	for v in get_tree().get_nodes_in_group("vehicles"):
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		v.sleeping = true

# ============================ audio (procedural) ============================

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	s.data = data
	return s

func _build_audio() -> void:
	var shot := PackedFloat32Array()
	shot.resize(2600)
	for i in shot.size():
		var t := float(i) / 22050.0
		shot[i] = (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.9
	snd_shot = _wav(shot)
	var boom := PackedFloat32Array()
	boom.resize(20000)
	var lp := 0.0
	for i in boom.size():
		var t := float(i) / 22050.0
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.12
		boom[i] = clampf((lp * 2.2 + sin(TAU * 52.0 * t * exp(-t * 1.5)) * 0.8) * exp(-t * 4.5), -1.0, 1.0)
	snd_boom = _wav(boom)

func _sound(pos: Vector3, stream: AudioStream, vol_db := 0.0, pitch_scale := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch_scale
	p.unit_size = 30.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

# ============================ materials / environment ============================

func mat(c: int, shade := 0) -> StandardMaterial3D:
	var key := c * 8 + shade
	if not mats.has(key):
		var f: float = SHADES[shade]
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(
			clampf(((c >> 16) & 0xFF) / 255.0 * f, 0, 1),
			clampf(((c >> 8) & 0xFF) / 255.0 * f, 0, 1),
			clampf((c & 0xFF) / 255.0 * f, 0, 1))
		m.roughness = 0.85    # matte and weathered, not plastic
		mats[key] = m
	return mats[key]

func matv(c: int) -> StandardMaterial3D:
	return mat(c, randi() % SHADES.size())

func _build_environment() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 20, 70)
	add_child(cam)
	cam.look_at(Vector3(0, 2, 0))
	cam.current = true
	get_viewport().msaa_3d = Viewport.MSAA_2X

	# overcast western-front light: pale sun, heavy haze
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.05
	sun.light_color = Color8(242, 234, 216)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 170.0
	add_child(sun)
	sun.look_at_from_position(Vector3(40, 70, 55), Vector3.ZERO, Vector3.UP)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color8(0x8a, 0x94, 0x90)
	sky_mat.sky_horizon_color = Color8(0xb0, 0xb3, 0xa5)
	sky_mat.ground_horizon_color = Color8(0xb0, 0xb3, 0xa5)
	sky_mat.ground_bottom_color = Color8(0x6a, 0x66, 0x58)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color8(0xa8, 0xab, 0x9c)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ============================ low-level spawners ============================

func _static_box(pos: Vector3, size: Vector3, color: int, rotz := 0.0, rotx := 0.0) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box
	mi.scale = size
	mi.material_override = matv(color)
	b.add_child(mi)
	b.transform = Transform3D(Basis(Vector3(1, 0, 0), rotx) * Basis(Vector3(0, 0, 1), rotz), pos)
	add_child(b)

func _decal_box(pos: Vector3, size: Vector3, color: int, ry := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box
	mi.material_override = mat(color)
	mi.transform = Transform3D(Basis(Vector3.UP, ry) * Basis.from_scale(size), pos)
	add_child(mi)
	return mi

## jitter: ±fraction on x/z size + a touch of random yaw — hand-built, not machine-perfect
func spawn_brick(pos: Vector3, b_basis: Basis, size: Vector3, color: int, linvel: Vector3, asleep: bool, jitter := 0.0) -> RigidBody3D:
	if jitter > 0.0:
		size.x *= randf_range(1.0 - jitter, 1.0 + jitter)
		size.z *= randf_range(1.0 - jitter, 1.0 + jitter)
		b_basis = b_basis * Basis(Vector3.UP, randf_range(-0.04, 0.04))
	var b := RigidBody3D.new()
	b.add_to_group("bricks")
	b.mass = maxf(0.5, size.x * size.y * size.z * 0.3)
	b.physics_material_override = brick_pm
	b.linear_damp = 0.08
	b.angular_damp = 0.8
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box
	mi.scale = size
	mi.material_override = matv(color)
	b.add_child(mi)
	b.transform = Transform3D(b_basis, pos)
	add_child(b)
	b.linear_velocity = linvel
	b.sleeping = asleep
	return b

# ============================ the western front ============================
## Layout (z axis): enemy rear < -48 | enemy trench -40..-34 | NO-MAN'S-LAND -28..28 |
## allied trench 34..40 | allied rear > 48. The river runs north-south at x ~85..115.

func _build_world() -> void:
	# mud plain — with a cutout where the diggable earth field goes (bedrock beneath it)
	_static_box(Vector3(0, -2, 163.2), Vector3(600, 4, 273.5), 0x584e3e)
	_static_box(Vector3(0, -2, -163.2), Vector3(600, 4, 273.5), 0x584e3e)
	_static_box(Vector3(-175, -2, 0), Vector3(250, 4, 53), 0x584e3e)
	_static_box(Vector3(175, -2, 0), Vector3(250, 4, 53), 0x584e3e)
	_static_box(Vector3(0, -6.85, 0), Vector3(101, 4, 54), 0x453c30)   # bedrock

	# M-EARTH: no-man's-land is REAL diggable ground — a 40x21 grid of earth columns
	earth = EarthField.new()
	add_child(earth)
	earth.setup(self, Vector3(-50, 0, -26.25), 40, 21)

	_trench_line(34.0, false)   # allied (parapet faces -z)
	_trench_line(-34.0, true)   # enemy  (parapet faces +z)

	# ---- no-man's-land: craters, wire, mud, stumps, wreckage ----
	for c in [[-45.0, -12.0, 3.2], [-28.0, 8.0, 2.6], [-12.0, -18.0, 3.8], [2.0, 14.0, 2.4],
		[16.0, -6.0, 3.4], [34.0, 18.0, 2.8], [48.0, -14.0, 3.0], [60.0, 6.0, 2.4],
		[-60.0, 14.0, 2.6], [8.0, -2.0, 4.2]]:
		_crater(Vector3(c[0], 0, c[1]), c[2])
	for wx in [-64.0, -48.0, -32.0, -16.0, 0.0, 16.0, 32.0, 48.0, 64.0]:
		_wire_fence(Vector3(wx, 0, 24.0), 0.0)
		_wire_fence(Vector3(wx + 4.0, 0, -24.0), 0.2)
	for s in [[-55.0, -5.0], [-38.0, 16.0], [-20.0, -10.0], [-4.0, 6.0], [12.0, 18.0],
		[26.0, -16.0], [42.0, 4.0], [56.0, 16.0], [64.0, -8.0], [-66.0, 2.0]]:
		_stump(Vector3(s[0], 0, s[1]))
	# ruined village on the west flank
	_ruin(Vector3(-52, 0, 4), 4, 3)
	_ruin(Vector3(-40, 0, -8), 3, 4)

	# ---- allied rear: road, airstrip, tents, emplacements ----
	_decal_box(Vector3(0, 0.05, 58), Vector3(5, 0.1, 26), 0x4e463a)
	_decal_box(Vector3(0, 0.05, 70), Vector3(130, 0.1, 5), 0x4e463a)
	_decal_box(Vector3(-2, 0.045, 62), Vector3(80, 0.09, 9), 0x69604f)   # airstrip
	_static_box(Vector3(-45, 1.5, 57), Vector3(0.15, 3.0, 0.15), GUN)     # windsock
	_static_box(Vector3(-45, 3.1, 57.6), Vector3(0.25, 0.35, 1.3), 0xa06a38)
	for t in [[-60.0, 72.0], [-52.0, 76.0], [22.0, 74.0]]:
		_tent(Vector3(t[0], 0, t[1]))
	_sandbags(Vector3(-26, 0, 73), Vector3.RIGHT, 8, 0.0)                 # artillery revetment
	_sandbags(Vector3(-26, 0, 79), Vector3.RIGHT, 8, 0.0)

	# behind-lines trees (the front itself is stumps only)
	for t in [[-70.0, 78.0], [46.0, 78.0], [66.0, 68.0], [-70.0, -76.0], [30.0, -74.0]]:
		_tree(Vector3(t[0], 0, t[1]))

	# ---- the river + crossing ----
	var water := MeshInstance3D.new()
	water.mesh = unit_box
	water.scale = Vector3(LAKE_RECT.size.x, WATER_LEVEL, LAKE_RECT.size.y)
	water.position = Vector3(LAKE_RECT.position.x + LAKE_RECT.size.x / 2.0, WATER_LEVEL / 2.0,
		LAKE_RECT.position.y + LAKE_RECT.size.y / 2.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.22, 0.3, 0.3, 0.66)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.2
	water.material_override = wm
	add_child(water)

	_vehicles()
	_dummies()

## A trench line at z = front_z .. front_z+6 (channel), dug into raised ground slabs.
## enemy=true mirrors it (channel at -front_z-6 .. -front_z, parapet facing +z).
func _trench_line(front_z: float, enemy: bool) -> void:
	var s := -1.0 if enemy else 1.0
	var fz := front_z                     # channel front edge (nearer no-man's-land)
	var rz := front_z + 6.0 * s           # channel rear edge
	var wall_c := [MUD, MUD2, CLAY, 0x66594a]
	# raised ground: front slab (between channel and no-man's-land)
	_static_box(Vector3(0, 0.9, fz - 3.0 * s), Vector3(140, 1.8, 6), MUD2)
	# rear slabs with exit gaps at x -50 / 0 / 50, ramps in the gaps
	for seg in [[-61.5, 17.0], [-25.0, 44.0], [25.0, 44.0], [61.5, 17.0]]:
		_static_box(Vector3(seg[0], 0.9, rz + 4.0 * s), Vector3(seg[1], 1.8, 8), MUD2)
	for gx in [-50.0, 0.0, 50.0]:
		_static_box(Vector3(gx, 0.62, rz + 4.0 * s), Vector3(5, 1.0, 9.5), 0x66594a, 0.0, -0.26 * s)
	# destructible dirt lining on both channel faces
	for i in 87:
		var x := -69.2 + i * 1.6
		spawn_brick(Vector3(x, 0.9, fz + 0.4 * s), Basis.IDENTITY, Vector3(1.6, 1.8, 0.7), wall_c[i % 4], Vector3.ZERO, true, 0.05)
		spawn_brick(Vector3(x, 0.9, rz - 0.4 * s), Basis.IDENTITY, Vector3(1.6, 1.8, 0.7), wall_c[(i + 2) % 4], Vector3.ZERO, true, 0.05)
	# sandbag parapet on top of the front slab, hugging the channel edge
	_sandbags(Vector3(-69, 0, fz - 1.2 * s), Vector3.RIGHT, 58, 1.8)
	# firing steps + duckboards inside the channel
	for i in 12:
		var x2 := -66.0 + i * 12.0
		spawn_brick(Vector3(x2, 0.4, fz + 1.3 * s), Basis.IDENTITY, Vector3(3.0, 0.8, 1.2), WOOD2, Vector3.ZERO, true, 0.06)
	for i in 20:
		_decal_box(Vector3(-66.5 + i * 7.0, 0.03, fz + 3.0 * s), Vector3(2.8, 0.05, 1.1), WOOD)

func _sandbags(start: Vector3, dir: Vector3, n: int, base_y: float) -> void:
	for i in n:
		for layer in 2:
			var off := 1.2 if layer == 1 else 0.0
			if layer == 1 and i == n - 1:
				continue
			var p := start + dir * (i * 2.4 + off)
			var c := SBAG if (i + layer) % 2 == 0 else SBAG2
			spawn_brick(Vector3(p.x, base_y + 0.3 + layer * 0.54, p.z), Basis.IDENTITY, Vector3(2.3, 0.55, 0.75), c, Vector3.ZERO, true, 0.08)

func _crater(center: Vector3, r: float) -> void:
	var mi := _decal_box(center + Vector3(0, 0.1, 0), Vector3(r * 2.6, 0.04, r * 2.6), 0x453c30, randf_range(0, TAU))
	mi.visible = true
	var n := 9
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var p := center + Vector3(cos(a) * r, 0.45, sin(a) * r)
		spawn_brick(p, Basis(Vector3(sin(a), 0, -cos(a)), randf_range(0.15, 0.4)),
			Vector3(1.7, 0.7, 1.2), MUD if i % 2 == 0 else MUD2, Vector3.ZERO, true, 0.1)

func _wire_fence(pos: Vector3, ry: float) -> void:
	var b := Basis(Vector3.UP, ry)
	for px in [-1.6, 1.6]:
		spawn_brick(pos + b * Vector3(px, 0.75, 0), b, Vector3(0.15, 1.3, 0.15), GUN, Vector3.ZERO, true, 0.0)
	for wy in [0.5, 0.85, 1.2]:
		spawn_brick(pos + b * Vector3(0, wy, 0), b * Basis(Vector3.UP, randf_range(-0.06, 0.06)),
			Vector3(3.6, 0.07, 0.07), WIRE, Vector3.ZERO, true, 0.0)

func _stump(base: Vector3) -> void:
	spawn_brick(base + Vector3(0, 0.72, 0), Basis(Vector3(1, 0, 0), randf_range(-0.12, 0.12)),
		Vector3(0.9, 1.2, 0.9), 0x54402c, Vector3.ZERO, true, 0.15)

func _mud_patch(center: Vector3, nx: int, nz: int) -> void:
	var tsize := Vector3(3.2, 1.1, 3.2)
	for ix in nx:
		for iz in nz:
			var x := center.x + (ix - (nx - 1) / 2.0) * 3.3
			var z := center.z + (iz - (nz - 1) / 2.0) * 3.3
			for layer in 2:
				spawn_brick(Vector3(x, tsize.y / 2.0 + layer * tsize.y, z), Basis.IDENTITY, tsize,
					[MUD, MUD2, CLAY][(ix + iz + layer) % 3], Vector3.ZERO, true, 0.08)

## a shelled ruin: wall columns of random surviving height, no roof, rubble around
func _ruin(origin: Vector3, nx: int, nz: int) -> void:
	var bw := 3.0; var bh := 1.5; var bt := 1.3
	var half_x := nx * bw / 2.0
	var half_z := nz * bw / 2.0
	var seed_i := int(origin.x) + int(origin.z) * 7
	for i in nx:
		for zs in [-1.0, 1.0]:
			var h := absi((seed_i + i * 3 + int(zs * 2)) % 4)
			for row in h:
				var x := origin.x + (i - (nx - 1) / 2.0) * bw
				var z: float = origin.z + zs * (half_z - bt * 0.5)
				spawn_brick(Vector3(x, bh * 0.5 + row * bh, z), Basis.IDENTITY, Vector3(bw, bh, bt),
					STONE if (i + row) % 2 == 0 else STONE2, Vector3.ZERO, true, 0.04)
	for j in nz:
		for xs in [-1.0, 1.0]:
			var h2 := absi((seed_i + j * 5 + int(xs * 3)) % 4)
			for row in h2:
				var x2: float = origin.x + xs * (half_x - bt * 0.5)
				var z2 := origin.z + (j - (nz - 1) / 2.0) * bw
				spawn_brick(Vector3(x2, bh * 0.5 + row * bh, z2), Basis.IDENTITY, Vector3(bt, bh, bw),
					STONE if (j + row) % 2 == 0 else STONE2, Vector3.ZERO, true, 0.04)
	for i in 14:
		var a := randf_range(0, TAU)
		var rr := randf_range(1.0, half_x + 3.0)
		spawn_brick(origin + Vector3(cos(a) * rr, 0.4, sin(a) * rr), Basis(Vector3.UP, randf_range(0, TAU)),
			Vector3(randf_range(0.7, 1.8), randf_range(0.4, 0.9), randf_range(0.6, 1.4)),
			[STONE, STONE2, WOOD2][i % 3], Vector3.ZERO, true, 0.0)

func _tent(base: Vector3) -> void:
	_static_box(base + Vector3(0, 1.05, -1.15), Vector3(4.2, 0.14, 3.0), CANVAS, 0.0, 0.85)
	_static_box(base + Vector3(0, 1.05, 1.15), Vector3(4.2, 0.14, 3.0), CANVAS, 0.0, -0.85)

func _tree(base: Vector3) -> void:
	var th := 1.5
	for k in 3:
		spawn_brick(base + Vector3(0, th * 0.5 + k * th, 0), Basis.IDENTITY, Vector3(1.1, th, 1.1), 0x54402c, Vector3.ZERO, true, 0.1)
	var cy := base.y + 3.0 * th + 1.0
	var canopy := [[0.0, 0.0, 0.0], [2.0, 0.2, 0.0], [-2.0, 0.2, 0.0], [0.0, 0.2, 2.0], [0.0, 0.2, -2.0], [0.0, 1.7, 0.0]]
	for i in canopy.size():
		var o: Array = canopy[i]
		var c := 0x4c5a34 if i % 2 == 0 else 0x5a6840
		spawn_brick(Vector3(base.x + o[0], cy + o[1], base.z + o[2]), Basis.IDENTITY, Vector3(2.2, 2.2, 2.2), c, Vector3.ZERO, true, 0.12)

const SOLDIER_PARTS := [
	[0.42, -1.45, -0.1, 0.72, 0.5, 1.15, BLK], [-0.42, -1.45, -0.1, 0.72, 0.5, 1.15, BLK],
	[0.42, -0.75, 0.0, 0.78, 1.3, 0.85, DOLV], [-0.42, -0.75, 0.0, 0.78, 1.3, 0.85, DOLV],
	[0.0, 0.2, 0.0, 1.6, 1.5, 0.95, GRN], [0.0, 0.15, -0.5, 1.5, 1.15, 0.35, GUN],
	[0.0, 0.25, 0.6, 1.15, 1.25, 0.55, PACK],
	[1.02, 0.15, 0.0, 0.5, 1.35, 0.7, OLV], [-1.02, 0.15, 0.0, 0.5, 1.35, 0.7, OLV],
	[0.0, 1.2, -0.05, 0.8, 0.8, 0.8, SKIN], [0.0, 1.62, 0.0, 1.0, 0.5, 1.02, OLV],
	[0.0, 1.45, -0.55, 1.0, 0.18, 0.3, OLV], [0.0, 0.98, 0.0, 0.95, 0.3, 0.7, DOLV],
	[0.42, -1.05, -0.5, 0.5, 0.35, 0.32, GUN], [-0.42, -1.05, -0.5, 0.5, 0.35, 0.32, GUN],
	[0.7, 0.05, -0.85, 0.22, 0.32, 1.5, GUN], [0.7, 0.12, -1.75, 0.1, 0.1, 0.5, BLK],
	[0.7, -0.28, -1.0, 0.18, 0.5, 0.22, BLK]]

func _dummies() -> void:
	var recolor := {GRN: FGREY, DOLV: FGREY2, OLV: FGREY2, PACK: 0x4f544e}
	var dparts: Array = []
	for p in SOLDIER_PARTS:
		var q: Array = p.duplicate()
		if recolor.has(q[6]):
			q[6] = recolor[q[6]]
		dparts.append(q)
	# five in the enemy trench channel, three exposed on their rear slab
	for d in [[-45.0, -37.0, 0.2, 1.78], [-25.0, -36.5, -0.2, 1.78], [-5.0, -37.0, 0.1, 1.78],
		[15.0, -36.5, -0.3, 1.78], [35.0, -37.0, 0.2, 1.78],
		[-30.0, -45.0, 0.3, 3.58], [10.0, -46.0, -0.1, 3.58], [40.0, -45.0, 0.2, 3.58]]:
		_vehicle({"pos": Vector3(d[0], d[3], d[1]), "yaw": d[2], "parts": dparts,
			"hit": [[0.0, -0.1, 0.0, 2.0, 3.4, 1.2]], "mass": 6.0, "kind": "dummy",
			"static": true, "fragile": true})

func _vehicles() -> void:
	var tank := [[0.0,-0.4,0.0,8.0,2.0,4.2,OLV],[0.0,-1.3,2.5,8.4,1.4,1.1,GUN],[0.0,-1.3,-2.5,8.4,1.4,1.1,GUN],
		[0.0,0.5,2.6,8.4,0.6,0.4,DOLV],[0.0,0.5,-2.6,8.4,0.6,0.4,DOLV],[-0.5,1.2,0.0,4.2,1.6,3.2,DOLV],
		[-0.5,2.2,0.0,1.4,0.5,1.4,OLV],[3.8,1.2,0.0,6.0,0.55,0.55,GUN],[1.6,2.3,0.8,1.6,0.35,0.35,BLK],
		[3.9,-0.2,0.0,1.2,1.4,4.0,DOLV],[-3.4,0.9,1.1,1.0,1.2,1.0,PACK],[-3.4,0.9,-1.1,1.0,1.2,1.0,PACK],
		[-1.6,2.7,1.2,0.1,2.0,0.1,BLK],[-4.0,0.1,1.6,0.35,0.35,1.3,GUN],
		[4.0,-0.2,1.5,0.4,0.45,0.25,LGY],[4.0,-0.2,-1.5,0.4,0.45,0.25,LGY]]
	var jeep := [[0.0,-0.3,0.0,6.0,1.1,3.0,TAN],[1.6,0.2,0.0,2.6,0.8,2.8,TAN],[-0.9,0.8,0.0,2.6,1.2,2.8,DOLV],
		[-2.6,0.4,0.0,0.5,1.2,2.8,GUN],[2.0,-1.0,1.6,1.4,1.4,0.7,BLK],[2.0,-1.0,-1.6,1.4,1.4,0.7,BLK],
		[-2.0,-1.0,1.6,1.4,1.4,0.7,BLK],[-2.0,-1.0,-1.6,1.4,1.4,0.7,BLK],[0.4,1.35,0.0,0.12,1.0,2.7,GUN],
		[-0.9,1.95,1.25,0.14,1.0,0.14,GUN],[-0.9,1.95,-1.25,0.14,1.0,0.14,GUN],[-0.9,2.45,0.0,0.14,0.14,2.7,GUN],
		[3.05,0.05,1.0,0.3,0.4,0.25,LGY],[3.05,0.05,-1.0,0.3,0.4,0.25,LGY],[-2.95,0.6,0.0,0.35,1.5,1.5,BLK],
		[2.3,-0.2,0.0,0.15,0.6,3.0,GUN]]
	# an old-school BIPLANE: stacked wings + wooden struts, open cockpit (V for pilot's view,
	# sighting under the top wing like it's 1917)
	var plane := [[0.0,0.0,0.0,9.0,1.4,1.4,GRY],
		[0.5,-0.25,0.0,2.6,0.3,11.0,LGY],   # lower wing
		[0.5,1.75,0.0,2.6,0.3,11.0,LGY],    # upper wing
		[0.5,0.75,4.2,0.18,1.8,0.18,WOOD2],[0.5,0.75,-4.2,0.18,1.8,0.18,WOOD2],   # outer struts
		[0.5,0.75,1.6,0.18,1.8,0.18,WOOD2],[0.5,0.75,-1.6,0.18,1.8,0.18,WOOD2],   # cabane struts
		[-3.7,1.1,0.0,1.3,2.1,0.35,GRY],
		[-3.7,0.2,0.0,1.6,0.35,4.6,LGY],[4.7,0.0,0.0,0.5,3.4,0.5,BLK],[4.35,0.0,0.0,0.9,1.3,1.3,GUN],
		[2.3,1.05,0.0,0.12,0.7,1.15,GUN],   # windscreen frame
		[0.7,1.0,0.0,0.28,0.85,0.95,WOOD2], # seat back
		[1.15,0.72,0.0,0.75,0.22,0.95,WOOD2], # seat base
		[1.95,0.92,0.0,0.22,0.4,0.95,BLK]]  # instrument panel
	var boat := [[0.0,-0.3,0.0,11.0,1.8,4.2,BLU],[5.6,0.3,0.0,1.8,1.1,2.6,BLU],[-1.8,1.1,0.0,3.4,1.6,3.0,GRY],
		[-1.8,2.2,0.0,0.5,1.0,0.5,BLK],[3.0,0.7,1.5,3.0,0.5,0.4,DOLV],[3.0,0.7,-1.5,3.0,0.5,0.4,DOLV]]
	var turret := [[0.0,-1.1,0.0,3.4,1.6,3.4,GRY],[0.0,0.3,0.0,2.4,1.2,2.4,DOLV],[1.9,0.7,0.55,4.2,0.4,0.4,GUN],
		[1.9,0.7,-0.55,4.2,0.4,0.4,GUN],[-0.6,0.9,0.0,1.6,1.0,1.8,OLV]]
	var aa := [[0.0,-1.9,0.0,3.4,1.0,3.4,DOLV],[0.0,-1.0,0.0,2.4,0.8,2.4,GRN],[-0.7,0.2,0.0,1.4,1.3,1.8,GUN],
		[1.8,0.9,0.5,5.2,0.35,0.35,GUN,0.55],[1.8,0.9,-0.5,5.2,0.35,0.35,GUN,0.55],
		[1.8,1.7,0.5,5.2,0.35,0.35,GUN,0.55],[1.8,1.7,-0.5,5.2,0.35,0.35,GUN,0.55]]
	var arty := [[0.0,-0.6,0.0,5.0,1.5,3.0,GRN],[0.0,-1.5,1.7,2.8,2.8,0.5,BLK],[0.0,-1.5,-1.7,2.8,2.8,0.5,BLK],
		[1.8,1.3,0.0,9.5,0.75,0.75,DOLV,0.42],[-3.4,-0.8,0.0,4.5,0.45,0.45,GUN],[0.6,0.6,0.0,2.0,1.2,2.4,DOLV]]

	var tank_hit := [[0.0,-0.7,0.0,8.4,2.6,6.1],[-0.5,1.2,0.0,4.2,1.6,3.2],[3.8,1.2,0.0,5.6,0.6,0.6]]
	var jeep_hit := [[0.0,-0.5,0.0,6.0,2.4,3.4],[-0.9,0.9,0.0,2.6,1.4,2.8]]
	var plane_hit := [[0.0,0.0,0.0,9.0,1.4,1.4],[0.5,0.75,0.0,2.8,2.4,11.0],[-3.7,0.7,0.0,1.6,2.9,4.6]]  # wing cage covers both wings
	var boat_hit := [[0.0,-0.3,0.0,11.0,1.8,4.2],[5.6,0.3,0.0,1.8,1.1,2.6],[-1.8,1.1,0.0,3.4,1.6,3.0]]
	var turret_hit := [[0.0,-1.1,0.0,3.4,1.6,3.4],[0.0,0.35,0.0,2.6,1.3,2.6],[1.9,0.7,0.0,4.2,0.4,1.5]]
	var aa_hit := [[0.0,-1.5,0.0,3.4,1.8,3.4],[-0.7,0.2,0.0,1.4,1.3,1.8],[1.8,1.3,0.0,4.8,1.1,1.7,0.55]]
	var arty_hit := [[0.0,-0.6,0.0,5.0,1.5,3.0],[0.0,-1.5,0.0,2.8,2.8,3.9],[1.8,1.3,0.0,8.0,0.8,0.8,0.42],[-3.4,-0.8,0.0,4.5,0.5,0.5]]

	_vehicle({"pos": Vector3(24, 2.7, 50), "yaw": 0.15, "parts": tank, "hit": tank_hit, "mass": 60.0,
		"kind": "tank", "drivable": true, "max_speed": 15.0, "accel": 22.0, "turn_rate": 2.2, "turn_accel": 10.0, "grip": 9.0})
	_vehicle({"pos": Vector3(60, 3.8, 44), "yaw": -0.5, "parts": jeep, "hit": jeep_hit, "mass": 20.0,
		"kind": "jeep", "drivable": true, "max_speed": 24.0, "accel": 26.0, "turn_rate": 2.6, "turn_accel": 9.0, "grip": 7.0})
	_vehicle({"pos": Vector3(-40, 1.5, 62), "yaw": 0.0, "parts": plane, "hit": plane_hit, "mass": 25.0,
		"kind": "plane", "drivable": true, "max_speed": 50.0, "accel": 28.0, "turn_rate": 1.2, "turn_accel": 6.0,
		"grip": 2.0, "takeoff": 13.0, "damp": 0.08})
	_vehicle({"pos": Vector3(95, 1.45, 20), "yaw": 1.57, "parts": boat, "hit": boat_hit, "mass": 40.0,
		"kind": "boat", "drivable": true, "max_speed": 18.0, "accel": 10.0, "turn_rate": 1.8, "turn_accel": 8.0, "grip": 2.0})
	_vehicle({"pos": Vector3(-30, 3.75, 31), "yaw": 1.57, "parts": turret, "hit": turret_hit, "mass": 30.0,
		"kind": "turret", "static": true})
	_vehicle({"pos": Vector3(30, 2.6, 68), "yaw": 1.57, "parts": aa, "hit": aa_hit, "mass": 15.0, "kind": "aa"})
	_vehicle({"pos": Vector3(-20, 3.0, 76), "yaw": 1.57, "parts": arty, "hit": arty_hit, "mass": 20.0, "kind": "arty"})

func _vehicle(cfg: Dictionary) -> void:
	var v := Vehicle.new()
	v.add_to_group("vehicles")
	v.kind = cfg.get("kind", "prop")
	v.parts = cfg["parts"]
	v.fragile = cfg.get("fragile", false)
	v.drivable = cfg.get("drivable", false)
	v.mannable = v.kind in ["tank", "jeep", "plane", "boat", "turret", "aa", "arty"]
	if v.mannable:
		v.add_to_group("mannable")
	var ext := 0.0
	for p in v.parts:
		ext = maxf(ext, Vector3(p[0], p[1], p[2]).length() + maxf(p[3], maxf(p[4], p[5])) * 0.5)
	v.extent = ext
	v.mass = cfg.get("mass", 10.0)
	v.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	v.center_of_mass = Vector3(0, -0.8, 0)
	v.physics_material_override = drive_pm if v.drivable else brick_pm
	v.linear_damp = cfg.get("damp", 0.4 if v.drivable else 0.08)
	v.angular_damp = 4.0 if v.drivable else 0.8
	v.takeoff_speed = cfg.get("takeoff", 18.0)
	if cfg.get("static", false):
		v.freeze = true
	if v.drivable:
		v.max_speed = cfg.get("max_speed", 15.0)
		v.accel = cfg.get("accel", 22.0)
		v.turn_rate = cfg.get("turn_rate", 1.5)
		v.turn_accel = cfg.get("turn_accel", 6.0)
		v.grip = cfg.get("grip", 9.0)
	v.water_rect = LAKE_RECT
	for p in v.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = unit_box
		mi.material_override = matv(p[6])
		var rz: float = p[7] if p.size() > 7 else 0.0
		mi.transform = Transform3D(Basis(Vector3(0, 0, 1), rz) * Basis.from_scale(Vector3(p[3], p[4], p[5])), Vector3(p[0], p[1], p[2]))
		v.add_child(mi)
	for hb in cfg["hit"]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(hb[3], hb[4], hb[5])
		cs.shape = sh
		var rz2: float = hb[6] if hb.size() > 6 else 0.0
		cs.transform = Transform3D(Basis(Vector3(0, 0, 1), rz2), Vector3(hb[0], hb[1], hb[2]))
		v.add_child(cs)
	v.transform = Transform3D(Basis(Vector3.UP, cfg.get("yaw", 0.0)), cfg["pos"])
	add_child(v)
	v.sleeping = true

func _build_player() -> void:
	player = Player.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 3.2
	cs.shape = cap
	cs.name = "Shape"
	player.add_child(cs)
	var body := Node3D.new()
	body.name = "Body"
	player.add_child(body)
	# first 15 parts are the body (order matters — player.gd animates by child index);
	# the rifle's 3 parts go under their own pivot node so the whole gun can raise/swing
	for p in SOLDIER_PARTS.slice(0, 15):
		var mi := MeshInstance3D.new()
		mi.mesh = unit_box
		mi.material_override = mat(p[6])
		mi.position = Vector3(p[0], p[1], p[2])
		mi.scale = Vector3(p[3], p[4], p[5])
		body.add_child(mi)
	var rifle := Node3D.new()
	rifle.name = "Rifle"
	rifle.position = Vector3(0.7, 0.05, -0.6)
	for rp in [[0.0, 0.0, -0.25, 0.22, 0.32, 1.5, GUN], [0.0, 0.07, -1.15, 0.1, 0.1, 0.5, BLK],
		[0.0, -0.33, -0.4, 0.18, 0.5, 0.22, BLK]]:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = unit_box
		mi2.material_override = mat(rp[6])
		mi2.position = Vector3(rp[0], rp[1], rp[2])
		mi2.scale = Vector3(rp[3], rp[4], rp[5])
		rifle.add_child(mi2)
	body.add_child(rifle)
	player.position = Vector3(0, 3.2, 37)   # spawn in the allied trench
	add_child(player)

func _vm_box(root: Node3D, pos: Vector3, size: Vector3, color: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box
	mi.material_override = mat(color)
	mi.position = pos
	mi.scale = size
	root.add_child(mi)

## viewmodels: what premium feels like — you can SEE the weapon in your hands.
## Camera space: -Z is forward. One root per weapon; sway/bob/kick animate the parent.
func _build_viewmodel() -> void:
	viewmodel = Node3D.new()
	cam.add_child(viewmodel)
	for w in [1, 2, 3, 4]:
		var root := Node3D.new()
		viewmodel.add_child(root)
		vm_roots[w] = root
		# right arm: sleeve, forearm, hand (shared pose across weapons)
		_vm_box(root, Vector3(0.38, -0.36, -0.42), Vector3(0.13, 0.13, 0.3), GRN)
		_vm_box(root, Vector3(0.38, -0.35, -0.62), Vector3(0.11, 0.11, 0.28), SKIN)
		_vm_box(root, Vector3(0.37, -0.34, -0.8), Vector3(0.12, 0.1, 0.14), SKIN)
	var r1: Node3D = vm_roots[1]   # RIFLE: stock, body, barrel, front sight, support arm
	_vm_box(r1, Vector3(0.35, -0.38, -0.55), Vector3(0.09, 0.17, 0.4), WOOD)
	_vm_box(r1, Vector3(0.35, -0.33, -1.05), Vector3(0.08, 0.13, 0.75), WOOD2)
	_vm_box(r1, Vector3(0.35, -0.3, -1.65), Vector3(0.05, 0.05, 0.55), GUN)
	_vm_box(r1, Vector3(0.35, -0.235, -1.5), Vector3(0.02, 0.07, 0.02), BLK)
	_vm_box(r1, Vector3(0.12, -0.4, -0.95), Vector3(0.24, 0.1, 0.1), GRN)
	_vm_box(r1, Vector3(0.03, -0.38, -1.02), Vector3(0.11, 0.1, 0.13), SKIN)
	# the bolt handle — slides back and forward during the cycle
	vm_bolt = MeshInstance3D.new()
	vm_bolt.mesh = unit_box
	vm_bolt.material_override = mat(BLK)
	vm_bolt_base = Vector3(0.42, -0.3, -0.92)
	vm_bolt.position = vm_bolt_base
	vm_bolt.scale = Vector3(0.09, 0.035, 0.035)
	r1.add_child(vm_bolt)
	var r2: Node3D = vm_roots[2]   # ROCKET: shoulder tube
	_vm_box(r2, Vector3(0.36, -0.28, -0.95), Vector3(0.2, 0.2, 1.25), DOLV)
	_vm_box(r2, Vector3(0.36, -0.28, -1.6), Vector3(0.24, 0.24, 0.12), GUN)
	_vm_box(r2, Vector3(0.36, -0.28, -0.32), Vector3(0.24, 0.24, 0.12), GUN)
	_vm_box(r2, Vector3(0.1, -0.4, -0.8), Vector3(0.26, 0.1, 0.1), GRN)
	_vm_box(r2, Vector3(0.0, -0.38, -0.88), Vector3(0.11, 0.1, 0.13), SKIN)
	var r3: Node3D = vm_roots[3]   # GRENADE: held tin + lever
	_vm_box(r3, Vector3(0.37, -0.36, -0.95), Vector3(0.16, 0.2, 0.16), DOLV)
	_vm_box(r3, Vector3(0.41, -0.28, -0.95), Vector3(0.04, 0.12, 0.04), LGY)
	var r4: Node3D = vm_roots[4]   # SHOVEL: handle, blade, support hand
	_vm_box(r4, Vector3(0.36, -0.42, -0.85), Vector3(0.06, 0.06, 0.9), WOOD)
	_vm_box(r4, Vector3(0.36, -0.42, -1.42), Vector3(0.26, 0.34, 0.05), GRY)
	_vm_box(r4, Vector3(0.13, -0.45, -0.65), Vector3(0.24, 0.1, 0.1), GRN)
	_vm_box(r4, Vector3(0.03, -0.43, -0.72), Vector3(0.11, 0.1, 0.13), SKIN)

## render-rate viewmodel animation: sway lags the look, bob follows the feet, kick punches
## and recovers, switch dips and raises, sprint lowers the weapon, R-click aims the rifle,
## the bolt cycles after every shot, the rocket reloads, the grenade winds up and swings.
func _process(dt: float) -> void:
	if viewmodel == null or player == null:
		return
	var show := first_person and driving == null
	viewmodel.visible = show
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var sprinting := driving == null and Input.is_physical_key_pressed(KEY_SHIFT) and speed > 10.0 and player.is_on_floor()
	if show:
		for w in vm_roots:
			vm_roots[w].visible = (w == weapon)
		if weapon != prev_weapon:
			prev_weapon = weapon
			vm_raise = 0.0
			nade_charging = false
		vm_raise = minf(vm_raise + dt * 5.0, 1.0)
		vm_kick = maxf(vm_kick - dt * 6.0, 0.0)
		vm_bolt_t = maxf(vm_bolt_t - dt, 0.0)
		vm_reload_t = maxf(vm_reload_t - dt, 0.0)
		vm_throw_t = maxf(vm_throw_t - dt, 0.0)
		var ads_target := 1.0 if (weapon == 1 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not sprinting) else 0.0
		ads = lerpf(ads, ads_target, minf(dt * 10.0, 1.0))
		vm_sway = vm_sway.lerp(Vector3.ZERO, minf(dt * 9.0, 1.0))
		if player.is_on_floor() and speed > 1.0:
			bob_phase += dt * clampf(speed, 0.0, 22.0) * 0.55
		var bob := Vector3(sin(bob_phase) * 0.012, -absf(cos(bob_phase)) * 0.012, 0) * clampf(speed / 12.0, 0.0, 1.4)
		var pose := ADS_OFFSET * ads
		var rot_x := 0.0
		var rot_z := 0.0
		if sprinting:                      # weapon drops to a run carry
			pose += Vector3(0.09, -0.18, 0.07)
			rot_x -= 0.55
			rot_z += 0.2
		if weapon == 1 and vm_bolt_t > 0.0:   # bolt cycle: dip, cant, work the handle
			var bt := 1.0 - vm_bolt_t          # 0 -> 1 over the cycle
			var bell := sin(minf(bt * 2.6, PI))
			rot_z += bell * 0.28
			rot_x += bell * 0.1
			pose += Vector3(0.02, -0.06, 0.07) * bell
			vm_bolt.position = vm_bolt_base + Vector3(0.015, 0.0, 0.14) * sin(minf(bt * 3.4, PI))
		if weapon == 2 and vm_reload_t > 0.0: # rocket reload: tube swings down and back up
			var dip := sin(clampf(vm_reload_t / 2.2, 0.0, 1.0) * PI)
			rot_x -= dip * 0.85
			pose += Vector3(0.06, -0.3, 0.14) * dip
		if vm_throw_t > 0.0:                  # grenade: pull back, then whip forward
			var tt := vm_throw_t / 0.28
			rot_x += (tt - 0.45) * 1.7
			pose += Vector3(0.0, 0.1, 0.15) * tt
		if nade_charging:                     # wind-up hold
			rot_x += 0.5
			pose += Vector3(0.0, 0.06, 0.12)
		viewmodel.position = vm_sway * (1.0 - 0.7 * ads) + bob * (1.0 - 0.8 * ads) + pose \
			+ Vector3(0, -(1.0 - vm_raise) * 0.3, vm_kick * 0.1)
		viewmodel.rotation = Vector3(vm_kick * 0.07 - (1.0 - vm_raise) * 0.45 + rot_x, 0.0, rot_z)
	var target_fov := 75.0
	if ads > 0.05 and show:
		target_fov = lerpf(75.0, 60.0, ads)
	elif sprinting:
		target_fov = 83.0
	elif _flying():
		target_fov = 82.0
	cam.fov = lerpf(cam.fov, target_fov, minf(dt * 8.0, 1.0))

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_font_size_override("font_size", 15)
	cl.add_child(hud)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 24)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cl.add_child(cross)

# ============================ input ============================

func _aim_dir() -> Vector3:
	return -Vector3(sin(pitch) * sin(yaw), cos(pitch), sin(pitch) * cos(yaw)).normalized()

func _flying() -> bool:
	return driving != null and driving.kind == "plane"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := FP_SENS if (first_person or vehicle_fp) else ORBIT_SENS
		s *= 1.0 - 0.45 * ads   # steadier hand while aiming down sights
		yaw -= event.relative.x * s
		var hi := 2.95 if (first_person or vehicle_fp or _flying()) else 1.5
		pitch = clampf(pitch - event.relative.y * s, 0.15, hi)
		vm_sway = (vm_sway + Vector3(-event.relative.x, event.relative.y, 0) * 0.0004) \
			.clamp(Vector3(-0.05, -0.05, 0), Vector3(0.05, 0.05, 0))
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: dist = clampf(dist - 3.0, 8.0, 120.0)
			MOUSE_BUTTON_WHEEL_DOWN: dist = clampf(dist + 3.0, 8.0, 120.0)
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					capture_grace = 0.25
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_V:
				if driving != null:
					vehicle_fp = not vehicle_fp    # cockpit / chase toggle
				else:
					first_person = not first_person
				_apply_camera_mode()
			KEY_E:
				_enter_exit()
			KEY_1: weapon = 1
			KEY_2: weapon = 2
			KEY_3: weapon = 3
			KEY_4: weapon = 4
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _apply_camera_mode() -> void:
	player.visible = not (first_person or driving != null)

func _enter_exit() -> void:
	if driving != null:
		var side: Vector3 = driving.global_transform.basis.z
		player.global_position = driving.global_position + side * 4.0 + Vector3.UP * 1.5
		player.get_node("Shape").disabled = false
		player.set_physics_process(true)
		player.velocity = driving.linear_velocity
		driving.possessed = false
		driving.throttle = 0.0
		driving.steer = 0.0
		driving = null
		vehicle_fp = false
		_apply_camera_mode()
		return
	var best: Vehicle = null
	var bd := 12.0
	for v in get_tree().get_nodes_in_group("mannable"):
		var d: float = v.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = v
	if best != null:
		driving = best
		best.possessed = true
		vehicle_fp = false
		player.get_node("Shape").disabled = true
		player.set_physics_process(false)
		_apply_camera_mode()

# ============================ weapons ============================

func _cd(key: String, t: float) -> bool:
	if cooldowns.get(key, 0.0) > 0.0:
		return false
	cooldowns[key] = t
	return true

func _shoot(origin: Vector3, vel: Vector3, visual: float, radius: float, power: float,
		gscale: float, fuse: float, source: Node, tracer: bool) -> void:
	var p := Projectile.new()
	p.main = self
	p.radius = radius
	p.power = power
	p.fuse = fuse
	p.source = source
	p.mass = 2.0
	p.gravity_scale = gscale
	if fuse > 0.0:
		p.physics_material_override = bounce_pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = maxf(visual * 0.5, 0.12)
	cs.shape = sh
	p.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box
	mi.scale = Vector3.ONE * visual
	if tracer:
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(1.0, 0.85, 0.4)
		tm.emission_enabled = true
		tm.emission = Color(1.0, 0.7, 0.25)
		tm.emission_energy_multiplier = 3.5
		mi.material_override = tm
	else:
		mi.material_override = mat(GUN)
	p.add_child(mi)
	p.position = origin
	add_child(p)
	p.linear_velocity = vel
	_muzzle_fx(origin, power >= 25.0)
	_sound(origin, snd_shot, -6.0 if power < 25.0 else 0.0, randf_range(0.9, 1.1) if power < 25.0 else 0.55)

func _try_fire() -> void:
	if capture_grace > 0.0 or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# shovel build: R-click stacks carried spoil onto the aimed earth column
	if driving == null and weapon == 4 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if _cd("shovelb", 0.42):
			_dig_action(true)
			vm_kick = 0.5
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var lmb_edge := lmb and not lmb_prev
	var aim := _aim_dir()
	if driving == null:
		var origin: Vector3 = player.global_position + Vector3(0, 1.35, 0) + aim * 1.6
		# grenade is hold-to-aim: arc shows while held, release lobs it
		if weapon == 3:
			if lmb and cooldowns.get("nade", 0.0) <= 0.0:
				nade_charging = true
			elif nade_charging and not lmb:
				nade_charging = false
				if _cd("nade", 1.1):
					vm_throw_t = 0.28
					player.flash("throw")
					get_tree().create_timer(0.13).timeout.connect(_throw_nade.bind(origin, aim))
			return
		nade_charging = false
		if not lmb:
			return
		match weapon:
			1:
				# BOLT-ACTION: one aimed shot per click, then you work the bolt
				if lmb_edge and _cd("rifle", 1.15):
					_shoot(origin, aim * 150.0, 0.16, 2.4, 15.0, 0.12, 0.0, null, true)
					vm_kick = 0.8
					vm_bolt_t = 1.0
					pitch = clampf(pitch - 0.03, 0.15, 2.95)   # camera recoil: view kicks UP
					recoil_return += 0.017                      # ...and walks partly back down
					player.flash("fire")
					get_tree().create_timer(0.5).timeout.connect(_bolt_clack)
			2:
				if lmb_edge and _cd("rocket", 2.6):
					_shoot(origin, aim * 55.0, 0.45, 8.0, 42.0, 0.25, 0.0, null, false)
					vm_kick = 1.0
					vm_reload_t = 2.2
					pitch = clampf(pitch - 0.05, 0.15, 2.95)
					recoil_return += 0.028
					cam_shake += 0.18
					player.flash("fire")
					get_tree().create_timer(1.5).timeout.connect(_reload_clunk)
			4:
				if _cd("shovel", 0.42):
					_dig_action(false)
					vm_kick = 0.7
					player.flash("dig")
		return
	if not lmb:
		return
	var fwd: Vector3 = driving.global_transform.basis.x.normalized()
	match driving.kind:
		"tank":
			if _cd("veh", 1.6):
				var o: Vector3 = driving.to_global(Vector3(7.2, 1.2, 0))
				var d := (fwd + Vector3.UP * 0.04).normalized()
				_shoot(o, d * 85.0, 0.5, 8.0, 45.0, 0.4, 0.0, driving, false)
				driving.apply_central_impulse(-d * driving.mass * 2.0)
				cam_shake += 0.4
		"jeep":
			if _cd("veh", 0.12):
				_shoot(driving.to_global(Vector3(3.4, 0.9, 0)), fwd * 120.0, 0.15, 2.2, 12.0, 0.1, 0.0, driving, true)
		"plane":
			if _cd("veh", 0.12):
				_shoot(driving.to_global(Vector3(5.2, -0.2, 0)),
					driving.global_transform.basis.x.normalized() * 130.0 + driving.linear_velocity,
					0.15, 2.4, 14.0, 0.1, 0.0, driving, true)
		"boat":
			if _cd("veh", 0.8):
				_shoot(driving.to_global(Vector3(6.0, 1.0, 0)), (fwd + Vector3.UP * 0.06).normalized() * 80.0,
					0.4, 6.0, 30.0, 0.4, 0.0, driving, false)
		"turret":
			if _cd("veh", 0.7):
				_shoot(driving.to_global(Vector3(4.3, 0.7, 0)), aim * 95.0, 0.35, 5.0, 26.0, 0.3, 0.0, driving, false)
		"aa":
			if _cd("veh", 0.15):
				_shoot(driving.to_global(Vector3(3.8, 1.6, 0)), aim * 130.0, 0.2, 2.6, 14.0, 0.1, 0.0, driving, true)
				driving.apply_central_impulse(-aim * driving.mass * 0.15)
		"arty":
			if _cd("veh", 3.5):
				var d2 := (aim + Vector3.UP * 0.35).normalized()
				_shoot(driving.to_global(Vector3(6.2, 4.2, 0)), d2 * 55.0, 0.6, 12.0, 60.0, 1.0, 0.0, driving, false)
				driving.apply_central_impulse(-d2 * driving.mass * 3.0)
				cam_shake += 0.6

func _throw_nade(o: Vector3, a: Vector3) -> void:
	_shoot(o, a * 22.0 + Vector3.UP * 6.0, 0.4, 8.0, 42.0, 1.3, 2.2, null, false)
	vm_kick = 0.45

func _bolt_clack() -> void:
	if player != null:
		_sound(player.global_position, snd_shot, -20.0, 1.8)

func _reload_clunk() -> void:
	if player != null:
		_sound(player.global_position, snd_shot, -18.0, 0.7)

## predicted grenade trajectory, drawn while the throw is held
func _update_arc(origin: Vector3, aim: Vector3) -> void:
	arc_mesh.clear_surfaces()
	arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var p := origin
	var v := aim * 22.0 + Vector3.UP * 6.0
	var g := Vector3(0, -20.0 * 1.3, 0)
	for k in 60:
		arc_mesh.surface_add_vertex(p)
		v += g * 0.05
		p += v * 0.05
		if p.y < 0.05:
			break
	arc_mesh.surface_add_vertex(p)
	arc_mesh.surface_end()

## swing the shovel at the earth: dig (spoil in) or build (spoil out)
func _dig_action(build: bool) -> void:
	var from: Vector3 = player.global_position + Vector3(0, 1.35, 0)
	var aim := _aim_dir()
	var q := PhysicsRayQueryParameters3D.create(from, from + aim * 5.5, 0xFFFFFFFF, [player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var obj: Object = hit["collider"]
	if obj == null or not obj.has_meta("earth"):
		return
	var i: int = obj.get_meta("earth")
	var pos: Vector3 = hit["position"]
	if build:
		if spoil > 0 and earth.place(i):
			spoil -= 1
			_dirt_fx(pos)
			_sound(pos, snd_shot, -16.0, 0.45)
	else:
		if earth.dig(i):
			spoil += 1
			_dirt_fx(pos)
			_sound(pos, snd_shot, -14.0, 0.35)
			if randi() % 2 == 0:   # a loose clod rolls out of the cut
				spawn_brick(pos + Vector3(0, 0.7, 0), Basis(Vector3.UP, randf_range(0, TAU)),
					Vector3(0.7, 0.5, 0.7), MUD, -aim * 2.0 + Vector3(0, 4.0, 0), false)

func _dirt_fx(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	_particles(root, Color(0.42, 0.36, 0.28), 8, 4.5, 0.5, 0.35, false)
	get_tree().create_timer(0.8).timeout.connect(root.queue_free)

# ============================ blasts ============================

func queue_blast(point: Vector3, radius := 8.0, power := 42.0, source: Node = null) -> void:
	blast_queue.append({"point": point, "radius": radius, "power": power, "source": source})

func _apply_blasts() -> void:
	if blast_queue.is_empty():
		return
	var blasts: Array = blast_queue.duplicate()
	blast_queue.clear()
	for bl in blasts:
		var point: Vector3 = bl["point"]
		var radius: float = bl["radius"]
		var power: float = bl["power"]
		var source = bl["source"]
		_explosion_fx(point, radius)
		if point.y < 4.0:
			_scorch(point, radius)
		# heavy blasts carve REAL craters out of the earth grid
		if earth != null and power >= SHATTER_POWER:
			var carved := earth.carve(point, radius * 0.9, power)
			if carved > 0:
				for j in mini(8, int(carved / 3.0) + 1):
					var ca := randf_range(0, TAU)
					spawn_brick(point + Vector3(cos(ca) * randf_range(1.0, 3.0), 1.2, sin(ca) * randf_range(1.0, 3.0)),
						Basis(Vector3.UP, ca), Vector3(randf_range(0.6, 1.1), 0.5, randf_range(0.6, 1.1)), MUD,
						Vector3(cos(ca) * randf_range(3.0, 9.0), randf_range(6.0, 14.0), sin(ca) * randf_range(3.0, 9.0)), false)
				print("EARTH carved %d cells" % carved)
		var pd: Vector3 = player.global_position - point
		var pdist := pd.length()
		var reach := radius + 3.0
		if pdist < reach and driving == null:
			var pf := power * (1.0 - pdist / reach)
			player.knock += pd.normalized() * pf * 0.7 + Vector3.UP * pf * 0.5
		cam_shake += clampf(power / 42.0, 0.2, 1.4) * clampf(1.0 - pdist / 45.0, 0.0, 1.0)
		var affected := 0
		for b in get_tree().get_nodes_in_group("bricks"):
			var d: Vector3 = b.global_position - point
			var bdist := d.length()
			if bdist <= radius:
				b.sleeping = false
				var f := power * (1.0 - bdist / radius)
				var inv := 1.0 / maxf(bdist, 0.7)
				b.linear_velocity += Vector3(d.x * inv * f, (absf(d.y) * inv * 0.6 + 0.5) * f, d.z * inv * f) * 0.55
				affected += 1
			elif Vector2(d.x, d.z).length() < radius * 0.75 and d.y > 0.0:
				b.sleeping = false
		for v in get_tree().get_nodes_in_group("vehicles"):
			if v == source:
				continue
			var vd: Vector3 = v.global_position - point
			var vreach: float = radius + v.extent
			if vd.length() > vreach:
				continue
			if power >= SHATTER_POWER or v.fragile:
				if v == driving:
					driving = null
					vehicle_fp = false
					player.get_node("Shape").disabled = false
					player.set_physics_process(true)
					player.global_position = v.global_position + Vector3.UP * 3.0
					_apply_camera_mode()
				var vt: Transform3D = v.global_transform
				for p in v.parts:
					var lp := Vector3(p[0], p[1], p[2])
					var size := Vector3(p[3], p[4], p[5])
					var rz: float = p[7] if p.size() > 7 else 0.0
					var wp: Vector3 = vt * lp
					wp.y = maxf(wp.y, size.y * 0.5 + 0.05)
					var d2: Vector3 = wp - point
					var bdist2: float = maxf(d2.length(), 0.7)
					var f2: float = power * (1.0 - minf(bdist2 / vreach, 0.95))
					var lv: Vector3 = d2 / bdist2 * f2 * 0.5 + Vector3(0, 0.12 * f2, 0)
					spawn_brick(wp, vt.basis * Basis(Vector3(0, 0, 1), rz), size, p[6], lv, false)
				v.queue_free()
			else:
				v.sleeping = false
				var f3: float = power * (1.0 - vd.length() / vreach)
				v.apply_central_impulse(vd.normalized() * f3 * 0.08 * v.mass)
		if affected > 0:
			print("BLAST at %.1f,%.1f,%.1f affected %d bricks" % [point.x, point.y, point.z, affected])

# ============================ FX ============================

## permanent-ish battle scarring: dark scorch decals under blasts (capped, oldest fade out)
func _scorch(point: Vector3, radius: float) -> void:
	var mi := _decal_box(Vector3(point.x, 0.1 + scorches.size() * 0.0012, point.z),
		Vector3(radius * 1.5, 0.03, radius * 1.5), 0x35302a, randf_range(0, TAU))
	scorches.append(mi)
	if scorches.size() > 40:
		var old: MeshInstance3D = scorches.pop_front()
		old.queue_free()

func _muzzle_fx(pos: Vector3, big: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.45)
	l.light_energy = 5.0 if big else 2.0
	l.omni_range = 9.0 if big else 5.0
	add_child(l)
	l.global_position = pos
	get_tree().create_timer(0.06).timeout.connect(l.queue_free)

func _particles(parent: Node3D, color: Color, amount: int, speed: float, life: float, cube: float, emissive: bool, translucent := false) -> void:
	var pp := CPUParticles3D.new()
	pp.one_shot = true
	pp.explosiveness = 1.0
	pp.amount = amount
	pp.lifetime = life
	pp.spread = 180.0
	pp.initial_velocity_min = speed * 0.45
	pp.initial_velocity_max = speed
	pp.gravity = Vector3(0, -9, 0) if not translucent else Vector3(0, 0.8, 0)
	pp.scale_amount_min = 0.5
	pp.scale_amount_max = 1.0
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * cube
	var mm := StandardMaterial3D.new()
	mm.albedo_color = color
	if translucent:
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		mm.emission_enabled = true
		mm.emission = color
		mm.emission_energy_multiplier = 3.0
	bm.material = mm
	pp.mesh = bm
	parent.add_child(pp)
	pp.emitting = true

func _explosion_fx(point: Vector3, radius: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = point
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.35)
	l.light_energy = 8.0
	l.omni_range = radius * 2.5
	root.add_child(l)
	var tw := root.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	_particles(root, Color(1.0, 0.6, 0.15), 26, radius * 2.0, 0.45, 0.5, true)
	_particles(root, Color(0.33, 0.3, 0.26), 16, radius * 0.9, 2.2, 0.9, false)
	# lingering battlefield dust — hangs in the air, drifts up slowly
	_particles(root, Color(0.5, 0.47, 0.4, 0.35), 10, radius * 0.4, 3.2, 1.5, false, true)
	get_tree().create_timer(3.6).timeout.connect(root.queue_free)
	_sound(point, snd_boom, clampf(radius - 6.0, -4.0, 8.0), clampf(9.0 / radius, 0.6, 1.3))

# ============================ game loop ============================

func _physics_process(dt: float) -> void:
	capture_grace = maxf(0.0, capture_grace - dt)
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - dt)
	# recoil recovery: the camera walks back down part of each kick
	if recoil_return > 0.0001:
		var rr := recoil_return * minf(dt * 9.0, 1.0)
		pitch = clampf(pitch + rr, 0.15, 2.95)
		recoil_return -= rr
	_apply_blasts()
	_try_fire()
	lmb_prev = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# grenade arc preview
	if nade_charging and driving == null:
		var a := _aim_dir()
		_update_arc(player.global_position + Vector3(0, 1.35, 0) + a * 1.6, a)
		arc_mi.visible = true
	elif arc_mi != null and arc_mi.visible:
		arc_mi.visible = false

	if driving != null:
		driving.aim = _aim_dir()
		driving.throttle = (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
		driving.steer = (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
		cam_target = driving.global_position + Vector3.UP * 2.5
	else:
		player.cam_yaw = yaw
		cam_target = player.global_position + Vector3.UP * 1.5

	if driving != null and vehicle_fp:
		# cockpit / driver's-seat view: eye rides the vehicle, free look
		var eye: Vector3 = driving.to_global(DRIVER_EYE.get(driving.kind, Vector3(0, 2.2, 0)))
		cam.global_transform = Transform3D(Basis.looking_at(_aim_dir(), Vector3.UP), eye)
	elif first_person and driving == null:
		var eye2: Vector3 = player.global_position + Vector3(0, 1.35, 0)
		cam.global_transform = Transform3D(Basis.looking_at(_aim_dir(), Vector3.UP), eye2)
	else:
		if pitch > 1.5 and not _flying():
			pitch = 1.5
		var pos := cam_target + Vector3(dist * sin(pitch) * sin(yaw), dist * cos(pitch), dist * sin(pitch) * cos(yaw))
		pos.y = maxf(pos.y, 0.6)
		cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(cam_target, Vector3.UP)

	# explosion / cannon shake, applied on top of whichever camera is live
	if cam_shake > 0.001:
		cam.global_transform.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * cam_shake * 0.2
		cam_shake = maxf(cam_shake - dt * 2.6, 0.0)

	_hud_tick(dt)
	if test_mode:
		_autotest(dt)

func _hud_tick(dt: float) -> void:
	hud_acc += dt
	if hud_acc < 0.2:
		return
	hud_acc = 0.0
	var awake := _count_awake()
	var mode: String
	if driving != null:
		var view := "cockpit" if vehicle_fp else "chase"
		mode = "%s  %.0f m/s  [%s view — V]  (E exit, L-click fire)" % [driving.kind.to_upper(), driving.linear_velocity.length(), view]
		if driving.kind == "plane":
			mode += "\nFLIGHT: hold W for throttle — the plane flies toward your AIM. Aim up to climb, down to dive."
	else:
		var wname: String = ["", "BOLT RIFLE: R-click aim", "ROCKET", "GRENADE: hold L, release to throw", "SHOVEL: L dig, R build"][weapon]
		mode = "on foot [%s]  (1 rifle | 2 rocket | 3 grenade | 4 shovel)  spoil: %d" % [wname, spoil]
		if first_person:
			mode += "  1st person"
	hud.text = "BRICKFIELD: WESTERN FRONT   %s\nawake bricks: %d   fps: %d\nWASD move/drive | Space jump | Shift sprint | E enter/exit | V camera | Esc mouse" \
		% [mode, awake, Engine.get_frames_per_second()]

func _count_awake() -> int:
	var awake := 0
	for b in get_tree().get_nodes_in_group("bricks"):
		if not b.sleeping:
			awake += 1
	return awake

# ============================ headless autotest ============================

func _possess(v: Vehicle) -> void:
	driving = v
	v.possessed = true
	player.get_node("Shape").disabled = true
	player.set_physics_process(false)

func _autotest(dt: float) -> void:
	test_t += dt
	if fmod(test_t, 2.0) < dt:
		print("AWAKE t=%.0f n=%d" % [test_t, _count_awake()])
	match test_stage:
		0:
			if test_t >= 2.5:
				print("PRE_BLAST awake=%d" % _count_awake())
				# M-EARTH checks: dig a column to bedrock, build one scoop back
				var ci := earth.col_at(Vector3(0, 0, 0))
				for k in 6:
					earth.dig(ci)
				print("DIG_TEST h=%d (started at %d)" % [earth.heights[ci], earth.depth_cells])
				earth.place(ci)
				print("PLACE_TEST h=%d" % earth.heights[ci])
				queue_blast(Vector3(10, 0.5, 5), 12.0, 60.0)   # artillery into the field -> crater
				queue_blast(Vector3(0, 1.2, 33.0))   # shell the allied parapet
				for v in get_tree().get_nodes_in_group("mannable"):
					if v.kind == "tank":
						_possess(v)
				print("TEST: possessed tank")
				test_stage = 1
		1:
			if driving != null:
				driving.throttle = 1.0
				driving.steer = 0.3
				if fmod(test_t, 0.5) < dt:
					var tp := driving.global_position
					print("TANK_POS %.1f,%.1f,%.1f" % [tp.x, tp.y, tp.z])
			if test_t >= 6.0 and driving != null:
				cooldowns.clear()
				var fwd: Vector3 = driving.global_transform.basis.x.normalized()
				var o: Vector3 = driving.to_global(Vector3(7.2, 1.2, 0))
				_shoot(o, (fwd + Vector3.UP * 0.04).normalized() * 85.0, 0.5, 8.0, 45.0, 0.4, 0.0, driving, false)
				print("TEST: tank cannon fired")
				test_stage = 2
		2:
			if test_t >= 8.0:
				if driving != null:
					driving.possessed = false
					driving.throttle = 0.0
				driving = null
				for v in get_tree().get_nodes_in_group("mannable"):
					if v.kind == "plane":
						_possess(v)
				print("TEST: possessed plane")
				test_stage = 3
		3:
			if driving != null:
				driving.throttle = 1.0
				var fwd: Vector3 = driving.global_transform.basis.x.normalized()
				driving.aim = (fwd + Vector3.UP * 0.45).normalized()
				if fmod(test_t, 0.5) < dt:
					var pp := driving.global_position
					print("PLANE_POS %.1f,%.1f,%.1f  speed=%.1f" % [pp.x, pp.y, pp.z, driving.linear_velocity.length()])
				if test_t >= 18.0:
					if driving.global_position.y > 8.0:
						print("PLANE_FLIES alt=%.1f" % driving.global_position.y)
					else:
						print("PLANE_GROUNDED alt=%.1f" % driving.global_position.y)
					test_stage = 4
		4:
			if test_t >= 24.0:
				print("TEST_DONE bricks=%d awake=%d" % [get_tree().get_nodes_in_group("bricks").size(), _count_awake()])
				get_tree().quit()
