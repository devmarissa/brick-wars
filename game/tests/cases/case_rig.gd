extends TestCase
## The rig: a part table with joints on it becomes a hierarchy that can be posed. RIG-SPEC §3.
##
## Every number asserted below can be worked out with a pencil from `fixtures/rig/core/leg.json`,
## which is why that file is built out of whole modules and right angles. A rig test whose
## expected values were read off a running rig agrees with whatever the rig happens to do.
##
## Two things this case exists to hold down. First: a rigged asset must land its meshes exactly
## where the flat baked path would have put them, or every asset that grows a joint silently
## moves. Second, and it is the sentence RIG-SPEC §3 spends a paragraph on — **a rig is not a
## collider**. Posing a leg moves meshes and nothing else.
##
## The arithmetic underneath — the two-bone solver and the gait engine — is `case_locomotion.gd`,
## which needs no loader and no fixtures to say what it says.

const FIXTURES := "res://tests/fixtures/rig"

## A tenth of a millimetre. Everything here is in metres on a 0.1 m grid, so anything this far
## apart is a different formula rather than a different rounding.
const EPSILON := 0.0001


func case_name() -> String:
	return "rig"


func run(t: TestContext) -> void:
	var world := _load()
	if world.is_empty():
		t.fail("the rig fixtures would not load, so nothing below means anything")
		return
	t.ok((world["validator"] as AssetValidator).refused.is_empty(),
		"the fixtures are valid content: " + _refusals(world))

	_hierarchy(t, world)
	_driving(t, world)
	_slider(t, world)
	_aiming(t, world)
	_not_a_collider(t, world)
	_unrigged(t, world)


## The bones, and the meshes hanging off them, in the asset's own space. The hip is at 20
## modules, the thigh's centre 6 below it, the shin's 12 below that and the foot's 7 below that
## — 2.0, 1.4, 0.2, −0.5 in metres, precisely the sum the flat path takes. The *joints* sit at
## the tops of their bones instead, because of `pivot`: 2.0, 0.8 and −0.5.
func _hierarchy(t: TestContext, world: Dictionary) -> void:
	var built := _build(world, "core:leg")
	t.ok(built.is_rigged(), "a part table with a joint on it builds a rig")
	t.eq(built.body_count(), 1, "and is still one body — a rig is meshes, not physics")

	var rig: Rig = built.rig
	if rig == null:
		t.fail("core:leg produced no rig, so the rest of this case cannot run")
		return
	t.ok(rig.warnings.is_empty(), "built without complaint: " + "\n".join(rig.warnings))
	t.eq(",".join(rig.order), "hip,thigh,shin,foot", "bones are kept in declaration order")

	_vec(t, _centre(rig, "hip"), Vector3(0, 2.0, 0), "the hip mesh sits where its offset says")
	_vec(t, _centre(rig, "thigh"), Vector3(0, 1.4, 0), "the thigh adds its offset to its parent's")
	_vec(t, _centre(rig, "shin"), Vector3(0, 0.2, 0), "the shin adds itself to both")
	_vec(t, _centre(rig, "foot"), Vector3(0, -0.5, 0), "and the foot to all three")

	_vec(t, rig.joint_position("thigh"), Vector3(0, 2.0, 0),
		"the hip joint is at the top of the thigh, not at the middle of it")
	_vec(t, rig.joint_position("shin"), Vector3(0, 0.8, 0), "the knee is 12 modules below it")
	_vec(t, rig.joint_position("foot"), Vector3(0, -0.5, 0), "and the ankle 12 below that")

	# ART-BIBLE §7: a bone points down its own -Z and is sized `[thickness, thickness, length]`,
	# so this is the number a leg's IK is handed. A rig whose bones were authored down Y would
	# report a thickness here and solve a limb a fifth of its real size.
	t.near((rig.bone("thigh") as Rig.Bone).length(), 1.2, EPSILON, "a bone knows its own length")
	t.ok((rig.bone("thigh") as Rig.Bone).articulates(), "a hinge articulates")
	t.ok(not (rig.bone("foot") as Rig.Bone).articulates(), "and a `fixed` joint does not")
	t.ok(not (rig.bone("hip") as Rig.Bone).articulates(), "nor does a part with no joint at all")


