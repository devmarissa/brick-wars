extends TestCase
## `core:soldier` walking, sprinting and jumping over `TestGround`. BUILD-ORDER C2's
## done-condition, as a test rather than as a screenshot.
##
## Everything below this runs against the real physics world, which is unlike every other rig case
## in the suite and is the point. `case_driver.gd` and `case_body.gd` measure the driver against
## `TestGround.height_at` as a pure function, with no world, no body and no frame having ticked —
## which is how they can assert exact numbers. This one adds gravity, a `CharacterBody3D`, a
## trimesh collider and `move_and_slide`, and asks a different question: when all of that is in
## the way, does the creature still end up standing on the ground.
##
## So the assertions here are about *behaviour under physics*, and they are deliberately loose
## where physics is involved and tight where it is not. A settled walker's feet must be on the
## surface to the millimetre, because that is planting and planting is arithmetic. Its speed after
## half a second of walking is within a few percent, because that is acceleration against a
## slope. Asserting the second as tightly as the first is how a suite becomes something people
## re-run until it passes.
##
## The one thing this case is not is a feel test. Whether 2.2 m/s is the right walk is a question
## for somebody holding a key down, and it is on the checklist as such.

const SHIPPED := "res://packs"

## Long enough for `ACCELERATION` to have done its work — full walk speed takes about a tenth of
## a second, and this is half of one.
const SETTLE := 30


func case_name() -> String:
	return "walker"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(SHIPPED)
	if world.is_empty():
		t.fail("the shipped packs would not load, so nothing below means anything")
		return
	var soldier := FixtureWorld.asset(world, "core:soldier")
	if soldier == null:
		t.fail("core:soldier did not resolve — see the validator's complaints above")
		return

	await _built_right(t, world, soldier)
	await _stands_on_the_ground(t, world, soldier)
	await _walks_and_sprints(t, world, soldier)
	await _jumps(t, world, soldier)
	await _climbs(t, world, soldier)
	await _the_horse_walks_too(t, world)
	_a_collider_that_stops_short_is_refused_in_words(t)


## What a walker is before it has moved: a rig, its legs, and its own declared collision — not a
## collider per bone. RIG-SPEC §3 spends a paragraph on that and this is the line holding it.
func _built_right(t: TestContext, world: Dictionary, soldier: ResolvedAsset) -> void:
	var walker := Walker.of(soldier, world["materials"], world["palette"])
	t.ok(walker.rig != null, "a soldier makes a walker with a rig")
	t.ok(walker.warnings.is_empty(),
		"and no complaints on the way: " + "\n".join(walker.warnings))
	t.eq(walker.locomotion.legs.size(), 2, "with two legs the driver resolved")
	t.eq(walker.locomotion.type, "legged", "and a legged locomotion type")

	var shapes := 0
	var bodies := 0
	for child in walker.get_children():
		if child is CollisionShape3D:
			shapes += 1
		if child is RigidBody3D:
			bodies += 1
	t.eq(shapes, 2, "carrying the two collision boxes its file declares, not one per bone")
	t.eq(bodies, 0, "and no rigid body — a character is moved by its controller, not by physics")
	walker.queue_free()


## Dropped onto flat ground and left alone. The feet have to end up *on* the surface, and the
## body has to end up where the feet say — which is the whole chain from a JSON file to a pose.
func _stands_on_the_ground(t: TestContext, world: Dictionary, soldier: ResolvedAsset) -> void:
	var walker := await _spawn(t, world, soldier, Vector3(0.0, 0.4, 0.0))
	t.near(walker.global_position.y, 0.0, 0.02,
		"a soldier dropped on the flat settles at the surface: %.3f" % walker.global_position.y)
	t.ok(not walker.last.is_empty(), "and the driver ran: " + walker.report())
	if walker.last.is_empty():
		return
	t.eq(String(walker.last["gait"]), "walk", "holding its slowest gait while standing still")
	t.ok(not bool(walker.last["unsupported"]), "and is not standing on nothing")

	# Each foot on the surface under it, to the millimetre. This is the assertion the whole
	# milestone is for — and it is measured against the analytic ground rather than against the
	# raycast the walker itself used, so the two have to agree.
	for leg in walker.locomotion.legs:
		var at: Vector3 = leg.plant["position"]
		t.near(at.y, TestGround.height_at(at.x, at.z), 0.002,
			"a planted foot is on the surface at (%.2f, %.2f)" % [at.x, at.z])
	walker.queue_free()


