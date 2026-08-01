extends TestCase
## `throw` — the verb that is `partial`, and the only one that uses that word. CORE-SPEC §2.
##
## The flight is C4's and the detonation is C5's, so a grenade here leaves the hand, arcs, bounces
## off what it meets, runs its fuse down and then goes quiet. **Nothing explodes**, and the test
## asserts that as a property rather than leaving it as an omission — because the failure mode of a
## milestone boundary is that somebody adds "just a little" of the next one, and the way to stop
## that is to have a test that fails when they do.
##
## It is the same line drawn twice before: `EarthCrater` is the earth's half of an explosion and not
## the explosion; `fire` produces a shot and does not resolve what it runs into. C4 gets things
## travelling. C5 gets what happens when they stop.
##
## The other claim worth pinning is that there is no lob code. A grenade arcs because it leaves at
## 18 m/s instead of 150, and `Ballistics` has never been told which is which — same call, same
## gravity, and the arc falls out of the number in the pack file.

const PACKS := "res://packs"
const EPSILON := 0.0001


func case_name() -> String:
	return "throw"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(PACKS)
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	if not set.load_core():
		t.fail("the vocabulary would not load: %s" % [", ".join(set.errors)])
		return
	var grenade := FixtureWorld.asset(world, "core:grenade")
	t.ok(grenade != null, "`core:grenade` exists as content")
	if grenade == null:
		return

	_it_leaves_the_hand(t, set, grenade)
	_an_arc_is_just_a_slow_bullet(t, grenade)
	await _it_bounces_off_what_it_meets(t, set, grenade)
	_and_then_it_goes_quiet(t, set, grenade)


func _it_leaves_the_hand(t: TestContext, set: VerbSet, grenade: ResolvedAsset) -> void:
	t.eq(String(grenade.data.get("slot", "")), "explosive_thrown", "in the slot for thrown things")
	t.eq(",".join(set.verbs_for("explosive_thrown")), "throw",
		"which is what says it can be thrown — the asset names no verb")

	var stats: Dictionary = grenade.data.get("stats", {})
	var request := { "stats": stats, "origin": Vector3(0.0, 1.5, 0.0), "aim": Vector3.FORWARD,
		"now": 0.0, "state": {} }

	var first := Verbs.dispatch(set, "throw", request)
	t.ok(first["ok"], "the first one is thrown: %s" % first["why"])
	var thrown: Dictionary = first["thrown"]
	t.near(float(thrown["speed"]), 18.0, EPSILON, "at the speed its own file gives it")
	t.near(float(thrown["fuse"]), 4.0, EPSILON, "with its own fuse on it")

	# Carried, not consumed. C5 reads both, and dropping them here would send the blast back to the
	# asset for numbers the throw already had in its hand.
	t.near(float(thrown["damage"]), 120.0, EPSILON, "carrying its damage untouched for C5")
	t.near(float(thrown["radius"]), 6.0, EPSILON, "and its radius, which C4 has no use for")

	# Two in the pouch, and the third is a refusal rather than an empty hand.
	var second := request.duplicate()
	second["state"] = first["state"]
	second["now"] = 1.0
	var next := Verbs.dispatch(set, "throw", second)
	t.ok(next["ok"], "the second one is thrown")
	var third := request.duplicate()
	third["state"] = next["state"]
	third["now"] = 2.0
	var empty := Verbs.dispatch(set, "throw", third)
	t.ok(not empty["ok"], "and the third is refused, because two is what a soldier carried")
	t.ok(String(empty["why"]).contains("thrown them all"), "saying so: %s" % empty["why"])

	var early := request.duplicate()
	early["state"] = first["state"]
	early["now"] = 0.4
	t.ok(not Verbs.dispatch(set, "throw", early)["ok"], "and throwing again inside the cycle is refused")


## No lob code. The arc is the number in the pack file meeting the same gravity everything else has.
func _an_arc_is_just_a_slow_bullet(t: TestContext, grenade: ResolvedAsset) -> void:
	var grenade_drop := Ballistics.drop_at(18.0, 20.0)
	var bullet_drop := Ballistics.drop_at(150.0, 20.0)
	t.ok(grenade_drop > bullet_drop * 60.0,
		"over 20 m a grenade falls %.1f m where a rifle round falls %.2f" % [
			grenade_drop, bullet_drop])

	# Which is the whole reason it is thrown *over* things rather than at them: at 18 m/s, twenty
	# metres of range costs about twelve metres of height, so the arc is the weapon.
	t.ok(grenade_drop > 10.0, "which is why you throw it over the parapet rather than through it")
	t.near(Ballistics.drop_at(18.0, 20.0, Ballistics.GRAVITY), grenade_drop, EPSILON,
		"and it is the same gravity as everything else in the world")


