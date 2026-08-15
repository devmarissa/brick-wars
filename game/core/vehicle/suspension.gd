class_name Suspension
extends RefCounted
## A wheel on a spring. RIG-SPEC §3 and §7, BUILD-ORDER C6, C6.
##
## The first **physical** constraint in the whole build, and that is worth stating plainly because
## everything articulated up to now has been kinematic. RIG-SPEC's own table says which is which:
##
##     | Hands on a wheel / controls | kinematic (IK) |
##     | Vehicle suspension travel   | physical (spring) |
##
## And BUILD-ORDER is specific about the order: *"Spring suspension and honest mass distribution
## come first and the handling model is tuned on top of them, rather than the other way round."*
## That sentence is the whole design. A handling model tuned first and given suspension afterwards
## is a handling model that fights its own springs, and the old build never got past it — which is
## why C6's done-condition names your sign-off on handling feel as a gate rather than a checkbox.
##
## ### A real joint, not a raycast
##
## The common shortcut is to cast a ray down from each wheel and push the chassis up by a
## spring-damper. It is stable, it is cheap, and it is what Godot's own `VehicleBody3D` does. It is
## also not what the spec asks for, and the difference is not academic: a raycast wheel cannot be
## torn off, cannot jam, cannot be bent by a shell, and has no mass of its own to throw the vehicle
## about when it drops into a crater. In a game whose entire premise is that the ground changes
## shape under you, those are the interesting cases rather than the edge cases.
##
## So a wheel is a real body held to the chassis by a `Generic6DOFJoint3D` with a linear spring on
## its travel axis: free to move up and down within limits, locked everywhere else, spinning on its
## own axis. `DEVIATIONS-C6.md` records the cost — it is more expensive and more delicate than a
## raycast, and if it does not survive contact with forty vehicles that is the deviation to revisit.
##
## ### The constraint budget starts counting here
##
## RIG-SPEC §2 sets a per-object budget of 20 physical constraints, and the validator has carried a
## dormant rule saying *"nothing counts it because there is not a physical constraint anywhere in
## the build"*. There is now: four wheels is four joints, which is the first real number that rule
## has ever had to measure.

## Travel, in metres: how far a wheel may move from where it hangs. Up is compression.
const TRAVEL_UP := 0.28
const TRAVEL_DOWN := 0.12

## Spring stiffness in newtons per metre, and damping in newton-seconds per metre.
##
## Stiffness is derived rather than chosen: a spring should sit at about a third of its travel under
## the weight it carries, so `k = mass * gravity / (TRAVEL_UP / 3)`. Picking a number instead means
## every vehicle of a different mass rides differently for no reason a pack author could have
## predicted, which is exactly the sort of thing BUILD-ORDER means by tuning handling on top of
## honest mass distribution rather than under it.
const REST_FRACTION := 3.0

## Damping as a fraction of critical. 0.35 is soft enough to soak a crater lip and firm enough not
## to wallow — a vehicle that oscillates after every bump reads as a toy.
const DAMPING_RATIO := 0.35

## What a wheel is made of. `timber` because the eras this game spans run from siege engines to
## lorries and a spoked wooden wheel covers most of them — and because there is no `rubber` in the
## palette, which is a gap a pneumatic-tyred era would have to fill rather than something to fake
## here with a material that means something else.
const WHEEL_MATERIAL := &"timber"

## What a wheel weighs relative to the chassis, per wheel. Wheels have to be light enough that the
## chassis dominates the handling and heavy enough that dropping into a hole throws the vehicle
## about, which is the behaviour a raycast cannot produce at all.
const WHEEL_MASS_FRACTION := 0.04


