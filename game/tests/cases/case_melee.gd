extends TestCase
## `melee`, and the entrenching tool that proves a slot can carry two verbs. CORE-SPEC §2.
##
## The claim being cashed here was made at C1 and has been sitting in a note ever since.
## `melee_light`'s own description reads *"knife, shortsword, entrenching tool"*, and `verbs.json`
## puts that slot under **both** `melee` and `dig`. `core:shovel` is one object, in one slot, that
## digs a hole and hits people — which is why armies issued it, and which a tidier one-verb-per-slot
## model would have had to invent a `tool` slot to express.
##
## The contact test runs against real physics rather than a mocked space. A sweep that works against
## a stub and not against Jolt is a sweep that does not work, and this is the milestone where the
## same sweep starts being shared between a bullet and a shovel — so it wants the real thing under
## it before C5 puts a hundred bricks in front of it.

const PACKS := "res://packs"
const EPSILON := 0.0001


func case_name() -> String:
	return "melee"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(PACKS)
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	if not set.load_core():
		t.fail("the vocabulary would not load: %s" % [", ".join(set.errors)])
		return

	var shovel := FixtureWorld.asset(world, "core:shovel")
	t.ok(shovel != null, "`core:shovel` exists as content")
	if shovel == null:
		return

	_one_object_two_verbs(t, set, shovel)
	_swinging_costs_time_whether_or_not_it_lands(t, set, shovel)
	await _it_hits_something_real(t, set, shovel)
	_and_what_it_hits_takes_damage(t)


## The two-verbs-on-one-slot claim, asserted rather than described.
func _one_object_two_verbs(t: TestContext, set: VerbSet, shovel: ResolvedAsset) -> void:
	t.eq(String(shovel.data.get("slot", "")), "melee_light",
		"the entrenching tool is in the slot whose note has named it since C1")
	t.eq(",".join(set.verbs_for("melee_light")), "dig,melee",
		"and that slot offers both verbs — the asset names neither of them itself")

	var stats: Dictionary = shovel.data.get("stats", {})
	for stat in VerbMelee.REQUIRED_STATS:
		t.ok(stats.has(stat), "it supplies `%s`, which its slot requires" % stat)
	t.ok(not stats.has("spread"),
		"and no `spread` — a miss the player did not cause is not a thing a swing has")

	# C4's registry review put `dig_cm` on the melee slots rather than inventing an `entrenching`
	# slot, and this is the assertion that makes the choice pay: the same asset that swings also
	# carries the number that says how much earth it moves. A separate slot would have forced a
	# choice between the shovel being a weapon and the shovel being a tool.
	t.eq(int(stats.get("dig_cm", 0)), 25, "and it carries `dig_cm`, which is what makes it a tool too")


## The design line that matters more than it looks: a swing that connects with nothing still costs
## the recovery. "The cycle only starts on a hit" is the rule that turns melee into a button nobody
## ever lets go of.
func _swinging_costs_time_whether_or_not_it_lands(t: TestContext, set: VerbSet,
		shovel: ResolvedAsset) -> void:
	var stats: Dictionary = shovel.data.get("stats", {})
	var swing := { "stats": stats, "origin": Vector3.ZERO, "aim": Vector3.FORWARD,
		"now": 0.0, "state": {} }

	var missed := Verbs.dispatch(set, "melee", swing)
	t.ok(missed["ok"], "a swing at nothing still happens: %s" % missed["why"])
	t.ok(not (missed["strike"] as Dictionary)["hit"], "and connects with nothing")
	t.near(float((missed["state"] as Dictionary)["ready_at"]), 0.9, EPSILON,
		"and costs the full recovery anyway, which is what stops melee being a held button")
	t.near(float((missed["strike"] as Dictionary)["damage"]), 0.0, EPSILON,
		"a miss deals nothing")

	var early := swing.duplicate()
	early["state"] = missed["state"]
	early["now"] = 0.5
	var refused := Verbs.dispatch(set, "melee", early)
	t.ok(not refused["ok"], "swinging again inside the recovery is refused")
	t.ok(String(refused["why"]).contains("still recovering"), "and says so: %s" % refused["why"])

	var ready := swing.duplicate()
	ready["state"] = missed["state"]
	ready["now"] = 0.9
	t.ok(Verbs.dispatch(set, "melee", ready)["ok"], "and allowed once the recovery is over")

	var no_aim := swing.duplicate()
	no_aim["aim"] = Vector3.ZERO
	t.ok(not Verbs.dispatch(set, "melee", no_aim)["ok"], "a swing with no direction is refused")
	t.ok(not Verbs.dispatch(set, "melee", { "stats": {} })["ok"],
		"and a weapon with no stat block is refused rather than read as zeroes")

	# The one the suite did not have, and the reason it did not: no test ever passed `ignore`, so
	# nothing exercised the line that read it. A `Dictionary` hands its values back untyped, and
	# assigning a plain `Array` into an `Array[RID]` is a *runtime* abort rather than a parse error —
	# it compiled, the gate was green, and it died the first time somebody pressed the key. Passed
	# here exactly as a caller builds it: an array literal, straight into a dictionary.
	var with_arms := swing.duplicate()
	with_arms["ignore"] = [RID()]
	var swung := Verbs.dispatch(set, "melee", with_arms)
	t.ok(swung != null and swung.has("ok"),
		"a swing that excludes the arm holding the tool survives being asked for")
	t.ok(swung["ok"], "and happens: %s" % swung["why"])


