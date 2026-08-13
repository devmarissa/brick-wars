extends TestCase
## The medieval mining loop — C5's acceptance test. MATERIAL-SPEC §6.
##
## §6 calls this *"the acceptance test for materials the way the horse test is for rigs"*, and sets
## it out in six steps:
##
##     1. Dig a tunnel under the wall — chalk, hardness 2, holds a 65° face
##     2. Prop the roof with timber — support_vertical 70 holds the span
##     3. Pack it with brush and light it
##     4. Fire consumes the props: flammability 0.70, on_burnt: charred
##     5. charred_timber has support_vertical 20 — the span exceeds what the props hold
##     6. The tunnel collapses, the ground subsides, the wall above it comes down
##
## The claim being tested is not that this *works* — it is that **no code was written for any of
## it**. Nothing knows what a prop is, what a tunnel is, or that step 5 follows step 4. A burnt prop
## is a brick whose `material_id` changed, and a support calculation that already existed reads the
## new number and gets a different answer than it did a minute ago.
##
## §6: *"That is how mining actually worked, and here it's an emergent consequence of six material
## properties... This is the payoff for building materials into the core instead of the Great War
## pack."* So what each section asserts is the *number* it depended on, not the outcome alone —
## because an outcome anybody could have produced by writing mining code proves nothing.

const EPSILON := 0.0001


func case_name() -> String:
	return "mining loop"


func run(t: TestContext) -> void:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	if not (palette.load_core() and materials.load_core(palette)):
		t.fail("core materials would not load, so nothing below means anything")
		return

	_one_chalk_holds_a_face(t, materials)
	_two_timber_holds_the_span(t, materials)
	await _three_and_four_fire_consumes_the_props(t, materials, palette)
	_five_charred_timber_does_not_hold(t, materials)
	await _six_and_the_wall_above_comes_down(t, materials, palette)


## 1 · Chalk, hardness 2, holds a steep face — which is why you can tunnel in it at all, and why a
## spade cannot. Both numbers were already asserted at C3 and C5; this is the step depending on them.
func _one_chalk_holds_a_face(t: TestContext, materials: MaterialSet) -> void:
	t.eq(int(materials.get_def(&"chalk").get("hardness", 0)), 2,
		"chalk is hardness 2, so a spade is refused by it and a pick is not")
	t.ok(not materials.can_work(&"chalk", 1), "the spade cannot open the gallery")
	t.ok(materials.can_work(&"chalk", 3), "the pick can")
	t.ok(EarthRepose.step_cm(int(materials.get_def(&"chalk").get("angle_of_repose", 0))) >
		EarthRepose.step_cm(int(materials.get_def(&"sand").get("angle_of_repose", 0))),
		"and it stands far steeper than sand, which is what makes a gallery possible")


## 2 · Timber props. `support_vertical` 70 is the number holding the roof up.
func _two_timber_holds_the_span(t: TestContext, materials: MaterialSet) -> void:
	t.eq(int(materials.get_def(&"timber").get("support_vertical", 0)), 70,
		"timber holds a span at 70")
	t.ok(Integrity.cohesion_of(&"timber", materials) > 50.0,
		"and holds together well enough that a gallery is not constantly shedding its roof")