## Turning hinges, and the limits holding them.
func _driving(t: TestContext, world: Dictionary) -> void:
	var rig := _rig(world, "core:leg")
	if rig == null:
		t.fail("core:leg produced no rig")
		return

	# The shin turns 90° about x, which swings it and the foot with it from straight down to
	# straight forward: the ankle leaves (0, −0.5, 0) and arrives at (0, 0.8, −1.3), a stride's
	# worth of geometry that is one assignment because the foot is a child of the shin.
	t.near(rig.drive("shin", 90.0), 90.0, EPSILON, "a hinge inside its limits applies in full")
	t.near(rig.driven("shin"), 90.0, 0.001, "and reads back the angle it was given")
	_vec(t, rig.joint_position("foot"), Vector3(0, 0.8, -1.3),
		"posing a bone carries everything below it")
	t.near(rig.strained("shin"), 0.0, EPSILON, "a pose inside the limits strains nothing")

	# A joint that can be driven past its limits is a joint whose limits are a comment.
	t.near(rig.drive("shin", 200.0), 140.0, EPSILON, "past the top limit clamps to it")
	t.near(rig.driven("shin"), 140.0, 0.001, "and the bone is actually there")
	t.near(rig.drive("shin", -50.0), 0.0, EPSILON, "and past the bottom clamps to that")
	t.near(rig.drive("thigh", -300.0), -90.0, EPSILON, "each bone against its own limits")

	t.near(rig.drive("foot", 30.0), 0.0, EPSILON, "a `fixed` joint refuses to be driven")
	t.near(rig.drive("nose", 30.0), 0.0, EPSILON, "and so does a bone that is not there")

	# Back to the file's `rest`, which is where the mesh positions above were measured.
	rig.rest_pose()
	t.near(rig.driven("shin"), 0.0, 0.001, "rest_pose puts a hinge back where the file idles it")
	_vec(t, _centre(rig, "foot"), Vector3(0, -0.5, 0), "and the meshes back where they started")


## The slider: the one joint whose units are modules of travel and the one that moves a bone
## instead of turning it. The ram idles 8 modules down the housing's -Z and runs −4 to +6.
## Every position below carries the housing's own 2 modules of lift, because `joint_position`
## answers in the asset's space rather than in the parent's.
func _slider(t: TestContext, world: Dictionary) -> void:
	var rig := _rig(world, "core:piston")
	if rig == null:
		t.fail("core:piston produced no rig")
		return

	_vec(t, rig.joint_position("ram"), Vector3(0, 0.2, -0.8), "the ram idles where its offset says")
	t.near(rig.driven("ram"), 0.0, EPSILON, "and reads as zero travel")

	# A slider with no `axis` runs along the bone, and the bone points down -Z (ART-BIBLE §7),
	# so +2 modules of travel is 0.2 m further forward rather than 0.2 m further back.
	t.near(rig.drive("ram", 2.0), 2.0, EPSILON, "two modules of travel apply in full")
	_vec(t, rig.joint_position("ram"), Vector3(0, 0.2, -0.6), "and moves the bone along its own axis")
	t.near(rig.driven("ram"), 2.0, 0.001, "travel reads back in modules, signed")

	t.near(rig.drive("ram", 40.0), 6.0, EPSILON, "travel clamps at the top of its range")
	_vec(t, rig.joint_position("ram"), Vector3(0, 0.2, -0.2), "at the far end of its stroke")
	t.near(rig.drive("ram", -40.0), -4.0, EPSILON, "and at the bottom")
	_vec(t, rig.joint_position("ram"), Vector3(0, 0.2, -1.2), "backing the ram into the housing")
	t.near(rig.driven("ram"), -4.0, 0.001, "which reads back negative, not as a bare distance")


## Aiming, which is how a solved limb is applied, and `strained`, which is what replaces the
## clamping `aim` deliberately does not do.
func _aiming(t: TestContext, world: Dictionary) -> void:
	var rig := _rig(world, "core:leg")
	if rig == null:
		t.fail("core:leg produced no rig")
		return

	# Swing the thigh from hanging down to pointing forward: 90° about x, against limits of
	# [−90, 20]. `aim` does it anyway — the solver answered a geometry question — and `strained`
	# is where the driver finds out the answer cost 70° more than the leg has.
	rig.aim("thigh", Vector3(0, 2, 0), Vector3(0, 2, -1), Vector3.UP)
	t.near(rig.driven("thigh"), 90.0, 0.001, "an aimed bone reports an angle like a driven one")
	t.near(rig.strained("thigh"), 70.0, 0.001, "and says how far past its limits it was put")
	_vec(t, rig.joint_position("shin"), Vector3(0, 2, -1.2), "carrying the knee out with it")

	# The bone below, aimed while its parent is somewhere unusual. `aim` takes world-space
	# points and the chain above has to be undone, or a hoof points wherever the shoulder does.
	rig.rest_pose()
	rig.aim("shin", rig.joint_position("shin"), Vector3(0, 0.8, -1), Vector3.UP)
	_vec(t, rig.joint_position("foot"), Vector3(0, 0.8, -1.3), "a bone aims in the asset's space")
	t.near(rig.strained("shin"), 0.0, EPSILON, "and this one is well inside its range")

	rig.rest_pose()
	t.near(rig.strained("thigh"), 0.0, EPSILON, "rest_pose clears the strain with the pose")
	t.near(rig.strained("hip"), 0.0, EPSILON, "an unjointed part is never strained")


