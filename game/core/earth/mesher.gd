class_name EarthMesher
extends RefCounted
## Turning columns into a surface — organic ground *and* vertical trench walls, from one field.
## EARTH-SPEC §2.
##
## The risk this file exists to avoid is stated in §2 and it is a real one: a smooth heightfield
## loses the crisp vertical trench wall, which would be a terrible trade in a game about digging
## in. So the mesh is **slope-dependent**, and which of the two you get is decided by the terrain
## rather than by an authoring mode:
##
## - Neighbouring columns within the cliff threshold are **connected**: they share a corner height,
##   the surface runs continuously between them, and normals are smoothed across the join. Open
##   ground, crater bowls, spoil heaps and shell-churned mud come out genuinely curved.
## - Neighbours past it are **broken**: each keeps its own height at the shared corner, which opens
##   a vertical gap, and a skirt fills it with flat normals. Trench walls, parapets, cut faces and
##   dugout entrances stay sharp.
##
## §2's own sentence for why that matters: *"Dig a trench and it has vertical walls because you cut
## it steeply; shell that trench and the walls slump past 60° and it becomes an organic churned
## bowl. The transition between those two states is the game."*
##
## ### How a column becomes geometry
##
## Each column emits a quad whose four corners sit at its diagonal midpoints — a quarter of a cell
## in each direction. A corner's height is the mean of the columns meeting there that this column
## is still *connected* to. Where everything is connected that is the same value every neighbour
## computes, so the surface is continuous with no seam and no special case. Where a cliff cuts a
## neighbour out of the average, the two columns disagree about the corner by exactly the height of
## the step, and that disagreement is the wall.
##
## Corner heights are the one place this file leaves integer centimetres, because a mean of four is
## a mean of four. Nothing derived from it feeds back into the field — the mesh is an output — so
## §5's determinism argument is untouched.

## 60°, as the height step between neighbouring column centres that counts as a cliff. §2 gives the
## angle; the cells are 0.5 m apart, so `tan(60°) × 50 cm` is 87 cm. Stated as centimetres because
## the comparison happens against integer heights and a trigonometric call per edge per frame would
## be a strange way to spend a budget.
const CLIFF_CM := 87

## A quarter of a cell, in metres — half the distance between column centres, which is where one
## column's top stops and its neighbour's begins.
const HALF_CELL := EarthField.CELL_M * 0.5

## The four corners of a column's top, as diagonal offsets in cells. Order matters: it is the
## winding of the quad, and Godot 4 winds front faces clockwise (`case_geometry.gd` measures this
## rather than trusting anybody's memory).
const CORNERS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

## Per-vertex colour variation, ART-BIBLE §6b — the same trick brickwork uses, so ground reads as
## non-uniform and hand-mixed without a texture and without a grid. Seeded off the cell so it is
## stable: terrain that shimmered when a chunk remeshed would be worse than no variation at all.
const SHADE_RANGE := 0.06


## Build one chunk's surface. Takes the field rather than the chunk because the columns along a
## chunk's far edge need their neighbours to decide whether they are connected, and those live in
## the chunk next door — a mesher that only saw its own chunk would put a seam at every border and
## the seams would move when the ground was dug.
static func build(field: EarthField, chunk: Vector2i, palette: Palette,
		materials: MaterialSet) -> ArrayMesh:
	var origin := chunk * EarthChunk.SIZE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()

	for z in EarthChunk.SIZE:
		for x in EarthChunk.SIZE:
			var cell := origin + Vector2i(x, z)
			_column(field, cell, palette, materials, vertices, normals, colours)

	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Whether two columns are part of one surface or are a wall. The whole of §2's decision, in one
## comparison against one number.
static func connected(field: EarthField, a: Vector2i, b: Vector2i) -> bool:
	return absi(field.surface_cm(a) - field.surface_cm(b)) <= CLIFF_CM


## A corner's height for one column, in centimetres: the mean of the columns meeting there that
## this one is still connected to.
##
## Two columns either side of a cliff compute different answers for the same corner, and that is
## deliberate — the gap between their answers is exactly the step, and the skirt fills it. Two
## columns on open ground compute the same answer, so their quads meet exactly and the surface has
## no seam in it.
static func corner_cm(field: EarthField, cell: Vector2i, corner: Vector2i) -> int:
	var total := field.surface_cm(cell)
	var count := 1
	# The three other columns meeting at this corner: the two orthogonal neighbours and the
	# diagonal. A neighbour cut off by a cliff contributes nothing, which is what keeps a trench
	# lip flat instead of sagging toward the floor of its own trench.
	var around: Array[Vector2i] = [Vector2i(corner.x, 0), Vector2i(0, corner.y), corner]
	for offset in around:
		var other := cell + offset
		if connected(field, cell, other):
			total += field.surface_cm(other)
			count += 1
	return total / count