## 3 and 4 · Light it, and let it burn. `flammability` 0.70 and `on_burnt: charred` are §6's own
## figures, and the thing that changes is what the prop is *made of*.
func _three_and_four_fire_consumes_the_props(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	t.near(float(materials.get_def(&"timber").get("flammability", 0.0)), 0.70, EPSILON,
		"timber's flammability is §6's 0.70")
	t.eq(String((materials.get_def(&"timber").get("fire", {}) as Dictionary).get("on_burnt", "")),
		"charred", "and it burns to `charred`")

	var stage := _stage(t)
	var fire := Fire.of(materials, palette)
	stage.add_child(fire)

	var prop := Brick.spawn(stage, Vector3(0, 1.0, 0), Basis.IDENTITY, Vector3(0.3, 2.0, 0.3),
		&"timber", Vector3.ZERO, materials, palette)
	await t.ticks(2)

	t.ok(fire.light(prop), "a timber prop catches")
	t.ok(fire.is_burning(prop), "and is burning")
	t.eq(prop.material_id, &"timber", "still timber while there is fuel in it")

	# Chalk will not catch, which is why the gallery does not burn along with the props.
	var rock := Brick.spawn(stage, Vector3(0.4, 1.0, 0), Basis.IDENTITY, Vector3(0.3, 0.3, 0.3),
		&"chalk", Vector3.ZERO, materials, palette)
	await t.ticks(2)
	t.ok(not fire.light(rock), "chalk will not light — flammability 0, and no flag anywhere says so")

	# Burn it down. 90 fuel at 0.7 a second is a bit over two minutes, run here in a loop.
	for i in 200:
		fire.burn(1.0)
		if prop.material_id != &"timber":
			break

	t.eq(prop.material_id, &"charred_timber", "and when the fuel runs out it is charred timber")
	t.eq(fire.burnt, 1, "which the fire counted")
	t.ok(not fire.is_burning(prop), "and it has stopped burning, having nothing left to burn")
	t.ok(is_instance_valid(rock), "the chalk beside it never caught at all")

	stage.queue_free()


## 5 · The number that does the work. Nothing weakened the prop — it is a different material now,
## and the support calculation reads the new one.
func _five_charred_timber_does_not_hold(t: TestContext, materials: MaterialSet) -> void:
	var whole := int(materials.get_def(&"timber").get("support_vertical", 0))
	var charred := int(materials.get_def(&"charred_timber").get("support_vertical", 0))
	t.eq(charred, 20, "charred timber holds 20 where timber held 70")
	t.ok(charred < whole / 3, "a bit under a third — the span now exceeds what the props hold")

	# And it is looser, so a collapse travels further through it: `Integrity`'s reach is inverse to
	# cohesion, and charring drops cohesion as well as support.
	t.ok(Integrity.reach_for(&"charred_timber", materials) >
		Integrity.reach_for(&"timber", materials),
		"and news of a failure travels further through charred timber than through sound timber")


## 6 · The wall above comes down. This is the only step with any staging in it, and even here the
## only thing the test does is take the props away and tell the ground.
func _six_and_the_wall_above_comes_down(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	var stage := _stage(t)
	# Five props across the span, seated on the floor, and the wall resting *exactly* on top of them.
	# The first version left a 0.3 m gap and dropped the wall onto the props: it never settled, so
	# nothing was ever asleep, so there was nothing for step 6 to wake. The staging was wrong, not
	# the mechanism — but it is the sort of wrong that reads as a broken feature.
	const PROP_TOP := 2.0
	const COURSE := 0.5
	var props: Array = []
	for i in 5:
		props.append(Brick.spawn(stage, Vector3((i - 2) * 0.6, PROP_TOP * 0.5, 0), Basis.IDENTITY,
			Vector3(0.4, PROP_TOP, 0.4), &"timber", Vector3.ZERO, materials, palette))

	var above: Array = []
	for x in 6:
		for y in 3:
			above.append(Brick.spawn(stage,
				Vector3((x - 2.5) * COURSE, PROP_TOP + COURSE * 0.5 + y * COURSE, 0),
				Basis.IDENTITY, Vector3(COURSE, COURSE, COURSE), &"brick_masonry", Vector3.ZERO,
				materials, palette))
	await t.ticks(150)

	var asleep := 0
	for brick in above:
		if (brick as RigidBody3D).sleeping:
			asleep += 1
	t.ok(asleep > above.size() / 2, "the wall over the gallery settles and sleeps")

	var began := 0.0
	for brick in above:
		began += (brick as Node3D).global_position.y
	began /= above.size()

	# Fire the props. Nothing here mentions collapse — the props go, and the ground is told.
	for prop in props:
		(prop as Node).queue_free()
	await t.ticks(4)
	var woken := 0
	for i in 3:
		woken += Integrity.support_removed(t.host.get_tree(),
			Vector3(i * 1.2 - 1.2, 2.0, 0), &"charred_timber", materials)
	t.ok(woken > 0, "burning the props out wakes the %d brick(s) that were resting on them" % woken)

	await t.ticks(150)
	var ended := 0.0
	for brick in above:
		ended += (brick as Node3D).global_position.y
	ended /= above.size()

	t.ok(ended < began - 0.3,
		"and the wall above subsides: mean height %.2f m down to %.2f" % [began, ended])

	stage.queue_free()


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