## Walk, then sprint. The speeds are the controller's; which gait comes out of them is the
## soldier's gait table, and the two have to agree or a sprinting creature walks its legs.
func _walks_and_sprints(t: TestContext, world: Dictionary, soldier: ResolvedAsset) -> void:
	var walker := await _spawn(t, world, soldier, Vector3(0.0, 0.2, 6.0))
	var from := walker.global_position

	walker.wish = Vector2(0.0, -1.0)
	await t.ticks(SETTLE)
	var speed := Vector3(walker.velocity.x, 0.0, walker.velocity.z).length()
	t.near(speed, Walker.WALK_SPEED, 0.3, "walking reaches walking speed: %.2f m/s" % speed)
	t.ok(walker.global_position.z < from.z - 0.5, "and gets somewhere: " + walker.report())
	t.eq(String(walker.last["gait"]), "walk", "at a gait its own file calls a walk")
	t.ok(walker.locomotion.phase > 0.0, "with a cycle that has advanced")

	walker.sprinting = true
	await t.ticks(SETTLE)
	speed = Vector3(walker.velocity.x, 0.0, walker.velocity.z).length()
	t.near(speed, Walker.SPRINT_SPEED, 0.4, "sprinting reaches sprinting speed: %.2f m/s" % speed)
	t.eq(String(walker.last["gait"]), "sprint", "and the gait table hands over to `sprint`")

	# Feet still on the ground while moving, which is the failure planting exists to prevent:
	# a creature at speed whose feet are a few centimetres into the surface looks fine in a
	# screenshot and wrong in motion.
	for leg in walker.locomotion.legs:
		if not bool(leg.plant["planted"]):
			continue
		var at: Vector3 = leg.plant["position"]
		t.near(at.y, TestGround.height_at(at.x, at.z), 0.002,
			"a foot planted at sprint is still on the surface")
	walker.queue_free()


## Up, and back down. Jumping is the one verb here that is purely the body's — the driver has no
## say in it — so what is being checked is that the two do not fight: the rig must come with the
## body rather than staying behind on the ground.
func _jumps(t: TestContext, world: Dictionary, soldier: ResolvedAsset) -> void:
	var walker := await _spawn(t, world, soldier, Vector3(0.0, 0.2, 0.0))
	var standing := walker.global_position.y

	walker.jump_wanted = true
	await t.ticks(8)
	t.ok(walker.global_position.y > standing + 0.3,
		"a jump leaves the ground: %.2f m up" % (walker.global_position.y - standing))
	t.ok(walker.velocity.y != 0.0, "with vertical velocity, which standing never has")
	# The rig is a child of the body, so it rises with it by construction — what could go wrong
	# is the driver pinning it back down to the ground it can still see below.
	t.ok(walker.rig.root.global_position.y > standing + 0.2,
		"and the creature's meshes come up with it rather than staying on the ground")

	await t.ticks(60)
	t.near(walker.global_position.y, standing, 0.02,
		"and it lands back where it started: %.3f" % walker.global_position.y)
	t.ok(walker.is_on_floor(), "on the floor again")
	walker.queue_free()


## The done-condition's "over uneven ground". The ramp rises a quarter, so walking up it the
## creature has to gain height — and its feet have to stay on a surface that is no longer level.
func _climbs(t: TestContext, world: Dictionary, soldier: ResolvedAsset) -> void:
	var walker := await _spawn(t, world, soldier, Vector3(1.5, 0.2, 0.0))
	var from := walker.global_position.y

	walker.wish = Vector2(1.0, 0.0)
	await t.ticks(90)
	t.ok(walker.global_position.y > from + 0.2,
		"walking up the ramp gains height: %.2f m" % (walker.global_position.y - from))
	t.near(walker.global_position.y, TestGround.height_at(walker.global_position.x, 0.0), 0.06,
		"and it is standing on the ramp rather than above or inside it")

	var tilt := rad_to_deg(walker.rig.root.basis.y.angle_to(Vector3.UP))
	t.ok(tilt > 0.2, "with the body tilted onto the slope: %.2f degrees" % tilt)
	t.ok(tilt < 14.04, "part of the way, not all of it — `body_pitch` is 0.08, not 1")

	# Turning banks the creature, and this line pins more than it looks like it does. The lean is
	# computed from the yaw *rate*, which only exists once the body has been moved — so the two
	# halves of `_physics_process` have to run in that order, and a version that posed the rig
	# first would have no rate to lean by. `case_body.gd` tests the lean against the driver
	# directly; this tests that the controller actually wires it through.
	walker.wish = Vector2(0.0, -1.0)
	await t.ticks(20)
	var banked := 0.0
	for i in 30:
		walker.wish = Vector2(1.0, -0.3).normalized()
		await t.ticks(1)
		banked = maxf(banked, rad_to_deg(walker.rig.root.basis.x.angle_to(Vector3.RIGHT)))
	t.ok(banked > 0.5, "and turning hard banks it into the turn: %.2f degrees" % banked)
	t.ok(banked <= Locomotion.MAX_LEAN + 0.001, "no further than MAX_LEAN")
	walker.queue_free()


