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
## The plate, the sun, the sky and the camera are carried over from the greybox unchanged,
## on purpose. They are the parts of the picture that are not being tested, and holding
## them still is what makes the before-and-after screenshots comparable.

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
	{"id": "core:wall_sandbag", "at": Vector3(0.0, DROP_HEIGHT, 0.0)},
	{"id": "core:watchtower", "at": Vector3(-8.2, 0.0, -3.2), "yaw": 20.0},
	{"id": "core:crate", "at": Vector3(2.4, DROP_HEIGHT, 1.9), "yaw": -15.0},
	{"id": "core:crate_ammo", "at": Vector3(3.2, DROP_HEIGHT, 3.3), "yaw": 30.0},
	{"id": "core:barrel", "at": Vector3(1.0, DROP_HEIGHT, 3.0), "yaw": 45.0},
	{"id": "testpack:cairn", "at": Vector3(-2.9, DROP_HEIGHT, 3.0)},
	{"id": "testpack:crate_reinforced", "at": Vector3(4.3, DROP_HEIGHT, 1.5), "yaw": 10.0},
]

var spawned: Array[BuiltAsset] = []


## Builds the world and returns what it put in it. Takes the content module rather than
## reaching for it, so this is callable straight from a test with no kernel around it.
func build(content: Module) -> Array[BuiltAsset]:
	_add_ground()
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
			entry["at"])
		add_child(built)
		spawned.append(built)
	return spawned


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
	return "sandbox: %d asset(s)\n%s" % [spawned.size(), "\n".join(lines)]


func _add_ground() -> void:
	add_child(make_ground())


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
	cam.global_position = Vector3(5.6, 2.5, 7.0)
	cam.look_at(Vector3(-2.2, 1.2, 0.4))
	cam.current = true
