extends TestCase
## A wheel on a real spring. C6, RIG-SPEC §3 and §7, BUILD-ORDER C6.
##
## The first **physical** constraint in the build. Everything articulated before this — every joint
## in every rig, the soldier, the horse — has been kinematic, driven by code that sets a transform.
## RIG-SPEC's own table is what says this one is different:
##
##     | Hands on a wheel / controls | kinematic (IK) |
##     | Vehicle suspension travel   | physical (spring) |
##
## And the order matters as much as the mechanism. BUILD-ORDER: *"Spring suspension and honest mass
## distribution come first and the handling model is tuned on top of them, rather than the other way
## round."* A handling model tuned first and given springs afterwards is one that fights its own
## suspension — which is what the old build had, and why C6's done-condition makes Marissa's
## handling sign-off a named gate rather than a checkbox.
##
## So this tests the spring **before there is any handling at all**: does a vehicle rest at the ride
## height its own mass implies, and does the wheel actually travel when the ground moves? Those are
## the two things everything after this is tuned on top of.

const EPSILON := 0.0001


func case_name() -> String:
	return "suspension"


func run(t: TestContext) -> void:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	if not (palette.load_core() and materials.load_core(palette)):
		t.fail("core materials would not load, so nothing below means anything")
		return

	_the_rate_comes_off_the_load(t)
	await _it_rests_at_ride_height(t, materials, palette)
	await _and_the_wheel_travels_when_the_ground_does(t, materials, palette)


## The spring rate is derived rather than authored, and that is the whole of "honest mass
## distribution comes first". A number picked by hand means every vehicle of a different mass rides
## differently for no reason a pack author could have predicted.
func _the_rate_comes_off_the_load(t: TestContext) -> void:
	var light := Suspension.stiffness_for(100.0)
	var heavy := Suspension.stiffness_for(400.0)
	t.near(heavy / light, 4.0, 0.01,
		"four times the load is four times the spring rate — the rate is derived, not chosen")

	# The promise the derivation makes: a corner settles at about a third of its travel.
	var carries := 250.0
	var sag := carries * Ballistics.GRAVITY / Suspension.stiffness_for(carries)
	t.near(sag, Suspension.rest_travel(), 0.001,
		"and a laden corner sags to %.3f m, which is a third of its %.2f m of travel" % [
			sag, Suspension.TRAVEL_UP])

	# Damping scales with the spring, or a heavy vehicle wallows and a light one is dead.
	t.ok(Suspension.damping_for(400.0) > Suspension.damping_for(100.0),
		"damping rises with the rate rather than being a constant")
	t.ok(Suspension.DAMPING_RATIO < 1.0, "and stays under critical, so a bump is soaked not deadened")


## The first thing to check about a suspension is not that it moves — it is that it holds the
## vehicle up at all, and at a height nobody typed in.
func _it_rests_at_ride_height(t: TestContext, materials: MaterialSet, palette: Palette) -> void:
	var stage := _stage(t)
	var made := _cart(stage, Vector3(0, 1.2, 0), materials, palette)
	var chassis: RigidBody3D = made["chassis"]
	await t.ticks(180)

	t.ok(chassis.global_position.y > 0.35,
		"the cart is held up off the ground at %.2f m rather than lying on its belly" % [
			chassis.global_position.y])
	t.ok(chassis.global_position.y < 1.2,
		"and has settled down onto its springs rather than hanging where it was spawned")
	t.ok(absf(chassis.global_rotation.x) < 0.25 and absf(chassis.global_rotation.z) < 0.25,
		"sitting level rather than nose-down on a corner that collapsed")

	# Four wheels is four physical constraints — the first real number RIG-SPEC §2's per-object
	# budget of 20 has ever had to measure, and the reason the validator's rule was dormant.
	t.eq((made["wheels"] as Array).size(), 4, "on four wheels")
	t.ok((made["wheels"] as Array).size() <= 20,
		"which is four physical constraints against RIG-SPEC §2's budget of 20")

	stage.queue_free()


## And the thing the done-condition actually names: **visible suspension travel**.
func _and_the_wheel_travels_when_the_ground_does(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	var stage := _stage(t)
	var made := _cart(stage, Vector3(0, 1.2, 0), materials, palette)
	var chassis: RigidBody3D = made["chassis"]
	var wheels: Array = made["wheels"]
	await t.ticks(180)

	var settled: Array[float] = []
	for wheel in wheels:
		settled.append(_travel_of(chassis, wheel as Node3D))

	# Drop a kerb under one corner and watch that corner alone move.
	var kerb := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.5, 1.2)
	shape.shape = box
	kerb.add_child(shape)
	kerb.position = Vector3(0.7, 0.25, 0.9)
	stage.add_child(kerb)

	# Wake everything. **A sleeping body does not react to ground that appears under it** — the same
	# lesson C5 learned about ground being taken away, arriving from the opposite direction. Without
	# this the cart sat at exactly the same height before and after the kerb, and the suspension
	# looked welded when it had simply never been asked a question.
	chassis.sleeping = false
	for wheel in wheels:
		(wheel as RigidBody3D).sleeping = false
	await t.ticks(120)

	var moved := 0.0
	for i in wheels.size():
		moved = maxf(moved, absf(_travel_of(chassis, wheels[i] as Node3D) - settled[i]))
	t.ok(moved > 0.02,
		"a wheel travels %.3f m when the ground under it changes — which is the clause" % moved)
	t.ok(moved <= Suspension.TRAVEL_UP + Suspension.TRAVEL_DOWN + 0.02,
		"and stays inside its limits rather than pulling out of the arch")

	t.ok(chassis.global_position.y > 0.35, "with the cart still up on its springs afterwards")

	# Two corners compress while two extend, which is the difference between a suspension and a lift:
	# the chassis rides the average rather than following the highest wheel.
	var up := 0
	var down := 0
	for i in wheels.size():
		var shift := _travel_of(chassis, wheels[i] as Node3D) - settled[i]
		if shift > 0.01:
			up += 1
		elif shift < -0.01:
			down += 1
	t.ok(up > 0 and down > 0,
		"%d corner(s) compressed and %d drooped — the chassis rides the average" % [up, down])

	stage.queue_free()


## How far a wheel is from where it hangs, along the chassis's own up.
func _travel_of(chassis: RigidBody3D, wheel: Node3D) -> float:
	return (chassis.global_transform.affine_inverse() * wheel.global_position).y


## A four-wheeled chassis. Built here rather than authored as an asset because C6's vehicle *format*
## is not built yet — this is the spring being tested, not the content pipeline, and pretending
## otherwise would mean authoring a vehicle against a system nobody has written.
func _cart(into: Node3D, at: Vector3, materials: MaterialSet, palette: Palette) -> Dictionary:
	var chassis := Brick.spawn(into, at, Basis.IDENTITY, Vector3(1.6, 0.4, 2.6),
		&"timber", Vector3.ZERO, materials, palette)
	chassis.name = "chassis"
	chassis.mass = 600.0
	chassis.remove_from_group(&"bricks")

	var wheels: Array = []
	var corner := 600.0 / 4.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wheel := Suspension.hang(chassis, Vector3(sx * 0.9, -0.35, sz * 1.0),
				0.35, 0.25, corner, materials, palette)
			if wheel != null:
				wheels.append(wheel)
	return { "chassis": chassis, "wheels": wheels }


func _stage(t: TestContext) -> Node3D:
	var stage := Node3D.new()
	t.host.add_child(stage)
	var pad := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	pad.add_child(shape)
	pad.position = Vector3(0.0, -0.5, 0.0)
	stage.add_child(pad)
	return stage
