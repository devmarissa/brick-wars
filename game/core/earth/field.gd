class_name EarthField
extends RefCounted
## The ground, as a grid of 0.5 m columns you can dig. EARTH-SPEC §1, §4, §8.
##
## Where a cell *is* — world space, chunk indices, the 0.5 m plan grid — is `EarthGrid`. This is
## what is in it.
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

## What the field is made of when nobody has said otherwise. `loam` holds 38° — about 39 cm of
## step per cell — which is the middle of the soil range and the sane default for open ground.
const DEFAULT_MATERIAL := &"loam"

## How deep a fresh chunk's ground goes below its surface before it becomes bedrock nobody digs.
## Not a physical claim — bedrock is where the spans stop — but the number a chunk is born with.
const FLOOR_CM := -2000

## Lower than any map's bedrock: a water table nobody has set is one nothing can reach.
const NO_WATER := -100000

var palette: Array[StringName] = []
var chunks: Dictionary = {}          ## Vector2i -> EarthChunk

## The map's water table, in absolute centimetres. EARTH-SPEC §8.
##
## A level and a fill rule, and deliberately not a simulation: §8 is explicit that *"a level, a fill
## rule and a wetness multiplier get 90% of the feel for 5% of the work"*, and that full water
## simulation is out of scope. Dig below it and the hole fills; what fills is not tracked as
## volume, because there is nothing interesting to say about where it came from.
##
## `NO_WATER` is a level far below any map's bedrock, which is what a map with a water table
## nobody has set means.
var water_cm := NO_WATER

## Where modifications are written down, or null for a field nobody is recording. EARTH-SPEC §5.
##
## **Only actions are logged, never slumping.** That distinction is the whole saving §5 is built
## on: the server sends the dig and every client derives the collapse itself, so a log that
## recorded the settle queue's moves would send the one thing that never needs sending — and would
## then apply it twice on replay, once from the events and once from the settling they cause.
var log: EarthLog = null

# The most recently touched chunk, so a run of reads inside one chunk costs a comparison rather
# than a hash. Invalidated by nothing on purpose: chunks are never removed, so a remembered one
# cannot go stale — and if removal ever arrives, this is the line that has to hear about it.
var _recent: EarthChunk = null
var _recent_key := Vector2i(2147483647, 2147483647)

## The tick modifications are stamped with. Bumped by whatever owns the simulation.
var tick := 0

## Cells whose face is held by revetment, and the angle it holds them at. EARTH-SPEC §3.
##
## Sparse, because shoring is rare and deliberate: a few hundred cells along the walls of a trench
## somebody built, against a map of millions. Timber, wattle, sandbag facing and corrugated sheet
## all do the same thing here — they let a wall stand steeper than the soil ever would — and taking
## the revetment away lifts the override, wakes the settle queue, and brings the wall down. §3 calls
## that "a genuine loop: trenches need maintenance, and destroying revetment is worth doing."
var shoring: Dictionary = {}         ## Vector2i -> whole degrees

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


# ---------------------------------------------------------------- reading

## The chunk holding a cell, made on demand. The field is unbounded and empty chunks cost nothing
## until something asks about them, which is what lets a map be 800 m without allocating 800 m.
func chunk_for(cell: Vector2i, make := true) -> EarthChunk:
	var key := EarthGrid.chunk_of(cell)
	# The chunk we looked at last, remembered. Every caller that matters reads in a run — the mesher
	# walks a chunk column by column, the settle queue works a neighbourhood — so the same chunk
	# comes back thousands of times before a different one does, and each of those was a dictionary
	# hash. Measured at C4b: this is on the path that was costing 45 ms per chunk rebuild.
	if key == _recent_key and _recent != null:
		return _recent
	if chunks.has(key):
		_recent_key = key
		_recent = chunks[key]
		return _recent
	if not make:
		return null
	var chunk := EarthChunk.flat(key, 0, _surface_cm, _material_index)
	chunks[key] = chunk
	_recent_key = key
	_recent = chunk
	return chunk


## The surface of a column, in absolute centimetres.
##
## Reads never allocate. That is not an optimisation, it is a correctness rule: the settle queue
## asks every cell about its eight neighbours, so a read that made a chunk would have the earth
## growing 3 kB every time something looked over the edge of the world — and, worse, would change
## the field's rolling hash by being *observed*. A cell in a chunk nobody has touched is the ground
## the field was made of, which is exactly what an unallocated chunk means.
func surface_cm(cell: Vector2i) -> int:
	var chunk := chunk_for(cell, false)
	if chunk == null:
		return _surface_cm
	var local := EarthGrid.local_of(cell)
	return chunk.base_cm + chunk.surface_cm(local.x, local.y)


