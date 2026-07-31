class_name EarthRepose
extends RefCounted
## How steep a face of a given soil will stand, as a whole number of centimetres per cell.
## EARTH-SPEC §3, MATERIAL-SPEC §5.
##
## §3's rule in one line: cut a face shallower than the material's angle of repose and it stands
## indefinitely; cut it steeper and it slumps until it doesn't. That is the difference between sand
## — useless to build with at 30° — and the chalk the Great War tunnelled through at 65°, and it
## costs one number per material that the material file already carries.
##
## ### Why this is a table and not a call to `tan`
##
## The comparison happens per cell per neighbour per settle tick, up to 512 cells a frame, so a
## trigonometric call would be a strange way to spend a budget. It is also the wrong *kind* of
## arithmetic: §5 stakes the netcode on every client deriving identical slumping from the same
## events, and identical means bit-for-bit. `tan()` is a float, and a float that differs in its last
## place on one machine puts a centimetre of earth somewhere else, then a metre, and nothing says
## so. So the angles — whole degrees, which is how `MATERIAL-SPEC` §5 states them — are turned into
## whole centimetres once, at load, and everything downstream is integer comparison.

## The distance between column centres, which is what an angle is a slope *over*.
const RUN_CM := EarthField.CELL_CM

## Diagonal neighbours are √2 further apart, so they may hold a proportionally bigger step before
## the face is as steep. As a rational rather than a float, for the reason above: 1414/1000 is
## exact on every machine and `sqrt(2.0)` is not quite.
const DIAGONAL_NUM := 1414
const DIAGONAL_DEN := 1000

## Nothing stands on nothing, and nothing needs to stand past vertical.
const MIN_DEGREES := 1
const MAX_DEGREES := 89

## What a material with no `angle_of_repose` is treated as. Loam's 38° — the middle of the soil
## range — because a missing angle is a data gap rather than a claim that the stuff is frictionless.
const DEFAULT_DEGREES := 38

static var _table: PackedInt32Array = PackedInt32Array()


## The most a face may step between two orthogonally adjacent columns and still stand, in whole
## centimetres. Built once and remembered.
static func step_cm(degrees: int) -> int:
	if _table.is_empty():
		_build()
	return _table[clampi(degrees, 0, MAX_DEGREES + 1)]


## The same for a diagonal neighbour, which is further away and so holds more.
static func diagonal_step_cm(degrees: int) -> int:
	return step_cm(degrees) * DIAGONAL_NUM / DIAGONAL_DEN


## What a column's surface will stand at: the material's angle, less the penalty for having been
## dug. §4 gives spoil repose −15°, which is why a parapet thrown up from a trench slumps in weather
## that the trench wall opposite shrugs off.
static func for_column(field: EarthField, cell: Vector2i, materials: MaterialSet) -> int:
	# Revetment wins outright rather than adding to the soil: a sandbag facing holds a wall at the
	# angle the facing holds, and what is behind it stops being the question. Taking it away drops
	# straight back to what the earth can do on its own, which is how a wall comes down when its
	# shoring burns.
	var held := field.shoring_at(cell)
	if held > 0:
		return clampi(held, MIN_DEGREES, MAX_DEGREES)
	var degrees := degrees_of(materials, field.material_at(cell))
	if field.is_disturbed(cell):
		degrees -= EarthSpan.DISTURBED_REPOSE_PENALTY
	return clampi(degrees, MIN_DEGREES, MAX_DEGREES)


static func degrees_of(materials: MaterialSet, material: StringName) -> int:
	var def := materials.get_def(material)
	return int(def.get("angle_of_repose", DEFAULT_DEGREES))


## `tan(degrees) × the distance between columns`, in whole centimetres, for every angle a material
## can have. Done once so the settle loop never touches a float.
static func _build() -> void:
	_table.resize(MAX_DEGREES + 2)
	for degrees in _table.size():
		if degrees < MIN_DEGREES:
			_table[degrees] = 0
		else:
			_table[degrees] = int(round(tan(deg_to_rad(mini(degrees, MAX_DEGREES))) * RUN_CM))
