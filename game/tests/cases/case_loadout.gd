extends TestCase
## What a soldier carries, and therefore what a soldier can do. `CHECKLIST` §4.
##
## The claim being tested is small to state and is the last structural piece of C4: **classes pick
## slots, packs fill them.** A class declares the archetype slots it goes out with; a `kit` says
## which asset is in each; and the core never learns what a Lee-Enfield is.
##
## The assertion that makes it worth having is the derived one. A class does not list verbs and
## could not if it wanted to. It lists slots, each slot already says which verbs dispatch it, and
## what a soldier can do falls out of that union. So `core:rifleman` can dig — not because anybody
## wrote "riflemen can dig", but because the entrenching tool in his hands is in `melee_light`,
## which C4's registry review put under both `melee` and `dig`. **Take the shovel out of his kit and
## he stops being able to dig, in the same edit**, with no second list to keep in step.
##
## That is the whole reason the review refused to add an `entrenching` slot: a shovel that had to
## choose between being a weapon and being a tool would have made this untrue.

const PACKS := "res://packs"
const FIXTURES := "res://tests/fixtures/loadout"


func case_name() -> String:
	return "loadout"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(PACKS)
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	var registry := SlotSet.new()
	if not (set.load_core() and registry.load_core()):
		t.fail("core data would not load")
		return

	_a_class_is_a_soldier_plus_a_kit(t, world, set, registry)
	_what_he_can_do_is_derived(t, world, set, registry)
	_a_pack_class_needs_no_core_changes(t, world, set, registry)
	_the_refusals(t, world, set, registry)


func _a_class_is_a_soldier_plus_a_kit(t: TestContext, world: Dictionary, set: VerbSet,
		registry: SlotSet) -> void:
	var rifleman := FixtureWorld.asset(world, "core:rifleman")
	t.ok(rifleman != null, "`core:rifleman` exists")
	if rifleman == null:
		return

	# `extends`, doing the job C1 built it for: everything about how this man moves comes from
	# `core:soldier` and the only thing added is what is in his hands.
	t.ok(rifleman.inherited(), "and is a soldier plus a kit rather than a second soldier")
	t.ok(rifleman.data.has("locomotion"),
		"inheriting the gait table it never mentions: %s" % rifleman.source_of("locomotion"))
	t.eq(rifleman.source_of("locomotion"), "core:soldier", "straight off the body it extends")
	t.eq(rifleman.parts().size(), 15, "and all fifteen of its parts")

	var kit := Loadout.of(rifleman, world["resolver"], set, registry)
	t.ok(kit.is_valid(), "the loadout builds: %s" % [", ".join(kit.errors)])
	t.eq(kit.slots.size(), 3, "carrying three things")
	t.eq(kit.item("ranged_slow"), "core:rifle", "a rifle")
	t.eq(kit.item("melee_light"), "core:shovel", "an entrenching tool")
	t.eq(kit.item("explosive_thrown"), "core:grenade", "and two grenades")


