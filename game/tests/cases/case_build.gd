extends TestCase
## `build` — and the loop EARTH-SPEC has been assembling since C3. CORE-SPEC §2, FORMAT-SPEC §7.
##
## C4 reserved this verb to C5 with an argument, and this is the case that pays it off:
##
## > placing a sandbag wall is a couple of hours' work, and a sandbag wall that does not topple
## > sideways where a clay one slumps is a prop with a placement cost.
##
## It topples now — `support_lateral` on sandbag is 8 against clay's 35 — so the thing being placed
## is a buildable rather than scenery, and the verb can go live.
##
## The claim worth testing is the cost. `cost.spoil` is not an abstract resource: it is spade-bites
## of actual field, carved out of the cells around where the wall is going, by the same
## `EarthField.carve` that `dig` calls. That is EARTH-SPEC §4's loop closing — *digging produces
## spoil, spoil is what a parapet is made of* — and it makes the cost self-limiting in a way no
## counter would be. Build on bedrock and there is nothing to fill the bags with.

const EPSILON := 0.0001


func case_name() -> String:
	return "build"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root("res://packs")
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	if not set.load_core():
		t.fail("the vocabulary would not load: %s" % [", ".join(set.errors)])
		return
	var materials: MaterialSet = world["materials"]
	var barrier := FixtureWorld.asset(world, "core:sandbag_barrier")
	t.ok(barrier != null, "`core:sandbag_barrier` exists as content")
	if barrier == null:
		return

	_a_buildable_is_not_scenery(t, set, barrier, materials)
	_the_cost_is_earth(t, set, barrier, materials)
	_and_bedrock_will_not_fill_a_sandbag(t, set, barrier, materials)
	_a_refusal_leaves_no_scrape(t, set, barrier, materials)


func _a_buildable_is_not_scenery(t: TestContext, set: VerbSet, barrier: ResolvedAsset,
		materials: MaterialSet) -> void:
	t.eq(String(barrier.data.get("kind", "")), "buildable",
		"it is a buildable rather than a structure — `core:wall_sandbag` is the scenery version")
	t.eq(String(barrier.data.get("slot", "")), "barrier", "filling the slot for walls and revetments")
	t.eq(",".join(set.verbs_for("barrier")), "build",
		"and the slot is what says it can be built — the asset names no verb")

	# The argument C4 made when it reserved this verb, now checkable.
	t.ok(Integrity.topples(&"sandbag", materials),
		"a sandbag wall comes apart into bags rather than slumping as a mass")
	t.ok(not Integrity.topples(&"clay", materials), "which is not what a clay bank does")


## §4's loop, closed. The wall is made of the ground it stands on.
func _the_cost_is_earth(t: TestContext, set: VerbSet, barrier: ResolvedAsset,
		materials: MaterialSet) -> void:
	var field := EarthField.flat(materials, 0, &"loam")
	var cell := Vector2i(6, 6)
	# Warm the chunk before measuring: reads deliberately do not allocate, so a total taken before
	# the first write is zero for the reason `case_dig` spells out.
	field.carve(cell, 1)
	field.deposit(cell, 1)
	var before := EarthAudit.surface_sum_cm(field)

	var got := Verbs.dispatch(set, "build", {
		"stats": barrier.data.get("stats", {}), "cost": barrier.data.get("cost", {}),
		"field": field, "cell": cell, "now": 0.0, "state": {} })
	t.ok(got["ok"], "a sandbag barrier goes up: %s" % got["why"])

	var bags := int((barrier.data.get("cost", {}) as Dictionary)["spoil"])
	t.eq(got["moved_cm"], bags * VerbBuild.SPOIL_UNIT_CM,
		"paid for with %d spade-bites of earth, in the same unit `dig` moves" % bags)
	t.ok(EarthAudit.surface_sum_cm(field) < before,
		"and the ground is lower than it was — the wall came out of the field")

	# Spread rather than dug out of one hole. Taking it all from the centre would leave a pit the
	# wall then falls into, which is a real failure and not a tidiness preference.
	var deepest := 0
	var scraped := 0
	for dz in range(-VerbBuild.GATHER_CELLS, VerbBuild.GATHER_CELLS + 1):
		for dx in range(-VerbBuild.GATHER_CELLS, VerbBuild.GATHER_CELLS + 1):
			var cut := -field.surface_cm(cell + Vector2i(dx, dz))
			if cut > 0:
				scraped += 1
			deepest = maxi(deepest, cut)
	t.ok(scraped > 1, "taken from %d cells rather than one" % scraped)
	t.ok(deepest <= VerbBuild.PER_CELL_CM,
		"none of them deeper than %d cm, so it is a scrape and not a pit" % VerbBuild.PER_CELL_CM)

	# Building again immediately is refused: it takes time, and the time is the asset's own.
	var again := Verbs.dispatch(set, "build", {
		"stats": barrier.data.get("stats", {}), "cost": barrier.data.get("cost", {}),
		"field": field, "cell": cell, "now": 0.5, "state": got["state"] })
	t.ok(not again["ok"], "and building again inside the build time is refused")
	t.ok(String(again["why"]).contains("still building"), "saying so: %s" % again["why"])
	t.near(float((got["state"] as Dictionary)["ready_at"]), 2.5, EPSILON,
		"which is the `build_time` on the asset rather than a number in the engine")


