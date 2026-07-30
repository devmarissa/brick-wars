extends Node
## BRICK WARS — BLAST FEEL FIXTURE
##
## BUILD-ORDER §1e. The one irreplaceable thing in the old prototype is how blowing
## things up FELT. "It felt good" is a specification; this is it written down before it
## evaporates.
##
## It loads a build, spawns identical structures at a fixed location with a fixed seed,
## detonates identical charges, and records what happened: how much moved, how fast, how
## high, how far it scattered, how long it took to stop. Run it against the archived
## prototype to make a baseline; run it against the rebuild to prove nothing was lost.
##
## Determinism note: this is deterministic ON ONE MACHINE. Jolt is not bit-identical
## across platforms, so a Linux baseline and a macOS rebuild are not comparable. Always
## capture the baseline and the comparison on the same hardware.

const SEED := 20260730
const MAX_TICKS := 900          # 15 s at 60 Hz — hard stop if something never settles
const SETTLE_SPEED := 0.30      # m/s; below this a brick counts as stopped
const SETTLE_HOLD := 30         # ticks everything must stay still before we call it settled
const SAMPLE_EVERY := 2         # timeline resolution, in ticks
const SHOT_TICKS := [0, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192]
const VOID_Y := -20.0           # below this a brick has left the world; freeze and count it
const MEASURE_RADIUS := 80.0    # only bricks this close to the scenario are measured
const CAM_BACK := 10.0          # screenshot camera: metres behind the observer
const CAM_UP := 5.0             # ...and metres above
const EJECTION_CAP := 200.0     # m/s; above this is an interpenetration artefact, not feel.
                                # Counted separately so it can't poison the peak-speed
                                # number — the rebuild should not reproduce a bug.
const OBSERVER_OFFSET := Vector3(8, 1.5, 0)    # where the player stands for every shot
                                               # (inside knockback reach for every charge
                                               #  here, so no scenario reads a flat zero)

# Test structures live far from the built world so the fixture measures the BLAST and not
# the map. The earth scenarios are the exception and deliberately sit in no-man's-land.
const PAD := Vector3(600, 0, 600)
const PAD_SIZE := Vector3(240, 1, 240)

var main_node: Node = null
var results := {}
var shots_dir := ""
var strays := 0          # projectiles that appeared during the current scenario
var strays_total := 0
var last_shot_hash := 0  # to notice when a capture repeated the previous rendered frame
var dupe_shots := 0
var dupe_shots_total := 0


## THE FIXTURE MUST OWN THE INPUT.
##
## Learned the hard way on the first real capture: the prototype grabs the mouse on start
## and fires from the player on left-click, and the observer we teleport in is standing 8 m
## from the charge with a loaded rifle. One click in the window to focus it put a round into
## the test wall — 112 m/s peak instead of 11, a brick thrown 94 m, and a baseline that
## looked plausible and was wrong. A fixture that can be perturbed by touching the window is
## not a fixture.
##
## Three layers, because this must not be able to happen twice:
##   1. hold the mouse released, which is the first thing main._try_fire() checks
##   2. pin the capture grace, which is the second thing it checks
##   3. destroy anything that gets fired anyway, in the tick it was born, and COUNT it —
##      a contaminated run must say so rather than quietly writing a baseline
##
## This runs before main's own _physics_process (parent before child in tree order), so the
## gag is always in place before the game reads the mouse.
func _physics_process(_dt: float) -> void:
	if main_node == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "capture_grace" in main_node:
		main_node.capture_grace = 999.0
	for c in main_node.get_children():
		# a Projectile is a rigid body that knows whether it has gone off; nothing else in
		# the world is. Kept duck-typed so this still works against the rebuild.
		if c is RigidBody3D and "exploded" in c:
			strays += 1
			c.queue_free()


