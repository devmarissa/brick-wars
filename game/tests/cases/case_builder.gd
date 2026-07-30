extends TestCase
## The builder: a validated part table becomes meshes, collision shapes and rigid bodies.
##
## Everything here runs through the whole loader, on fixture assets, because the builder's
## real contract is with the format rather than with its own arguments. An asset that
## declares `hollow` weighs less; an asset that declares `mass` weighs exactly that; a
## structure comes apart into bricks and a prop does not; a wall builds identically twice.
## That last one is not a graphics test. Two clients that disagree about where brick four
## went have desynced, and the seed is the only thing standing in the way.
##
## The arithmetic underneath — volumes, winding, which primitive collides as what — is in
## `case_geometry.gd`, which needs no loader and no fixtures to say what it says.

const FIXTURES := "res://tests/fixtures/build"

## MATERIAL-SPEC §5, and the whole reason the mass numbers below are integers.
const DENSITY_STONE := 2700.0
const DENSITY_PLANK := 600.0

## One tenth of a gram. The masses here are in the thousands of kilograms, so anything this
## far apart is a different formula rather than a different rounding.
const EPSILON := 0.0001


func case_name() -> String:
	return "builder"


func run(t: TestContext) -> void:
	var world := _load()
	if world.is_empty():
		t.fail("the builder fixtures would not load, so nothing below means anything")
		return
	t.ok((world["validator"] as AssetValidator).refused.is_empty(),
		"the fixtures are valid content: " + _refusals(world))

	_derived_mass(t, world)
	_declared_mass(t, world)
	_bodies(t, world)
	_colliders(t, world)
	_parents(t, world)
	_deterministic(t, world)


## Volume × density and nowhere else (MATERIAL-SPEC §2). Three one-metre stone cubes are
## three cubic metres of stone, and there is exactly one arithmetic that gets to say so.
func _derived_mass(t: TestContext, world: Dictionary) -> void:
	var solid := _build(world, "core:pillar")
	t.near(solid.mass, 3.0 * DENSITY_STONE, 0.01, "three cubic metres of stone weigh 3 × 2700 kg")
	t.ok(not solid.mass_declared, "and nothing typed that number, so it is not marked as declared")

	# The same pillar with `hollow`, which is a one-module shell: each cube keeps 1 − 0.8³ of
	# itself. A crate that weighs what a solid block of oak weighs is a crate nobody can throw.
	var hollow := _build(world, "core:pillar_hollow")
	t.near(hollow.mass, 3.0 * (1.0 - 0.8 * 0.8 * 0.8) * DENSITY_STONE, 0.01,
		"hollow keeps a one-module shell of each part and nothing else")
	t.ok(hollow.mass < solid.mass, "which is lighter than solid, as an inherited field should be")

	# Six stone blocks, each 0.8 × 0.4 × 0.4. This is the number the wall's own mass override
	# below is measured against, so it is worth pinning on its own.
	var wall := _build(world, "core:wall")
	t.near(wall.mass, 6.0 * 0.128 * DENSITY_STONE, 0.01, "a wall weighs the sum of its bricks")

	var post := _build(world, "core:post")
	t.ok(post.mass > 0.0, "and a part table with a primitive in it still produces a mass")


## A `mass` in the file wins, and the built asset says that it did, so `--resolve` and the boot
## log can tell a number the world produced from a number a person typed.
func _declared_mass(t: TestContext, world: Dictionary) -> void:
	var stated := _build(world, "core:pillar_stated")
	t.near(stated.mass, 42.0, EPSILON, "a declared mass overrides the derived one")
	t.ok(stated.mass_declared, "and is recorded as declared")
	t.near(stated.bodies[0].mass, 42.0, EPSILON, "the body itself carries it, not just the record")

	# On a stack of bricks the declared mass is a statement about the whole stack, so it is
	# spread in proportion. The alternative — a thousand kilograms per brick — is a wall that
	# demolishes the world when it falls over.
	var heavy := _build(world, "core:wall_heavy")
	t.near(heavy.mass, 1000.0, EPSILON, "a declared mass on a stack of bricks is the stack's")
	var summed := 0.0
	for body in heavy.bodies:
		summed += body.mass
	t.near(summed, 1000.0, 0.01, "and it is spread across them rather than given to each")
	t.near(heavy.bodies[0].mass, 1000.0 / 6.0, 0.01,
		"in proportion to what each of them already weighed")


