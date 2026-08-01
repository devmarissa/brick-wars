extends TestCase
## The blast fixture's wall, standing — and nothing hitting it. C5, `BUILD-ORDER` §1e.
##
## This case exists because of the order the fixture has to be rebuilt in, and the order is the
## whole risk of the milestone.
##
## `blast-fixture/` is *the* irreplaceable thing in the old project: a captured record of how the
## blast felt, taken while the old build still ran, because "it felt good" is a specification that
## evaporates. C5's done-condition is that the rebuild reproduces it. But the fixture as captured
## drives the **old** `main.gd` — it calls `main_node.spawn_brick`, reads `main_node.SHATTER_POWER`
## — so reproducing it means two separate jobs, and doing them in the wrong order wastes days:
##
## 1. Stand up the *same scenario* in the rebuild.
## 2. Port the blast so the numbers come out inside tolerance.
##
## If (1) is even slightly wrong — a wall one brick short, a brick of a different size or density,
## a different stacking jitter — then every metric in (2) is measuring the scenario rather than the
## blast, and the impulse constant gets "tuned" to compensate for a wall that was built wrong. That
## is a day lost to a number that was correct all along.
##
## So this proves (1) with **no blast at all**, against the facts in the reference that do not
## depend on one: a wall is 120 bricks, all 120 survive, and left alone it stands still and goes to
## sleep. `scatter.structure_bricks: 120` and `surviving: 120` are in the baseline for both wall and
## pile scenarios and are the cheapest possible check that the scenario matches.
##
## Nothing here asserts anything about a blast, and it should not — there isn't one yet.

## Straight out of `blast-fixture/blast_fixture.gd`, and deliberately duplicated rather than
## imported: the fixture is a *record* and this is a claim about matching it. Two copies that must
## agree is the point — if the fixture is ever re-captured with a different wall, this goes red and
## somebody has to look, which is exactly what should happen.
const WALL_BRICK := Vector3(1.0, 0.5, 0.5)
const WALL_WIDE := 10
const WALL_HIGH := 6
const WALL_DEEP := 2
const WALL_JITTER := 0.04
const PILE_COUNT := 120
const PILE_JITTER := 0.06

## What the reference says a wall and a pile are made of. `sandbag` and `mud` are the rebuild's
## names for the old build's `SBAG` and `MUD`.
const WALL_MATERIAL := &"sandbag"
const PILE_MATERIAL := &"mud"

## The baseline's own figures for both structures.
const STRUCTURE_BRICKS := 120

## Below this a brick counts as stopped, from the fixture's `SETTLE_SPEED`.
const SETTLE_SPEED := 0.30


func case_name() -> String:
	return "fixture wall"


func run(t: TestContext) -> void:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	if not (palette.load_core() and materials.load_core(palette)):
		t.fail("core materials would not load, so nothing below means anything")
		return

	await _a_wall_is_a_hundred_and_twenty_bricks(t, materials, palette)
	await _and_left_alone_it_stands(t, materials, palette)
	_the_same_wall_twice(t, materials, palette)


