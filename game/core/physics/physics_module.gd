extends Module
## Bricks, the Jolt configuration, and the sleep discipline that makes thousands of them
## affordable. CORE-SPEC §2, "Physics & destruction" — blast, structural integrity, debris
## lifecycle and fire spread land here in C5.

const BrickScene := preload("res://core/physics/brick.gd")

## The three proven values (BUILD-ORDER §1a). Verified against ProjectSettings at boot,
## because a silent drift here reads as "the game feels heavy now" six weeks later and
## nobody thinks to check a .godot file.
const REQUIRED_ENGINE := "Jolt Physics"
const REQUIRED_GRAVITY := 20.0
const REQUIRED_SLEEP_THRESHOLD := 0.35

## Ticks to wait before putting a freshly spawned body to sleep. Setting `sleeping = true`
## before the body has entered the physics space is silently overwritten — this cost real
## days to find, and it is why bulk spawns used to wake the whole world.
const SLEEP_DELAY_TICKS := 2

var settings_ok := false
var settings_problem := ""

var _pending_sleep: Array = []   # [[body, ticks_left], ...]
var _colour_cache: Dictionary = {}


func module_name() -> StringName:
	return &"physics"


func module_init() -> void:
	settings_ok = _verify_settings()


func _physics_process(_dt: float) -> void:
	if _pending_sleep.is_empty():
		return
	var still: Array = []
	for entry in _pending_sleep:
		var body: RigidBody3D = entry[0]
		if not is_instance_valid(body):
			continue
		entry[1] -= 1
		if entry[1] <= 0:
			body.sleeping = true
		else:
			still.append(entry)
	_pending_sleep = still


## Spawn one brick. `asleep` uses the delayed-sleep pattern above, so a thousand bricks
## placed by a map author cost nothing until something disturbs them.
func spawn_brick(pos: Vector3, size: Vector3, colour: Color,
		asleep := false, rot := Basis.IDENTITY) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(BrickScene)
	body.add_to_group(&"bricks")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material_for(colour)
	body.add_child(mesh)

	add_child(body)
	body.global_transform = Transform3D(rot, pos)

	if asleep:
		_pending_sleep.append([body, SLEEP_DELAY_TICKS])
	return body


func count_bricks() -> int:
	return get_tree().get_nodes_in_group(&"bricks").size()


func count_awake() -> int:
	var awake := 0
	for b in get_tree().get_nodes_in_group(&"bricks"):
		if is_instance_valid(b) and not b.sleeping:
			awake += 1
	return awake


func clear_bricks() -> void:
	for b in get_tree().get_nodes_in_group(&"bricks"):
		b.queue_free()
	_pending_sleep.clear()


## One material per colour rather than one per brick — a StandardMaterial3D each would put
## thousands of unique materials in the scene and cost more than the physics does.
func _material_for(colour: Color) -> StandardMaterial3D:
	var key := colour.to_rgba32()
	if _colour_cache.has(key):
		return _colour_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	_colour_cache[key] = mat
	return mat


func _verify_settings() -> bool:
	var engine_name: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 0.0)
	var sleep: float = ProjectSettings.get_setting(
		"physics/jolt_physics_3d/simulation/sleep_velocity_threshold", -1.0)

	var problems: Array[String] = []
	if engine_name != REQUIRED_ENGINE:
		problems.append("physics engine is '%s', must be '%s'" % [engine_name, REQUIRED_ENGINE])
	if not is_equal_approx(gravity, REQUIRED_GRAVITY):
		problems.append("gravity is %s, must be %s" % [gravity, REQUIRED_GRAVITY])
	if not is_equal_approx(sleep, REQUIRED_SLEEP_THRESHOLD):
		problems.append("Jolt sleep_velocity_threshold is %s, must be %s — below this the "
			% [sleep, REQUIRED_SLEEP_THRESHOLD] + "world never sleeps and the frame rate dies")

	settings_problem = "; ".join(problems)
	if not problems.is_empty():
		push_error("physics: project settings drifted from the proven values — " + settings_problem)
		return false
	return true
