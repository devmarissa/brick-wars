extends Node3D
## The C1 world: a plate, a light, a camera — and everything else out of a JSON file.
##
## The greybox this replaces built its wall in code. A hundred and fourteen `spawn_brick`
## calls from three constants, and every one of those bricks now comes out of
## `packs/core/wall_sandbag.json` instead, through the same reader, resolver, validator and
## builder a workshop upload goes through. That substitution is the whole of C1 in one
## sentence: if the wall still stands up, the format is real, and if it never stands up
## again the format was a description of something else.
##
## What is still code is *where things go*. FORMAT-SPEC describes assets, not scenes, and a
## map format is C7's problem — so `LAYOUT` is a table rather than a sequence of calls,
## which makes turning it into a file later a reader instead of a rewrite.
##
## The sun, the sky and the camera were carried over from the greybox unchanged through C1, on
## purpose: they are the parts of the picture that are not being tested, and holding them still is
## what makes the before-and-after screenshots comparable. The floor stopped being one of those at
## C2. A flat plate cannot show foot planting — every foot lands at y = 0 whether the solver works
## or not — so the world is `TestGround` now, and the plate survives only as `make_ground()` for
## the physics tests that still need something flat to be meaningful on.
##
## Swapping it is not free, and the cost is `_on_ground`. Every `LAYOUT` position was authored
## against a floor at zero: the watchtower stood at y = 0 at (-5, -2.4), which on this ground is
## inside the bowl where the surface is -0.358, and half the crates landed partly inside the
## terrain. Rather than re-author nine hand-placed positions against a surface that will be
## replaced again at C3 by the real earth field, each entry is lifted by the height of the ground
## under it. The table still reads as "0.12 m above the floor, wherever the floor is".

const GROUND_SIZE := Vector3(60, 1, 60)
const GROUND_COLOUR := Color("5e5240")
const SKY_COLOUR := Color("6d7480")

## Assets start just above rest and fall to it, so the world settles instead of bursting.
##
## The number is tied to the smallest thing in the world, not to the largest. A sandbag is
## 0.2 m tall, and a 0.6 m drop — which is what this was while the bags were hay-bale sized —
## gives the bottom course enough speed to shove the courses above it sideways before the
## stack has touched anything. Roughly half a bag's height lands everything without any of it
## arriving fast enough to matter.
const DROP_HEIGHT := 0.12

## Where each asset stands, in metres, with an optional yaw in degrees. Two packs are
## represented deliberately: the last two lines come from TESTPACK, so a screenshot of this
## world is a screenshot of a non-core pack putting objects into the game.
const LAYOUT := [
	{"id": "core:wall_sandbag", "at": Vector3(0.4, DROP_HEIGHT, -0.8)},
	{"id": "core:watchtower", "at": Vector3(-5.0, 0.0, -2.4), "yaw": 20.0},
	{"id": "core:crate", "at": Vector3(2.6, DROP_HEIGHT, 1.2), "yaw": -15.0},
	{"id": "core:crate_ammo", "at": Vector3(3.4, DROP_HEIGHT, 3.2), "yaw": 30.0},
	{"id": "core:barrel", "at": Vector3(1.3, DROP_HEIGHT, 2.4), "yaw": 45.0},
	{"id": "testpack:cairn", "at": Vector3(-3.2, DROP_HEIGHT, 1.5)},
	{"id": "testpack:crate_reinforced", "at": Vector3(4.6, DROP_HEIGHT, 1.0), "yaw": 10.0},
	# The two that verified C1's first two clauses, kept in the world rather than deleted
	# after the demonstration. `core:table` was a new prop added as one JSON file and nothing
	# else; `core:table_map` is that prop plus a canvas sheet, in five lines of `extends`.
	{"id": "core:table", "at": Vector3(-4.3, DROP_HEIGHT, 3.4), "yaw": -70.0},
	{"id": "core:table_map", "at": Vector3(-1.6, DROP_HEIGHT, 4.2), "yaw": 15.0},
]

