extends TestCase
## The column-span field: storage, digging, and the two claims the rest of C3 is built on.
## EARTH-SPEC §1, §4, §5.
##
## Two of the assertions here are load-bearing for the whole milestone and the rest are arithmetic
## around them.
##
## **Volume is conserved.** §4: *"material removed has to go somewhere. Digging is not deletion."*
## That is what makes a trench come with a parapet made of its own spoil, without anything having
## decided that it should, and it is the difference between digging feeling like work and feeling
## like a subtract brush.
##
## **The arithmetic is exact.** §5 stakes the netcode on it: slumping is never sent over the wire,
## because every client derives the same collapse from the same dig. That holds only while nothing
## in the path produces a float. There is no way to test "no floats" directly, so what is tested is
## the property that would break — the same events applied twice give byte-identical state — and
## `rolling_hash` is what makes it cheap to say.
##
## Nothing here is meshed or drawn. `TestGround` remains the suite's analytic surface, deliberately:
## every rig case asserts exact numbers against `TestGround.height_at` worked out by hand, and
## re-baselining them onto a surface nobody can compute with a pencil would trade a real property
## for a moving one. The real field replaces `TestGround` in the *sandbox*, not in the tests.

const EPSILON := 0.0001


func case_name() -> String:
	return "earth field"


func run(t: TestContext) -> void:
	var materials := _materials()
	if materials == null:
		t.fail("core materials would not load, so nothing below means anything")
		return

	_cells_and_chunks(t)
	_storage(t, materials)
	_spans_from_the_first_line(t, materials)
	_digging_conserves_volume(t, materials)
	_the_same_events_give_the_same_ground(t, materials)


## The grid, before any ground exists. Columns are addressed by their centres — §2 meshes between
## column centres, so a cell that started at its corner would make every triangle a half-cell
## correction somebody has to remember.
func _cells_and_chunks(t: TestContext) -> void:
	t.eq(EarthField.cell_at(0.0, 0.0), Vector2i(0, 0), "the origin is the centre of cell zero")
	t.eq(EarthField.cell_at(0.24, 0.0), Vector2i(0, 0), "and a point inside that cell is in it")
	t.eq(EarthField.cell_at(0.26, 0.0), Vector2i(1, 0), "past the halfway line it is the next one")
	t.eq(EarthField.cell_at(-0.26, 0.0), Vector2i(-1, 0), "which works the same way going negative")
	t.eq(EarthField.centre_of(Vector2i(3, -2)), Vector2(1.5, -1.0), "and a cell knows its own centre")

	# 32 cells to a chunk, and the negative side is where an off-by-one hides: `floor` and `posmod`
	# rather than integer division, which truncates toward zero and would put cells -1 and 0 in the
	# same chunk.
	t.eq(EarthField.chunk_of(Vector2i(0, 0)), Vector2i(0, 0), "cell zero is in chunk zero")
	t.eq(EarthField.chunk_of(Vector2i(31, 31)), Vector2i(0, 0), "and so is the far corner of it")
	t.eq(EarthField.chunk_of(Vector2i(32, 0)), Vector2i(1, 0), "the next cell along starts a chunk")
	t.eq(EarthField.chunk_of(Vector2i(-1, -1)), Vector2i(-1, -1),
		"and the cell before the origin is in the chunk before it, not in chunk zero")
	t.eq(EarthField.local_of(Vector2i(-1, -1)), Vector2i(31, 31),
		"landing at the far corner of that chunk rather than at a negative index")


## Three bytes a column, which §9 lists as a budget and this makes a number somebody can check.
func _storage(t: TestContext, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0)
	t.ok(field.palette.size() > 5,
		"the field's palette is the earth materials: %s" % [", ".join(field.palette)])
	t.ok(not field.palette.has(&"steel"), "and only those — a column of steel has no repose angle")

	var chunk := EarthChunk.flat(Vector2i.ZERO, 0, 120, 0)
	t.eq(chunk.bytes_used(), EarthChunk.CELLS * EarthChunk.BYTES_PER_COLUMN,
		"a chunk is three bytes a column: two of height and one of material")
	t.eq(chunk.bytes_used(), 3072, "which for 32 x 32 is 3 kB — 8 MB for an 800 m map (§9)")

	# `i16`, packed by hand because GDScript has no such array. The negative side is the half that
	# a hand-rolled encoding gets wrong, and the ends are where it wraps.
	for height in [0, 1, -1, 327, -2000, EarthChunk.HEIGHT_MAX, EarthChunk.HEIGHT_MIN]:
		chunk.set_surface_cm(4, 7, height)
		t.eq(chunk.surface_cm(4, 7), height, "a column stores %d cm and reads it back" % height)

	chunk.set_surface_cm(4, 7, 0)
	t.ok(not chunk.is_disturbed(4, 7), "virgin ground is not disturbed")
	chunk.set_disturbed(4, 7, true)
	t.ok(chunk.is_disturbed(4, 7), "and dug ground is")
	t.eq(chunk.material_index(4, 7), 0,
		"with the flag living in the top bit of the material byte, not costing a fourth byte")


