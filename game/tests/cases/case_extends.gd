extends TestCase
## `extends`, and the paper trail it has to leave. FORMAT-SPEC §6, §10.
##
## Two things are being proven. The first is that every row of the merge table does exactly
## what the table says and nothing adjacent to it — scalars replace, objects merge key by
## key, `parts` wipes, `parts+` appends, `parts~` nudges one member and leaves the rest of it
## inherited. Those five rows are the whole feature, and a variant that costs five lines only
## stays worth having while all five behave predictably.
##
## The second is the one the fixture folder is shaped around: seven packs each break exactly
## one rule, all of them are in the folder at once, and the three good packs load anyway. A
## workshop upload that extends an asset its author deleted last week is a normal Tuesday.
## What is not acceptable is it taking the other three hundred packs with it.
##
## The fixtures are a separate root from `fixtures/packs`, which is about manifests. Mixing
## them would mean every new asset test had to keep the manifest test's pack count right.

const ASSETS := "res://tests/fixtures/assets"

const GOOD := [
	"alpha:crate_reinforced", "alpha:rifle_bolt", "alpha:rifle_carbine",
	"alpha:rifle_marksman", "alpha:rifle_sniper", "beta:rifle_issue", "core:prop_crate",
]


func case_name() -> String:
	return "extends"


func run(t: TestContext) -> void:
	var world := _load()
	_the_merge_table(t, world)
	_provenance(t, world)
	_depth_and_reach(t, world)
	_refusals(t, world)
	_nothing_else_broke(t, world)
	_determinism(t)


## The whole fixture set, read and resolved the way the content module does it.
func _load() -> Dictionary:
	var packs := PackSet.new()
	packs.discover([ASSETS] as Array[String])
	var index := AssetIndex.new()
	index.scan(packs)
	var resolver := AssetResolver.new()
	resolver.resolve_all(index, packs)
	return { "packs": packs, "index": index, "resolver": resolver }


func _the_merge_table(t: TestContext, world: Dictionary) -> void:
	var sniper := _asset(world, "alpha:rifle_sniper")
	t.ok(sniper != null, "the variant resolved at all")
	if sniper == null:
		return

	# Scalar row: the child's `name` wins, and the fields it never mentioned come down.
	t.eq(sniper.name(), "Scoped Rifle", "a scalar the child sets replaces the parent's")
	t.eq(sniper.kind(), "weapon", "a scalar it does not set is inherited")
	t.eq(String(sniper.data.get("slot", "")), "ranged_slow", "including the slot it fills")

	# Object row: `{"zoom": 4.0}` adds one stat and keeps the other four.
	var stats: Dictionary = sniper.data.get("stats", {})
	t.eq(stats.size(), 5, "the stat block deep-merged rather than being replaced")
	t.eq(float(stats.get("zoom", 0.0)), 4.0, "the new stat arrived")
	t.eq(float(stats.get("damage", 0.0)), 105.0, "the overridden one changed")
	t.eq(float(stats.get("velocity", 0.0)), 150.0, "and the untouched ones survived")

	# `parts~` row: one field of one named member, everything else about it inherited.
	var barrel := _part(sniper, "barrel")
	t.eq(ResolvedAsset.value_text(barrel.get("size")), "[3, 3, 30]", "`parts~` lengthened the barrel")
	t.eq(String(barrel.get("material", "")), "steel", "and left its material alone")
	t.eq(String(barrel.get("colour", "")), "gunmetal", "and its colour")

	# `parts+` row: appended, in order, after everything inherited.
	t.eq(sniper.parts().size(), 4, "the scope was added to the three inherited parts")
	t.eq(", ".join(sniper.part_names()), "receiver, barrel, stock, scope",
		"appended at the end, and the inherited order is untouched")
	t.eq(sniper.data.get("collider", []).size(), 1, "the collider list came down unmentioned")

	# List row without a suffix: wipe and redeclare.
	var carbine := _asset(world, "alpha:rifle_carbine")
	t.eq(carbine.parts().size(), 1, "`parts` with no suffix replaces the whole list")
	t.eq(float(carbine.data.get("stats", {}).get("damage", 0.0)), 95.0,
		"which does not touch anything that is not a part")

	# Baking. The base is merged into four different variants, and none of them may write
	# back into it — a shared dictionary here would mean the last variant to load quietly
	# rewrote the rifle every other one inherited from.
	var bolt := _asset(world, "alpha:rifle_bolt")
	t.eq(ResolvedAsset.value_text(_part(bolt, "barrel").get("size")), "[3, 3, 22]",
		"the base still has its own barrel after four variants merged over it")
	t.eq(bolt.parts().size(), 3, "and its own part count")


