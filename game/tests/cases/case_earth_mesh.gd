extends TestCase
## Meshing the field: organic ground and vertical trench walls out of the same columns.
## EARTH-SPEC §2.
##
## §2's claim is that one rule produces both, decided by the terrain rather than by an authoring
## mode — *"dig a trench and it has vertical walls because you cut it steeply; shell that trench
## and the walls slump past 60° and it becomes an organic churned bowl."* That is a claim about
## geometry, so it is tested as geometry: how many faces come back vertical, how many level, and
## where the transition between the two sits.
##
## None of it is judged by eye. A mesh that looks plausible in a screenshot and has a seam at every
## chunk border looks fine until somebody digs across one, and by then the cause is four systems
## away from the symptom.

const EPSILON := 0.0001

## The step that separates smooth ground from a wall, per `EarthMesher.CLIFF_CM`. Restated here so
## a change to the threshold has to be a deliberate edit in two places rather than a silent one.
const CLIFF_CM := 87


func case_name() -> String:
	return "earth mesh"


func run(t: TestContext) -> void:
	var world := _world()
	if world.is_empty():
		t.fail("core content data would not load, so nothing below means anything")
		return

	_flat_ground_is_flat(t, world)
	_the_threshold_decides(t, world)
	_a_trench_has_vertical_walls(t, world)
	_a_slumped_trench_does_not(t, world)
	_columns_agree_across_a_chunk_border(t, world)
	_walls_face_outward(t, world)


## The degenerate case, and the one that catches a winding mistake: flat ground is a flat sheet,
## every normal up, no walls anywhere.
func _flat_ground_is_flat(t: TestContext, world: Dictionary) -> void:
	var field := EarthField.flat(world["materials"], 0)
	var mesh := _mesh(field, world)
	t.ok(mesh != null, "flat ground meshes at all")
	if mesh == null:
		return

	var faces := _faces(mesh)
	t.eq(faces["level"], faces["total"], "every face of flat ground is level")
	t.eq(faces["vertical"], 0, "and none of it is wall")
	# Two triangles a column, and nothing else — a skirt on flat ground would be a wall of no
	# height, which `_quad` drops rather than emitting as a degenerate triangle.
	t.eq(faces["total"], EarthChunk.SIZE * EarthChunk.SIZE * 2,
		"two triangles a column, and no degenerate skirts")
	t.ok(faces["up"] == faces["total"],
		"with every normal pointing up rather than into the ground, which is the winding")


## §2's rule is a threshold, so what matters is which side of it a step falls on. A step just under
## it is ground; a step just over it is a wall. The transition is the whole decision.
func _the_threshold_decides(t: TestContext, world: Dictionary) -> void:
	for step in [CLIFF_CM - 10, CLIFF_CM + 10]:
		var field := EarthField.flat(world["materials"], 0)
		# A straight edge across the middle of the chunk: everything past x = 16 raised by `step`.
		for z in EarthChunk.SIZE + 2:
			for x in range(16, EarthChunk.SIZE + 2):
				field.deposit(Vector2i(x, z - 1), step)
		var faces := _faces(_mesh(field, world))
		if step < CLIFF_CM:
			t.eq(faces["vertical"], 0,
				"a %d cm step is inside the threshold, so the ground ramps rather than breaking" % step)
			t.ok(faces["sloped"] > 0, "and there is a slope where the step is")
		else:
			t.ok(faces["vertical"] > 0,
				"a %d cm step is past it, so a wall appears: %d vertical faces" % [
					step, faces["vertical"]])
			t.ok(EarthMesher.connected(field, Vector2i(15, 4), Vector2i(16, 4)) == (step < CLIFF_CM),
				"and `connected` agrees with the mesh about which side of the threshold it is on")


## The case the whole of §2 is written to protect: a trench you cut has vertical walls.
func _a_trench_has_vertical_walls(t: TestContext, world: Dictionary) -> void:
	var field := _trench(world, 150)
	var faces := _faces(_mesh(field, world))
	t.ok(faces["vertical"] >= 40,
		"a 150 cm trench is walled along both its sides: %d vertical faces" % faces["vertical"])
	t.ok(faces["level"] > faces["vertical"],
		"with the ground either side of it still flat, not all wall")

	# The lip stays level rather than sagging toward the floor of the trench it is beside. That is
	# `corner_cm` refusing to average a neighbour it is cut off from, and it is what makes a
	# parapet read as an edge you can take cover behind.
	t.eq(EarthMesher.corner_cm(field, Vector2i(6, 4), Vector2i(1, 0)), 0,
		"a column beside the cut keeps its own height at the shared corner")
	t.eq(EarthMesher.corner_cm(field, Vector2i(7, 4), Vector2i(-1, 0)), -150,
		"and the column in the trench keeps its own, 150 cm below — the gap is the wall")


