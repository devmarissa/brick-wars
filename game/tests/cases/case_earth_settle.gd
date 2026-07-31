extends TestCase
## Earth obeying its own angle of repose. EARTH-SPEC §3.
##
## The behaviour: cut a face shallower than the soil holds and it stands indefinitely; cut it
## steeper and it slumps until it doesn't. That one rule is the difference between sand, which is
## nearly useless to build with at 30°, and the chalk the Great War tunnelled through at 65° — and
## it is the thing that makes a trench something you maintain rather than something you cut once.
##
## Three claims here are load-bearing and the rest are arithmetic around them:
##
## **It conserves volume.** Slumping is the same earth in a different place. A settle that created
## or destroyed any would be a subtract brush wearing a physics costume.
## **It terminates.** A rule that moves half an excess converges; one that moved all of it would
## oscillate, and one that moves a rounded-down half could spin forever on a single centimetre.
## **It is identical every time.** §5 does not replicate slumping at all — the server sends the dig
## and every client derives the collapse itself — which is only true if the arithmetic is exact and
## the order is fixed.

const EPSILON := 0.0001


func case_name() -> String:
	return "earth settle"


func run(t: TestContext) -> void:
	var materials := _materials()
	if materials == null:
		t.fail("core materials would not load, so nothing below means anything")
		return

	_the_threshold(t, materials)
	_a_steep_face_comes_down(t, materials)
	_a_shallow_one_does_not(t, materials)
	_soil_decides_how_steep(t, materials)
	_dug_ground_holds_less(t, materials)
	_the_budget_is_a_budget(t, materials)
	_the_same_collapse_every_time(t, materials)


## The angle, turned into the whole number of centimetres a face may step between columns. Cells
## are 0.5 m apart, so this is `tan(angle) × 50 cm`.
func _the_threshold(t: TestContext, materials: MaterialSet) -> void:
	t.eq(EarthRepose.step_cm(45), 50, "45 degrees is one cell across for one cell down: 50 cm")
	t.eq(EarthRepose.step_cm(38), 39, "loam's 38 degrees holds a 39 cm step")
	t.eq(EarthRepose.step_cm(30), 29, "sand's 30 holds 29")
	t.eq(EarthRepose.step_cm(65), 107, "and chalk's 65 holds over a metre")
	t.ok(EarthRepose.step_cm(30) < EarthRepose.step_cm(55),
		"a material that holds a steeper angle holds a taller step, which is the whole idea")

	# Diagonals are further apart, so they hold proportionally more before the face is as steep.
	t.eq(EarthRepose.diagonal_step_cm(45), 70, "a diagonal neighbour is root-two further away")
	t.eq(EarthRepose.degrees_of(materials, &"chalk"), 65, "and the angles come from the material file")
	t.eq(EarthRepose.degrees_of(materials, &"mud"), 15,
		"including mud at 15, which is the Great War in one number")


## The case §3 is written for: a cut steeper than the soil holds comes down.
func _a_steep_face_comes_down(t: TestContext, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0, &"loam")
	var before := field.surface_sum_cm()
	# A 3 m cliff in loam, which holds 39 cm to a cell. It has no business standing.
	for z in 12:
		for x in range(8, 20):
			field.sculpt(Vector2i(x, z), 300)

	var settle := EarthSettle.of(materials)
	for z in 12:
		settle.disturb(Vector2i(8, z))
	var looked := settle.run_to_rest(field)

	t.ok(looked > 0, "the queue had work to do: %d cells looked at" % looked)
	t.ok(settle.moved_cm > 0, "and earth moved: %d column-cm" % settle.moved_cm)
	t.eq(settle.pending(), 0, "it settled rather than running forever")

	# The face is now inside what loam holds, everywhere along it.
	var worst := 0
	for z in 12:
		worst = maxi(worst, field.surface_cm(Vector2i(8, z)) - field.surface_cm(Vector2i(7, z)))
	t.ok(worst <= EarthRepose.step_cm(38),
		"and no step along it is steeper than loam stands: %d cm against a limit of %d" % [
			worst, EarthRepose.step_cm(38)])

	# The claim that makes it earth rather than a brush.
	t.eq(field.surface_sum_cm(), before + 12 * 12 * 300,
		"with every centimetre still in the field — slumping moves earth, it does not spend it")


## And the other half: a face the soil can hold is left alone. Without this the rule would just be
## "everything flattens", which is a different and much worse game.
func _a_shallow_one_does_not(t: TestContext, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0, &"loam")
	for z in 8:
		for x in range(6, 14):
			field.sculpt(Vector2i(x, z), 30)      # a 30 cm step; loam holds 39

	var settle := EarthSettle.of(materials)
	var was := field.rolling_hash()
	for z in 8:
		settle.disturb(Vector2i(6, z))
	settle.run_to_rest(field)

	t.eq(settle.moved_cm, 0, "a step inside the angle of repose does not move at all")
	t.eq(field.rolling_hash(), was, "and the ground is bit-for-bit what it was")