## FORMAT-SPEC §6: "a wrong number three levels up is a bad afternoon". This is the thing
## that makes it a two-minute one instead.
func _provenance(t: TestContext, world: Dictionary) -> void:
	var sniper := _asset(world, "alpha:rifle_sniper")
	t.eq(sniper.source_of("parts[barrel].size"), "alpha:rifle_sniper", "the patched field")
	t.eq(sniper.source_of("parts[barrel].material"), "alpha:rifle_bolt", "the inherited one next to it")
	t.eq(sniper.source_of("parts[scope].shape"), "alpha:rifle_sniper", "an appended part")
	t.eq(sniper.source_of("stats.zoom"), "alpha:rifle_sniper", "a stat the variant added")
	t.eq(sniper.source_of("stats.velocity"), "alpha:rifle_bolt", "one it inherited")
	t.eq(sniper.source_of("kind"), "alpha:rifle_bolt", "and a scalar it never mentioned")

	# A field nobody wrote down is a question with an answer, not a gap. This is the case
	# that catches "why is this zero" without anybody opening a file.
	t.eq(sniper.source_of("parts[barrel].jitter"), "core (default)", "an unwritten field is a default")

	# Three levels, so the field genuinely came from two documents ago.
	var marksman := _asset(world, "alpha:rifle_marksman")
	t.eq(marksman.source_of("stats.damage"), "alpha:rifle_sniper", "from the middle of the chain")
	t.eq(marksman.source_of("stats.capacity"), "alpha:rifle_bolt", "from the top of it")
	t.eq(float(marksman.data.get("stats", {}).get("zoom", 0.0)), 8.0, "and the leaf still wins")

	# The dump the spec asked for, in the spec's own layout.
	var dump := sniper.dump_part("barrel", { "jitter": 0.0 })
	t.ok(dump.contains("size      [3, 3, 30]   ← alpha:rifle_sniper"),
		"the provenance dump reads as specified:\n" + dump)
	t.ok(dump.contains("← core (default)"), "including the fields nobody wrote")
	t.ok(sniper.dump().contains("alpha:rifle_bolt → alpha:rifle_sniper"),
		"and the whole-asset dump shows the chain")

	# The whole-asset dump is the one a person reads at three in the morning, and both of the
	# ways it can quietly stop being readable are things a green test suite happily allowed
	# once already: a path wider than its column running into its own value, and container
	# rows printing an entire part list on one line under a single attribution.
	var whole := sniper.dump()
	t.ok(not whole.contains("\nparts "), "no row for the part list itself")
	t.ok(not whole.contains("\nparts[barrel] "), "nor for a part as a whole")
	var collided := ""
	for text in whole.split("\n"):
		var l := String(text)
		if not l.contains("←"):
			continue
		if l.get_slice("←", 0).strip_edges().split(" ", false).size() < 2:
			collided = l
			break
	t.eq(collided, "", "every row keeps its path and its value apart")


func _depth_and_reach(t: TestContext, world: Dictionary) -> void:
	var marksman := _asset(world, "alpha:rifle_marksman")
	t.eq(", ".join(marksman.chain), "alpha:rifle_bolt, alpha:rifle_sniper, alpha:rifle_marksman",
		"three levels is legal, and the chain is recorded base-first")

	# Cross-pack, declared: the thing the whole dependency apparatus exists to permit.
	var issue := _asset(world, "beta:rifle_issue")
	t.ok(issue != null, "a declared cross-pack extends is allowed")
	t.eq(float(issue.data.get("stats", {}).get("capacity", 0.0)), 10.0, "and merges normally")
	t.eq(issue.source_of("stats.damage"), "alpha:rifle_bolt", "across the pack boundary")

	# Core is the exception to the declaration rule, because `core_version` already is the
	# declaration. Every pack in existence writing the same `depends` line would be theatre.
	var crate := _asset(world, "alpha:crate_reinforced")
	t.ok(crate != null, "extending core needs no declared dependency")
	t.eq(String(_part(crate, "slat").get("material", "")), "steel", "and patches across it")
	t.eq(String(_part(crate, "body").get("material", "")), "plank", "leaving the rest of core's crate")

	# §8 reference resolution: own pack first, then core.
	var index: AssetIndex = world["index"]
	t.eq(index.resolve_reference("rifle_bolt", &"alpha"), "alpha:rifle_bolt", "a bare name is own-pack first")
	t.eq(index.resolve_reference("prop_crate", &"alpha"), "core:prop_crate", "then core")
	t.eq(index.resolve_reference("core:prop_crate", &"beta"), "core:prop_crate", "qualified names are left alone")