## Bouncing, against real physics. It is most of what makes a grenade a tactical object rather than
## a slow bullet — it is how you get one into a dugout you cannot see into.
func _it_bounces_off_what_it_meets(t: TestContext, set: VerbSet, grenade: ResolvedAsset) -> void:
	var stage := Node3D.new()
	t.host.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	stage.add_child(floor_body)
	await t.ticks(2)

	var space := stage.get_world_3d().direct_space_state
	var thrown: Dictionary = Verbs.dispatch(set, "throw", {
		"stats": grenade.data.get("stats", {}), "origin": Vector3(0.0, 1.5, 0.0),
		"aim": Vector3(0.0, -0.35, -1.0), "now": 0.0, "state": {} })["thrown"]

	var went_up_again := false
	var lowest := 999.0
	for frame in 90:
		thrown = VerbThrow.fly(space, thrown, 1.0 / 60.0)
		var at: Vector3 = thrown["origin"]
		lowest = minf(lowest, at.y)
		if int(thrown["bounces"]) > 0 and Vector3(thrown["velocity"]).y > 0.1:
			went_up_again = true
		if thrown["spent"]:
			break

	# A contact the object is already moving *away* from must not be flipped, and this is the case
	# that produces it: a graze, where the sweep reports a wall the grenade is passing rather than
	# arriving at. Reflecting there sends it back the way it came for no reason anybody watching
	# could account for — and it is invisible in the bouncing test above, because a grenade falling
	# onto a floor is always arriving.
	var leaving := Vector3(1.0, 2.0, 0.0)
	t.ok(Projectile.bounce(leaving, Vector3.UP, 0.42).is_equal_approx(leaving),
		"a contact the object is already moving away from does not reverse it")
	var arriving := Vector3(1.0, -2.0, 0.0)
	t.ok(Projectile.bounce(arriving, Vector3.UP, 0.42).y > 0.0,
		"while one it is moving into does come back up")
	t.ok(Projectile.bounce(arriving, Vector3.UP, 0.42).length() < arriving.length(),
		"having lost speed on the way, because a bounce is not free")
	t.ok(Projectile.bounce(arriving, Vector3.ZERO, 0.42).is_equal_approx(arriving),
		"and a contact with no normal is not a bounce at all")

	# Same untyped-array trap as `melee`, on the other verb that takes an `ignore` list. Asserted
	# here rather than assumed fixed, because the two were written from the same line.
	var excluded: Dictionary = Verbs.dispatch(set, "throw", {
		"stats": grenade.data.get("stats", {}), "origin": Vector3(0.0, 1.5, 0.0),
		"aim": Vector3.FORWARD, "now": 0.0, "state": {} })["thrown"]
	var flew := VerbThrow.fly(space, excluded, 1.0 / 60.0, [RID()])
	t.ok(flew != null and flew.has("origin"),
		"a grenade thrown past the thrower's own body survives being flown")

	t.ok(int(thrown["bounces"]) > 0, "a thrown grenade bounces: %d time(s)" % thrown["bounces"])
	t.ok(went_up_again, "coming back up off the floor rather than stopping dead where it landed")
	t.ok(lowest > -1.0, "and it never ends up under the floor, which is the sweep doing its job")

	stage.queue_free()


## And then it goes quiet — which is the assertion that keeps C5 out of C4.
func _and_then_it_goes_quiet(t: TestContext, set: VerbSet, grenade: ResolvedAsset) -> void:
	var thrown: Dictionary = Verbs.dispatch(set, "throw", {
		"stats": grenade.data.get("stats", {}), "origin": Vector3(0.0, 1.5, 0.0),
		"aim": Vector3.FORWARD, "now": 0.0, "state": {} })["thrown"]

	t.ok(not thrown.has("spent"), "a grenade that has just left the hand is not spent")
	var ticks := 0
	while not thrown.get("spent", false) and ticks < 600:
		thrown = VerbThrow.fly(null, thrown, 1.0 / 60.0)
		ticks += 1

	t.ok(thrown["spent"], "the fuse runs out after %d frames" % ticks)
	t.near(float(ticks) / 60.0, 4.0, 0.05, "which is the four seconds the asset asked for")
	t.near(float(thrown["fuse"]), 0.0, EPSILON, "with no fuse left to run")

	# The line, asserted rather than left as an omission. If somebody adds "just a little" of C5 to
	# C4, this is what goes red.
	for forbidden in ["blast", "exploded", "detonated", "damage_dealt"]:
		t.ok(not thrown.has(forbidden),
			"and nothing exploded — no `%s`, because the blast is C5's" % forbidden)
	t.near(float(thrown["damage"]), 120.0, EPSILON,
		"the damage is still sitting on it, unspent, waiting for the milestone that reads it")
