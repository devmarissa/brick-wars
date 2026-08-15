class_name Drive
extends RefCounted
## Making a sprung vehicle go where it is pointed. CORE-SPEC §2, FORMAT-SPEC §7, C6.
##
## BUILD-ORDER is unusually specific about the order this had to be built in, and it is the whole
## design of this file:
##
## > Handling is **built here, not ported** (§1b). Spring suspension and honest mass distribution
## > come first and the handling model is tuned on top of them, rather than the other way round.
##
## So force goes in **at the wheels**, where they touch the ground, and the chassis moves because
## its suspension is pushed. Nothing here shoves the chassis directly. The difference sounds
## academic and is not: a model that drives the chassis and lets the wheels follow is a model that
## climbs kerbs it should stop at, corners at the same rate with two wheels off the ground as with
## four, and fights its own springs every time the ground changes — which is exactly the thing the
## old build never got past, and why C6's done-condition makes Marissa's sign-off a named gate.
##
## The consequence worth stating: **a wheel that is not touching anything does nothing.** Drive a
## vehicle off a crater lip and it coasts, because the wheels are in the air and there is nothing to
## push against. Nobody wrote that rule.
##
## ### The three stats, and what each is actually for
##
## `max_speed`, `accel`, `turn_rate` and `grip` come off the asset (FORMAT-SPEC §7's vehicle block).
##
## **`grip`** is the interesting one and the reason a tank and a cart feel different at the same
## speed. It caps how hard a wheel may push *sideways* — so a low-grip vehicle understeers into a
## turn and slides, and a high-grip one bites. It is not a friction coefficient dressed up: the
## sideways force is capped rather than scaled, so a gentle corner is unaffected and a hard one
## breaks away, which is what a grip limit means to a driver.
##
## ### It applies impulses and reports; it does not read input
##
## Same shape as everything else in this build. `apply` takes a throttle and a steer and does the
## physics, and where those two numbers came from — a key, a bot, C8's replay of somebody else's
## drive — is not its business.
##
## **Impulses rather than forces**, and that is a correctness point rather than a preference.
## `apply_central_force` survives only until the next physics step and is therefore sensitive to
## *when* in the frame it was called; a caller driving from outside the physics callback gets its
## force silently discarded. The first version of this used forces, reported four wheels grounded
## and four driving, and moved the cart exactly 0.00 m — everything looked right and nothing
## happened. `impulse = force × delta` is the same physics with none of the timing.

## How far the steered wheels may turn, in radians. About 32°, which is a road vehicle's lock; a
## tracked thing steers by braking one side instead and does not use this at all.
const MAX_STEER := 0.55

## How much of a wheel's drive force may go sideways before it slides, per unit of `grip`. Tuned so
## that `grip` values in the same range as the other stats (a cart 6, a lorry 9, a tank 14) land
## somewhere sensible, rather than making the pack author guess at a Newton figure.
const GRIP_SCALE := 260.0

## Below this speed, in m/s, a vehicle is treated as stopped for the purpose of drag and steering.
## Without it a parked vehicle jitters as the model argues with the springs about a millimetre.
const STOPPED := 0.15

## How hard a vehicle is slowed when nothing is on the throttle, as a fraction of `accel`. Engine
## braking and rolling resistance together; a vehicle that coasts forever reads as ice.
const COAST_DRAG := 0.35


## One step of driving. `throttle` is -1..1 and `steer` is -1..1.
##
## `wheels` is the array `Suspension.hang` returned, and `steered` is how many of them turn — the
## front pair on a cart, none on a tank. Returns what it did, which is what a HUD and a test both
## want and neither should have to work out again.
static func apply(chassis: RigidBody3D, wheels: Array, stats: Dictionary,
		throttle: float, steer: float, delta: float, steered := 2) -> Dictionary:
	if chassis == null or wheels.is_empty():
		return { "driven": 0, "grounded": 0, "speed": 0.0, "slid": false }

	var max_speed := float(stats.get("max_speed", 10.0))
	var accel := float(stats.get("accel", 8.0))
	var grip := float(stats.get("grip", 8.0)) * GRIP_SCALE
	var forward := -chassis.global_basis.z
	var speed := chassis.linear_velocity.dot(forward)

	var grounded := 0
	var driven := 0
	var slid := false

	for i in wheels.size():
		var wheel := wheels[i] as RigidBody3D
		if wheel == null or not _touching(wheel):
			continue
		grounded += 1

		# Which way this wheel points. Only the steered ones turn, and they turn about the chassis's
		# up rather than their own, or a wheel on a slope steers into the hill.
		var heading := forward
		if i < steered and absf(steer) > 0.001:
			heading = forward.rotated(chassis.global_basis.y, -steer * MAX_STEER)

		# Drive. Nothing past the vehicle's own top speed, and the force is shared between however
		# many wheels are actually down — which is why losing contact costs you acceleration.
		if absf(throttle) > 0.001 and absf(speed) < max_speed:
			var push := heading * throttle * accel * chassis.mass / float(wheels.size())
			wheel.apply_central_impulse(push * delta)
			driven += 1
		elif absf(speed) > STOPPED:
			# Coasting: engine braking and rolling resistance, against the direction of travel.
			wheel.apply_central_impulse(-forward * signf(speed) * accel * COAST_DRAG
				* chassis.mass / float(wheels.size()) * delta)

		# Grip. A wheel resists sliding sideways up to a limit and no further, which is what makes a
		# hard corner break away while a gentle one does not.
		var sideways := chassis.global_basis.x
		var slip := wheel.linear_velocity.dot(sideways)
		if absf(slip) > 0.01:
			var resist := -sideways * slip * chassis.mass / float(wheels.size())
			if resist.length() > grip:
				resist = resist.normalized() * grip
				slid = true
			wheel.apply_central_impulse(resist * delta)

	# Yaw. The steered wheels have already pushed the vehicle round; this is the rest of the turn,
	# and it is scaled by how much of the vehicle is actually on the ground — a car on two wheels
	# does not corner like a car on four.
	if grounded > 0 and absf(steer) > 0.001 and absf(speed) > STOPPED:
		var authority := float(grounded) / float(wheels.size())
		var turn := float(stats.get("turn_rate", 2.0)) * -steer * authority \
			* clampf(absf(speed) / maxf(max_speed, 0.001), 0.0, 1.0)
		chassis.angular_velocity = Vector3(chassis.angular_velocity.x,
			lerpf(chassis.angular_velocity.y, turn, clampf(delta * 6.0, 0.0, 1.0)),
			chassis.angular_velocity.z)

	return { "driven": driven, "grounded": grounded, "speed": speed, "slid": slid }


## Whether a wheel has anything under it. Asked of the physics engine rather than tracked, because
## the ground changes shape in this game and anything cached about it is wrong within a shell or two.
static func _touching(wheel: RigidBody3D) -> bool:
	var space := wheel.get_world_3d().direct_space_state if wheel.is_inside_tree() else null
	if space == null:
		return false
	var radius := _radius_of(wheel)
	var found := Projectile.sweep(space, wheel.global_position,
		wheel.global_position - Vector3.UP * (radius + 0.08), [wheel.get_rid()])
	return found["hit"]


static func _radius_of(wheel: RigidBody3D) -> float:
	for child in wheel.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			return ((child as CollisionShape3D).shape as BoxShape3D).size.y * 0.5
	return 0.35
