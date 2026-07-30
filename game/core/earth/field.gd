class_name EarthField
extends RefCounted
## The ground, as a grid of 0.5 m columns you can dig. EARTH-SPEC §1, §4.
##
## Twenty-five times the plan resolution of the prototype's 2.5 m grid, and — more importantly —
## continuous height instead of 0.8 m steps. §10 is blunt that the steps were more of the problem
## than the cell width: a single old cell was wider and taller than a soldier, which is why the
## terrain read as a pile of rectangles. A soldier is 3.6 cells tall and about 1.2 wide now, so
## the ground is finer than the thing standing on it.
##
## ### Everything here is integers
##
## Heights are centimetres, and no operation in this file produces a float. That is §5's design
## resting on §1's storage: slumping is never sent over the wire, because every client derives the
## same collapse from the same dig — which is true exactly as long as the arithmetic is exact. A
## float in the settle path costs a centimetre on one machine, then a metre, and nothing says so.
## `rolling_hash` is how a disagreement gets caught rather than assumed away.
##
## ### Digging is not deleting
##
## §4's rule, and it is what makes earth feel like a substance: material removed has to go
## somewhere. `carve` does not destroy volume, it *returns* it, and the caller has to put it
## somewhere — which is why cutting a trench raises a parapet out of its own spoil without anything
## deciding that it should. Ground that has been moved is marked `disturbed` and stands less
## steeply than the same shape cut from virgin clay.

## Half a metre, in centimetres. EARTH-SPEC §1.
const CELL_CM := 50
const CELL_M := 0.5

## Chunks are 32 × 32 cells, so 16 m. §9.
const CHUNK_CELLS := EarthChunk.SIZE

## What the field is made of when nobody has said otherwise. `loam` holds 38° — about 39 cm of
## step per cell — which is the middle of the soil range and the sane default for open ground.
const DEFAULT_MATERIAL := &"loam"

## How deep a fresh chunk's ground goes below its surface before it becomes bedrock nobody digs.
## Not a physical claim — bedrock is where the spans stop — but the number a chunk is born with.
const FLOOR_CM := -2000

var palette: Array[StringName] = []
var chunks: Dictionary = {}          ## Vector2i -> EarthChunk

var _surface_cm := 0
var _material_index := 0


## A field of one material, flat, with the palette that decides how materials pack into bytes.
##
## The palette is sorted, and that is what makes a chunk's bytes reproducible: two machines that
## loaded the same content produce the same indices, so §5's chunk hashes are comparable at all.
static func flat(materials: MaterialSet, surface_cm := 0,
		material := DEFAULT_MATERIAL) -> EarthField:
	var field := EarthField.new()
	field.palette = _palette_of(materials)
	field._surface_cm = surface_cm
	field._material_index = maxi(0, field.palette.find(material))
	return field


## Every material the field can be made of, in a stable order. Only `earth`-class materials can be
## ground — `MATERIAL-SPEC` §2 gives them the `angle_of_repose` the whole of §3 runs on, and a
## column of steel would have nothing to slump by.
static func _palette_of(materials: MaterialSet) -> Array[StringName]:
	return materials.names_in_class("earth")


# ---------------------------------------------------------------- world and cells

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


# ---------------------------------------------------------------- reading

## The chunk holding a cell, made on demand. The field is unbounded and empty chunks cost nothing
## until something asks about them, which is what lets a map be 800 m without allocating 800 m.
func chunk_for(cell: Vector2i, make := true) -> EarthChunk:
	var key := chunk_of(cell)
	if chunks.has(key):
		return chunks[key]
	if not make:
		return null
	var chunk := EarthChunk.flat(key, 0, _surface_cm, _material_index)
	chunks[key] = chunk
	return chunk


## The surface of a column, in absolute centimetres.
func surface_cm(cell: Vector2i) -> int:
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	return chunk.base_cm + chunk.surface_cm(local.x, local.y)


## Every span in a column, bottom first. The primitive; §2's mesher, §3's settle queue and §6's
## tunnels all read this rather than a height, so a split column is a longer array and not a
## different path through the code.
func spans_at(cell: Vector2i) -> Array[EarthSpan]:
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	var out := chunk.spans_at(local.x, local.y, palette)
	if chunk.base_cm != 0:
		for span in out:
			span.bottom_cm += chunk.base_cm
			span.top_cm += chunk.base_cm
	return out