## FORMAT-SPEC has nothing to say about body granularity, and it decides whether a wall falls
## down or tips over. `bricks` by kind for structures, `single` for everything else, and the
## asset may say so itself.
func _bodies(t: TestContext, world: Dictionary) -> void:
	t.eq(_build(world, "core:pillar").body_count(), 1, "a prop is one body")
	t.eq(_build(world, "core:wall").body_count(), 6, "a structure is one body per part")
	t.eq(_build(world, "core:wall_slab").body_count(), 1,
		"and an asset that says `single` is one, whatever its kind defaults to")

	t.eq(AssetBuilder.body_mode_of(_asset(world, "core:wall")), "bricks",
		"the mode a structure gets without asking")
	t.eq(AssetBuilder.body_mode_of(_asset(world, "core:pillar")), "single", "and the one a prop gets")

	# Every body joins `bricks`, which is the group the physics module counts and the blast
	# model will reach for. A body outside it is a body nothing in the game can see.
	var wall := _build(world, "core:wall")
	for body in wall.bodies:
		t.ok(body.is_in_group(&"bricks"), "%s is in the group physics counts" % body.name)
	t.ok(wall.aabb().size.x > 0.4, "and the whole thing reports a box the camera can frame")

	# In `bricks` mode collision follows each part's own shape, which is the one place the
	# declared-collider rule does not reach and does not want to: a brick is a box, and the
	# steel band round a fence post is a cylinder.
	var post := _build(world, "core:post")
	t.eq(post.body_count(), 4, "a post is four bodies")
	t.ok(_shape_of(post.bodies[0]) is BoxShape3D, "its blocks collide as boxes")
	t.ok(_shape_of(post.bodies[3]) is CylinderShape3D, "and its band as the cylinder it is")


## Declared, never derived (FORMAT-SPEC §6) — the compound-collider lesson from the tank. An
## asset that declares nothing gets one box round the whole of it, which is right for a crate
## and wrong for a rifle, so the validator says so out loud rather than letting it happen
## quietly.
func _colliders(t: TestContext, world: Dictionary) -> void:
	var crate := _build(world, "core:crate")
	t.eq(_shapes_of(crate.bodies[0]).size(), 2,
		"a two-box compound is built as two boxes and not as five parts")
	var first: BoxShape3D = _shapes_of(crate.bodies[0])[0].shape
	t.near(first.size.y, 0.5, EPSILON, "at the size the file gave, in metres")

	var bare := _build(world, "core:crate_bare")
	var fitted: Array[CollisionShape3D] = _shapes_of(bare.bodies[0])
	t.eq(fitted.size(), 1, "an asset with none declared gets one box, not one per part")
	var box: BoxShape3D = fitted[0].shape
	t.near(box.size.x, 0.8, EPSILON, "fitted round everything the asset is made of — x")
	t.near(box.size.y, 0.9, EPSILON, "y")
	t.near(box.size.z, 0.9, EPSILON, "z")
	t.near(fitted[0].position.y, 0.4, EPSILON, "and centred on that envelope rather than on the origin")

	var said := _warnings_about(world, "core:crate_bare")
	t.ok(said.contains("no `collider`"), "and the author is told it happened: " + said)
	t.ok(said.contains("barrel or a gap"), "and what it costs on anything that is not a crate")
	t.ok(not _warnings_about(world, "core:crate").contains("no `collider`"),
		"an asset that declared its own hears nothing")
	t.ok(not _warnings_about(world, "core:wall").contains("no `collider`"),
		"nor does a stack of bricks, which collides as its bricks")


## `parent` composes transforms, so a hand on an arm on a base is where all three put it.
## This is the machinery the modded horse's legs will hang off, and it is worth pinning now
## while it is three blocks rather than a rig.
func _parents(t: TestContext, world: Dictionary) -> void:
	var arm := _build(world, "core:arm")
	t.eq(arm.body_count(), 3, "an arm is three bodies")
	t.near(arm.bodies[0].position.y, 0.2, EPSILON, "the base sits where it says it does")
	t.near(arm.bodies[1].position.y, 0.6, EPSILON, "the upper adds its own offset to its parent's")
	t.near(arm.bodies[2].position.y, 1.0, EPSILON, "and the hand adds itself to both")

	var builder := AssetBuilder.new()
	builder.build(_asset(world, "core:arm"), world["materials"], world["palette"])
	t.ok(builder.errors.is_empty(), "and a well-formed chain builds without complaint")