## The count, and the arithmetic behind it. 10 x 6 x 2 is the fixture's wall and 120 is what the
## baseline records for `structure_bricks` — so if either the loop or the constant drifts, the two
## disagree here rather than in a blast metric three steps later.
func _a_wall_is_a_hundred_and_twenty_bricks(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	t.eq(WALL_WIDE * WALL_HIGH * WALL_DEEP, STRUCTURE_BRICKS,
		"the fixture's wall is ten wide, six high and two deep")

	var stage := _stage(t)
	var made := _wall(stage, Vector3.ZERO, materials, palette)
	await t.ticks(2)

	t.eq(made.size(), STRUCTURE_BRICKS,
		"and building it makes exactly that many bricks: %d" % made.size())
	t.eq(Brick.all(t.host.get_tree()).size(), STRUCTURE_BRICKS,
		"all of which are in the `bricks` group, which is how a blast will find them")

	# Mass matters as much as count. A brick of the right size and the wrong density takes a
	# different impulse from the same push, and every launch-speed metric moves with it.
	var one: Brick = made[0]
	t.ok(one.mass > Brick.MIN_MASS,
		"a sandbag brick weighs %.1f kg, from its material's own density" % one.mass)
	t.near(one.mass, materials.mass_for(WALL_MATERIAL,
		WALL_BRICK.x * WALL_BRICK.y * WALL_BRICK.z), 0.01,
		"which is the density in the material file and not a number in the fixture")
	t.eq(one.material_id, WALL_MATERIAL, "and it knows what it is made of")

	stage.queue_free()


## The claim that makes the whole comparison meaningful: **before a blast, nothing moves.** If the
## wall settles by falling over, `moved_over_half_metre` is already 120 without anything having
## exploded, and the baseline's 120 would be matched for entirely the wrong reason.
func _and_left_alone_it_stands(t: TestContext, materials: MaterialSet, palette: Palette) -> void:
	var stage := _stage(t)
	var made := _wall(stage, Vector3.ZERO, materials, palette)
	var began: Array[Vector3] = []
	for brick in made:
		began.append((brick as Brick).global_position)

	# Long enough for a badly built wall to have collapsed visibly, short enough to stay a test.
	await t.ticks(90)

	var moved := 0
	var furthest := 0.0
	var awake := 0
	var fell := 0
	for i in made.size():
		var brick: Brick = made[i]
		var shift := brick.global_position.distance_to(began[i])
		furthest = maxf(furthest, shift)
		if shift > 0.5:
			moved += 1
		if brick.linear_velocity.length() > SETTLE_SPEED:
			awake += 1
		if brick.global_position.y < -1.0:
			fell += 1

	t.eq(fell, 0, "no brick fell out of the world")
	t.eq(moved, 0, "and none moved half a metre: the wall stands until something hits it")
	t.ok(furthest < 0.12,
		"the whole wall shifted at most %.3f m settling onto the pad" % furthest)
	t.eq(awake, 0, "and everything is asleep, which is the sleep discipline C0 built")

	stage.queue_free()


## The same wall built twice is the same wall, to the millimetre.
##
## The stacking jitter is what makes it look hand-built rather than like a lattice, and a jitter
## seeded off anything but the brick's own position would make every fixture run a different
## arrangement — which would turn every measured metric into noise and make the tolerances in
## `compare_baselines.py` meaningless.
func _the_same_wall_twice(t: TestContext, materials: MaterialSet, palette: Palette) -> void:
	var first := _stage(t)
	var second := _stage(t)
	var a := _wall(first, Vector3.ZERO, materials, palette)
	var b := _wall(second, Vector3.ZERO, materials, palette)

	var worst := 0.0
	var worst_turn := 0.0
	for i in a.size():
		worst = maxf(worst, (a[i] as Brick).global_position.distance_to(
			(b[i] as Brick).global_position))
		worst_turn = maxf(worst_turn, _basis_gap(
			(a[i] as Brick).global_basis, (b[i] as Brick).global_basis))
	t.ok(worst < 0.0001, "two walls built from the same numbers agree on every position")
	t.ok(worst_turn < 0.0001, "and on every brick's jittered angle: %.7f" % worst_turn)

	# Different place, different jitter — or the seed is not doing its job and every brick in the
	# world is turned identically, which reads as a lattice again.
	var elsewhere := _wall(second, Vector3(40.0, 0.0, 0.0), materials, palette)
	var same_turn := _basis_gap((a[0] as Brick).global_basis, (elsewhere[0] as Brick).global_basis)
	t.ok(same_turn > 0.0001, "while a wall somewhere else is jittered differently")

	first.queue_free()
	second.queue_free()


# ---------------------------------------------------------------- the fixture's own geometry

## The fixture's wall, brick for brick. Lifted from `blast_fixture.gd::_spawn_structure`.
func _wall(into: Node3D, at: Vector3, materials: MaterialSet, palette: Palette) -> Array:
	var made := []
	for ix in WALL_WIDE:
		for iy in WALL_HIGH:
			for iz in WALL_DEEP:
				var p := at + Vector3(
					(ix - 4.5) * WALL_BRICK.x,
					WALL_BRICK.y * 0.5 + iy * WALL_BRICK.y,
					(iz - 0.5) * WALL_BRICK.z)
				made.append(Brick.spawn(into, p, Basis.IDENTITY, WALL_BRICK, WALL_MATERIAL,
					Vector3.ZERO, materials, palette, WALL_JITTER))
	return made


## A pad to stand on, and somewhere to put it. The fixture's own pad is 240 m across and 600 m from
## the origin so brick scenarios measure the blast and nothing else; this is the same idea at the
## size a test needs.
func _stage(t: TestContext) -> Node3D:
	var stage := Node3D.new()
	t.host.add_child(stage)
	var pad := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	pad.add_child(shape)
	pad.position = Vector3(0.0, -0.5, 0.0)
	stage.add_child(pad)
	return stage


## How far apart two orientations are, as the largest disagreement between their axes.
##
## Not the angle between their quaternions, which is what this measured first and got wrong. That
## goes through `acos` near 1, where the derivative is unbounded — two bases identical to float
## precision came out 0.000977 rad apart, which is not a difference between the walls but the
## precision floor of the measurement. Comparing the axes directly has no such amplification.
func _basis_gap(a: Basis, b: Basis) -> float:
	return maxf(maxf((a.x - b.x).length(), (a.y - b.y).length()), (a.z - b.z).length())
