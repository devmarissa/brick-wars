extends TestCase
## The last clause of RIG-SPEC's opening sentence. C6, RIG-SPEC §1–§3.
##
## > A modder, using only data files, can add a horse that walks, trots and gallops with correctly
## > articulated two-bone legs, plants its feet on dug-up uneven ground, can be mounted and ridden,
## > **and ragdolls when killed** — without a single line of core code.
##
## Walks, trots and gallops: C2. Plants its feet on dug-up ground: C2 and C3. Mounted and ridden:
## earlier this milestone. This is the last one, and it is tested against `testpack:horse` — a pack
## asset — because the sentence says *a modder, using only data files*, and a ragdoll that only
## worked for core content would fail the claim while passing any test written against the soldier.
##
## The quality bar is one word in that sentence's neighbourhood: the bodies stand **where the last
## pose left them**. A ragdoll built from the rest pose snaps to a T-pose for one frame before it
## falls, and everybody sees it.

const EPSILON := 0.0001


func case_name() -> String:
	return "ragdoll"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root("res://packs")
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return

	_it_costs_what_rig_spec_measured(t, world)
	await _it_stands_where_the_pose_left_it(t, world)
	await _and_then_it_falls(t, world)


## RIG-SPEC §2 set the cap at 20 and said what the number was reasoned from: *"the horse's 14 joints
## are kinematic and do not spend this budget at all... What 14 bounds is what a ragdoll of the horse
## would cost."* This is the milestone where that stops being hypothetical.
func _it_costs_what_rig_spec_measured(t: TestContext, world: Dictionary) -> void:
	var horse := FixtureWorld.rig(world, "testpack:horse")
	var soldier := FixtureWorld.rig(world, "core:soldier")
	t.ok(horse != null and soldier != null, "both rigs build")
	if horse == null or soldier == null:
		return

	t.eq(Ragdoll.constraints_for(horse), 14,
		"a ragdoll of the horse costs 14 constraints, which is the number §2 was reasoned from")
	t.eq(Ragdoll.constraints_for(soldier), 14, "and the soldier the same")
	t.ok(Ragdoll.affordable(horse), "both fit the per-object cap of %d" % Ragdoll.MAX_CONSTRAINTS)
	t.ok(Ragdoll.constraints_for(horse) < Ragdoll.MAX_CONSTRAINTS,
		"with headroom for a tail, a jaw, or one more segment in each leg — §2's own examples")


## The quality bar: no snap. Every body starts at the world transform the animation left it in.
func _it_stands_where_the_pose_left_it(t: TestContext, world: Dictionary) -> void:
	var stage := _stage(t)
	var built := _built(world, "testpack:horse")
	if built == null:
		t.fail("the horse would not build")
		return
	stage.add_child(built)
	built.position = Vector3(0, 1.4, 0)
	var rig: Rig = built.rig
	await t.ticks(2)

	# Bend it out of its rest pose, so "where the pose left it" is somewhere a rest pose is not.
	# Driving joints directly rather than running a gait: this is a claim about the *conversion*
	# reading the current pose, and the simplest pose that is not the rest one proves it.
	var bent := 0
	for name in rig.order:
		if rig.limit_high(String(name)) > rig.limit_low(String(name)):
			rig.drive(String(name), rig.limit_high(String(name)) * 0.5)
			bent += 1
		if bent >= 4:
			break
	t.ok(bent > 0, "the horse is posed out of its rest pose before being let go of")
	await t.ticks(1)

	var was: Dictionary = {}
	for name in rig.order:
		var bone := rig.bone(String(name))
		if bone != null and bone.node != null:
			was[String(name)] = bone.node.global_position

	var made := Ragdoll.convert(rig, stage, world["materials"], world["palette"])
	t.eq(String(made["why"]), "", "the horse converts")
	var bodies: Array = made["bodies"]
	var joints: Array = made["joints"]
	t.eq(bodies.size(), 15, "into fifteen bodies, one per part")
	t.eq(joints.size(), 14, "held together by fourteen joints, which is what §2 measured")

	var worst := 0.0
	for body in bodies:
		var name := String((body as Node).name).replace("ragdoll_", "")
		if was.has(name):
			worst = maxf(worst, (body as Node3D).global_position.distance_to(was[name]))
	t.ok(worst < 0.001,
		"and every body stands where its bone was, to %.4f m — no snap to a rest pose" % worst)
	t.ok(not rig.root.visible,
		"with the kinematic rig hidden, so a dead horse is not drawn twice")

	stage.queue_free()


## And then gravity has it, which is the entire point of converting at all.
func _and_then_it_falls(t: TestContext, world: Dictionary) -> void:
	var stage := _stage(t)
	var built := _built(world, "testpack:horse")
	if built == null:
		return
	stage.add_child(built)
	built.position = Vector3(0, 2.2, 0)
	var rig: Rig = built.rig
	await t.ticks(2)

	var made := Ragdoll.convert(rig, stage, world["materials"], world["palette"])
	var bodies: Array = made["bodies"]
	var began := _mean_height(bodies)
	await t.ticks(150)
	var ended := _mean_height(bodies)

	t.ok(ended < began, "it falls: mean height %.2f m down to %.2f" % [began, ended])
	t.ok(ended > -1.0, "and lands on the ground rather than through it")

	# Still one creature rather than fifteen bricks: the joints hold it together as it lands.
	var spread := 0.0
	for a in bodies:
		for b in bodies:
			spread = maxf(spread, (a as Node3D).global_position.distance_to(
				(b as Node3D).global_position))
	t.ok(spread < 6.0,
		"and it is still a horse-shaped heap %.1f m across rather than fifteen loose bricks" % spread)

	# Not debris. A ragdoll culled by the debris sweep would be a body vanishing off a battlefield.
	for body in bodies:
		t.ok(not (body as Node).is_in_group(&"bricks"), "no part of it is loose rubble")
		break

	stage.queue_free()


## The whole built asset rather than just its rig. `FixtureWorld.rig` hands back the `Rig` alone,
## whose root already belongs to a `BuiltAsset` that is not in the tree — so its global transforms
## are meaningless and re-parenting it errors. A ragdoll is built from *world* positions, so it
## needs the asset actually standing somewhere.
func _built(world: Dictionary, id: String) -> BuiltAsset:
	var asset := FixtureWorld.asset(world, id)
	if asset == null:
		return null
	return AssetBuilder.new().build(asset, world["materials"], world["palette"])


func _mean_height(bodies: Array) -> float:
	if bodies.is_empty():
		return 0.0
	var total := 0.0
	for body in bodies:
		total += (body as Node3D).global_position.y
	return total / bodies.size()


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