## The payoff. Nothing below is authored anywhere; all of it is worked out from the slots.
func _what_he_can_do_is_derived(t: TestContext, world: Dictionary, set: VerbSet,
		registry: SlotSet) -> void:
	var rifleman := FixtureWorld.asset(world, "core:rifleman")
	if rifleman == null:
		return
	var kit := Loadout.of(rifleman, world["resolver"], set, registry)

	t.eq(",".join(kit.verbs(set)), "dig,fire,melee,throw",
		"what he can do is the union of what he carries — and he never declares a verb")
	t.ok(not rifleman.data.has("verbs"),
		"there is no `verbs` field on the class, and there is nowhere in the format to put one")

	t.ok(kit.can(set, "fire"), "he can fire, because something in his hands is `ranged_slow`")

	# End to end, which is C4's done-condition arriving through the front door: a class out of a pack
	# file, holding a weapon out of a pack file, firing it through the dispatcher — with the core
	# never having been told what either of them is.
	var rifle := (world["resolver"] as AssetResolver).get_asset(kit.item("ranged_slow"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var shot := Verbs.dispatch(set, "fire", {
		"stats": rifle.data.get("stats", {}), "origin": Vector3(0.0, 1.5, 0.0),
		"aim": Vector3.FORWARD, "now": 0.0, "state": kit.state["ranged_slow"], "rng": rng })
	t.ok(shot["ok"], "and firing the weapon out of his own kit works: %s" % shot["why"])
	t.eq(int((shot["state"] as Dictionary)["rounds"]), 4, "spending one of the five he came out with")
	t.ok(kit.can(set, "dig"),
		"and he can dig — not because anybody said so, but because his tool is `melee_light`")
	t.ok(not kit.can(set, "enter"), "he cannot get into a vehicle, having no vehicle")

	# The edit that proves it is derived rather than coincidental: take the shovel away and digging
	# goes with it, in the same change, with no second list to remember.
	var stripped := rifleman.data.duplicate(true)
	stripped["loadout"] = ["ranged_slow", "explosive_thrown"]
	(stripped["kit"] as Dictionary).erase("melee_light")
	var lighter := ResolvedAsset.new()
	lighter.id = "core:rifleman"
	lighter.data = stripped
	var without := Loadout.of(lighter, world["resolver"], set, registry)
	t.ok(without.is_valid(), "a rifleman who left his shovel behind is still a legal class")
	t.ok(not without.can(set, "dig"), "and cannot dig any more")
	t.ok(not without.can(set, "melee"), "nor swing at anybody, for the same one reason")
	t.ok(without.can(set, "fire"), "while still being able to fire")


## TESTPACK's half, which is the same claim `testpack:bow` makes one layer down.
func _a_pack_class_needs_no_core_changes(t: TestContext, world: Dictionary, set: VerbSet,
		registry: SlotSet) -> void:
	var archer := FixtureWorld.asset(world, "testpack:archer")
	t.ok(archer != null, "`testpack:archer` exists, out of a pack that is not core")
	if archer == null:
		return

	var kit := Loadout.of(archer, world["resolver"], set, registry)
	t.ok(kit.is_valid(), "and builds through the identical call: %s" % [", ".join(kit.errors)])
	t.eq(kit.item("ranged_slow"), "testpack:bow",
		"with a bow where the rifleman has a rifle, in the same slot")
	t.ok(kit.can(set, "fire"), "so he fires by the same verb")
	t.ok(kit.can(set, "dig"), "and digs, carrying a core tool in a pack class")
	t.ok(not kit.can(set, "throw"), "but throws nothing, carrying nothing thrown")

	# A class in a mod extending a core body, holding one core item and one of its own, and nothing
	# in the engine knows any of it happened.
	t.ok(archer.inherited(), "a pack class extends the core soldier")
	t.eq(archer.source_of("locomotion"), "core:soldier", "and moves like one")


## Every refusal has a way of being got wrong that would otherwise fail much later and much quieter.
func _the_refusals(t: TestContext, world: Dictionary, set: VerbSet, registry: SlotSet) -> void:
	t.ok(not Loadout.of(null, world["resolver"], set, registry).is_valid(),
		"a loadout with no class is refused")

	var empty := ResolvedAsset.new()
	empty.id = "test:pacifist"
	empty.data = { "kind": "character", "slot": "infantry" }
	var nothing := Loadout.of(empty, world["resolver"], set, registry)
	t.ok(not nothing.is_valid(), "a class carrying nothing is refused")
	t.ok(_said(nothing.errors, "authoring mistake"),
		"as a mistake rather than as a pacifist: %s" % [", ".join(nothing.errors)])

	var invented := ResolvedAsset.new()
	invented.id = "test:wrong"
	invented.data = { "loadout": ["trebuchet"] }
	t.ok(_said(Loadout.of(invented, world["resolver"], set, registry).errors, "not a slot"),
		"a class carrying a slot the registry never heard of is refused")

	# The one that matters most. Without it a class could put a horse in a rifle slot, and the first
	# thing to notice would be `fire` reading a stat block with no `velocity` in it — two systems
	# away from the file that was wrong.
	var muddled := ResolvedAsset.new()
	muddled.id = "test:muddled"
	muddled.data = { "loadout": ["ranged_slow"], "kit": { "ranged_slow": "core:shovel" } }
	var wrong := Loadout.of(muddled, world["resolver"], set, registry)
	t.ok(not wrong.is_valid(), "an asset put in a slot it does not declare is refused")
	t.ok(_said(wrong.errors, "melee_light"),
		"naming what it actually is: %s" % [", ".join(wrong.errors)])

	var missing := ResolvedAsset.new()
	missing.id = "test:ghost"
	missing.data = { "loadout": ["ranged_slow"], "kit": { "ranged_slow": "core:nonexistent" } }
	t.ok(_said(Loadout.of(missing, world["resolver"], set, registry).errors, "no such asset"),
		"and a kit naming an asset nobody wrote is refused")

	var elsewhere := ResolvedAsset.new()
	elsewhere.id = "test:elsewhere"
	elsewhere.data = { "loadout": ["ranged_slow"], "kit": { "melee_light": "core:shovel" } }
	t.ok(_said(Loadout.of(elsewhere, world["resolver"], set, registry).errors, "does not carry"),
		"as is a kit filling a slot the class never declared")

	var twice := ResolvedAsset.new()
	twice.id = "test:twice"
	twice.data = { "loadout": ["ranged_slow", "ranged_slow"] }
	t.ok(_said(Loadout.of(twice, world["resolver"], set, registry).errors, "one pair of hands"),
		"and a class carrying the same slot twice")


func _said(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false