## RIG-SPEC §3, the sentence this file is arranged around: a rig is not a collider. A horse
## gets a body box and maybe a head box, never eight leg colliders — and not only for the cost.
## A rig that collides with itself fights its own solver, visibly.
func _not_a_collider(t: TestContext, world: Dictionary) -> void:
	var built := _build(world, "core:leg")
	var rig: Rig = built.rig
	if rig == null or built.bodies.is_empty():
		t.fail("core:leg produced no rig to check the colliders of")
		return

	t.eq(_shapes_under(rig.root), 0, "there is not one collision shape anywhere inside the rig")

	var shapes := _kids(built.bodies[0], "CollisionShape3D")
	t.eq(shapes.size(), 1, "the body carries the one box the asset declared")
	var box := shapes[0] as CollisionShape3D
	t.near((box.shape as BoxShape3D).size.y, 2.4, EPSILON, "at the size the file gave, in metres")
	_vec(t, box.position, Vector3(0, 1.0, 0), "and where the file put it")

	# The point of the two assertions above is this one: pose the leg into a shape nothing like
	# the box, and the box has not noticed.
	rig.drive("thigh", -90.0)
	rig.drive("shin", 140.0)
	_vec(t, box.position, Vector3(0, 1.0, 0), "a pose does not move the collider")
	t.near((box.shape as BoxShape3D).size.y, 2.4, EPSILON, "nor resize it")
	t.eq(_shapes_under(rig.root), 0, "and posing grows no shapes of its own")


## `parent` on its own is not a rig. Parenting is a convenience for placing parts relative to
## one another; a rig is what you get when something articulates. An ordinary multi-part prop
## stays on the flat baked path, where the physics engine never sees a hierarchy it does not
## need — which is most of the assets in the game.
func _unrigged(t: TestContext, world: Dictionary) -> void:
	var asset := _asset(world, "core:strut")
	if asset == null:
		t.fail("core:strut would not resolve")
		return
	t.ok(not Rig.is_rigged(asset), "an asset that uses `parent` and no joint is not a rig")
	t.ok(Rig.is_rigged(_asset(world, "core:leg")), "and one with a joint is")

	var built := _build(world, "core:strut")
	t.ok(built.rig == null and not built.is_rigged(), "so nothing built a rig for it")

	# The meshes hang directly off the body with their transforms baked, exactly as they did
	# before rigs existed, and at the positions `case_builder.gd` proves the flat path produces.
	var meshes := _kids(built.bodies[0], "MeshInstance3D")
	t.eq(meshes.size(), 2, "its meshes hang straight off the body")
	_vec(t, (meshes[0] as Node3D).position, Vector3(0, 0.6, 0), "the post where its offset says")
	_vec(t, (meshes[1] as Node3D).position, Vector3(0, 1.2, -0.4), "and the arm on its parent's")


## The fixtures run through the whole loader, exactly as `content_module` runs the real one. A
## rig test that hand-made a part dictionary would test a format nobody writes: half of what
## `Rig.build` reads is defaults `PartRules` filled in.
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


func _rig(world: Dictionary, id: String) -> Rig:
	return _build(world, id).rig


## Where a node sits in the asset's own space, composed by walking up to the rig root. Not
## `global_transform`: none of this is in a scene tree, and asking would be an error in the
## log and an identity nobody wanted.
func _in_space(rig: Rig, node: Node3D) -> Vector3:
	var at := node
	var out := Vector3.ZERO
	while at != null and at != rig.root:
		out = at.transform * out
		at = at.get_parent() as Node3D
	return out


## The centre of a bone's mesh, which is the number the flat path would have baked.
func _centre(rig: Rig, name: String) -> Vector3:
	var bone: Rig.Bone = rig.bone(name)
	if bone == null:
		return Vector3.INF
	for child in bone.node.get_children():
		if child is MeshInstance3D:
			return _in_space(rig, child)
	return Vector3.INF


func _vec(t: TestContext, got: Vector3, want: Vector3, what: String) -> void:
	t.ok(got.distance_to(want) < EPSILON, "%s — got %s, wanted %s" % [what, got, want])


func _shapes_under(node: Node) -> int:
	var found := 0
	for child in node.get_children():
		if child is CollisionShape3D:
			found += 1
		found += _shapes_under(child)
	return found


## The direct children of a node of one class — the shapes hanging on a body, or the meshes.
func _kids(node: Node, want: String) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child.is_class(want):
			out.append(child)
	return out


func _refusals(world: Dictionary) -> String:
	var said := ""
	for problem in (world["validator"] as AssetValidator).errors:
		said += "\n    " + String(problem)
	return said if said != "" else "(nothing was refused)"
