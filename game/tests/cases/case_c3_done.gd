extends TestCase
## C3's done-condition, walked in its own order.
##
## `BUILD-ORDER.md`, verbatim:
##
## > **Done when:** you can dig anywhere on the map, a trench you cut has vertical walls that slump
## > organically when shelled, craters have raised rims made of their own spoil, chalk holds a
## > steeper face than sand without a line of special-case code, and every modification is a
## > serialised event you could replay.
##
## Five clauses, and each gets a section below in the order the sentence puts them. This is the same
## shape C1 and C2 were closed in: the done-condition is a sentence somebody wrote before any of it
## existed, and the only honest way to mark it is to run it rather than to read the code and agree
## with yourself.
##
## One thing this case cannot do and says so: it does not fire a shell. Blast — radius, falloff,
## impulse, what it does to people — is C5's, and `EarthCrater` is only the earth's half of it, which
## is the half §4 specifies. "Shelled" here means a crater formed in the ground, which is what the
## clause is about.

const EPSILON := 0.0001


func case_name() -> String:
	return "C3 done-condition"


func run(t: TestContext) -> void:
	var world := _world()
	if world.is_empty():
		t.fail("core content data would not load, so nothing below means anything")
		return

	_one_dig_anywhere(t, world)
	_two_a_trench_with_walls_that_slump_when_shelled(t, world)
	_three_craters_have_rims_of_their_own_spoil(t, world)
	_four_chalk_holds_what_sand_does_not(t, world)
	_five_every_modification_replays(t, world)


## 1 · "you can dig anywhere on the map"
##
## Anywhere means anywhere, including a long way from the origin and on the negative side of it,
## where an off-by-one in the chunk arithmetic would live. Chunks are made on demand, so the map
## has no edge to fall off — the deformable *area* is a policy nobody has set yet
## (`DEVIATIONS-C3.md` A1), not a limit the storage imposes.
func _one_dig_anywhere(t: TestContext, world: Dictionary) -> void:
	var field := EarthField.flat(world["materials"], 0)
	var far: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(5, 7), Vector2i(-1, -1), Vector2i(-40, 33),
		Vector2i(600, -600), Vector2i(-1200, 950),
	]
	for cell in far:
		var got := field.carve(cell, 75)
		t.eq(got, 75, "dug 75 cm at (%d, %d)" % [cell.x, cell.y])
		t.eq(field.surface_cm(cell), -75, "and the ground there is 75 cm lower")
	# Five, not six: (0, 0) and (5, 7) are both inside chunk (0, 0), which is the arithmetic
	# working rather than a cell going missing.
	t.eq(field.chunks.size(), 5, "chunks appear on demand and no sooner")
	# A kilometre out and a kilometre back: the arithmetic does not drift, which is the thing that
	# would make "anywhere" quietly mean "anywhere near the middle".
	t.eq(field.surface_cm(Vector2i(600, -600)), -75, "the far one is still where it was left")
	t.eq(field.surface_cm(Vector2i(601, -600)), 0, "and its neighbour is untouched")