func _ready() -> void:
	var out_dir := _arg("--fixture-out", "res://fixture_out")
	shots_dir = out_dir.path_join("shots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots_dir))

	# Screenshots are grabbed from the viewport on physics ticks, so the window must render
	# at least as fast as physics runs or captures repeat (see _shot). Nothing here touches
	# the simulation — physics is fixed-step and does not care how often we draw.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

	main_node = load("res://main.tscn").instantiate()
	add_child(main_node)

	# let the world build and put itself to sleep
	for i in 20:
		await get_tree().physics_frame

	_build_pad()

	results = {
		"fixture_version": 2,
		"godot": Engine.get_version_info()["string"],
		"seed": SEED,
		"physics_hz": Engine.physics_ticks_per_second,
		"platform": OS.get_name(),
		"settle_speed_threshold": SETTLE_SPEED,
		# false if anything fired during the run. A baseline that isn't clean is not a
		# baseline; the comparison tool refuses to use it.
		"clean": true,
		"stray_projectiles": 0,
		# captures that came back byte-identical to the previous one. Cosmetic only —
		# the flipbook, never the numbers.
		"duplicate_frames": 0,
		"scenarios": [],
	}

	for sc in _scenarios():
		var r: Dictionary = await _run_scenario(sc)
		results["scenarios"].append(r)
		print("  %s %-24s %3d moved · peak %6.1f m/s · %5.1f m high · shake %.2f · knock %5.1f · settled %.2f s"
			% ["→" if r["integrity"]["stray_projectiles"] == 0 else "!!",
			   sc["name"], r["scatter"]["moved_over_half_metre"], r["impulse"]["peak_speed"],
			   r["wake"]["peak_height"], r["felt"]["shake_peak"],
			   r["felt"]["player_knock_peak"], r["settle"]["seconds"]])

	results["stray_projectiles"] = strays_total
	results["clean"] = strays_total == 0
	results["duplicate_frames"] = dupe_shots_total

	var f := FileAccess.open(out_dir.path_join("blast_baseline.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("\nFIXTURE DONE → %s" % out_dir.path_join("blast_baseline.json"))

	if strays_total > 0:
		printerr("\n!! CONTAMINATED RUN — %d projectile(s) were fired during measurement." % strays_total)
		printerr("!! Something sent input to the window. Do not use this as a baseline;")
		printerr("!! close anything sitting on the game window and run it again.")
		get_tree().quit(3)
		return
	get_tree().quit()


# ---------------------------------------------------------------- scenarios

func _scenarios() -> Array:
	return [
		# The core question: what does a standard shell do to a stacked wall?
		{"name": "wall_standard_shell", "structure": "wall",
		 "at": PAD + Vector3(0, 0, 0), "radius": 8.0, "power": 42.0, "offset": Vector3(0, 1.0, 5.0)},

		# Half power — below SHATTER_POWER (25), so it shoves rather than shatters.
		# The difference between these two IS the feel we're protecting.
		{"name": "wall_light_charge", "structure": "wall",
		 "at": PAD + Vector3(0, 0, 0), "radius": 8.0, "power": 18.0, "offset": Vector3(0, 1.0, 5.0)},

		# Heavy charge, point blank. The showpiece.
		{"name": "wall_heavy_point_blank", "structure": "wall",
		 "at": PAD + Vector3(0, 0, 0), "radius": 12.0, "power": 80.0, "offset": Vector3(0, 1.5, 2.0)},

		# Airburst above the wall — tests the downward/outward split.
		{"name": "wall_airburst", "structure": "wall",
		 "at": PAD + Vector3(0, 0, 0), "radius": 10.0, "power": 42.0, "offset": Vector3(0, 6.0, 0.0)},

		# A loose pile rather than a stacked wall: same charge, different structure.
		{"name": "pile_standard_shell", "structure": "pile",
		 "at": PAD + Vector3(0, 0, 0), "radius": 8.0, "power": 42.0, "offset": Vector3(0, 1.0, 5.0)},

		# Free-air burst with nothing but the pad: isolates camera shake and earth response.
		{"name": "empty_standard_shell", "structure": "none",
		 "at": PAD + Vector3(0, 0, 0), "radius": 8.0, "power": 42.0, "offset": Vector3(0, 1.0, 0.0)},

		# In no-man's-land, on the real earth field, to capture carve counts and crater lip.
		# Far apart so neither shot's crater or debris reaches the other. These two run in
		# the live world rather than on the pad, so they are the ones with run-to-run
		# spread — see the README on tolerances.
		{"name": "earth_standard_shell", "structure": "none", "isolation": "world",
		 "at": Vector3(-25, 0, 0), "radius": 8.0, "power": 42.0, "offset": Vector3(0, 0.5, 0.0)},
		{"name": "earth_heavy_charge", "structure": "none", "isolation": "world",
		 "at": Vector3(25, 0, 0), "radius": 12.0, "power": 80.0, "offset": Vector3(0, 0.5, 0.0)},
	]


# ---------------------------------------------------------------- structures

## A static plate far from the world, so brick scenarios measure the blast and nothing else.
func _build_pad() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PAD_SIZE
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = PAD + Vector3(0, -0.5, 0)


func _spawn_structure(kind: String, at: Vector3) -> Array:
	var made := []
	match kind:
		"wall":
			# 10 wide x 6 high x 2 deep of half-metre bricks, hand-stacked with jitter,
			# which is what the game's own walls are.
			var bs := Vector3(1.0, 0.5, 0.5)
			for ix in 10:
				for iy in 6:
					for iz in 2:
						var p := at + Vector3(
							(ix - 4.5) * bs.x,
							bs.y * 0.5 + iy * bs.y,
							(iz - 0.5) * bs.z)
						made.append(main_node.spawn_brick(
							p, Basis.IDENTITY, bs, main_node.SBAG, Vector3.ZERO, true, 0.04))
		"pile":
			# Same brick count, dumped rather than stacked.
			for i in 120:
				var a := randf_range(0, TAU)
				var rr := sqrt(randf()) * 2.6
				var p := at + Vector3(cos(a) * rr, 0.3 + randf() * 2.2, sin(a) * rr)
				made.append(main_node.spawn_brick(
					p, Basis(Vector3.UP, a), Vector3(1.0, 0.5, 0.5),
					main_node.MUD, Vector3.ZERO, false, 0.06))
		"none":
			pass
	return made


# ---------------------------------------------------------------- the run

func _run_scenario(sc: Dictionary) -> Dictionary:
	# Snapshot the world BEFORE anything is spawned. Everything not in here — the test
	# structure included — gets removed afterwards, which is what keeps each scenario from
	# inheriting the last one's rubble.
	var pre_ids := {}
	for b in get_tree().get_nodes_in_group("bricks"):
		pre_ids[b.get_instance_id()] = true

	strays = 0
	dupe_shots = 0
	last_shot_hash = 0
	seed(SEED)
	var at: Vector3 = sc["at"]
	var bricks: Array = _spawn_structure(sc["structure"], at)

	# settle the structure before measuring anything
	for i in 90:
		await get_tree().physics_frame
	for b in bricks:
		if is_instance_valid(b):
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			b.sleeping = true
	await get_tree().physics_frame

	var start_pos := {}
	for b in bricks:
		if is_instance_valid(b):
			start_pos[b.get_instance_id()] = b.global_position

	var earth_before := _earth_height_sum()
	var pre_bricks := get_tree().get_nodes_in_group("bricks").size()
	var point: Vector3 = at + sc["offset"]

	# Camera shake and player knockback both fall off with distance from the PLAYER, so
	# they only mean anything if the player is standing somewhere fixed. Put the observer
	# ten metres away, on the ground, for every shot.
	var obs = main_node.player
	var obs_pos: Vector3 = at + OBSERVER_OFFSET
	obs.velocity = Vector3.ZERO
	obs.knock = Vector3.ZERO
	obs.global_position = obs_pos
	_frame_camera(obs_pos, point)

	seed(SEED)
	main_node.cam_shake = 0.0
	main_node.queue_blast(point, sc["radius"], sc["power"])

	var timeline := []
	var peak_speed := 0.0
	var peak_height := -1e9
	var peak_height_tick := 0
	var peak_awake := 0
	var peak_awake_tick := 0
	var peak_shake := 0.0
	var shake_last_tick := -1
	var peak_knock := 0.0
	var first_tick_speeds := []
	var still_for := 0
	var settled_tick := -1
	var last_moving_tick := 0
	var lost := 0
	var ejections := 0
	var shot_i := 0
	var obs_drift := 0.0

	for t in MAX_TICKS:
		await get_tree().physics_frame

		var awake := 0
		var speed_sum := 0.0
		var max_y := -1e9
		var moving := 0
		for b in get_tree().get_nodes_in_group("bricks"):
			if not is_instance_valid(b) or b.sleeping:
				continue
			# anything that has left the world would fall forever and never let the
			# scenario settle — park it and count it, because "sent it into orbit" is
			# itself a fact about the blast
			if b.global_position.y < VOID_Y:
				b.freeze = true
				b.sleeping = true
				lost += 1
				continue
			# only this scenario's neighbourhood counts; a brick still twitching somewhere
			# else in the map is not this explosion's business
			if b.global_position.distance_to(at) > MEASURE_RADIUS:
				continue
			awake += 1
			var s: float = b.linear_velocity.length()
			speed_sum += s
			if s > SETTLE_SPEED:
				moving += 1
			if s > peak_speed and s < EJECTION_CAP:
				peak_speed = s
			elif s >= EJECTION_CAP:
				ejections += 1
			if b.global_position.y > max_y:
				max_y = b.global_position.y

		if t == 0:
			for b in get_tree().get_nodes_in_group("bricks"):
				if is_instance_valid(b) and not b.sleeping \
						and b.global_position.distance_to(at) <= MEASURE_RADIUS:
					first_tick_speeds.append(minf(b.linear_velocity.length(), EJECTION_CAP))

		if awake > peak_awake:
			peak_awake = awake
			peak_awake_tick = t
		if max_y > peak_height:
			peak_height = max_y
			peak_height_tick = t
		if main_node.cam_shake > peak_shake:
			peak_shake = main_node.cam_shake
		if main_node.cam_shake > 0.001:
			shake_last_tick = t
		var kn: float = (obs.knock as Vector3).length()
		if kn > peak_knock:
			peak_knock = kn
		# How far the observer ended up from where we put them. It's deterministic — the
		# blast throws them the same way every time — so it doubles as a tripwire: if
		# someone leans on a movement key during a run, this is the number that moves.
		var od: float = obs.global_position.distance_to(obs_pos)
		if od > obs_drift:
			obs_drift = od

		if t % SAMPLE_EVERY == 0:
			timeline.append({
				"tick": t,
				"awake": awake,
				"moving": moving,
				"mean_speed": snappedf(speed_sum / maxf(awake, 1), 0.01),
				"max_y": snappedf(max_y if max_y > -1e8 else 0.0, 0.01),
				"shake": snappedf(main_node.cam_shake, 0.001),
			})

		if shot_i < SHOT_TICKS.size() and t == SHOT_TICKS[shot_i]:
			_shot("%s_t%03d" % [sc["name"], t])
			shot_i += 1

		if moving == 0:
			still_for += 1
			if still_for >= SETTLE_HOLD:
				settled_tick = last_moving_tick
				break
		else:
			still_for = 0
			last_moving_tick = t

	_shot("%s_settled" % sc["name"])

	# scatter
	var moved := 0
	var disp_sum := 0.0
	var disp_max := 0.0
	var alive := 0
	for b in bricks:
		if not is_instance_valid(b):
			continue
		alive += 1
		var d: float = b.global_position.distance_to(start_pos[b.get_instance_id()])
		disp_sum += d
		if d > 0.5:
			moved += 1
		if d > disp_max:
			disp_max = d

	var hz: float = float(Engine.physics_ticks_per_second)
	var ticks: int = settled_tick if settled_tick >= 0 else MAX_TICKS
	var res := {
		"name": sc["name"],
		"structure": sc["structure"],
		"isolation": sc.get("isolation", "pad"),
		"charge": {
			"point": _v(point), "radius": sc["radius"], "power": sc["power"],
			"above_shatter_threshold": sc["power"] >= main_node.SHATTER_POWER,
			"observer_at": _v(obs_pos),
			"observer_distance": snappedf(obs_pos.distance_to(point), 0.01),
		},
		"impulse": {
			"bricks_launched_first_tick": first_tick_speeds.size(),
			"peak_speed": snappedf(peak_speed, 0.01),
			"mean_launch_speed": snappedf(_mean(first_tick_speeds), 0.01),
			"max_launch_speed": snappedf(_max(first_tick_speeds), 0.01),
			"ejection_artefacts": ejections,
		},
		"wake": {
			"peak_height": snappedf(peak_height if peak_height > -1e8 else 0.0, 0.01),
			"peak_height_tick": peak_height_tick,
			"peak_awake": peak_awake,
			"peak_awake_tick": peak_awake_tick,
		},
		"felt": {
			"shake_peak": snappedf(peak_shake, 0.001),
			"shake_seconds": snappedf((shake_last_tick + 1) / hz, 0.01),
			"player_knock_peak": snappedf(peak_knock, 0.01),
			"observer_drift": snappedf(obs_drift, 0.01),
		},
		"integrity": {
			"stray_projectiles": strays,
			"duplicate_frames": dupe_shots,
		},
		"earth": {
			"height_cells_removed": earth_before - _earth_height_sum(),
			"debris_spawned": get_tree().get_nodes_in_group("bricks").size() - pre_bricks,
		},
		"settle": {
			"ticks": ticks,
			"seconds": snappedf(ticks / hz, 0.01),
			"timed_out": settled_tick < 0,
		},
		"scatter": {
			"structure_bricks": bricks.size(),
			"surviving": alive,
			"moved_over_half_metre": moved,
			"mean_displacement": snappedf(disp_sum / maxf(alive, 1), 0.01),
			"max_displacement": snappedf(disp_max, 0.01),
			"left_the_world": lost,
		},
		"timeline": timeline,
	}

	strays_total += strays
	dupe_shots_total += dupe_shots
	await _cleanup(pre_ids)
	return res


## Leave the world exactly as we found it, minus the crater. Anything that wasn't a brick
## before this scenario ran — the test structure, spall, thrown earth — goes away, so no
## scenario can be contaminated by the one before it.
func _cleanup(pre_ids: Dictionary) -> void:
	for b in get_tree().get_nodes_in_group("bricks"):
		if is_instance_valid(b) and not pre_ids.has(b.get_instance_id()):
			b.queue_free()
	await get_tree().physics_frame
	# let anything the blast disturbed come back to rest before the next measurement
	for i in 30:
		await get_tree().physics_frame
	for b in get_tree().get_nodes_in_group("bricks"):
		if is_instance_valid(b) and not b.freeze:
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			b.sleeping = true
	main_node.cam_shake = 0.0
	await get_tree().physics_frame


# ---------------------------------------------------------------- helpers

func _earth_height_sum() -> int:
	if main_node.earth == null:
		return 0
	var s := 0
	for h in main_node.earth.heights:
		s += h
	return s


## Put the chase camera over the observer's shoulder, looking at the charge, so every
## screenshot sequence is framed the same way and two runs can be flicked between.
## Only affects what's recorded — the camera is not part of the simulation.
func _frame_camera(from: Vector3, toward: Vector3) -> void:
	main_node.first_person = false
	var d := toward - from
	var flat := Vector3(d.x, 0, d.z)
	if flat.length() < 0.01:
		flat = Vector3(0, 0, 1)
	var back := -flat.normalized() * CAM_BACK + Vector3.UP * CAM_UP
	main_node.dist = back.length()
	main_node.yaw = atan2(back.x, back.z)
	main_node.pitch = acos(clampf(back.y / back.length(), -1.0, 1.0))
	main_node._apply_camera_mode()


## The viewport texture only updates on a *draw* frame, and this runs on physics frames.
## With vsync on, physics at 60 Hz and the display at 60 Hz sit exactly on the aliasing
## boundary: one hitch and the engine takes two physics steps inside a single drawn frame,
## and both captures read back the same image. The first Mac capture came back with
## t002≡t004, t006≡t008 and t012≡t016 byte for byte — the flipbook quietly running at half
## rate in exactly the front-loaded window it was designed to be dense in.
##
## Vsync is off and max_fps uncapped (see _ready) so draws now comfortably outnumber physics
## steps. When it happens anyway, count it — a degraded flipbook should say so rather than be
## discovered by md5 six months later. It does NOT make the run unclean: every measured
## number comes from physics state, not from pixels, so the baseline is unaffected either way.
func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	var h := hash(img.get_data())
	if h == last_shot_hash:
		dupe_shots += 1
	last_shot_hash = h
	img.save_png(shots_dir.path_join(name + ".png"))


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += x
	return s / a.size()


func _max(a: Array) -> float:
	var m := 0.0
	for x in a:
		if x > m:
			m = x
	return m


func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
	return fallback