## The two creatures C2 is judged by, and where they walk. Circles rather than straight lines,
## because a screenshot has to catch them mid-stride and a walker heading due north leaves the map
## while the tool is still settling. The radius is a consequence of the speed and the turn rate,
## not a number of its own: at `WALK_SPEED` and this much yaw per second a walker comes round in
## about two and a half metres, which fits between the props and the edge.
##
## Both centres are clear of the bowl and clear of everything in `LAYOUT`. The horse's is out on
## the ramp on purpose — a creature walking across a slope is the whole of what foot planting buys,
## and on flat ground it is indistinguishable from a creature with no solver at all.
const DEMO_TURN := 0.9
const WALKERS := [
	{"id": "core:soldier", "around": Vector2(1.2, -4.2), "phase": 0.0},
	{"id": "testpack:horse", "around": Vector2(5.8, -4.6), "phase": PI},
]

var spawned: Array[BuiltAsset] = []
var walkers: Array[Walker] = []

## The ground, as of C3 — a real column field rather than a fixed surface.
var earth: EarthTerrain = null

var _earth_moved := 0

var _headings: Array[float] = []
var _demo := 0.0


## Builds the world and returns what it put in it. Takes the content module rather than
## reaching for it, so this is callable straight from a test with no kernel around it.
func build(content: Module) -> Array[BuiltAsset]:
	_add_ground(content)
	_add_light()
	_add_environment()
	_add_camera()

	spawned.clear()
	for entry in LAYOUT:
		var built := build_asset(content, String(entry["id"]))
		if built == null:
			continue
		built.transform = Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(float(entry.get("yaw", 0.0))), 0.0)),
			_on_ground(entry["at"]))
		add_child(built)
		spawned.append(built)
	_add_walkers(content)
	return spawned


## A position authored against a flat floor, lifted onto the real surface. Off the map the height
## is meaningless, so it stays where it was put and falls — which is the honest outcome and looks
## like one, rather than a prop hovering at the height of the last valid sample.
func _on_ground(at: Vector3) -> Vector3:
	if earth == null:
		return at
	return Vector3(at.x, at.y + earth.field.height_at(at.x, at.z), at.z)


## The soldier and the horse, walking. This is the part of the sandbox that is not a still life,
## and it is here rather than in a mode of its own because C2's done-condition is a sentence about
## two creatures moving over uneven ground — so the world the milestone is judged in has to have
## them in it.
func _add_walkers(content: Module) -> void:
	walkers.clear()
	_headings.clear()
	for entry in WALKERS:
		var asset: ResolvedAsset = content.resolver.get_asset(String(entry["id"]))
		if asset == null:
			push_error("sandbox: no asset `%s` for a walker — its pack may be off" % entry["id"])
			continue
		var walker := Walker.of(asset, content.materials, content.palette)
		for problem in walker.warnings:
			push_warning("sandbox: %s: %s" % [entry["id"], problem])
		var around: Vector2 = entry["around"]
		walker.position = _on_ground(Vector3(around.x, DROP_HEIGHT, around.y - _radius()))
		add_child(walker)
		# Paired with its phase rather than indexed against `WALKERS` later. A walker that fails
		# to build is skipped, and then the two arrays are different lengths — no crash, because
		# this one is always the shorter, but the surviving creature quietly walks the missing
		# one's path. Cheaper to carry the number than to remember that.
		walkers.append(walker)
		_headings.append(float(entry["phase"]))


## Drive the demo. Each walker is asked for a heading that turns at a constant rate, which walks
## it round a circle it cannot leave — deterministic, and the same picture every capture.
func _physics_process(delta: float) -> void:
	_demo += delta
	for i in walkers.size():
		var heading := _demo * DEMO_TURN + _headings[i]
		walkers[i].wish = Vector2(cos(heading), sin(heading))


## How wide a circle a walker at walking speed makes at `DEMO_TURN`. Stated as the arithmetic it
## is, so that changing either number does not silently walk a creature into the watchtower.
static func _radius() -> float:
	return Walker.WALK_SPEED / DEMO_TURN