## C2's other done-condition clause: *a four-legged test creature walks using the same system*.
##
## "The same system" is the whole claim, and it is why this section is in this file rather than in
## a horse-shaped one of its own. `testpack:horse` goes through the identical `Walker`, the
## identical `Locomotion`, the identical `Footing` — and it comes out of a *non-core pack*, which
## is the part RIG-SPEC §5 is actually arguing for: `legged` sits in the locomotion type list
## beside `wheeled` so that a rideable animal is something a modder writes rather than something
## core has to grow a system for. If that were false, this section would need core changes to
## pass. It needs none.
func _the_horse_walks_too(t: TestContext, world: Dictionary) -> void:
	var horse := FixtureWorld.asset(world, "testpack:horse")
	t.ok(horse != null, "TESTPACK's horse resolved — a non-core pack adding a walking creature")
	if horse == null:
		return

	var walker := await _spawn(t, world, horse, Vector3(-2.0, 0.3, 6.0))
	t.ok(walker.warnings.is_empty(), "it builds without complaint: " + "\n".join(walker.warnings))
	t.eq(walker.locomotion.legs.size(), 4, "with four legs, through the same driver as the soldier")

	# The sentence RIG-SPEC §4 spends a paragraph on, now on shipped pack content rather than on a
	# fixture: a knee and a hock are one function reading two rest poses, with no field between
	# them. `case_leg.gd` asserts it against numbers authored to be checked by hand; this asserts
	# it against an animal somebody actually authored.
	t.ok(walker.locomotion.legs[0].bend.z < 0.0, "its forelegs bend forward, like knees")
	t.ok(walker.locomotion.legs[2].bend.z > 0.0, "and its hind legs backward, like hocks")

	# Measured against the surface rather than against zero: the horse stands past `TestGround`'s
	# lip, where the ground genuinely is 0.4 m up, and an assertion of 0 there would be testing
	# the map rather than the creature.
	var under := TestGround.height_at(walker.global_position.x, walker.global_position.z)
	t.near(walker.global_position.y, under, 0.05,
		"it settles on the ground rather than into it: %.3f on ground at %.3f" % [
			walker.global_position.y, under])
	for leg in walker.locomotion.legs:
		var at: Vector3 = leg.plant["position"]
		t.near(at.y, TestGround.height_at(at.x, at.z), 0.002,
			"and each of its four feet is on the surface")

	var from := walker.global_position
	walker.wish = Vector2(0.0, -1.0)
	await t.ticks(SETTLE)
	t.ok(walker.global_position.z < from.z - 0.5, "it walks: " + walker.report())
	t.eq(String(walker.last["gait"]), "walk", "at a four-beat walk")

	# Its own gait table hands over at 2.2, below the soldier's 2.6 — a horse trots where a
	# soldier is still walking, which is the point of the table being the pack's rather than
	# core's.
	walker.sprinting = true
	await t.ticks(SETTLE)
	t.eq(String(walker.last["gait"]), "trot", "and trots when the controller asks for more speed")
	walker.queue_free()


## The guard that stops the worst failure in this file from being silent, and the fixture that
## proves it still fires. `core:sunken` is legal content — a collider is one to four hand-fitted
## boxes and the format says nothing about where they reach — whose one box stops a metre above its
## soles. That settles the creature into the ground and then asks every foot to reach *upward* for
## a surface above its own ideal position, which it cannot do.
##
## This section exists because the guard had nothing that tripped it. `testpack:horse` taught the
## lesson and then the horse was fixed, so the triggering condition stopped existing anywhere in
## the repo — and a check nobody has ever seen fire is a check nobody knows still works. It is the
## same standard the driver's policy lines are held to.
func _a_collider_that_stops_short_is_refused_in_words(t: TestContext) -> void:
	var world := FixtureWorld.load_root("res://tests/fixtures/rig")
	var sunken := FixtureWorld.asset(world, "core:sunken")
	t.ok(sunken != null, "the fixture is valid content — this is not a validation failure")
	if sunken == null:
		return

	var walker := Walker.of(sunken, world["materials"], world["palette"])
	var said := "\n".join(walker.warnings)
	t.ok(said.contains("above its origin"), "and a walker built from it complains: " + said)
	t.ok(said.contains("settle") and said.contains("feet will not reach"),
		"naming both halves of what will go wrong, since neither points at a collider on its own")
	t.ok(walker.locomotion.legs.size() == 2,
		"while still building — it is a warning, because the creature is legal and merely wrong")
	walker.queue_free()

	# And the shipped pair do not trip it, which is what makes the assertion above mean something
	# rather than being a guard that fires on everything.
	var shipped := FixtureWorld.load_root(SHIPPED)
	for id in ["core:soldier", "testpack:horse"]:
		var asset := FixtureWorld.asset(shipped, id)
		if asset == null:
			continue
		var fine := Walker.of(asset, shipped["materials"], shipped["palette"])
		t.ok(fine.warnings.is_empty(), "%s does not trip it: %s" % [id, "\n".join(fine.warnings)])
		fine.queue_free()


## A walker and the ground under it, settled. The ground goes in first: a creature that spawns
## before there is anything to stand on spends its first frames in free fall and its first
## `plant` calls finding nothing, which is a different test than any of these mean to be.
func _spawn(t: TestContext, world: Dictionary, soldier: ResolvedAsset,
		at: Vector3) -> Walker:
	var ground := TestGround.make()
	t.host.add_child(ground)
	var walker := Walker.of(soldier, world["materials"], world["palette"])
	walker.position = at
	t.host.add_child(walker)
	await t.ticks(SETTLE)
	return walker