## And the other half of the same sentence: shell it, and it stops being a wall. Nothing switches
## mode; the terrain crossed the threshold and the mesher noticed.
func _a_slumped_trench_does_not(t: TestContext, world: Dictionary) -> void:
	var sharp := _faces(_mesh(_trench(world, 150), world))
	var slumped := _faces(_mesh(_trench(world, 60), world))
	t.ok(sharp["vertical"] > 0, "a steep cut is walled")
	t.eq(slumped["vertical"], 0, "and the same cut, slumped past the threshold, is not")
	t.ok(slumped["sloped"] > 0, "it is a bowl with sides instead: %d sloped faces" % slumped["sloped"])
	t.ok(not EarthMesher.connected(_trench(world, 150), Vector2i(6, 4), Vector2i(7, 4)),
		"which is one comparison against one number, and nothing else")


## Chunks are meshed one at a time, and the columns along a border need their neighbours to decide
## whether they are connected. A mesher that only saw its own chunk would put a seam at every
## border — invisible on flat ground, and a crack you can see through the moment somebody digs
## across one.
func _columns_agree_across_a_chunk_border(t: TestContext, world: Dictionary) -> void:
	var field := EarthField.flat(world["materials"], 0)
	# A ramp running straight through the border between chunk 0 and chunk 1.
	for z in 6:
		for x in range(28, 38):
			field.deposit(Vector2i(x, z), (x - 28) * 20)

	var last := Vector2i(EarthChunk.SIZE - 1, 3)      # last column of chunk 0
	var first := Vector2i(EarthChunk.SIZE, 3)          # first column of chunk 1
	t.eq(EarthGrid.chunk_of(last), Vector2i(0, 0), "the two columns really are in different chunks")
	t.eq(EarthGrid.chunk_of(first), Vector2i(1, 0), "one either side of the border")
	t.ok(EarthMesher.connected(field, last, first), "and on this ramp they are connected ground")
	# The corner they share: each computes it from its own neighbourhood, and on connected ground
	# they have to arrive at the same number or the two chunks' meshes do not meet.
	t.eq(EarthMesher.corner_cm(field, last, Vector2i(1, 1)),
		EarthMesher.corner_cm(field, first, Vector2i(-1, 1)),
		"they compute the same height for the corner they share, so the meshes meet exactly")


# ---------------------------------------------------------------- helpers

## A field with a two-cell trench cut across it, `depth` centimetres deep.
func _trench(world: Dictionary, depth: int) -> EarthField:
	var field := EarthField.flat(world["materials"], 0)
	for z in EarthChunk.SIZE + 2:
		for x in [7, 8]:
			field.carve(Vector2i(x, z - 1), depth)
	return field


func _mesh(field: EarthField, world: Dictionary) -> ArrayMesh:
	return EarthMesher.build(field, Vector2i.ZERO, world["palette"], world["materials"])


## Every triangle sorted by which way it faces. Level, vertical and sloped are the three the spec
## talks about, so they are the three counted.
func _faces(mesh: ArrayMesh) -> Dictionary:
	var out := {"total": 0, "level": 0, "vertical": 0, "sloped": 0, "up": 0}
	if mesh == null:
		return out
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, normals.size(), 3):
		var normal := normals[i]
		out["total"] += 1
		var tilt := rad_to_deg(normal.angle_to(Vector3.UP))
		if tilt < 1.0:
			out["level"] += 1
		elif tilt > 89.0:
			out["vertical"] += 1
		else:
			out["sloped"] += 1
		if normal.y > 0.0:
			out["up"] += 1
	return out


func _world() -> Dictionary:
	var palette := Palette.new()
	if not palette.load_core():
		return {}
	var materials := MaterialSet.new()
	if not materials.load_core(palette):
		return {}
	return {"palette": palette, "materials": materials}


## Which way a wall faces, which is not a detail: a skirt wound inside-out is a wall lit from
## within the earth, and it renders black. Six of the first eight were, and the screenshot showed
## a trench as a slab of dark grey — the geometry was right and the winding was not.
##
## The four skirt call sites hand their corners in in whatever order the top quad had them, so
## rather than four hand-checked orderings the wall is told which way it must face and flips itself
## if it disagrees. This is what says it still does.
func _walls_face_outward(t: TestContext, world: Dictionary) -> void:
	var field := EarthField.flat(world["materials"], 0)
	field.carve(Vector2i(5, 5), 150)          # one column dropped, so it is walled on all four sides
	var mesh := _mesh(field, world)
	if mesh == null:
		t.fail("a one-column hole produced no mesh")
		return

	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var hole := EarthGrid.centre_of(Vector2i(5, 5))
	var walls := 0
	var facing := 0
	for i in range(0, normals.size(), 3):
		if absf(normals[i].y) > 0.1:
			continue
		walls += 1
		var middle := (points[i] + points[i + 1] + points[i + 2]) / 3.0
		var toward := Vector3(hole.x - middle.x, 0.0, hole.y - middle.z).normalized()
		if normals[i].dot(toward) > 0.5:
			facing += 1

	t.eq(walls, 8, "a single dropped column is walled on all four sides, two triangles each")
	t.eq(facing, walls, "and every one of those faces into the hole rather than into the earth")