static func _column(field: EarthField, cell: Vector2i, palette: Palette, materials: MaterialSet,
		vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray) -> void:
	var centre := EarthField.centre_of(cell)
	var top: Array[Vector3] = []
	for corner in CORNERS:
		var corner_v: Vector2i = corner
		top.append(Vector3(
			centre.x + corner_v.x * HALF_CELL,
			corner_cm(field, cell, corner_v) * 0.01,
			centre.y + corner_v.y * HALF_CELL))

	var base := _colour_of(field, cell, palette, materials)
	# One shade per *vertex*, not per column (ART-BIBLE §6b). Keyed on the corner's own position in
	# half-cells, so the four columns meeting at a corner all compute the same shade for it and the
	# variation reads as mixed ground rather than as a chequerboard of 0.5 m tiles — which is
	# exactly what per-column shading looked like.
	var tint: Array[Color] = []
	for corner in CORNERS:
		tint.append(_shaded(base, cell * 2 + (corner as Vector2i)))
	_quad(top[0], top[1], top[2], top[3], tint, Vector3.ZERO, vertices, normals, colours)

	# A skirt to each of the two neighbours this column looks *down* on. Only two of the four, and
	# only downhill: the uphill neighbour emits the other side of the same wall, so a wall built
	# from both sides would be doubled and z-fight along its whole length.
	_skirt(field, cell, Vector2i(1, 0), top[1], top[2], base, vertices, normals, colours)
	_skirt(field, cell, Vector2i(0, 1), top[3], top[2], base, vertices, normals, colours)
	_skirt(field, cell, Vector2i(-1, 0), top[3], top[0], base, vertices, normals, colours)
	_skirt(field, cell, Vector2i(0, -1), top[0], top[1], base, vertices, normals, colours)


## The vertical face between a column and a lower neighbour. Flat normals, because a trench wall
## that shaded like a curved surface would read as a slope however vertical its geometry was.
static func _skirt(field: EarthField, cell: Vector2i, toward: Vector2i, a: Vector3, b: Vector3,
		colour: Color, vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray) -> void:
	var other := cell + toward
	if connected(field, cell, other):
		return
	var below := field.surface_cm(other)
	if below >= field.surface_cm(cell):
		return                                  # the uphill side emits this wall, not this one

	# Down to the neighbour's own corner heights, so the foot of the wall meets the floor of the
	# trench exactly rather than at the neighbour's centre height.
	var foot_a := Vector3(a.x, corner_cm(field, other, -toward + Vector2i(toward.y, toward.x)) * 0.01, a.z)
	var foot_b := Vector3(b.x, corner_cm(field, other, -toward - Vector2i(toward.y, toward.x)) * 0.01, b.z)
	foot_a.y = mini(int(foot_a.y * 100.0), below) * 0.01
	foot_b.y = mini(int(foot_b.y * 100.0), below) * 0.01
	# Wound to face the neighbour it looks down on. The four call sites hand their corners in in
	# whatever order the top quad had them, and half of them come out inside-out — which renders as
	# a wall lit from within the earth, i.e. black. Rather than four hand-checked orderings, the
	# wall is told which way it must face and `_quad` flips itself if it disagrees.
	var facing := Vector3(toward.x, 0.0, toward.y)
	var wall := colour.darkened(0.08)
	_quad(a, b, foot_b, foot_a, [wall, wall, wall, wall] as Array[Color], facing,
		vertices, normals, colours)


## Two triangles, wound so the front face points out, with one flat normal for the pair. Godot 4
## winds front faces clockwise: for triangle `a, b, c` the outward normal is `(c - a) × (b - a)`.
static func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Array[Color],
		facing: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.length_squared() < 0.5:
		return                                  # degenerate: a wall of no height
	# `facing` is the direction this face is supposed to point. Given one, a quad that came out
	# inside-out swaps its diagonal rather than being reordered at the call site.
	if facing.length_squared() > 0.0 and normal.dot(facing) < 0.0:
		var swap := b
		b = d
		d = swap
		var swap_tint := tint[1]
		tint = [tint[0], tint[3], tint[2], swap_tint] as Array[Color]
		normal = (c - a).cross(b - a).normalized()
	var order := [0, 1, 2, 0, 2, 3]
	var points := [a, b, c, a, c, d]
	for i in 6:
		vertices.append(points[i])
		normals.append(normal)
		colours.append(tint[order[i]])


## The span's material colour, with ART-BIBLE §6b's per-vertex variation folded in. Seeded off the
## cell so a chunk remeshed after a dig comes back the same shade it was.
static func _colour_of(field: EarthField, cell: Vector2i, palette: Palette,
		materials: MaterialSet) -> Color:
	var material := field.material_at(cell)
	var base := palette.colour(StringName(String(materials.get_def(material).get("colour", ""))))
	if field.is_disturbed(cell):
		# Dug ground reads darker and flatter — it is loose, it holds water, and §4 already says it
		# behaves differently. Costing it a shade makes spoil visible before anybody stands on it.
		return Color(base.r * 0.92, base.g * 0.92, base.b * 0.92)
	return base


## One corner's shade. Keyed on the corner rather than the column so that the four columns meeting
## there agree, which is the difference between mixed ground and a tiled floor.
static func _shaded(base: Color, corner_key: Vector2i) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(corner_key)
	var shade := 1.0 + rng.randf_range(-SHADE_RANGE, SHADE_RANGE)
	return Color(base.r * shade, base.g * shade, base.b * shade)