## Which soil it is decides how much comes down. Sand is nearly useless to build with; chalk is
## what you tunnel through.
func _soil_decides_how_steep(t: TestContext, materials: MaterialSet) -> void:
	var moved := {}
	for soil in [&"sand", &"loam", &"chalk"]:
		var field := EarthField.flat(materials, 0, soil)
		for z in 8:
			for x in range(6, 16):
				field.sculpt(Vector2i(x, z), 200)
		var settle := EarthSettle.of(materials)
		for z in 8:
			settle.disturb(Vector2i(6, z))
		settle.run_to_rest(field)
		moved[soil] = settle.moved_cm

	t.ok(moved[&"sand"] > moved[&"loam"], "the same cut in sand slumps more than in loam")
	t.ok(moved[&"loam"] > moved[&"chalk"], "and loam more than chalk")
	t.ok(moved[&"chalk"] > 0, "though even chalk gives way to a two-metre face")


## §4's `disturbed` flag, doing the work it was added for: spoil is weaker than the ground it came
## out of. A parapet slumps in weather the wall opposite shrugs off, and that is one bit.
func _dug_ground_holds_less(t: TestContext, materials: MaterialSet) -> void:
	var virgin := EarthField.flat(materials, 0, &"clay")
	var spoil := EarthField.flat(materials, 0, &"clay")
	for field in [virgin, spoil]:
		for z in 8:
			for x in range(6, 16):
				field.sculpt(Vector2i(x, z), 60)
	for z in 8:
		for x in range(6, 16):
			spoil.chunk_for(Vector2i(x, z)).set_disturbed(
				EarthField.local_of(Vector2i(x, z)).x, EarthField.local_of(Vector2i(x, z)).y, true)

	var a := EarthSettle.of(materials)
	var b := EarthSettle.of(materials)
	for z in 8:
		a.disturb(Vector2i(6, z))
		b.disturb(Vector2i(6, z))
	a.run_to_rest(virgin)
	b.run_to_rest(spoil)

	# 60 cm, against the 71 cm that clay's 55 degrees holds — and against the 42 cm that the same
	# clay holds once it has been dug, which is 55 less §4's 15.
	t.eq(a.moved_cm, 0, "clay at 55 degrees holds a 60 cm step without moving")
	t.ok(b.moved_cm > 0, "and the same clay, dug and dumped, does not: %d column-cm" % b.moved_cm)


## §9 budgets 512 cells a frame. A shell that dirties a thousand costs the same per frame as a
## spade that dirties nine — it just takes more frames, which is the point.
func _the_budget_is_a_budget(t: TestContext, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0, &"sand")
	for z in 20:
		for x in range(10, 30):
			field.sculpt(Vector2i(x, z), 400)
	var settle := EarthSettle.of(materials)
	for z in 20:
		settle.disturb(Vector2i(10, z))

	t.eq(settle.run(field, 16), 16, "a tick looks at exactly the budget it was given")
	t.ok(settle.pending() > 0, "and leaves the rest for the next one")
	var partway := settle.moved_cm
	settle.run_to_rest(field)
	t.ok(settle.moved_cm > partway, "which finishes across frames rather than in one")


## §5's claim, and the reason slumping is never sent over the wire: the same dig gives the same
## collapse, everywhere, forever.
func _the_same_collapse_every_time(t: TestContext, materials: MaterialSet) -> void:
	var hashes: Array[int] = []
	var totals: Array[int] = []
	for run in 2:
		var field := EarthField.flat(materials, 0, &"loam")
		var settle := EarthSettle.of(materials)
		# An irregular cut, so the answer is not symmetric enough to agree by luck.
		for i in 30:
			var cell := Vector2i(4 + (i * 7) % 19, 3 + (i * 5) % 13)
			field.carve(cell, 40 + i * 6)
			settle.disturb(cell)
		settle.run_to_rest(field)
		hashes.append(field.rolling_hash())
		totals.append(settle.moved_cm)

	t.eq(hashes[0], hashes[1], "two runs of the same dig settle to bit-identical ground")
	t.eq(totals[0], totals[1], "having moved exactly the same amount of earth doing it")
	t.ok(totals[0] > 0, "and it did actually slump, so the line above means something")


func _materials() -> MaterialSet:
	var palette := Palette.new()
	if not palette.load_core():
		return null
	var materials := MaterialSet.new()
	return materials if materials.load_core(palette) else null
