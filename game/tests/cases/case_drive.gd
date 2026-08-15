extends TestCase
## Handling, tuned on top of the springs rather than under them. C6, BUILD-ORDER C6 and §1b.
##
## > Handling is **built here, not ported**. Spring suspension and honest mass distribution come
## > first and the handling model is tuned on top of them, rather than the other way round.
##
## The order is the design. Force goes in at the wheels, where they touch the ground, and the
## chassis moves because its suspension is pushed — nothing drives the chassis directly. That
## sounds academic until you list what the other way round gets you: a vehicle that climbs kerbs it
## should stop at, corners identically with two wheels in the air as with four, and fights its own
## springs every time the ground changes. Which is precisely what the old build had, and why C6's
## done-condition makes Marissa's handling sign-off a *named* gate rather than a checkbox.
##
## So the assertion that matters most here is the one about contact: **a wheel touching nothing does
## nothing.** Nobody wrote that rule — it falls out of applying force at the wheels.

const EPSILON := 0.0001


func case_name() -> String:
	return "drive"


func run(t: TestContext) -> void:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	if not (palette.load_core() and materials.load_core(palette)):
		t.fail("core materials would not load, so nothing below means anything")
		return

	await _it_pulls_away(t, materials, palette)
	await _a_wheel_in_the_air_does_nothing(t, materials, palette)
	_the_stats_are_the_asset_s(t)


## It goes when you ask it to, and stops asking at its own top speed.
func _it_pulls_away(t: TestContext, materials: MaterialSet, palette: Palette) -> void:
	var stage := _stage(t)
	var made := _cart(stage, materials, palette)
	var chassis: RigidBody3D = made["chassis"]
	var wheels: Array = made["wheels"]
	await t.ticks(150)

	var stats := { "max_speed": 9.0, "accel": 7.0, "turn_rate": 1.8, "grip": 7.0 }
	var began := chassis.global_position
	var report: Dictionary = {}
	for i in 180:
		chassis.sleeping = false
		for wheel in wheels:
			(wheel as RigidBody3D).sleeping = false
		report = Drive.apply(chassis, wheels, stats, 1.0, 0.0, 1.0 / 60.0)
		await t.ticks(1)

	t.eq(int(report["grounded"]), 4, "all four wheels are on the ground")
	t.eq(int(report["driven"]), 4, "and all four are driving")
	var travelled := chassis.global_position.distance_to(began)
	t.ok(travelled > 2.0, "the cart pulls away: %.1f m under throttle" % travelled)
	t.ok(absf(float(report["speed"])) <= 9.0 + 1.0,
		"and does not exceed its own `max_speed`: %.2f m/s against 9" % report["speed"])

	# Let go and it slows rather than coasting forever — a vehicle that does not is one on ice.
	var rolling := absf(float(report["speed"]))
	for i in 90:
		chassis.sleeping = false
		report = Drive.apply(chassis, wheels, stats, 0.0, 0.0, 1.0 / 60.0)
		await t.ticks(1)
	t.ok(absf(float(report["speed"])) < rolling,
		"off the throttle it slows from %.2f to %.2f m/s" % [rolling, report["speed"]])

	stage.queue_free()


## The property that only falls out of driving at the wheels: **no contact, no drive.** Hold the
## cart in the air and full throttle achieves nothing at all.
func _a_wheel_in_the_air_does_nothing(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	var stage := _stage(t)
	var made := _cart(stage, materials, palette, Vector3(0, 8.0, 0))
	var chassis: RigidBody3D = made["chassis"]
	var wheels: Array = made["wheels"]
	chassis.freeze = true          # held up, as if slung or high-centred on a crater lip
	await t.ticks(30)

	var stats := { "max_speed": 9.0, "accel": 7.0, "turn_rate": 1.8, "grip": 7.0 }
	var report := Drive.apply(chassis, wheels, stats, 1.0, 0.0, 1.0 / 60.0)
	t.eq(int(report["grounded"]), 0, "nothing is touching the ground")
	t.eq(int(report["driven"]), 0, "so nothing drives, at full throttle")

	# And nothing was pushed: the report is not the only evidence, the wheels are.
	var moving := 0.0
	for wheel in wheels:
		moving = maxf(moving, absf((wheel as RigidBody3D).linear_velocity.z))
	t.ok(moving < 0.5,
		"no wheel was pushed forward by a throttle it had nothing to push against: %.2f m/s" % moving)

	stage.queue_free()


## Every number a driver feels comes off the asset rather than out of the engine — which is what
## makes a cart and a tank different vehicles rather than the same vehicle with a different mesh.
func _the_stats_are_the_asset_s(t: TestContext) -> void:
	t.ok(Drive.MAX_STEER > 0.4 and Drive.MAX_STEER < 0.8,
		"the steering lock is about a road vehicle's, in radians: %.2f" % Drive.MAX_STEER)
	t.ok(Drive.COAST_DRAG > 0.0,
		"and letting go of the throttle slows you, rather than leaving the vehicle on ice")

	# `grip` caps sideways force rather than scaling it, which is what a grip *limit* means: a gentle
	# corner is unaffected and a hard one breaks away, instead of everything being uniformly vaguer.
	t.ok(Drive.GRIP_SCALE > 1.0,
		"`grip` is scaled into newtons so a pack author writes 7 rather than guessing at a force")


## A four-wheeled sprung chassis, built here for the same reason `case_suspension` builds one: C6's
## vehicle *format* does not exist yet, and authoring a vehicle asset against a system nobody has
## written would be inventing content to satisfy a test.
func _cart(into: Node3D, materials: MaterialSet, palette: Palette,
		at := Vector3(0, 1.2, 0)) -> Dictionary:
	var chassis := Brick.spawn(into, at, Basis.IDENTITY, Vector3(1.6, 0.4, 2.6),
		&"timber", Vector3.ZERO, materials, palette)
	chassis.name = "chassis"
	chassis.mass = 600.0
	chassis.remove_from_group(&"bricks")

	var wheels: Array = []
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var wheel := Suspension.hang(chassis, Vector3(sx * 0.9, -0.35, sz * 1.0),
				0.35, 0.25, 150.0, materials, palette)
			if wheel != null:
				wheels.append(wheel)
	return { "chassis": chassis, "wheels": wheels }


func _stage(t: TestContext) -> Node3D:
	var stage := Node3D.new()
	t.host.add_child(stage)
	var pad := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	pad.add_child(shape)
	pad.position = Vector3(0.0, -0.5, 0.0)
	stage.add_child(pad)
	return stage
