class_name EarthChunk
extends RefCounted
## 32 × 32 cells of ground — 16 metres square — stored in three bytes a column. EARTH-SPEC §1, §9.
##
## The storage is the interesting part and it is doing three jobs at once, all of them stated as
## budgets in §9 rather than discovered later.
##
## **Two bytes of height, one of material, per column.** Heights are integer centimetres relative
## to the chunk's own base, held as `i16` — ±327 m of range, which is more than any map needs, and
## one centimetre is invisible while the arithmetic stays exact. GDScript has no `i16` array, so
## the two bytes are packed by hand into a `PackedByteArray`. That is deliberate rather than
## fussy: a `PackedInt32Array` would double the field's memory against §9's ~8 MB budget for an
## 800 m map, and the budget is the reason the resolution is affordable at all.
##
## **The material byte carries the `disturbed` flag in its top bit.** Thirty-three materials fit
## in seven bits with room to spare, and §4 wants one bit for dug-versus-virgin ground rather than
## a parallel set of loose materials. Three bytes a column, exactly as §9 says.
##
## **Multi-span columns live in a side table.** A typical column is one span, bedrock to surface,
## and the dense arrays describe exactly that. A column that has been tunnelled through holds its
## spans in `_extra` instead — sparse, because §6 caps them at four per column and they are rare.
## Nothing in C3 splits a span; the table is here so that when C3b does, it is a new case in code
## that already reads spans rather than a new shape for all of it.
##
## No floats anywhere. §5 stakes the whole netcode design on every client deriving identical
## slumping from the same events, which holds only while the arithmetic is exact.

const SIZE := 16
const CELLS := SIZE * SIZE

## `i16`, as two bytes. The range is the reason heights are chunk-relative rather than absolute:
## a map with a 40 m hill on it still stores centimetres near zero in every chunk.
const HEIGHT_MIN := -32768
const HEIGHT_MAX := 32767

## Seven bits of material index, one bit of `disturbed`. The index is into the field's palette,
## which is sorted, so the same content produces the same bytes on every machine.
const MATERIAL_MASK := 0x7F
const DISTURBED_BIT := 0x80
const MAX_MATERIAL := MATERIAL_MASK

## EARTH-SPEC §6. Enforced here as well as by the validator, because a runtime that trusts the
## validator is a runtime that breaks the day something builds a column another way.
const MAX_SPANS := 4

## Bytes per column, asserted rather than assumed — §9 lists it as a budget and this is what makes
## it a number somebody can check instead of an intention.
const BYTES_PER_COLUMN := 3

## Where this chunk sits, in chunks, and what its heights are measured from.
var at := Vector2i.ZERO
var base_cm := 0

## True when anything has changed since the last remesh. The mesher and the collision rebuild both
## read it; nothing here clears it.
var dirty := true

var _top := PackedByteArray()          ## two bytes a column, little-endian i16
var _material := PackedByteArray()     ## one byte a column: index | disturbed
var _extra: Dictionary = {}            ## cell index -> Array[EarthSpan], for tunnelled columns


## A chunk of solid ground: one span per column, bedrock to `surface_cm`, all of one material.
## `material_index` is into the field's palette rather than a name, because the palette is what
## makes the bytes reproducible.
static func flat(at_: Vector2i, base_cm_: int, surface_cm: int,
		material_index: int) -> EarthChunk:
	var chunk := EarthChunk.new()
	chunk.at = at_
	chunk.base_cm = base_cm_
	chunk._top.resize(CELLS * 2)
	chunk._material.resize(CELLS)
	for i in CELLS:
		chunk._write_height(i, surface_cm)
		chunk._material[i] = material_index & MATERIAL_MASK
	return chunk


## The index of a cell within this chunk. Callers pass chunk-local coordinates; the field is what
## knows about world space.
static func index_of(x: int, z: int) -> int:
	return z * SIZE + x


static func holds(x: int, z: int) -> bool:
	return x >= 0 and x < SIZE and z >= 0 and z < SIZE


## The surface, in centimetres relative to the chunk's base. The single most-asked question of the
## whole field, so it does not build a span to answer it.
func surface_cm(x: int, z: int) -> int:
	var i := index_of(x, z)
	if _extra.has(i):
		var spans: Array = _extra[i]
		return (spans[spans.size() - 1] as EarthSpan).top_cm
	return _read_height(i)


