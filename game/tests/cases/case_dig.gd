extends TestCase
## Dispatch, and the first live verb. CORE-SPEC §2, EARTH-SPEC §4.
##
## `dig` is deliberately the one that goes in first, and not because it is easy. VISION's era table
## puts **DIG** in the first column of every era it lists — siege ramp, mine under the tower, Vauban
## parallel, the sap, fighting position, IED hole — so it is the verb the whole "eras are data" bet
## rests on. Building the vocabulary around `fire` first and adding digging later is how you get a
## verb system shaped like a weapon system, which then has to be widened by the first pack that
## wants a shovel.
##
## The other half is dispatch itself: a reserved verb is *refused with the name of the milestone
## that owns it*, rather than quietly doing nothing. Content authored against a silent no-op looks
## like working content until somebody plays it.

const EPSILON := 0.0001


func case_name() -> String:
	return "dispatch and dig"


func run(t: TestContext) -> void:
	var materials := _materials()
	if materials == null:
		t.fail("core materials would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	if not set.load_core():
		t.fail("the vocabulary would not load: %s" % [", ".join(set.errors)])
		return

	_the_door(t, set, materials)
	_a_spadeful(t, set, materials)
	_where_the_spoil_may_go(t, set, materials)
	_bedrock(t, set, materials)
	_the_tool_decides_the_bite(t, set, materials)
	_a_trench_is_repetition(t, set, materials)


## Every interaction goes through one door, and the door answers honestly in three ways.
func _the_door(t: TestContext, set: VerbSet, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0)

	var nonsense := Verbs.dispatch(set, "yeet", { "field": field })
	t.ok(not nonsense["ok"], "a verb that is not a verb is refused")
	t.ok(String(nonsense["why"]).contains("vocabulary is fixed"),
		"and told the vocabulary is closed rather than that it made a typo")

	var later := Verbs.dispatch(set, "throw", { "field": field })
	t.ok(not later["ok"], "a declared-but-unbuilt verb is refused too")
	t.ok(String(later["why"]).contains("C4"),
		"naming the milestone that owns it: %s" % later["why"])
	t.ok(String(later["why"]).contains("refusal rather than a no-op"),
		"and saying why that is a refusal instead of silence")

	var enter := Verbs.dispatch(set, "enter", { "field": field })
	t.ok(String(enter["why"]).contains("C6"), "`enter` points at C6, which is the one that owns it")

	t.ok(not Verbs.dispatch(set, "dig", {})["ok"], "and a live verb with nothing to work on refuses")


## One bite, and the thing §4 insists on: the earth that came out is somewhere, not gone.
func _a_spadeful(t: TestContext, set: VerbSet, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0)
	var before := EarthAudit.surface_sum_cm(field)

	var got := Verbs.dispatch(set, "dig", {
		"field": field, "cell": Vector2i(4, 4), "spoil": Vector2i(5, 4), "depth_cm": 20 })
	t.ok(got["ok"], "a spadeful of earth comes out: %s" % got["why"])
	t.eq(got["moved_cm"], 20, "twenty centimetres of it")
	t.eq(field.surface_cm(Vector2i(4, 4)), -20, "the hole is that deep")
	t.eq(field.surface_cm(Vector2i(5, 4)), 20, "the pile beside it is that high")
	t.eq(EarthAudit.surface_sum_cm(field), before,
		"and the ground holds exactly as much earth as it did (§4: digging is not deletion)")

	t.ok(field.is_disturbed(Vector2i(4, 4)), "the cut is disturbed ground")
	t.ok(field.is_disturbed(Vector2i(5, 4)),
		"and so is the spoil, which is why a parapet slumps in weather the trench wall shrugs off")


## The refusals that make spoil a constraint rather than bookkeeping.
func _where_the_spoil_may_go(t: TestContext, set: VerbSet, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0)
	var base := { "field": field, "cell": Vector2i(0, 0), "spoil": Vector2i(1, 0), "depth_cm": 20 }

	var into_itself := base.duplicate()
	into_itself["spoil"] = Vector2i(0, 0)
	t.ok(not Verbs.dispatch(set, "dig", into_itself)["ok"],
		"spoil thrown into the hole it came from is refused — it would dig nothing")

	var too_far := base.duplicate()
	too_far["spoil"] = Vector2i(4, 0)
	var thrown := Verbs.dispatch(set, "dig", too_far)
	t.ok(not thrown["ok"], "and so is spoil thrown across the road")
	t.ok(String(thrown["why"]).contains("shovel reaches"), "because a shovel has a reach: %s" % thrown["why"])

	var greedy := base.duplicate()
	greedy["depth_cm"] = VerbDig.MAX_BITE_CM + 1
	var bite := Verbs.dispatch(set, "dig", greedy)
	t.ok(not bite["ok"], "a metre in one bite is refused")
	t.ok(String(bite["why"]).contains("slump between bites"),
		"which is what puts digging on a clock rather than being a limit for its own sake")

	var nothing := base.duplicate()
	nothing["depth_cm"] = 0
	t.ok(not Verbs.dispatch(set, "dig", nothing)["ok"], "and a dig that removes nothing is refused")
	t.eq(EarthAudit.surface_sum_cm(field), 0, "no refusal moved any earth on its way out")

	# Diagonal is fine — a shovel throws to the corner as easily as to the side, and a rule that
	# allowed only the four orthogonal neighbours would be a grid artefact rather than a constraint.
	var corner := base.duplicate()
	corner["spoil"] = Vector2i(1, 1)
	t.ok(Verbs.dispatch(set, "dig", corner)["ok"], "spoil thrown to the corner is allowed")


## The sharp one. A cut that reaches bedrock moves less earth than it was asked for, so the deposit
## has to be the *result* and not the request — otherwise every dig against bedrock quietly creates
## earth. C3 tested that at the field; this tests it through the verb, which is a different door
## into the same mistake.
func _bedrock(t: TestContext, set: VerbSet, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, EarthField.FLOOR_CM + 10)
	# Measured across the two cells rather than the whole field, and the reason is worth writing
	# down: `surface_sum_cm` sums the chunks that exist, and chunks are allocated on first write. A
	# whole-field total taken before the first dig is therefore zero — not because the ground is
	# empty but because none of it has been asked for yet — and the first carve appears to create a
	# chunk's worth of earth. Reads deliberately do not allocate (the defect C3 caught), so there is
	# no way to warm it up by looking. Two cells is the honest scope for a claim about two cells.
	var before := field.surface_cm(Vector2i(2, 2)) + field.surface_cm(Vector2i(3, 2))

	var got := Verbs.dispatch(set, "dig", {
		"field": field, "cell": Vector2i(2, 2), "spoil": Vector2i(3, 2), "depth_cm": 25 })
	t.ok(got["ok"], "digging the last ten centimetres above bedrock works")
	t.eq(got["moved_cm"], 10, "and yields ten, not the twenty-five it was asked for")
	t.eq(field.surface_cm(Vector2i(2, 2)) + field.surface_cm(Vector2i(3, 2)), before,
		"with the pile getting exactly what the hole gave up, not what the caller wanted")
	t.eq(field.surface_cm(Vector2i(2, 2)), EarthField.FLOOR_CM, "the hole is down to bedrock")

	var again := Verbs.dispatch(set, "dig", {
		"field": field, "cell": Vector2i(2, 2), "spoil": Vector2i(3, 2), "depth_cm": 25 })
	t.ok(not again["ok"], "digging bedrock again is refused")
	t.ok(String(again["why"]).contains("bedrock"), "and says so plainly: %s" % again["why"])


## The bite comes off the tool when there is one. Before C4's registry review it was a constant in
## code, because no slot supplied a number — which was the concrete cost of the missing slot and the
## thing that made the review worth doing rather than a tidy-up.
func _the_tool_decides_the_bite(t: TestContext, set: VerbSet, materials: MaterialSet) -> void:
	var world := FixtureWorld.load_root("res://packs")
	var shovel := FixtureWorld.asset(world, "core:shovel") if not world.is_empty() else null
	if shovel == null:
		t.fail("`core:shovel` would not load")
		return

	var field := EarthField.flat(materials, 0)
	var got := Verbs.dispatch(set, "dig", {
		"field": field, "cell": Vector2i(3, 3), "spoil": Vector2i(4, 3),
		"stats": shovel.data.get("stats", {}) })
	t.ok(got["ok"], "a dig with a shovel in hand works: %s" % got["why"])
	t.eq(got["moved_cm"], 25, "and takes the shovel's own `dig_cm`, not a number from the engine")

	# A pack cannot make a shovel that swallows the map. The cap is a ceiling on what a tool may
	# claim rather than the bite itself.
	var greedy := Verbs.dispatch(set, "dig", {
		"field": field, "cell": Vector2i(3, 5), "spoil": Vector2i(4, 5),
		"stats": { "dig_cm": VerbDig.MAX_BITE_CM + 40 } })
	t.ok(not greedy["ok"], "and a tool claiming more than the ceiling is refused")
	t.ok(String(greedy["why"]).contains("any tool may take"),
		"saying it is a ceiling rather than a preference: %s" % greedy["why"])


## What a soldier actually does: the same bite, over and over, until there is a hole to lie in and a
## bank to fire over. Nothing decides that a parapet should appear.
func _a_trench_is_repetition(t: TestContext, set: VerbSet, materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0, &"clay")
	var request := { "field": field, "cell": Vector2i(8, 8), "spoil": Vector2i(9, 8),
		"depth_cm": VerbDig.MAX_BITE_CM }

	var total := 0
	for i in 6:
		var got := Verbs.dispatch(set, "dig", request)
		t.ok(got["ok"], "bite %d comes out" % (i + 1))
		total += int(got["moved_cm"])

	t.eq(total, 6 * VerbDig.MAX_BITE_CM, "six bites move six bites' worth")
	t.eq(field.surface_cm(Vector2i(8, 8)), -150, "leaving a hole deep enough to stand in")
	t.eq(field.surface_cm(Vector2i(9, 8)), 150, "and a bank of its own spoil beside it")
	t.eq(EarthAudit.surface_sum_cm(field), 0, "with every centimetre still in the field")

	# And the earth is not asked to hold that on its own: a 300 cm step in clay is far past its
	# angle, so the settle queue takes it down. This is the loop EARTH-SPEC §3 describes and the
	# reason real trenches are revetted — the verb does not need to know any of it.
	var settle := EarthSettle.of(materials)
	settle.disturb(Vector2i(8, 8))
	settle.disturb(Vector2i(9, 8))
	settle.run_to_rest(field)
	t.ok(field.surface_cm(Vector2i(9, 8)) < 150, "the unrevetted spoil bank slumps")
	t.ok(field.surface_cm(Vector2i(8, 8)) > -150, "and the hole partly fills as it does")
	t.eq(EarthAudit.surface_sum_cm(field), 0, "still conserving every centimetre while it moves")


func _materials() -> MaterialSet:
	var palette := Palette.new()
	if not palette.load_core():
		return null
	var materials := MaterialSet.new()
	return materials if materials.load_core(palette) else null
