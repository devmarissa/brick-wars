class_name HeightPatch
extends RefCounted
## A chunk's surface heights, read once. EARTH-SPEC §2, §9.
##
## Its own file because it is its own idea and because it is the answer to a measured problem rather
## than a tidy-up.
##
## ### The measurement
##
## Rebuilding one 32x32 chunk cost **45 ms** — and up to eight chunks can be rebuilt in a frame, so
## a collapse could stall for a third of a second. Marissa's words were *"the terrain updates are
## super laggy"*, and the first guess would have been the collision shape. That guess was wrong:
## collision was 2.7 ms a chunk and meshing was the other 42.
##
## The reason was reads. Every corner of every column asked the field for its own height and its
## three neighbours', and asked *again* to decide whether each neighbour was connected — about ten
## trips for one corner, forty for a column, forty thousand for a chunk. Each trip did chunk
## arithmetic, a dictionary lookup and a byte unpack, for a number that had already been fetched
## several times that millisecond.
##
## So the heights are fetched **once**, into a flat array, and everything downstream reads that.
## A chunk needs 36x36 of them: its own 32x32, plus a two-cell border, because a column on the edge
## has a neighbour outside the chunk and *that* neighbour's corners reach one further still.
##
## ### It is a snapshot, and that is fine
##
## Nothing writes to the field between a patch being taken and the mesh being finished — remeshing
## happens after the settle queue has moved its earth for the frame, which `EarthTerrain` is
## explicit about. A patch that outlived a frame would be a bug; one is built per rebuild and
## dropped.

## How far past the chunk the patch reaches. Two, not one: a column on the chunk's edge emits a
## skirt down to a neighbour outside it, and that neighbour's own corner heights average *its*
## neighbours — one more cell out again.
const BORDER := 2

var origin: Vector2i = Vector2i.ZERO   ## world cell of the patch's own (0, 0)
var span := 0                          ## cells per side, including both borders

var _height := PackedInt32Array()
var _corners := PackedInt32Array()


## Read the heights around a whole chunk.
static func around(field: EarthField, chunk: Vector2i) -> HeightPatch:
	return _read(field, chunk * EarthChunk.SIZE - Vector2i(BORDER, BORDER),
		EarthChunk.SIZE + BORDER * 2)


## Read the heights around a single column — the same thing at the smallest size that answers
## anything, so the one-cell API and the whole-chunk one share an implementation rather than being
## two copies of the same averaging rule that drift apart.
static func around_cell(field: EarthField, cell: Vector2i) -> HeightPatch:
	return _read(field, cell - Vector2i(BORDER, BORDER), 1 + BORDER * 2)


## The surface at a world cell, in centimetres. Outside the patch this falls back to the field,
## which is correct but is the slow path — a caller hitting it in a loop has the wrong patch.
func at(cell: Vector2i, field: EarthField = null) -> int:
	var local := cell - origin
	if local.x < 0 or local.y < 0 or local.x >= span or local.y >= span:
		return field.surface_cm(cell) if field != null else 0
	return _height[local.y * span + local.x]


## The four corner heights of a column, in `EarthMesher.CORNERS` order.
##
## A corner is the mean of the columns meeting there that this one is still *connected* to — within
## `EarthMesher.CLIFF_CM` of it. Two columns either side of a cliff therefore compute different
## answers for the same corner, and the gap between their answers is exactly the step the skirt
## fills. Two columns on open ground compute the same answer, so their quads meet with no seam.
##
## Written into a buffer the patch owns rather than returned fresh. Allocating a small array per
## column was itself a measurable part of the cost once the reads were fixed, and the value is
## consumed immediately by the one caller.
func corners_at(cell: Vector2i, cliff_cm: int) -> PackedInt32Array:
	if _corners.is_empty():
		_corners.resize(4)
	var mine := at(cell)
	for i in 4:
		var corner: Vector2i = EarthMesher.CORNERS[i]
		var total := mine
		var count := 1
		for offset in [Vector2i(corner.x, 0), Vector2i(0, corner.y), corner]:
			var other := at(cell + offset)
			if absi(mine - other) <= cliff_cm:
				total += other
				count += 1
		_corners[i] = total / count
	return _corners


static func _read(field: EarthField, from: Vector2i, side: int) -> HeightPatch:
	var patch := HeightPatch.new()
	patch.origin = from
	patch.span = side
	patch._height.resize(side * side)
	for z in side:
		var row := z * side
		for x in side:
			patch._height[row + x] = field.surface_cm(from + Vector2i(x, z))
	return patch