## Every span in a column, bottom first. The primitive; §2's mesher, §3's settle queue and §6's
## tunnels all read this rather than a height, so a split column is a longer array and not a
## different path through the code.
func spans_at(cell: Vector2i) -> Array[EarthSpan]:
	var chunk := chunk_for(cell, false)
	if chunk == null:
		return [EarthSpan.make(EarthChunk.HEIGHT_MIN, _surface_cm,
			palette[_material_index] if _material_index < palette.size() else &"")]
	var local := EarthGrid.local_of(cell)
	var out := chunk.spans_at(local.x, local.y, palette)
	if chunk.base_cm != 0:
		for span in out:
			span.bottom_cm += chunk.base_cm
			span.top_cm += chunk.base_cm
	return out


## The surface in metres, for anything that thinks in metres — which is everything outside the
## earth system, including the foot planting that raycasts against it (§7).
func height_at(world_x: float, world_z: float) -> float:
	return surface_cm(EarthGrid.cell_at(world_x, world_z)) * 0.01


func material_at(cell: Vector2i) -> StringName:
	var chunk := chunk_for(cell, false)
	var index := _material_index
	if chunk != null:
		var local := EarthGrid.local_of(cell)
		index = chunk.material_index(local.x, local.y)
	return palette[index] if index < palette.size() else &""


func is_disturbed(cell: Vector2i) -> bool:
	var chunk := chunk_for(cell, false)
	if chunk == null:
		return false
	var local := EarthGrid.local_of(cell)
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
	var local := EarthGrid.local_of(cell)
	chunk.set_surface_cm(local.x, local.y, height_cm - chunk.base_cm)


## Hold a cell's face at a steeper angle than its soil would. Returns whether anything changed, so
## a caller can decide whether to wake the settle queue rather than waking it unconditionally.
func shore(cell: Vector2i, degrees: int) -> bool:
	var was := int(shoring.get(cell, 0))
	if was == degrees:
		return false
	if degrees <= 0:
		shoring.erase(cell)
	else:
		shoring[cell] = degrees
	return true


## Take the revetment away. The wall does not fall here — it falls when the settle queue next looks
## at it, which is the difference between a collapse and a deletion.
func unshore(cell: Vector2i) -> bool:
	return shore(cell, 0)


## The angle revetment holds this cell at, or 0 for bare earth.
func shoring_at(cell: Vector2i) -> int:
	return int(shoring.get(cell, 0))


## Whether this column's surface is under water.
func is_flooded(cell: Vector2i) -> bool:
	return surface_cm(cell) < water_cm


## How deep the water is over a column, in centimetres, or 0 for dry ground.
func flood_depth_cm(cell: Vector2i) -> int:
	return maxi(0, water_cm - surface_cm(cell))


# ---------------------------------------------------------------- digging

## Take earth out of a column, and hand it back rather than destroying it.
##
## §4's whole point: *"material removed has to go somewhere. Digging is not deletion."* The return
## value is the volume actually removed in column-centimetres — one centimetre of height over one
## cell — and it is not always what was asked for, because a cut can reach bedrock. A caller that
## ignores it has quietly deleted earth, which is the bug this signature exists to make awkward.
## `record` is false when the caller is the settle queue rather than somebody digging — see `log`.
func carve(cell: Vector2i, depth_cm: int, record := true) -> int:
	if depth_cm <= 0:
		return 0
	var chunk := chunk_for(cell)
	var local := EarthGrid.local_of(cell)
	var was := chunk.surface_cm(local.x, local.y)
	var floor_cm := FLOOR_CM - chunk.base_cm
	var now := maxi(was - depth_cm, floor_cm)
	var moved := chunk.set_surface_cm(local.x, local.y, now)
	if moved != 0:
		chunk.set_disturbed(local.x, local.y, true)
		if record and log != null:
			log.record(tick, 0, EarthLog.CARVE, cell, moved)
	return -moved


## Put earth onto a column. The other half of `carve`, and the reason a trench comes with a
## parapet: the spoil has nowhere else to be.
##
## Deposited ground is `disturbed` by definition — it is loose, it stands 15° shallower, and §4
## says that rather than adding a parallel set of loose materials.
func deposit(cell: Vector2i, volume_cm: int, record := true) -> int:
	if volume_cm <= 0:
		return 0
	var chunk := chunk_for(cell)
	var local := EarthGrid.local_of(cell)
	var moved := chunk.set_surface_cm(local.x, local.y,
		chunk.surface_cm(local.x, local.y) + volume_cm)
	if moved != 0:
		chunk.set_disturbed(local.x, local.y, true)
		if record and log != null:
			log.record(tick, 0, EarthLog.DEPOSIT, cell, moved)
	return moved