## The property that makes the cost real rather than bookkeeping.
func _and_bedrock_will_not_fill_a_sandbag(t: TestContext, set: VerbSet, barrier: ResolvedAsset,
		materials: MaterialSet) -> void:
	var bare := EarthField.flat(materials, EarthField.FLOOR_CM, &"loam")
	var refused := Verbs.dispatch(set, "build", {
		"stats": barrier.data.get("stats", {}), "cost": barrier.data.get("cost", {}),
		"field": bare, "cell": Vector2i(3, 3), "now": 0.0, "state": {} })
	t.ok(not refused["ok"], "there is nothing to fill the bags with on bedrock")
	t.ok(String(refused["why"]).contains("not enough earth"),
		"and it says why in those terms: %s" % refused["why"])
	t.ok(String(refused["why"]).contains("Bedrock"), "naming the reason rather than a shortfall")


## A refusal is not a half-done action. If the earth cannot be found, what was already taken goes
## back — §4's conservation claim does not get a holiday for failed actions.
func _a_refusal_leaves_no_scrape(t: TestContext, set: VerbSet, barrier: ResolvedAsset,
		materials: MaterialSet) -> void:
	# Two centimetres of soil over bedrock. The gather reaches 25 cells and may take 20 cm from each,
	# so ten would have been *plenty* — the first version of this test used it and the build quietly
	# succeeded, which is the test being wrong rather than the code.
	var thin := EarthField.flat(materials, EarthField.FLOOR_CM + 2, &"loam")
	var cell := Vector2i(4, 4)
	thin.carve(cell, 1)
	thin.deposit(cell, 1)
	var before := EarthAudit.surface_sum_cm(thin)

	var refused := Verbs.dispatch(set, "build", {
		"stats": barrier.data.get("stats", {}), "cost": barrier.data.get("cost", {}),
		"field": thin, "cell": cell, "now": 0.0, "state": {} })
	t.ok(not refused["ok"], "a barrier on two centimetres of soil is refused")
	t.eq(EarthAudit.surface_sum_cm(thin), before,
		"and every centimetre it had already picked up is put back — a refusal is not half an action")

	# Not just the total: every cell is where it was. Returning the right amount to the wrong cells
	# would pass a conservation check and still leave the ground reshaped, which is exactly what the
	# first version of `_return` did.
	var reshaped := 0
	for dz in range(-VerbBuild.GATHER_CELLS, VerbBuild.GATHER_CELLS + 1):
		for dx in range(-VerbBuild.GATHER_CELLS, VerbBuild.GATHER_CELLS + 1):
			if thin.surface_cm(cell + Vector2i(dx, dz)) != EarthField.FLOOR_CM + 2:
				reshaped += 1
	t.eq(reshaped, 0, "cell for cell, not just in total")