## `spans_at` is the primitive from the first line, and §1 says why: *"retrofitting spans onto a
## flat heightfield is a rewrite."* Nothing splits a column until C3b — so this is the assertion
## that keeps the shape honest while the reason for it is still a milestone away.
func _spans_from_the_first_line(t: TestContext, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 150, &"clay")
	var spans := field.spans_at(Vector2i(2, 3))
	t.eq(spans.size(), 1, "a typical column is one span, bedrock to surface")
	t.eq(spans[0].top_cm, 150, "topping out at the surface")
	t.eq(spans[0].material, &"clay", "made of what the field was made of")
	t.ok(spans[0].is_sane(), "and a sane span, with a top above its bottom")
	t.eq(field.surface_cm(Vector2i(2, 3)), 150, "which is what the surface shortcut says too")
	t.near(field.height_at(1.0, 1.5), 1.5, EPSILON, "and in metres, for everything outside the earth")

	# The `disturbed` flag is a property of the span rather than of the column, which is what lets
	# spoil sitting on virgin ground behave differently from the ground under it once §6 splits
	# them apart.
	var virgin := EarthSpan.make(-100, 0, &"clay")
	var spoil := EarthSpan.make(0, 40, &"clay", true)
	t.eq(virgin.repose_degrees(55), 55, "undisturbed clay stands at its own 55 degrees")
	t.eq(spoil.repose_degrees(55), 40, "and the same clay, dug and dumped, stands at 40 (§4)")
	t.eq(spoil.thickness_cm(), 40, "with the span knowing its own thickness")


## §4, and the reason a trench comes with a parapet.
func _digging_conserves_volume(t: TestContext, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0)
	var before := field.surface_sum_cm()

	# Cut a trench and pile every centimetre of it on the cell beside the cut. Nothing decides
	# that a parapet should appear; it appears because the earth had nowhere else to be.
	var spoil := 0
	for z in 6:
		spoil += field.carve(Vector2i(4, z), 60)
	t.eq(spoil, 6 * 60, "cutting six cells 60 cm deep yields exactly that much spoil")
	for z in 6:
		field.deposit(Vector2i(5, z), spoil / 6)

	t.eq(field.surface_sum_cm(), before, "and the ground has exactly as much earth in it as before")
	t.eq(field.surface_cm(Vector2i(4, 0)), -60, "the trench is 60 cm deep")
	t.eq(field.surface_cm(Vector2i(5, 0)), 60, "and the parapet beside it is 60 cm high")
	t.ok(field.is_disturbed(Vector2i(4, 0)), "the cut face is disturbed ground")
	t.ok(field.is_disturbed(Vector2i(5, 0)), "and so is the spoil heap, which is why it stands less steeply")

	# A cut that reaches bedrock moves less earth than it was asked for, and says so. A caller that
	# assumed it got what it asked for would have quietly created earth out of nothing.
	var deep := field.carve(Vector2i(9, 9), 999999)
	t.eq(deep, -EarthField.FLOOR_CM, "a cut to bedrock yields what was actually there, not what was asked")
	t.eq(field.carve(Vector2i(9, 9), 100), 0, "and cutting bedrock again yields nothing at all")
	t.eq(field.carve(Vector2i(1, 1), -50), 0, "a negative depth is not a deposit in disguise")


## §5's claim, tested as the property that would break if it were false. Two fields, the same
## events, identical state — which is what lets the server send a dig and let every client work
## out the collapse for itself.
func _the_same_events_give_the_same_ground(t: TestContext, materials: MaterialSet) -> void:
	var log := EarthLog.new()
	for i in 40:
		log.record(i, 1, EarthLog.CARVE, Vector2i(i % 7, i % 5), 20 + i)
		log.record(i, 1, EarthLog.DEPOSIT, Vector2i(i % 5, i % 7), 12 + i)

	var first := EarthField.flat(materials, 0)
	var second := EarthField.flat(materials, 0)
	t.eq(first.rolling_hash(), second.rolling_hash(), "two fresh fields start out identical")

	t.eq(log.replay(first), 80, "the log applies every carve and deposit in it")
	t.ok(first.rolling_hash() != second.rolling_hash(), "which changes the ground it was applied to")
	log.replay(second)
	t.eq(first.rolling_hash(), second.rolling_hash(),
		"and the same events on a second field give byte-identical ground (§5)")
	t.eq(first.surface_sum_cm(), second.surface_sum_cm(), "down to the last centimetre of earth")

	# Round-tripped through the wire, because the events a client derives its ground from arrive as
	# bytes rather than as dictionaries.
	var bytes := log.encode()
	t.eq(bytes.size(), log.size() * EarthLog.RECORD_BYTES, "the log encodes fixed-width")
	var back := EarthLog.decode(bytes)
	t.ok(back != null and back.size() == log.size(), "and decodes to the same number of events")
	var third := EarthField.flat(materials, 0)
	back.replay(third)
	t.eq(third.rolling_hash(), first.rolling_hash(),
		"and a field built from the decoded log agrees with one built from the original")

	t.ok(EarthLog.decode(PackedByteArray([1, 2, 3])) == null,
		"a truncated stream is refused rather than half-read into terrain")
	t.eq(EarthLog.op_name(EarthLog.COLLAPSE), "collapse", "every op §5 names has a name")


func _materials() -> MaterialSet:
	var palette := Palette.new()
	if not palette.load_core():
		return null
	var materials := MaterialSet.new()
	return materials if materials.load_core(palette) else null