func _refusals(t: TestContext, world: Dictionary) -> void:
	t.ok(_why(world, &"sneaky").contains("does not declare a dependency"),
		"reaching into an undeclared pack: " + _why(world, &"sneaky"))
	t.ok(_why(world, &"sneaky").contains("alpha:rifle_bolt"),
		"and the message names the asset as well as both packs")

	var deep := _why(world, &"toodeep")
	t.ok(deep.contains("4 deep") and deep.contains("cap is 3"), "a fourth level is refused: " + deep)
	for link in ["alpha:rifle_bolt", "alpha:rifle_sniper", "alpha:rifle_marksman", "toodeep:overreach"]:
		t.ok(deep.contains(link), "the depth message names %s" % link)

	t.ok(_why(world, &"ghost").contains("core:prop_barrel"),
		"extending something nobody publishes: " + _why(world, &"ghost"))

	var ring := _why(world, &"ouroboros")
	t.ok(ring.contains("cycle"), "a cycle is named as one: " + ring)
	t.ok(ring.contains("ouroboros:a") and ring.contains("ouroboros:b"), "and names both ends")

	# Both `parts~` mistakes, from two assets in one pack, reported in the same run. A
	# validator that stops at the first is a validator people fix their packs against one
	# message per run, and they give up around message three.
	var patchy := _why(world, &"patchy")
	t.ok(patchy.contains("has no `name`"), "a patch with no name is refused: " + patchy)
	t.ok(patchy.contains("patchy:base"), "and names the base asset, which is the file to fix")
	t.ok(patchy.contains("no member by that name"), "so is a patch naming a part that is not there")
	t.ok(patchy.contains("Present: body"), "and it is told what it could have named")

	t.ok(_why(world, &"dupes").contains("already claimed"),
		"two files claiming one id: " + _why(world, &"dupes"))
	t.ok(_why(world, &"wrongowner").contains("puts this asset in pack `alpha`"),
		"a pack cannot publish into another pack's namespace: " + _why(world, &"wrongowner"))


func _nothing_else_broke(t: TestContext, world: Dictionary) -> void:
	var packs: PackSet = world["packs"]
	var resolver: AssetResolver = world["resolver"]

	t.eq(", ".join(packs.order), "core, alpha, beta",
		"seven packs refused, and the three good ones loaded in dependency order")
	t.eq(", ".join(resolver.sorted_ids()), ", ".join(GOOD),
		"with every asset they publish resolved")
	t.eq(packs.disabled.size(), 7, "and the refusals stayed where they were")

	# A disabled pack's assets must not be reachable, or an `extends` into one would half-load
	# the very thing that was refused.
	t.ok(not resolver.has("patchy:base"), "a good asset in a refused pack does not load either")
	t.ok(resolver.get_asset("nothing:here") == null, "and an id nobody publishes is just absent")


## Byte-identical twice, including the provenance. Load order is netcode-visible, and a
## provenance map that changed between runs would make `--resolve` a coin toss.
func _determinism(t: TestContext) -> void:
	var first := _load()
	var second := _load()
	t.eq(", ".join((first["packs"] as PackSet).order), ", ".join((second["packs"] as PackSet).order),
		"the pack order is the same on the second run")
	var a: ResolvedAsset = (first["resolver"] as AssetResolver).get_asset("alpha:rifle_sniper")
	var b: ResolvedAsset = (second["resolver"] as AssetResolver).get_asset("alpha:rifle_sniper")
	t.eq(a.dump(), b.dump(), "and so is every field, its value, and where it came from")


func _asset(world: Dictionary, id: String) -> ResolvedAsset:
	return (world["resolver"] as AssetResolver).get_asset(id)


func _part(asset: ResolvedAsset, part_name: String) -> Dictionary:
	for part in asset.parts():
		if typeof(part) == TYPE_DICTIONARY and String(part.get("name", "")) == part_name:
			return part
	return {}


func _why(world: Dictionary, pack_id: StringName) -> String:
	return String((world["packs"] as PackSet).disabled.get(pack_id, ""))
