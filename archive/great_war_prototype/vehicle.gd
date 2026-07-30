class_name Vehicle
extends RigidBody3D
## A vehicle, emplacement, or shatterable multi-part prop.
## kinds: tank / jeep / plane / boat / turret / aa / arty / dummy
## Convention: vehicle FORWARD is +X (matches the part tables).

const WATER_LEVEL := 1.4

# -- feel-tuning knobs (accelerations, so they're independent of mass) --
var kind := "prop"
var drivable := false      # moves under player control (tank/jeep/plane/boat)
var mannable := false      # can be possessed at all (drivables + emplacements)
var fragile := false       # any blast shatters it (target dummies)
var max_speed := 15.0
var accel := 22.0          # m/s^2
var turn_rate := 1.5       # rad/s
var turn_accel := 6.0
var grip := 9.0            # lateral traction (lower = drifty)
var brake_rate := 3.0
var takeoff_speed := 18.0  # plane: speed where wings carry full weight

var parts: Array = []      # [x,y,z,sx,sy,sz,color,(rotz)] — debris on shatter
var extent := 0.0
var water_rect := Rect2()  # set by main for boats
var possessed := false
var throttle := 0.0
var steer := 0.0
var aim := Vector3.FORWARD # camera aim, set by main while possessed

func _physics_process(dt: float) -> void:
	if kind == "boat" and not (sleeping and not possessed):
		_buoyancy(dt)
	if not possessed:
		return
	sleeping = false
	match kind:
		"tank", "jeep":
			_drive_ground(dt)
		"plane":
			_fly(dt)
		"boat":
			_drive_boat(dt)
		_:
			pass # emplacements don't move; they just shoot (main handles firing)

func _fwd() -> Vector3:
	var f := global_transform.basis.x
	f.y = 0.0
	return f.normalized()

func _drive_ground(dt: float) -> void:
	var fwd := _fwd()
	var fs := linear_velocity.dot(fwd)
	if throttle > 0.0 and fs < max_speed:
		apply_central_force(fwd * accel * mass)
	elif throttle < 0.0 and fs > -max_speed * 0.4:
		apply_central_force(-fwd * accel * mass)
	var target_turn := steer * turn_rate * (minf(absf(fs), 6.0) / 6.0 * 0.4 + 0.6)
	apply_torque(Vector3.UP * (target_turn - angular_velocity.y) * turn_accel * mass)
	var lat := Vector3(-fwd.z, 0.0, fwd.x)
	linear_velocity -= lat * linear_velocity.dot(lat) * (1.0 - exp(-grip * dt))
	if throttle == 0.0:
		linear_velocity -= fwd * fs * (1.0 - exp(-brake_rate * dt))

func _fly(dt: float) -> void:
	var fwd := global_transform.basis.x.normalized()
	var fs := linear_velocity.dot(fwd)
	if throttle > 0.0 and fs < max_speed:
		apply_central_force(fwd * accel * mass)
	elif throttle < 0.0:
		apply_central_force(-fwd * accel * 0.6 * mass)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var lift := clampf(fs / takeoff_speed, 0.0, 1.0)
	apply_central_force(Vector3.UP * g * mass * lift * 1.03)   # wings carry the plane at speed
	if lift > 0.35:
		# arcade flight: steer the nose toward the camera aim, bank/level the wings
		apply_torque(fwd.cross(aim.normalized()) * turn_accel * mass * lift)
		apply_torque(global_transform.basis.y.cross(Vector3.UP) * turn_accel * 0.35 * mass * lift)
	else:
		apply_torque(Vector3.UP * steer * turn_accel * 0.5 * mass)  # taxiing
	# air grip: bleed off sideslip so it flies where the nose points
	var lat := linear_velocity - fwd * fs
	linear_velocity -= lat * (1.0 - exp(-2.2 * dt))

func _drive_boat(dt: float) -> void:
	var p := global_position
	var in_water := water_rect.has_point(Vector2(p.x, p.z)) and p.y < WATER_LEVEL + 0.8
	var fwd := _fwd()
	var fs := linear_velocity.dot(fwd)
	if in_water:
		if throttle > 0.0 and fs < max_speed:
			apply_central_force(fwd * accel * mass)
		elif throttle < 0.0 and fs > -max_speed * 0.4:
			apply_central_force(-fwd * accel * mass)
		var target_turn := steer * turn_rate * (minf(absf(fs), 5.0) / 5.0 * 0.6 + 0.4)
		apply_torque(Vector3.UP * (target_turn - angular_velocity.y) * turn_accel * mass)
		var lat := Vector3(-fwd.z, 0.0, fwd.x)
		linear_velocity -= lat * linear_velocity.dot(lat) * (1.0 - exp(-grip * dt))

func _buoyancy(_dt: float) -> void:
	var p := global_position
	if not water_rect.has_point(Vector2(p.x, p.z)):
		return
	var depth := WATER_LEVEL - p.y
	if depth > -1.0:
		var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		var sub := clampf((depth + 1.0) / 1.2, 0.0, 1.6)
		apply_central_force(Vector3.UP * g * mass * sub)
		apply_central_force(Vector3.UP * -linear_velocity.y * mass * 2.5)     # vertical damping
		var hv := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		apply_central_force(-hv * mass * 0.35)                                # water drag