## Every span in a column, bottom first. The primitive the rest of the earth reads — meshing,
## collision, digging and slumping all go through this, so a tunnel is a longer array rather than
## a different code path.
##
## The common case builds its one span on demand rather than storing it. That costs an allocation
## per call and buys the three-bytes-a-column budget, which is the right way round: columns are
## read in bulk by the mesher, which wants spans, and stored in bulk by the field, which wants
## bytes.
func spans_at(x: int, z: int, palette: Array[StringName]) -> Array[EarthSpan]:
	var i := index_of(x, z)
	if _extra.has(i):
		var out: Array[EarthSpan] = []
		for span in _extra[i] as Array:
			out.append((span as EarthSpan).duplicated())
		return out
	var byte := _material[i]
	return [EarthSpan.make(HEIGHT_MIN, _read_height(i),
		_name_of(byte & MATERIAL_MASK, palette), (byte & DISTURBED_BIT) != 0)]


## Replace a column's surface, keeping its material. Returns what actually changed, in
## centimetres, which is what the event log records and what conservation of volume is measured
## against — a carve that hit the floor of the chunk moved less earth than it was asked to.
func set_surface_cm(x: int, z: int, height: int) -> int:
	var i := index_of(x, z)
	var was := surface_cm(x, z)
	var now := clampi(height, HEIGHT_MIN, HEIGHT_MAX)
	if now == was:
		return 0
	if _extra.has(i):
		var spans: Array = _extra[i]
		(spans[spans.size() - 1] as EarthSpan).top_cm = now
	else:
		_write_height(i, now)
	dirty = true
	return now - was


## Mark a column as dug. §4: one flag, applied on top of whatever the material says.
func set_disturbed(x: int, z: int, value: bool) -> void:
	var i := index_of(x, z)
	if _extra.has(i):
		var spans: Array = _extra[i]
		(spans[spans.size() - 1] as EarthSpan).disturbed = value
		dirty = true
		return
	var byte := _material[i]
	_material[i] = (byte | DISTURBED_BIT) if value else (byte & MATERIAL_MASK)
	dirty = true


func material_index(x: int, z: int) -> int:
	return _material[index_of(x, z)] & MATERIAL_MASK


func is_disturbed(x: int, z: int) -> bool:
	var i := index_of(x, z)
	if _extra.has(i):
		var spans: Array = _extra[i]
		return (spans[spans.size() - 1] as EarthSpan).disturbed
	return (_material[i] & DISTURBED_BIT) != 0


## How many columns in this chunk have been split. Zero for the whole of C3; the number exists so
## that when it stops being zero, the cost of it is visible rather than inferred.
func split_columns() -> int:
	return _extra.size()


func bytes_used() -> int:
	return _top.size() + _material.size()


## A rolling hash of the chunk's state, for §5's drift detection — two clients that have applied
## the same events must agree, and this is how a mismatch is *caught* rather than assumed away.
## It is also what makes determinism cheap to assert in a test: same events, same number.
##
## FNV-1a over the raw bytes, masked to 32 bits because GDScript integers are 64-bit and an
## unmasked rolling hash would drift into a different value on a machine that widened differently.
func rolling_hash() -> int:
	var hash := 2166136261
	for byte in _top:
		hash = ((hash ^ byte) * 16777619) & 0xFFFFFFFF
	for byte in _material:
		hash = ((hash ^ byte) * 16777619) & 0xFFFFFFFF
	# Split columns are rare and are hashed by their contents rather than their storage, so a
	# column that was split and re-merged back to one span hashes the same as one that never was.
	for i in ContentLoader.sorted_names(_extra.keys()):
		for span in _extra[int(String(i))] as Array:
			var s := span as EarthSpan
			for value in [s.bottom_cm, s.top_cm, 1 if s.disturbed else 0]:
				hash = ((hash ^ (int(value) & 0xFFFF)) * 16777619) & 0xFFFFFFFF
	return hash


func _read_height(i: int) -> int:
	var low := _top[i * 2]
	var high := _top[i * 2 + 1]
	var value := low | (high << 8)
	return value - 65536 if value > HEIGHT_MAX else value


func _write_height(i: int, cm: int) -> void:
	var value := clampi(cm, HEIGHT_MIN, HEIGHT_MAX)
	if value < 0:
		value += 65536
	_top[i * 2] = value & 0xFF
	_top[i * 2 + 1] = (value >> 8) & 0xFF


static func _name_of(index: int, palette: Array[StringName]) -> StringName:
	return palette[index] if index >= 0 and index < palette.size() else &""