## The surface in metres, for anything that thinks in metres — which is everything outside the
## earth system, including the foot planting that raycasts against it (§7).
func height_at(world_x: float, world_z: float) -> float:
	return surface_cm(cell_at(world_x, world_z)) * 0.01


func material_at(cell: Vector2i) -> StringName:
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	var index := chunk.material_index(local.x, local.y)
	return palette[index] if index < palette.size() else &""


func is_disturbed(cell: Vector2i) -> bool:
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	return chunk.is_disturbed(local.x, local.y)


## Set a column outright, for **generating** a map rather than digging one.
##
## Deliberately separate from `carve` and `deposit`, and deliberately not logged: this creates and
## destroys earth, which is exactly what §4 forbids of digging. A map is authored and then dug, and
## conflating the two would mean either a generator that has to conserve volume against ground that
## does not exist yet, or a dig path with a back door in it. Nothing calls this after the world is
## up.
func sculpt(cell: Vector2i, height_cm: int) -> void:
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	chunk.set_surface_cm(local.x, local.y, height_cm - chunk.base_cm)


# ---------------------------------------------------------------- digging

## Take earth out of a column, and hand it back rather than destroying it.
##
## §4's whole point: *"material removed has to go somewhere. Digging is not deletion."* The return
## value is the volume actually removed in column-centimetres — one centimetre of height over one
## cell — and it is not always what was asked for, because a cut can reach bedrock. A caller that
## ignores it has quietly deleted earth, which is the bug this signature exists to make awkward.
func carve(cell: Vector2i, depth_cm: int) -> int:
	if depth_cm <= 0:
		return 0
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	var was := chunk.surface_cm(local.x, local.y)
	var floor_cm := FLOOR_CM - chunk.base_cm
	var now := maxi(was - depth_cm, floor_cm)
	var moved := chunk.set_surface_cm(local.x, local.y, now)
	if moved != 0:
		chunk.set_disturbed(local.x, local.y, true)
	return -moved


## Put earth onto a column. The other half of `carve`, and the reason a trench comes with a
## parapet: the spoil has nowhere else to be.
##
## Deposited ground is `disturbed` by definition — it is loose, it stands 15° shallower, and §4
## says that rather than adding a parallel set of loose materials.
func deposit(cell: Vector2i, volume_cm: int) -> int:
	if volume_cm <= 0:
		return 0
	var chunk := chunk_for(cell)
	var local := local_of(cell)
	var moved := chunk.set_surface_cm(local.x, local.y,
		chunk.surface_cm(local.x, local.y) + volume_cm)
	if moved != 0:
		chunk.set_disturbed(local.x, local.y, true)
	return moved


# ---------------------------------------------------------------- accounting

## The sum of every column's surface height, in centimetres. Not a physical volume — the columns
## all reach the same bedrock, so it differs from one by a constant — which makes it exactly the
## right thing to assert conservation against: carve a hundred and deposit a hundred and this
## number comes back to where it started.
func surface_sum_cm() -> int:
	var total := 0
	for key in chunks:
		var chunk: EarthChunk = chunks[key]
		for z in EarthChunk.SIZE:
			for x in EarthChunk.SIZE:
				total += chunk.base_cm + chunk.surface_cm(x, z)
	return total


func dirty_chunks() -> int:
	var count := 0
	for key in chunks:
		if (chunks[key] as EarthChunk).dirty:
			count += 1
	return count


## One number for the whole field's state, for §5's drift reconciliation and for asserting that
## two runs of the same events agree. Chunks are folded in sorted order, because a dictionary's
## iteration order is not a promise and a hash that depended on it would report drift that was
## only ever a different insertion sequence.
func rolling_hash() -> int:
	var hash := 2166136261
	var keys: Array = chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for key in keys:
		var chunk: EarthChunk = chunks[key]
		for value in [key.x & 0xFFFF, key.y & 0xFFFF, chunk.rolling_hash()]:
			hash = ((hash ^ int(value)) * 16777619) & 0xFFFFFFFF
	return hash