## Hang a wheel off a chassis. Returns the wheel body, already jointed.
##
## `at` is where the wheel sits in the chassis's own space, `radius` and `width` are its shape, and
## `carries` is the share of the vehicle's mass this corner holds — which is what sets the spring
## rate, so a laden lorry rides lower than an empty one without anybody authoring two springs.
static func hang(chassis: RigidBody3D, at: Vector3, radius: float, width: float,
		carries: float, materials: MaterialSet, palette: Palette) -> RigidBody3D:
	if chassis == null or chassis.get_parent() == null:
		return null

	var wheel := Brick.spawn(chassis.get_parent(),
		chassis.global_transform * at, chassis.global_basis,
		Vector3(width, radius * 2.0, radius * 2.0), WHEEL_MATERIAL, Vector3.ZERO, materials, palette)
	if wheel == null:
		return null
	wheel.name = "wheel"
	_make_it_round(wheel, radius, width)
	wheel.mass = maxf(Brick.MIN_MASS, chassis.mass * WHEEL_MASS_FRACTION)
	# A wheel is not rubble: it must not be culled, put to sleep by the debris sweep, or counted as
	# something a blast should launch on its own. Taking it out of the group is the cheapest way to
	# say that, and the group is the only thing that made it debris in the first place.
	wheel.remove_from_group(&"bricks")

	var joint := Generic6DOFJoint3D.new()
	joint.name = "suspension"
	chassis.get_parent().add_child(joint)
	joint.global_transform = Transform3D(chassis.global_basis, wheel.global_position)
	joint.node_a = chassis.get_path()
	joint.node_b = wheel.get_path()

	_lock_except_travel_and_spin(joint)
	_spring(joint, carries)
	return wheel


## Give the wheel a cylinder instead of the box `Brick.spawn` makes, with its axis along the axle.
##
## This is not cosmetic, and it was not obvious. A box wheel with the brick friction of 0.8 does not
## roll — it *drags*, and four of them are four brake pads. A 3000 N·s impulse on a 600 kg chassis
## produced 0.1 m/s and half a metre of travel, which looks like a broken drive model and is
## actually a vehicle sitting on its own skids. A wheel has to be round for the same reason it is
## round in life.
static func _make_it_round(wheel: RigidBody3D, radius: float, width: float) -> void:
	for child in wheel.get_children():
		if child is CollisionShape3D:
			var barrel := CylinderShape3D.new()
			barrel.radius = radius
			barrel.height = width
			(child as CollisionShape3D).shape = barrel
			# Godot's cylinder stands on its end; a wheel lies on its side, so the axle runs along
			# the chassis's X and the wheel turns about it.
			(child as CollisionShape3D).rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
		elif child is MeshInstance3D:
			var mesh := CylinderMesh.new()
			mesh.top_radius = radius
			mesh.bottom_radius = radius
			mesh.height = width
			(child as MeshInstance3D).mesh = mesh
			(child as MeshInstance3D).rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))


## Everything locked but the two things a wheel is allowed to do: move along its travel axis, and
## spin about its axle. A joint that leaves anything else free is a wheel that walks sideways out of
## its arch, which looks like a physics bug and is a missing limit.
static func _lock_except_travel_and_spin(joint: Generic6DOFJoint3D) -> void:
	# Every linear axis limited. The first version of this looped over the three axes and then set
	# `set_flag_x` inside the loop — so X was enabled three times and Y and Z never were, which in
	# Godot means *unlimited* rather than locked. The wheel came out welded to the chassis and
	# travelled exactly 0.000 m, which is how the test found it.
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)

	# Sideways and fore-aft: nailed. A wheel that can move in either is a wheel that walks out of
	# its arch, which reads as a physics bug and is a missing limit.
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Travel: the one axis that moves. Down is negative, compression positive.
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -TRAVEL_DOWN)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, TRAVEL_UP)

	# Angular: free about the axle, locked in the other two, or the wheel steers itself.
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	for param in [Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
			Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
		joint.set_param_y(param, 0.0)
		joint.set_param_z(param, 0.0)


## The spring itself, rated for the load this corner carries.
static func _spring(joint: Generic6DOFJoint3D, carries: float) -> void:
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, stiffness_for(carries))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, damping_for(carries))
	# Equilibrium at full droop, so the spring's only job is to resist compression. The vehicle's own
	# weight is what pulls it down to ride height, which is the honest way round and is exactly why
	# the rate has to be derived from the load rather than typed in.
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_EQUILIBRIUM_POINT, -TRAVEL_DOWN)


## Newtons per metre for a corner carrying `carries` kilograms, so that it settles at a third of its
## travel. Derived rather than authored — see `REST_FRACTION`.
static func stiffness_for(carries: float) -> float:
	return maxf(1.0, carries * Ballistics.GRAVITY / (TRAVEL_UP / REST_FRACTION))


## Damping for the same corner, as a fraction of critical: `2 * ratio * sqrt(k * m)`.
static func damping_for(carries: float) -> float:
	return 2.0 * DAMPING_RATIO * sqrt(stiffness_for(carries) * maxf(carries, 0.001))


## Where a corner should sit at rest, as a fraction of travel from full extension. The number the
## test measures against, and the thing `REST_FRACTION` promises.
static func rest_travel() -> float:
	return TRAVEL_UP / REST_FRACTION
