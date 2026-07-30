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
	walker.queue_free()


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
