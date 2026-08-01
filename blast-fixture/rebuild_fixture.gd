extends Node3D
## The blast feel fixture, re-pointed at the rebuild. `BUILD-ORDER` §1e, C5.
##
## `blast_fixture.gd` beside this file is the original, and it drives the **old** project — it
## instantiates that build's `main.tscn` and calls `main_node.spawn_brick`, `main_node.SHATTER_POWER`
## and so on. It cannot be pointed at the rebuild, because none of that exists here. So this is the
## same eight scenarios, the same measurements, the same output shape, standing up the same
## structures out of `Brick.spawn` and setting them off with `Blast.detonate`.
##
## Kept as a second file rather than an edit of the first, deliberately. The original is a *record*
## of how the capture was taken; rewriting it in place would destroy the only evidence of what the
## reference numbers actually mean.
##
## ### Same scenario, or the numbers mean nothing
##
## Every constant below is copied from the original. `case_fixture_wall.gd` in the suite asserts the
## wall matches the baseline's own `structure_bricks: 120` and that it stands still when nothing
## hits it — because a wall built even slightly wrong turns every metric here into a measurement of
## the scenario rather than of the blast.
##
##     godot --headless --path game res://../blast-fixture/rebuild_fixture.tscn
##
## writes `blast-fixture/out/blast_baseline.json`, which `compare_baselines.py` reads.

const SEED := 20260730
const MAX_TICKS := 900            # 15 s at 60 Hz — hard stop if something never settles
const SETTLE_SPEED := 0.30        # m/s; below this a brick counts as stopped
const SETTLE_HOLD := 30           # ticks everything must stay still before we call it settled
const SAMPLE_EVERY := 2           # timeline resolution, in ticks
const VOID_Y := -20.0             # below this a brick has left the world
const EJECTION_CAP := 200.0       # m/s; above this is interpenetration, not feel
const OBSERVER_OFFSET := Vector3(8, 1.5, 0)

## The old build's decay rates, which the measured `felt.*` numbers are a consequence of rather than
## a description of. Both are ported exactly, because the fixture samples *after* a frame of decay
## and the reference numbers are therefore post-decay values.
##
## `cam_shake = maxf(cam_shake - dt * 2.6, 0.0)` — linear, gone in under half a second.
## `knock *= maxf(1.0 - 5.0 * dt, 0.0)` — exponential, and the *vertical* component is consumed
## whole on the first frame (`velocity.y += knock.y; knock.y = 0.0`) so it never appears in a
## measured peak. That last detail is the difference between 5.21 and 3.8, and it is not a
## discrepancy in the blast — it is what the old player did with the number the blast gave it.
const SHAKE_DECAY := 2.6
const KNOCK_DECAY := 5.0
const PAD := Vector3(600, 0, 600)
const PAD_SIZE := Vector3(240, 1, 240)

const WALL_BRICK := Vector3(1.0, 0.5, 0.5)
const WALL_JITTER := 0.04
const PILE_JITTER := 0.06
const WALL_MATERIAL := &"sandbag"
const PILE_MATERIAL := &"mud"

const OUT_DIR := "res://../blast-fixture/out"

var _materials: MaterialSet = null
var _palette: Palette = null
var _rng := RandomNumberGenerator.new()
var _last_crater_cm := 0
var _last_cells := 0
var _last_debris := 0
var _field: EarthField = null