## 2 · "a trench you cut has vertical walls that slump organically when shelled"
##
## Both halves of the sentence, in one field: the walls are vertical *because it was cut steeply*,
## and they stop being vertical *because a shell landed*, with nothing switching mode in between.
func _two_a_trench_with_walls_that_slump_when_shelled(t: TestContext, world: Dictionary) -> void:
	var field := EarthField.flat(world["materials"], 0, &"clay")
	var settle := EarthSettle.of(world["materials"])
	# Revetted, because §3 is clear that unshored clay does not hold a 150 cm cut — and a trench
	# that fell down before the shell arrived would prove nothing about the shell.
	for z in range(2, 26):
		for x in [10, 11]:
			field.carve(Vector2i(x, z), 150)
			settle.disturb(Vector2i(x, z))
		for x in range(9, 13):
			field.shore(Vector2i(x, z), 80)
	settle.run_to_rest(field)

	var walled := _vertical_faces(field, world)
	t.ok(walled > 20, "a trench cut steeply has vertical walls: %d of them" % walled)
	t.eq(field.surface_cm(Vector2i(10, 10)), -150, "and its floor is where the spade left it")

	# Now shell it. The revetment goes with the ground it was holding — which is the loop §3 names:
	# destroying revetment is worth doing.
	for x in range(8, 14):
		for z in range(10, 16):
			field.unshore(Vector2i(x, z))
	EarthCrater.form(field, settle, Vector2i(11, 13), 5, 190)
	settle.run_to_rest(field)

	t.ok(_vertical_faces(field, world) < walled,
		"and after a shell lands in it, fewer of them are: %d" % _vertical_faces(field, world))

	# The wall is what changed, not the floor — a shell landing in a trench digs it deeper. So the
	# measurement is the step from the ground outside into the cut: sharp where nobody shelled,
	# slumped where somebody did.
	var shelled_step := field.surface_cm(Vector2i(8, 13)) - field.surface_cm(Vector2i(10, 13))
	var quiet_step := field.surface_cm(Vector2i(8, 4)) - field.surface_cm(Vector2i(10, 4))
	t.eq(quiet_step, 150, "the length of it nobody shelled still has its wall")
	t.ok(shelled_step < quiet_step,
		"and where the shell landed the wall has come down: a %d cm step against %d" % [
			shelled_step, quiet_step])
	t.eq(field.surface_cm(Vector2i(10, 4)), -150,
		"which is local — this is not a global reset")


## 3 · "craters have raised rims made of their own spoil"
##
## The rim is not decoration. §4: blast conserves about 70% of displaced volume onto the rim, the
## rest goes airborne. So a cratered field gets *rougher*, not lower, and the lip you take cover
## behind is the earth that used to be in the hole.
func _three_craters_have_rims_of_their_own_spoil(t: TestContext, world: Dictionary) -> void:
	var field := EarthField.flat(world["materials"], 0)
	var before := EarthAudit.surface_sum_cm(field)
	var displaced := EarthCrater.form(field, null, Vector2i(20, 20), 6, 160)

	t.ok(displaced > 0, "a shell displaces earth: %d column-cm" % displaced)
	t.ok(field.surface_cm(Vector2i(20, 20)) < -100, "leaving a hole where it landed")
	t.ok(field.surface_cm(Vector2i(28, 20)) > 0, "and a raised lip around it")
	t.ok(field.is_disturbed(Vector2i(28, 20)), "made of loose spoil, which stands less steeply")

	# 70% conserved, 30% gone to the air — the number §4 gives, and the reason it gives it: full
	# conservation makes craters look wrong.
	var kept := EarthAudit.surface_sum_cm(field) - before + displaced
	t.near(float(kept) / displaced, 0.70, 0.02,
		"with about 70%% of it on the rim and the rest blown away: %.2f" % (float(kept) / displaced))


