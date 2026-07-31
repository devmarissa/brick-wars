extends TestCase
## C4's done-condition, and the era boundary it exists to defend.
##
## `BUILD-ORDER`, verbatim:
##
## > **Done when:** a weapon defined in data fires, a bow and a rifle are the same code path,
## > and TESTPACK's bow works with zero core changes.
##
## Three clauses, and the middle one is the whole architectural bet. `VISION`: *"No `if weapon ==
## "rifle"` in the core. WW1 goes into a data pack alongside everything else, and if it can't be
## expressed in the pack format, the pack format is wrong."* Six eras from slings to guided
## missiles are supposed to be one code path with different numbers, and this is the first point
## where that is testable rather than aspirational.
##
## Both weapons go through `Verbs.dispatch(set, "fire", ...)` with nothing distinguishing them but
## the `stats` block the validator already accepted. If the bow ever needs one line the rifle did
## not, the bet is lost and this file is where it shows.
##
## The assets are loaded through the real content pipeline rather than hand-built, for the reason
## `FixtureWorld` gives: half of what the firing path reads is defaults `PartRules` filled in, and
## half of what makes a test fair is that the validator was given its chance to refuse the asset
## first.

const PACKS := "res://packs"
const EPSILON := 0.0001

## A fixed seed, because a shot nobody can reproduce is a desync waiting for C8. Every roll below
## is deterministic and the test asserts that it is.
const SEED := 20260731


func case_name() -> String:
	return "fire"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(PACKS)
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	if not set.load_core():
		t.fail("the vocabulary would not load: %s" % [", ".join(set.errors)])
		return

	_a_weapon_defined_in_data_fires(t, world, set)
	_a_bow_and_a_rifle_are_the_same_code_path(t, world, set)
	_the_difference_is_entirely_the_numbers(t, world, set)
	_at_a_cost_in_ammunition_and_time(t, world, set)
	_the_same_shot_twice(t, world, set)


## 1 · "a weapon defined in data fires"
##
## Nothing about this weapon is in the engine. It is a JSON file in a pack, it fills a slot the
## registry declared at C1, and it went through the validator on the way here.
func _a_weapon_defined_in_data_fires(t: TestContext, world: Dictionary, set: VerbSet) -> void:
	var rifle := FixtureWorld.asset(world, "core:rifle")
	t.ok(rifle != null, "`core:rifle` exists as content")
	if rifle == null:
		return
	t.eq(String(rifle.data.get("slot", "")), "ranged_slow", "filling the slot C1 declared for it")
	t.eq(",".join(set.verbs_for("ranged_slow")), "fire",
		"and the slot is what says it can be fired — the asset never names a verb")

	var got := Verbs.dispatch(set, "fire", _shot(rifle))
	t.ok(got["ok"], "it fires: %s" % got["why"])
	var shot: Dictionary = got["shot"]
	t.near(float(shot["speed"]), 150.0, EPSILON, "at the muzzle velocity its own file gave it")
	t.near(float(shot["damage"]), 95.0, EPSILON, "carrying the damage its own file gave it")
	t.near(Vector3(shot["velocity"]).length(), 150.0, 0.01,
		"and the velocity is the speed, not the speed plus whatever spread did to it")


## 2 and 3 · "a bow and a rifle are the same code path" · "TESTPACK's bow works with zero core
## changes"
##
## The bow is in a different pack, made of different materials, and shaped nothing like the rifle.
## It is in the **same slot** — `ranged_slow`, whose own note has read `bolt rifle, musket,
## crossbow, bow` since C1 — so it goes through the same call with the same arguments.
func _a_bow_and_a_rifle_are_the_same_code_path(t: TestContext, world: Dictionary,
		set: VerbSet) -> void:
	var bow := FixtureWorld.asset(world, "testpack:bow")
	t.ok(bow != null, "`testpack:bow` exists, out of a pack that is not core")
	if bow == null:
		return
	t.eq(String(bow.data.get("slot", "")), "ranged_slow",
		"in the same slot as the rifle rather than a bow-shaped one of its own")

	var got := Verbs.dispatch(set, "fire", _shot(bow))
	t.ok(got["ok"], "and it fires through the identical call: %s" % got["why"])
	t.near(float((got["shot"] as Dictionary)["speed"]), 55.0, EPSILON, "at an arrow's speed")

	# The clause that would fail silently. `ads_fov` is in `ranged_slow`'s optional list and the bow
	# does not supply it, because a bow is not brought to the eye the way a rifle is. A firing path
	# that had quietly come to require it would work for every gunpowder weapon ever authored and
	# break on the first bow — which is exactly the shape of bug TESTPACK exists to catch.
	t.ok(not (bow.data.get("stats", {}) as Dictionary).has("ads_fov"),
		"the bow declares no `ads_fov`, which `ranged_slow` lists as optional")
	t.ok(got["ok"], "and firing it does not need one")

	# Neither weapon is named anywhere in the core. Asserted against the source rather than trusted,
	# because this is the rule that decays one reasonable-looking line at a time.
	for path in ["res://core/verbs/fire.gd", "res://core/combat/ballistics.gd"]:
		var source := FileAccess.get_file_as_string(path).to_lower()
		t.ok(not source.contains("core:rifle") and not source.contains("testpack:bow"),
			"%s names neither weapon" % path)