## Real physics, real body, real sweep. A wall 1 m away is inside a 1.6 m reach; the same wall at
## 3 m is not, and nothing about that is arranged by the test beyond where the wall is.
func _it_hits_something_real(t: TestContext, set: VerbSet, shovel: ResolvedAsset) -> void:
	var stage := Node3D.new()
	t.host.add_child(stage)

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.0, -1.0)
	stage.add_child(wall)
	await t.ticks(2)

	var space := stage.get_world_3d().direct_space_state
	t.ok(space != null, "there is a physics world to swing in")

	var stats: Dictionary = shovel.data.get("stats", {})
	var at_the_wall := Verbs.dispatch(set, "melee", {
		"stats": stats, "origin": Vector3.ZERO, "aim": Vector3.FORWARD,
		"now": 0.0, "state": {}, "space": space })
	var strike: Dictionary = at_the_wall["strike"]
	t.ok(strike["hit"], "a shovel swung at a wall one metre away connects")
	t.near(float(strike["damage"]), 55.0, EPSILON, "for the damage its own file gives it")
	t.ok(Vector3(strike["position"]).distance_to(Vector3.ZERO) < 1.6,
		"landing inside its reach: %.2f m" % Vector3(strike["position"]).distance_to(Vector3.ZERO))

	# Move it past the reach and nothing about the call changes but the geometry.
	wall.position = Vector3(0.0, 0.0, -3.0)
	await t.ticks(2)
	var too_far := Verbs.dispatch(set, "melee", {
		"stats": stats, "origin": Vector3.ZERO, "aim": Vector3.FORWARD,
		"now": 0.0, "state": {}, "space": stage.get_world_3d().direct_space_state })
	t.ok(not (too_far["strike"] as Dictionary)["hit"],
		"and the same swing at the same wall three metres away does not")

	# The same sweep a bullet uses, which is the point: one hit-detection model, two ranges. A melee
	# system with its own would eventually disagree with the gun about what counts as cover.
	var shot := Projectile.sweep(stage.get_world_3d().direct_space_state, Vector3.ZERO,
		Vector3(0.0, 0.0, -10.0))
	t.ok(shot["hit"], "a rifle round down the same line hits the same wall")

	stage.queue_free()


## And the arithmetic on the other side of it, which is where C4 stops.
func _and_what_it_hits_takes_damage(t: TestContext) -> void:
	var first := Damage.to_body(Damage.SOLDIER_HEALTH, 55.0)
	t.near(float(first["health"]), 45.0, EPSILON, "a shovel takes a soldier to 45 of 100")
	t.ok(not first["killed"], "which is survivable, unlike a rifle round")
	var second := Damage.to_body(float(first["health"]), 55.0)
	t.ok(second["killed"], "and the second swing is not")

	# Two swings at 0.9s recovery is 1.8 seconds of work, against a bolt rifle's one round. That is
	# the whole balance argument for closing with somebody, and it comes out of two stat blocks
	# rather than out of anything anybody wrote here.
	t.ok(55.0 * 2 > Damage.SOLDIER_HEALTH, "two swings is enough, and it takes two")