## 4 · "chalk holds a steeper face than sand without a line of special-case code"
##
## The same call, the same path, two materials — and the only thing that differs is a number in the
## material file. If this needed an `if`, the whole design of soil-type-is-material would be a lie.
func _four_chalk_holds_what_sand_does_not(t: TestContext, world: Dictionary) -> void:
	var standing := {}
	for soil in [&"sand", &"loam", &"clay", &"chalk"]:
		var field := EarthField.flat(world["materials"], 0, soil)
		var settle := EarthSettle.of(world["materials"])
		for z in 10:
			for x in range(6, 18):
				field.sculpt(Vector2i(x, z), 250)
		for z in 10:
			settle.disturb(Vector2i(6, z))
		settle.run_to_rest(field)
		standing[soil] = field.surface_cm(Vector2i(6, 5)) - field.surface_cm(Vector2i(5, 5))

	t.ok(standing[&"chalk"] > standing[&"sand"],
		"chalk holds a steeper face than sand: %d cm against %d" % [
			standing[&"chalk"], standing[&"sand"]])
	t.ok(standing[&"clay"] > standing[&"loam"] and standing[&"loam"] > standing[&"sand"],
		"and the whole range orders itself the way the material file does")
	# Within, not equal to: a face does not stop at its limit, it slumps into a ramp that spreads
	# over several cells, and any one pair of them ends up somewhere under the limit. What the
	# material decides is how far it may go, which is the bound.
	for pair in [[&"chalk", 65], [&"clay", 55], [&"loam", 38], [&"sand", 30]]:
		var soil: StringName = pair[0]
		t.ok(standing[soil] <= EarthRepose.step_cm(int(pair[1])),
			"%s comes to rest inside its own angle: %d cm against a limit of %d" % [
				soil, standing[soil], EarthRepose.step_cm(int(pair[1]))])


## 5 · "every modification is a serialised event you could replay"
##
## And the half of that clause which is easy to miss: **slumping is not a modification.** §5 does
## not replicate it, because every client derives the same collapse from the same dig — so the log
## holds the digs, the replay re-runs the settling for itself, and the two fields agree bit for bit.
## A log that recorded the slumping would be sending the one thing that never needs sending, and
## would apply it twice on the way back in.
func _five_every_modification_replays(t: TestContext, world: Dictionary) -> void:
	var played := EarthField.flat(world["materials"], 0, &"loam")
	played.log = EarthLog.new()
	var settle := EarthSettle.of(world["materials"])

	for i in 12:
		played.tick = i
		var cell := Vector2i(6 + (i * 5) % 17, 4 + (i * 3) % 11)
		played.carve(cell, 60 + i * 9)
		settle.disturb(cell)
	EarthCrater.form(played, settle, Vector2i(14, 9), 4, 140)
	var moved_by_hand := played.log.size()
	settle.run_to_rest(played)

	t.ok(moved_by_hand > 12, "every dig and every shovel of spoil is an event: %d" % moved_by_hand)
	t.eq(played.log.size(), moved_by_hand,
		"and the slumping added none of them — it is derived, not sent (§5)")

	# Through the wire and back, because that is how the events reach the client that has to agree.
	var bytes := played.log.encode()
	var replayed := EarthField.flat(world["materials"], 0, &"loam")
	var again := EarthSettle.of(world["materials"])
	var decoded := EarthLog.decode(bytes)
	t.ok(decoded != null, "the log survives being turned into bytes and back")
	if decoded == null:
		return
	decoded.replay(replayed)
	for event in decoded.events:
		again.disturb(event["cell"])
	again.run_to_rest(replayed)

	t.eq(EarthAudit.rolling_hash(replayed), EarthAudit.rolling_hash(played),
		"and a field rebuilt from the events alone is bit-identical to the one they came from")
	t.eq(EarthAudit.surface_sum_cm(replayed), EarthAudit.surface_sum_cm(played), "down to the last centimetre of earth")


# ---------------------------------------------------------------- helpers

## How many faces the mesher calls vertical across the chunk at the origin — the same measurement
## `case_earth_mesh.gd` uses, because "vertical walls" has to mean the same thing in both places.
func _vertical_faces(field: EarthField, world: Dictionary) -> int:
	var mesh := EarthMesher.build(field, Vector2i.ZERO, world["palette"], world["materials"])
	if mesh == null:
		return 0
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var count := 0
	for i in range(0, normals.size(), 3):
		if rad_to_deg(normals[i].angle_to(Vector3.UP)) > 89.0:
			count += 1
	return count


func _world() -> Dictionary:
	var palette := Palette.new()
	if not palette.load_core():
		return {}
	var materials := MaterialSet.new()
	if not materials.load_core(palette):
		return {}
	return {"palette": palette, "materials": materials}