## The bet, made visible. One formula, one gravity, no branch — and a bullet shoots flat while an
## arrow has to be lobbed, purely because two numbers in two pack files differ.
func _the_difference_is_entirely_the_numbers(t: TestContext, world: Dictionary,
		set: VerbSet) -> void:
	var bullet := Ballistics.drop_at(150.0, 40.0)
	var arrow := Ballistics.drop_at(55.0, 40.0)
	t.near(bullet, 0.711, 0.01, "at 40 m a rifle round has dropped about 0.7 m")
	t.near(arrow, 5.289, 0.01, "and an arrow about 5.3 m")
	t.ok(arrow > bullet * 7.0, "which is the difference between a flat crack and a lobbed arc")

	# Same gravity as everything else in the world, and deliberately not the walker's 22. Two
	# gravities in one trajectory space is the bug where a shell and its own debris land in
	# different places, and nobody notices until C5.
	var world_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 0.0))
	t.near(Ballistics.GRAVITY, world_gravity, EPSILON,
		"a projectile falls at the world's gravity, checked against the project setting itself")
	t.ok(not is_equal_approx(Ballistics.GRAVITY, Walker.GRAVITY),
		"which is not the walker's, because a character is allowed to disagree about jumping")

	# Spread stays inside what the asset asked for. Bounded rather than exact: the roll is random,
	# the ceiling is policy.
	var rng := RandomNumberGenerator.new()
	var widest := 0.0
	for i in 200:
		rng.seed = SEED + i
		var away := Ballistics.scatter(Vector3.FORWARD, 0.16, rng).angle_to(Vector3.FORWARD)
		widest = maxf(widest, away)
	t.ok(widest <= 0.16 + EPSILON, "no shot goes further off true than its spread allows: %.4f" % widest)
	t.ok(widest > 0.10, "and the spread is actually used rather than being a decoration")


## "at a cost in ammunition and time" — the two things that make a bolt rifle feel like one, both
## read off the asset.
func _at_a_cost_in_ammunition_and_time(t: TestContext, world: Dictionary, set: VerbSet) -> void:
	var rifle := FixtureWorld.asset(world, "core:rifle")
	if rifle == null:
		return
	var stats: Dictionary = rifle.data.get("stats", {})
	var state := {}
	var now := 0.0

	# Five rounds, and the cycle refuses the sixth before the magazine does.
	var immediate := _shot(rifle)
	immediate["state"] = VerbFire.perform(_shot(rifle))["state"]
	immediate["now"] = 0.0
	var early := Verbs.dispatch(set, "fire", immediate)
	t.ok(not early["ok"], "firing again inside the cycle is refused")
	t.ok(String(early["why"]).contains("still cycling"), "and says so: %s" % early["why"])

	for i in 5:
		var request := _shot(rifle)
		request["state"] = state
		request["now"] = now
		var got := Verbs.dispatch(set, "fire", request)
		t.ok(got["ok"], "round %d of the magazine fires" % (i + 1))
		state = got["state"]
		now += float(stats["cycle"])

	var dry := _shot(rifle)
	dry["state"] = state
	dry["now"] = now
	var empty := Verbs.dispatch(set, "fire", dry)
	t.ok(not empty["ok"], "and the sixth is refused because there are five rounds in it")
	t.ok(String(empty["why"]).contains("empty"), "saying which: %s" % empty["why"])

	# Running dry is discovered by the next shot, not announced by the last — which is what a
	# bolt-action actually feels like.
	var refilled := VerbFire.refill(stats, state, now)
	t.eq(int(refilled["rounds"]), 5, "reloading puts the magazine back")
	t.ok(refilled.has("ready_at"), "and the weapon is busy while it happens")
	t.near(float(refilled["ready_at"]), now + 3.4, EPSILON, "and takes the time the asset says")


## Determinism. C8 has to reproduce a shot on a machine that did not roll it, and a global `randf()`
## makes that impossible in a way that surfaces as "hits sometimes disagree" two milestones later.
func _the_same_shot_twice(t: TestContext, world: Dictionary, set: VerbSet) -> void:
	var rifle := FixtureWorld.asset(world, "core:rifle")
	if rifle == null:
		return
	var first: Dictionary = Verbs.dispatch(set, "fire", _shot(rifle))["shot"]
	var again: Dictionary = Verbs.dispatch(set, "fire", _shot(rifle))["shot"]
	t.ok(Vector3(first["velocity"]).is_equal_approx(Vector3(again["velocity"])),
		"the same seed gives the same shot, exactly")

	var other := _shot(rifle)
	(other["rng"] as RandomNumberGenerator).seed = SEED + 1
	var different: Dictionary = Verbs.dispatch(set, "fire", other)["shot"]
	t.ok(not Vector3(first["velocity"]).is_equal_approx(Vector3(different["velocity"])),
		"and a different seed gives a different one, so the spread is real")

	var no_rng := _shot(rifle)
	no_rng.erase("rng")
	var refused := Verbs.dispatch(set, "fire", no_rng)
	t.ok(not refused["ok"], "firing without a seeded generator is refused rather than allowed")
	t.ok(String(refused["why"]).contains("C8"), "naming what it would break: %s" % refused["why"])


## One shot's worth of request, from an asset's own stat block. Fresh generator each time, seeded
## the same, so any two calls are comparable.
func _shot(asset: ResolvedAsset) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return {
		"stats": asset.data.get("stats", {}),
		"origin": Vector3(0.0, 1.5, 0.0),
		"aim": Vector3.FORWARD,
		"now": 0.0,
		"rng": rng,
	}
