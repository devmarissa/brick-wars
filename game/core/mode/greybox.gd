extends Node3D
## The C0 world: a plate, a stacked wall, a light and a camera.
##
## Ugly on purpose. Its entire job is to answer the four questions C0 is allowed to be
## judged on — does a world spawn, do bricks fall, do they stop, and does the whole thing
## survive a headless run — with nothing else in the frame to confuse the answer. Every bit
## of it is thrown away the moment C1 can build a wall from a JSON file, which is the point:
## nothing here is worth keeping, so nothing here is worth arguing about.
##
## The one thing it does take seriously is determinism. Fixed seed, fixed positions, fixed
## sizes — a test that can't reproduce its own world can't tell you anything.

const SEED := 20260730
const GROUND_SIZE := Vector3(60, 1, 60)
const WALL_COLUMNS := 10
const WALL_ROWS := 6
const WALL_DEPTH := 2
const BRICK := Vector3(1.0, 0.5, 0.5)     # MODULE = 0.1 m, so this is 10 × 5 × 5 modules
const DROP_HEIGHT := 0.6                  # bricks start just above rest, and fall to it

# ART-BIBLE §4. Even the throwaway world stays inside the palette — the day a stray
# saturated colour looks normal in a screenshot is the day the palette law stops working.
const SBAG := Color("9a8a68")
const SBAG2 := Color("8b7c5e")
const GROUND_COLOUR := Color("5e5240")
const SKY_COLOUR := Color("6d7480")

var bricks: Array[RigidBody3D] = []


## Builds the world and returns the bricks it dropped. Takes the physics module rather
## than reaching for it, so this is callable straight from a test with no kernel at all.
func build(physics: Module) -> Array[RigidBody3D]:
	_add_ground()
	_add_light()
	_add_environment()
	_add_camera()
	bricks = _add_wall(physics)
	return bricks


func _add_ground() -> void:
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

	add_child(ground)
	ground.position = Vector3(0, -GROUND_SIZE.y * 0.5, 0)


## A stacked wall, dropped from just above rest so it settles rather than explodes.
## Alternating shades per course, which is the jitter convention from the old build:
## identical bricks read as a texture, slightly varied ones read as masonry.
##
## Odd courses are offset half a brick — a running bond, so vertical joints don't line up
## into a seam the whole wall can hinge on. The first version offset them and kept them the
## same length, which pushed the end brick of every odd course half over the edge with
## nothing under it, and the first screenshot showed exactly what you'd expect: the corner
## quietly tipped off and lay on the ground. Real masonry ends those courses short. So does
## this one — odd courses are one brick narrower and inset at both ends.
func _add_wall(physics: Module) -> Array[RigidBody3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array[RigidBody3D] = []
	var origin := Vector3(
		-WALL_COLUMNS * BRICK.x * 0.5,
		BRICK.y * 0.5 + DROP_HEIGHT,
		-WALL_DEPTH * BRICK.z * 0.5)

	for row in WALL_ROWS:
		var staggered := row % 2 == 1
		var columns := WALL_COLUMNS - 1 if staggered else WALL_COLUMNS
		var offset := BRICK.x * 0.5 if staggered else 0.0
		for col in columns:
			for d in WALL_DEPTH:
				var pos := origin + Vector3(
					col * BRICK.x + offset, row * BRICK.y, d * BRICK.z)
				var colour := SBAG if rng.randf() < 0.5 else SBAG2
				out.append(physics.spawn_brick(pos, BRICK, colour))
	return out


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
	cam.global_position = Vector3(6.5, 3.2, 8.5)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.current = true
