extends TestCase
## What a refusal costs, and what the validator admits it is not checking. FORMAT-SPEC §10.
##
## `case_validator.gd` is the other half — whether a rule refuses the right thing with a message
## worth reading. This one starts after that verdict. Failure is *scoped*, so a pack that is wrong
## goes down alone; it *cascades*, so a variant of a refused asset does not quietly load as though
## its base were fine; core failing its own rules is a broken build rather than a pack problem;
## and the rules §10 asks for that nothing enforces yet are announced at every boot.
##
## That last one is a load-bearing habit rather than a nicety. A written rule that silently does
## not run is worse than one nobody wrote, because everyone downstream builds as though it were
## holding — so `AssetValidator.DORMANT` says out loud what it is not doing, and this case fails
## if that list stops matching what is actually unenforced.

const FIXTURES := "res://tests/fixtures/validate"
const FIXTURES_CORE := "res://tests/fixtures/validate_core"


func case_name() -> String:
	return "refusal"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES)
	if world.is_empty():
		t.fail("core content data would not load, so nothing below means anything")
		return

	_scoped_and_cascading(t, world)
	_when_core_is_the_broken_one(t)
	_dormant_rules(t)


func _scoped_and_cascading(t: TestContext, world: Dictionary) -> void:
	var packs: PackSet = world["packs"]
	var resolver: AssetResolver = world["resolver"]

	t.ok(not packs.is_enabled(&"broken"), "one refused asset disables the whole pack")
	t.ok(not resolver.has("broken:crate_fine"),
		"including the assets in it that were perfectly fine — it never half-loads")

	# `heir` broke no rule. It is off because the thing it is a variant of is off, and an
	# asset built on a refused one is not a thing that can be trusted to be what it says.
	t.ok(not packs.is_enabled(&"heir"), "a pack built on a refused one goes with it")
	t.ok(not resolver.has("heir:crate_tall"), "and its assets leave the resolved set too")
	t.ok(String(packs.disabled.get(&"heir", "")).contains("broken"),
		"and it is told which pack took it down: " + String(packs.disabled.get(&"heir", "")))

	# The isolation claim in one number: two packs off, two on, and every asset still standing
	# belongs to one of the two that are on.
	t.eq(packs.order.size(), 2, "the two clean packs are still in the load order")
	t.eq((world["validator"] as AssetValidator).refused.size(), 1,
		"the validator refused one pack, and the manifest graph took `heir` down after it")
	for id in resolver.sorted_ids():
		t.ok(packs.is_enabled((resolver.resolved[id] as ResolvedAsset).owner),
			"%s belongs to a pack that is still enabled" % id)


## Core failing its own rules, which is a different event from a pack failing.
##
## Nobody declares `depends` on core — `core_version` on the manifest is that declaration —
## so the edge from a pack to core is implicit, and for a while `PackSet._cascade()` walked
## straight past it. That left the validator's own asset-level cascade as the only thing
## standing between a refused base and a variant of it loading as though the base were fine,
## which is a lot of weight on the later of the two passes.
##
## `_cascade()` knows about the edge now, so it fires first and a dependent pack is told the
## thing it can actually act on: core is off, and here is the file and line that turned it
## off. Naming which of core's assets the pack happened to extend was more precise and less
## useful — a modder cannot fix `core:prop_crate` and does not need to know they touched it.
## The validator's cascade is still there underneath and still correct; it is a backstop now
## rather than the only guard.
func _when_core_is_the_broken_one(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES_CORE)
	if world.is_empty():
		t.fail("core content data would not load")
		return
	var validator: AssetValidator = world["validator"]
	var packs: PackSet = world["packs"]

	t.ok(validator.core_failed, "core breaking its own rules is reported as its own kind of event")
	t.ok(not packs.is_enabled(&"core"), "and core is refused rather than excused")
	t.ok(_about(world, "core:prop_bad").contains("`granite` is not a material"),
		"for the asset that actually broke a rule: " + _about(world, "core:prop_bad"))

	t.ok(not packs.is_enabled(&"rider"),
		"a pack extending core goes down with it, having declared no dependency to cascade along")

	# The reason it gets is core's, not its own. An author whose pack went down because core
	# broke has done nothing to fix, and the useful thing to hand them is the file and line
	# that actually broke — not a note about which core asset they happened to extend.
	var why := String(packs.disabled.get(&"rider", ""))
	t.ok(why.contains("`core` is disabled"), "and told the cause is core, not itself: " + why)
	t.ok(why.contains("bad.json"), "with the file that broke, which is the actionable part")
	t.ok(not why.contains("rider"), "and is not blamed for anything of its own")
	t.ok((world["resolver"] as AssetResolver).resolved.is_empty(),
		"nothing at all is left resolved, because everything descended from core")


## The rules §10 asks for that nothing here enforces yet, named rather than counted — asserted so
## that building one deletes a line from a test as well as from a constant. It was a bare count
## until the constraint budget split in two at C2 (per-object has a measured number now, from the
## horse; per-scene cannot have one until there are vehicles), and `got 4, wanted 3` does not say
## that.
func _dormant_rules(t: TestContext) -> void:
	var expected := ["core animation states", "budget per object", "budget per scene",
		"derived-material multipliers"]
	var report := AssetValidator.dormant_report()
	for topic in expected:
		t.ok(report.contains(topic), "the boot report names the `%s` rule" % topic)
	t.eq(AssetValidator.DORMANT.size(), expected.size(), "and declares exactly those")


## Everything said about one asset, run together — the messages are checked by content and
## an assertion per line would break every time one of them is reworded.
func _about(world: Dictionary, id: String) -> String:
	var said := ""
	for problem in (world["validator"] as AssetValidator).errors:
		if String(problem).begins_with(id + " —"):
			said += String(problem) + "\n"
	return said if said != "" else "(nothing was said about %s)" % id
