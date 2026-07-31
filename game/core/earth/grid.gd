class_name EarthGrid
extends RefCounted
## Where things are: the 0.5 m plan grid, and the arithmetic between world space, cells and chunks.
## EARTH-SPEC §1, §9.
##
## Pure geometry, no state, every function static. It is its own file because it is its own thing —
## `EarthField` is the earth *in* this grid, and `EarthMesher`, `EarthRepose` and the demo world all
## need to talk about cells without holding any ground. Splitting it also settled a question the
## 300-line cap asked: the field had grown a water table and a shoring register on top of digging
## and hashing, and the coordinate system was the one part of it that was not about earth at all.
##
## The one decision worth restating: **columns are addressed by their centres.** §2 meshes between
## column centres, so a cell that started at its corner would make every triangle a half-cell
## correction somebody has to remember.

## Half a metre, in centimetres. EARTH-SPEC §1.
const CELL_CM := 50
const CELL_M := 0.5

## Chunks are 32 × 32 cells, so 16 m. §9.
const CHUNK_CELLS := EarthChunk.SIZE


## The cell a world position is over. Columns are addressed by their centres, so the cell at
## (0, 0) is centred on the origin rather than starting there — which is what makes meshing
## between column centres (§2) a statement about the grid rather than a half-cell correction.
static func cell_at(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(roundi(world_x / CELL_M), roundi(world_z / CELL_M))


## Where a cell's centre is in the world, on the XZ plane.
static func centre_of(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_M, cell.y * CELL_M)


static func chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_CELLS), floori(float(cell.y) / CHUNK_CELLS))


static func local_of(cell: Vector2i) -> Vector2i:
	return Vector2i(posmod(cell.x, CHUNK_CELLS), posmod(cell.y, CHUNK_CELLS))