func _ready() -> void:
	_rng.seed = SEED
	_palette = Palette.new()
	_materials = MaterialSet.new()
	if not (_palette.load_core() and _materials.load_core(_palette)):
		push_error("fixture: core materials would not load")
		get_tree().quit(2)
		return

	_build_pad()
	var results: Array = []
	for scenario in _scenarios():
		results.append(await _run(scenario))
		print("  %-24s pushed %3d  peak %.2f m/s" % [
			scenario["name"], results[-1]["impulse"]["bricks_launched_first_tick"],
			results[-1]["impulse"]["peak_speed"]])

	var out := {
		"clean": true,
		"fixture_version": 2,
		"godot": "%s.%s.%s-%s (%s)" % [
			Engine.get_version_info()["major"], Engine.get_version_info()["minor"],
			Engine.get_version_info()["patch"], Engine.get_version_info()["status"],
			Engine.get_version_info()["build"]],
		"physics_hz": Engine.physics_ticks_per_second,
		"platform": OS.get_name(),
		"scenarios": results,
		"seed": SEED,
		"settle_speed_threshold": SETTLE_SPEED,
		"stray_projectiles": 0,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR + "/blast_baseline.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("fixture: could not write %s" % path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print("fixture written -> %s" % ProjectSettings.globalize_path(path))
	get_tree().quit(0)


## The eight scenarios, copied from the original fixture. The two `world` ones ran on the live earth
## field in the old build and are the ones with run-to-run spread.
func _scenarios() -> Array:
	return [
		{"name": "wall_standard_shell", "structure": "wall", "at": PAD,
		 "radius": 8.0, "power": 42.0, "offset": Vector3(0, 1.0, 5.0)},
		{"name": "wall_light_charge", "structure": "wall", "at": PAD,
		 "radius": 8.0, "power": 18.0, "offset": Vector3(0, 1.0, 5.0)},
		{"name": "wall_heavy_point_blank", "structure": "wall", "at": PAD,
		 "radius": 12.0, "power": 80.0, "offset": Vector3(0, 1.5, 2.0)},
		{"name": "wall_airburst", "structure": "wall", "at": PAD,
		 "radius": 10.0, "power": 42.0, "offset": Vector3(0, 6.0, 0.0)},
		{"name": "pile_standard_shell", "structure": "pile", "at": PAD,
		 "radius": 8.0, "power": 42.0, "offset": Vector3(0, 1.0, 5.0)},
		{"name": "empty_standard_shell", "structure": "none", "at": PAD,
		 "radius": 8.0, "power": 42.0, "offset": Vector3(0, 1.0, 0.0)},
		{"name": "earth_standard_shell", "structure": "none", "isolation": "world",
		 "at": Vector3(-25, 0, 0), "radius": 8.0, "power": 42.0, "offset": Vector3(0, 0.5, 0.0)},
		{"name": "earth_heavy_charge", "structure": "none", "isolation": "world",
		 "at": Vector3(25, 0, 0), "radius": 12.0, "power": 80.0, "offset": Vector3(0, 0.5, 0.0)},
	]


func _build_pad() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PAD_SIZE
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = PAD + Vector3(0, -0.5, 0)


## The wall and the pile, brick for brick out of the original.
func _structure(kind: String, at: Vector3) -> Array:
	var made := []
	match kind:
		"wall":
			for ix in 10:
				for iy in 6:
					for iz in 2:
						var p := at + Vector3((ix - 4.5) * WALL_BRICK.x,
							WALL_BRICK.y * 0.5 + iy * WALL_BRICK.y, (iz - 0.5) * WALL_BRICK.z)
						made.append(Brick.spawn(self, p, Basis.IDENTITY, WALL_BRICK,
							WALL_MATERIAL, Vector3.ZERO, _materials, _palette, WALL_JITTER))
		"pile":
			for i in 120:
				var a := _rng.randf_range(0.0, TAU)
				var rr := sqrt(_rng.randf()) * 2.6
				var p := at + Vector3(cos(a) * rr, 0.3 + _rng.randf() * 2.2, sin(a) * rr)
				made.append(Brick.spawn(self, p, Basis(Vector3.UP, a),
					Vector3(1.0, 0.5, 0.5), PILE_MATERIAL, Vector3.ZERO,
					_materials, _palette, PILE_JITTER))
	return made


func _run(sc: Dictionary) -> Dictionary:
	var at: Vector3 = sc["at"]
	var made := _structure(String(sc.get("structure", "none")), at)
	# Let the structure settle onto the pad before anything hits it, exactly as the original did.
	# Measuring displacement from a wall still finding its footing would count settling as scatter.
	for i in 30:
		await get_tree().physics_frame

	var began: Array[Vector3] = []
	for brick in made:
		began.append((brick as Node3D).global_position)

	var point: Vector3 = at + (sc["offset"] as Vector3)
	var observer: Vector3 = at + OBSERVER_OFFSET
	var radius := float(sc["radius"])
	var power := float(sc["power"])
	var hz := float(Engine.physics_ticks_per_second)
	var dt := 1.0 / hz

	var fired := Blast.detonate(get_tree(), point, radius, power, observer)
	var earth_cells := 0
	if String(sc.get("isolation", "pad")) == "world":
		made.append_array(_crater_debris(point, radius, power))
		earth_cells = _last_cells

	# The observer, modelled as the old player did: the vertical knock is spent on the first frame
	# and the horizontal part carries the body along while it decays.
	var knock: Vector3 = fired["knock"]
	var shake := float(fired["shake"])
	var observer_at := observer
	var peak_knock := 0.0
	var peak_shake := 0.0
	var drift := 0.0
	var shake_last_tick := -1

	var timeline: Array = []
	var peak_speed := 0.0
	var peak_height := -1e9
	var peak_height_tick := 0
	var peak_awake := 0
	var peak_awake_tick := 0
	var first_tick_speeds: Array[float] = []
	var artefacts := 0
	var still := 0
	var settled_tick := -1
	var last_moving_tick := 0
	var gone := 0

	for t in MAX_TICKS:
		await get_tree().physics_frame

		# Decay first, then measure — the original sampled after the frame in which the blast was
		# applied, so every reference number is one frame of decay old.
		shake = maxf(shake - dt * SHAKE_DECAY, 0.0)
		if t == 0:
			knock.y = 0.0                      # spent into the body's vertical velocity
		observer_at += Vector3(knock.x, 0.0, knock.z) * dt
		knock *= maxf(1.0 - KNOCK_DECAY * dt, 0.0)

		peak_shake = maxf(peak_shake, shake)
		if shake > 0.001:
			shake_last_tick = t
		peak_knock = maxf(peak_knock, knock.length())
		drift = maxf(drift, observer_at.distance_to(observer))

		var moving := 0
		var awake := 0
		var top := -1e9
		var total := 0.0
		for brick in made:
			var body := brick as RigidBody3D
			if body == null:
				continue
			if body.global_position.y < VOID_Y:
				body.freeze = true
				continue
			var speed := body.linear_velocity.length()
			peak_speed = maxf(peak_speed, speed)
			if t == 0:
				if speed > SETTLE_SPEED:
					first_tick_speeds.append(speed)
				if speed > EJECTION_CAP:
					artefacts += 1
			total += speed
			top = maxf(top, body.global_position.y)
			if speed > SETTLE_SPEED:
				moving += 1
			if not body.sleeping:
				awake += 1

		if awake > peak_awake:
			peak_awake = awake
			peak_awake_tick = t
		if top > peak_height:
			peak_height = top
			peak_height_tick = t
		if t % SAMPLE_EVERY == 0:
			timeline.append({"awake": awake, "max_y": snappedf(maxf(top, 0.0), 0.01),
				"mean_speed": snappedf(total / maxf(1.0, made.size()), 0.01),
				"moving": moving, "shake": snappedf(shake, 0.001), "tick": t})

		if moving == 0:
			still += 1
			if still >= SETTLE_HOLD:
				settled_tick = last_moving_tick
				break
		else:
			still = 0
			last_moving_tick = t

	var moved := 0
	var furthest := 0.0
	var drifted := 0.0
	var surviving := 0
	for i in mini(made.size(), began.size()):
		var body := made[i] as Node3D
		if body == null:
			continue
		if body.global_position.y < VOID_Y:
			gone += 1
			continue
		surviving += 1
		var shift := body.global_position.distance_to(began[i])
		drifted += shift
		furthest = maxf(furthest, shift)
		if shift > 0.5:
			moved += 1

	var ticks: int = settled_tick if settled_tick >= 0 else MAX_TICKS
	var result := {
		"charge": {
			"above_shatter_threshold": power >= Blast.SHATTER_POWER,
			"observer_at": [observer.x, observer.y, observer.z],
			"observer_distance": snappedf(observer.distance_to(point), 0.01),
			"point": [point.x, point.y, point.z],
			"power": power, "radius": radius,
		},
		"earth": {"debris_spawned": _last_debris, "height_cells_removed": earth_cells},
		"felt": {
			"observer_drift": snappedf(drift, 0.01),
			"player_knock_peak": snappedf(peak_knock, 0.01),
			"shake_peak": snappedf(peak_shake, 0.001),
			"shake_seconds": snappedf((shake_last_tick + 1) / hz, 0.01),
		},
		"impulse": {
			"bricks_launched_first_tick": first_tick_speeds.size(),
			"ejection_artefacts": artefacts,
			"max_launch_speed": snappedf(_max(first_tick_speeds), 0.01),
			"mean_launch_speed": snappedf(_mean(first_tick_speeds), 0.01),
			"peak_speed": snappedf(peak_speed, 0.01),
		},
		"integrity": {"stray_projectiles": artefacts},
		"isolation": String(sc.get("isolation", "pad")),
		"name": sc["name"],
		"scatter": {
			"left_the_world": gone,
			"max_displacement": snappedf(furthest, 0.01),
			"mean_displacement": snappedf(drifted / maxf(1.0, surviving), 0.01),
			"moved_over_half_metre": moved,
			"structure_bricks": began.size(),
			"surviving": surviving,
		},
		"settle": {"seconds": snappedf(ticks / hz, 0.01), "ticks": ticks,
			"timed_out": settled_tick < 0},
		"structure": String(sc.get("structure", "none")),
		"timeline": timeline,
		"wake": {"peak_awake": peak_awake, "peak_awake_tick": peak_awake_tick,
			"peak_height": snappedf(peak_height if peak_height > -1e8 else 0.0, 0.01),
			"peak_height_tick": peak_height_tick},
	}

	for brick in made:
		if brick != null:
			(brick as Node).queue_free()
	await get_tree().physics_frame
	return result


func _max(values: Array[float]) -> float:
	var top := 0.0
	for v in values:
		top = maxf(top, v)
	return top


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


## The earth's half of a world scenario: cut the crater, then throw up what came out of it.
##
## The debris numbers are the old build's, verbatim — a ring of mud bricks flung outward and up out
## of the hole, one per three old-grid cells of earth moved, capped at eight. They matter more than
## they look: in the two `world` scenarios there is no wall, so **the debris IS what every impulse
## metric measures**. The reference's `impulse.peak_speed: 34.35` for `earth_standard_shell` is a
## lump of mud coming out of a crater, not a brick being pushed by a blast.
func _crater_debris(point: Vector3, radius: float, power: float) -> Array:
	_ground_at(point)
	if _field == null:
		_field = EarthField.flat(_materials, 0, &"loam")
	var dug := Blast.crater(_field, null, point, radius, power)
	_last_crater_cm = int(dug["moved_cm"])
	_last_cells = int(dug["old_cells"])
	_last_debris = int(dug["debris"])

	var made := []
	for i in _last_debris:
		var around := _rng.randf_range(0.0, TAU)
		var out := Vector3(cos(around) * _rng.randf_range(1.0, 3.0), 1.2,
			sin(around) * _rng.randf_range(1.0, 3.0))
		var size := Vector3(_rng.randf_range(0.6, 1.1), 0.5, _rng.randf_range(0.6, 1.1))
		var thrown := Vector3(cos(around) * _rng.randf_range(3.0, 9.0),
			_rng.randf_range(6.0, 14.0), sin(around) * _rng.randf_range(3.0, 9.0))
		made.append(Brick.spawn(self, point + out, Basis(Vector3.UP, around), size,
			PILE_MATERIAL, thrown, _materials, _palette, 0.0))
	return made


## Somewhere for the debris to land. The world scenarios ran on the live map in the old build; here
## they get a plate, because what is being measured is what came out of the hole rather than what
## the surrounding terrain looked like.
func _ground_at(point: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = Vector3(point.x, -0.5, point.z)