## Two clients build the same wall down to the last brick, or they have desynced. The look
## depends on the draws being random; the netcode depends on them being the same random.
func _deterministic(t: TestContext, world: Dictionary) -> void:
	var first := _build(world, "core:wall")
	var second := _build(world, "core:wall")

	var same_shape := true
	var same_colour := true
	for i in first.bodies.size():
		var a: MeshInstance3D = _mesh_of(first.bodies[i])
		var b: MeshInstance3D = _mesh_of(second.bodies[i])
		if not a.transform.is_equal_approx(b.transform):
			same_shape = false
		if (a.material_override as StandardMaterial3D).albedo_color != \
				(b.material_override as StandardMaterial3D).albedo_color:
			same_colour = false
	t.ok(same_shape, "the same wall built twice jitters identically")
	t.ok(same_colour, "and shades identically")

	# Jitter has to actually do something, or the test above passes for the wrong reason.
	var varied := false
	var scales: Array[float] = []
	for body in first.bodies:
		scales.append(_mesh_of(body).transform.basis.get_scale().x)
	for scale in scales:
		if not is_equal_approx(scale, scales[0]):
			varied = true
	t.ok(varied, "and the bricks are not all the same size, which is what jitter is for")

	# The collider follows the jittered size rather than the declared one, or a wall looks
	# hand-stacked and collides as though it were not.
	var brick: BoxShape3D = _shape_of(first.bodies[0])
	t.near(brick.size.x, _mesh_of(first.bodies[0]).transform.basis.get_scale().x * 0.8, 0.001,
		"and each brick collides at the size it is drawn, not the size it was written")

	# ART-BIBLE §3: the shade is one of four multiples of the palette colour, so a wall of one
	# colour reads as masonry. A fifth value would mean the draw had escaped the table.
	var palette: Palette = world["palette"]
	var base := palette.colour(&"stone2")
	for body in first.bodies:
		var lit := (_mesh_of(body).material_override as StandardMaterial3D).albedo_color
		var factor := lit.r / maxf(0.0001, base.r)
		var known := false
		for shade in AssetBuilder.SHADES:
			if is_equal_approx(snappedf(factor, 0.0001), snappedf(float(shade), 0.0001)):
				known = true
		t.ok(known, "%s is shaded by one of the four values in the table" % body.name)


## The fixtures run through the whole loader, exactly as `content_module` runs the real one.
## A builder test that hand-made a part dictionary would be testing a format nobody writes:
## the defaults `PartRules` fills in are half of what the builder reads.
func _load() -> Dictionary:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	var slots := SlotSet.new()
	if not (palette.load_core() and materials.load_core(palette) and slots.load_core()):
		return {}

	var packs := PackSet.new()
	packs.discover([FIXTURES] as Array[String])
	var index := AssetIndex.new()
	index.scan(packs)
	var resolver := AssetResolver.new()
	resolver.resolve_all(index, packs)

	var validator := AssetValidator.new()
	validator.validate_all(resolver, index, packs, materials, palette, slots)
	return { "resolver": resolver, "validator": validator, "materials": materials,
		"palette": palette }


func _asset(world: Dictionary, id: String) -> ResolvedAsset:
	return (world["resolver"] as AssetResolver).get_asset(id)


func _build(world: Dictionary, id: String) -> BuiltAsset:
	var asset := _asset(world, id)
	if asset == null:
		return BuiltAsset.new()
	return AssetBuilder.new().build(asset, world["materials"], world["palette"])


func _mesh_of(body: RigidBody3D) -> MeshInstance3D:
	for child in body.get_children():
		if child is MeshInstance3D:
			return child
	return MeshInstance3D.new()


func _shape_of(body: RigidBody3D) -> Shape3D:
	var shapes := _shapes_of(body)
	return shapes[0].shape if not shapes.is_empty() else null


func _shapes_of(body: RigidBody3D) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for child in body.get_children():
		if child is CollisionShape3D:
			out.append(child)
	return out


func _warnings_about(world: Dictionary, id: String) -> String:
	var said := ""
	for warning in (world["validator"] as AssetValidator).warnings:
		if String(warning).begins_with(id + " —"):
			said += String(warning) + "\n"
	return said


func _refusals(world: Dictionary) -> String:
	var said := ""
	for problem in (world["validator"] as AssetValidator).errors:
		said += "\n    " + String(problem)
	return said if said != "" else "(nothing was refused)"