## One asset, built through the whole pipeline and handed back unparented and unplaced.
##
## Static, and separate from `build`, so a test can stand a single wall up in an otherwise
## empty scene. A test that has to build the whole sandbox to look at one asset ends up
## measuring the sandbox.
static func build_asset(content: Module, id: String) -> BuiltAsset:
	var asset: ResolvedAsset = content.resolver.get_asset(id)
	if asset == null:
		# Not an assertion, because the honest cause is usually a disabled pack rather than a
		# typo — and a pack going down must not take the rest of the world with it.
		push_error("sandbox: no asset `%s` — it is missing, or the pack that has it is off" % id)
		return null

	var builder := AssetBuilder.new()
	var built := builder.build(asset, content.materials, content.palette)
	for problem in builder.errors:
		push_error("sandbox: %s: %s" % [id, problem])
	return built


## One line per asset for the boot log. Masses are derived from volume × density unless the
## file said otherwise, so this is also the cheapest sanity check there is: a crate that
## weighs two tonnes is a density with a decimal point in the wrong place.
func report() -> String:
	var lines: Array[String] = []
	for built in spawned:
		lines.append("  %-28s %3d bod%s  %8.1f kg%s" % [
			built.asset_id, built.body_count(), "y " if built.body_count() == 1 else "ies",
			built.mass, "  (declared)" if built.mass_declared else ""])
	for walker in walkers:
		lines.append("  %-28s %s" % [walker.asset_id, walker.report()])
	if earth != null:
		lines.append("  " + earth.report())
		lines.append("  trench cut: %d column-cm of earth moved, and all of it is still in the field"
			% _earth_moved)
	return "sandbox: %d asset(s), %d walker(s)\n%s" % [
		spawned.size(), walkers.size(), "\n".join(lines)]


## The real earth field, as of C3. `TestGround`'s shape — sampled from it rather than reinvented,
## so the before-and-after screenshots compare the *ground*, not two different maps that both have
## a hill — plus a trench cut into it, which is the thing slope-dependent meshing exists to show.
##
## `TestGround` itself stays exactly where it is: it is the suite's analytic surface and every rig
## case asserts exact numbers against it. What changed is what the sandbox stands on.
func _add_ground(content: Module) -> void:
	var field := EarthField.flat(content.materials, 0)
	earth = EarthTerrain.of(field, content.palette, content.materials)
	_earth_moved = DemoGround.make(field, earth.settle)
	add_child(earth)
	earth.build_all()


## The plate, with its top face at y = 0. Static and separate for the same reason
## `build_asset` is: a test that wants one wall still needs something for it to land on,
## and it should land on the same floor the game uses rather than a second one that drifts.
static func make_ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = GROUND_SIZE
	shape.shape = box
	ground.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = GROUND_SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOUR
	mesh.mesh = box_mesh
	mesh.material_override = mat
	ground.add_child(mesh)

	ground.position = Vector3(0, -GROUND_SIZE.y * 0.5, 0)
	return ground


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)


## Just enough ambient light to read shape on the shadowed side. With none at all, half of
## every brick is pure black and you cannot tell a settled wall from a collapsed one in a
## screenshot — which matters, because a screenshot is how this milestone gets judged.
func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOUR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = SKY_COLOUR
	env.ambient_light_energy = 0.55

	var node := WorldEnvironment.new()
	node.name = "Environment"
	node.environment = env
	add_child(node)


func _add_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	add_child(cam)
	# Pulled back and raised at C2. The C1 framing was chosen for a still life of props on a flat
	# plate; the subject now is two creatures walking over ground with a slope, a step and a hole
	# in it, and the walkers' circles reach four metres further from the camera than anything in
	# `LAYOUT` does. A frame that crops them is a frame that shows none of what the milestone did.
	# Aimed along the trench at C3. The creatures are still in frame, but the subject is the ground
	# now: a cut with vertical walls, its own spoil heaped beside it as a smooth parapet, and the
	# ramp behind — one picture with both halves of the meshing rule in it.
	cam.global_position = Vector3(-6.9, 1.1, 0.4)
	cam.look_at(Vector3(-9.1, -1.0, -4.2))
	cam.current = true
