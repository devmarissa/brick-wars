extends TestCase
## Manifests, semver ranges, and the order packs load in. FORMAT-SPEC §9, §11.
##
## The thing being proven here is not that good packs load. It is that bad ones are refused
## one at a time — that a broken workshop upload is disabled, reported with a reason its
## author can act on, and stepped over, while every other pack in the folder loads exactly
## as it would have (FORMAT-SPEC §10).
##
## The fixture folder is deliberately a mess: three packs that form a working chain, one
## with a manifest full of mistakes, one that needs a core from the future, one whose base
## pack has moved on without it, one that needs a pack nobody installed, three in a ring,
## and a folder that is not a pack at all. All of it goes in at once, because a validator
## that only works on one problem at a time has not met a real content folder.

const PACKS := "res://tests/fixtures/packs"
const DUPES := "res://tests/fixtures/packs_dupe"
const NOWHERE := "res://tests/fixtures/no_such_folder"


func case_name() -> String:
	return "pack order"


func run(t: TestContext) -> void:
	_versions(t)
	_ranges(t)
	_the_messy_folder(t)
	_refusing_core_takes_everything_with_it(t)
	_duplicate_ids(t)
	_manifest_rules(t)


func _versions(t: TestContext) -> void:
	var e: Array[String] = []
	t.eq(SemVer.parse("1.2.3", "x", e), Vector3i(1, 2, 3), "major.minor.patch")
	t.eq(SemVer.parse("0.4", "x", e), Vector3i(0, 4, 0), "a partial version fills in zeroes")
	t.eq(SemVer.parse("2", "x", e), Vector3i(2, 0, 0), "so does a bare major")
	t.eq(", ".join(e), "", "none of those are mistakes")

	# Prerelease tags are refused rather than half-understood. A range that gets silently
	# misparsed fails later, somewhere else, as a missing asset.
	t.eq(SemVer.parse("1.0.0-beta", "x", e), Vector3i(-1, -1, -1), "a prerelease tag is refused")
	t.ok(_mentions(e, "prerelease"), "by name: " + "; ".join(e))

	e.clear()
	t.eq(SemVer.parse("1.x", "x", e), Vector3i(-1, -1, -1), "so is a wildcard component")
	t.eq(SemVer.parse("1.2.3.4", "x", e), Vector3i(-1, -1, -1), "and a fourth component")

	t.eq(SemVer.compare(Vector3i(0, 4, 0), Vector3i(0, 10, 0)), -1,
		"0.4 is older than 0.10 — numbers, not text")
	t.eq(SemVer.compare(Vector3i(1, 0, 0), Vector3i(1, 0, 0)), 0, "equal versions compare equal")


func _ranges(t: TestContext) -> void:
	var e: Array[String] = []
	t.ok(SemVer.satisfies("0.4.0", ">=0.4", "x", e), "0.4.0 satisfies >=0.4")
	t.ok(not SemVer.satisfies("0.3.9", ">=0.4", "x", e), "0.3.9 does not")
	t.ok(SemVer.satisfies("0.4.7", ">=0.3 <0.5", "x", e), "a two-clause range is an intersection")
	t.ok(not SemVer.satisfies("0.5.0", ">=0.3 <0.5", "x", e), "and `<0.5` excludes 0.5.0 itself")
	t.ok(SemVer.satisfies("9.9.9", "*", "x", e), "`*` takes anything")
	t.ok(SemVer.satisfies("1.2.3", "=1.2.3", "x", e), "`=` pins")
	t.eq(", ".join(e), "", "all of that is legal range syntax")

	# The unsupported operators are the ones a semver-literate author will reach for first,
	# so they are refused with the supported list rather than misread.
	for bad in ["^1.0", "~1.0", ">=1.0 || <0.5", "1.0"]:
		e.clear()
		t.ok(not SemVer.is_valid_range(bad, "x", e), "`%s` is refused" % bad)
		t.ok(_mentions(e, "Supported:"), "`%s` is told what it could have written instead" % bad)


func _the_messy_folder(t: TestContext) -> void:
	var installed := PackSet.new()
	t.ok(not installed.discover([PACKS] as Array[String]), "a folder with broken packs in it reports so")

	t.eq(installed.order, [&"base_ok", &"child_ok", &"grandchild_ok"] as Array[StringName],
		"the good chain loads, dependencies first")
	t.ok(installed.is_enabled(&"child_ok"), "and every pack in it is enabled")

	# Determinism. Two scans of the same folder, same order — otherwise a pack that wins an
	# id collision on one server loses it on another.
	var again := PackSet.new()
	again.discover([PACKS] as Array[String])
	t.eq(", ".join(again.order), ", ".join(installed.order), "the order is identical between runs")

	t.ok(_reason(installed, &"too_new_core").contains("needs core >=9.0"),
		"a pack from the future is refused: " + _reason(installed, &"too_new_core"))
	t.ok(_reason(installed, &"too_new_core").contains("C1"),
		"and told which core this is, in terms of the build order")

	t.ok(_reason(installed, &"needs_missing").contains("not installed"),
		"a pack needing something nobody has: " + _reason(installed, &"needs_missing"))

	# The refusal the whole semver subset exists for: the base pack moved, and this one has
	# never been tested against where it moved to.
	t.ok(_reason(installed, &"needs_newer").contains("0.3.2"),
		"a base pack that has moved on: " + _reason(installed, &"needs_newer"))

	# A pack whose id is itself malformed cannot be keyed by id or disabled by name, so it
	# is reported against its folder and dropped. Everything else gets to exist and be
	# switched off, which is what lets the boot report say "installed but off" rather than
	# leaving the player wondering where their pack went.
	t.ok(_mentions(installed.errors, "packs/bad_manifest"),
		"a pack with no usable id is reported against its folder, not crashed on")
	t.ok(_mentions(installed.errors, "is not a pack id"),
		"and the manifest's own problems come with it")

	for id in [&"ring_a", &"ring_b", &"ring_c"]:
		t.ok(_reason(installed, id).contains("cycle"), "%s is caught in the cycle" % id)
	t.ok(_reason(installed, &"ring_a").contains("ring_b") and _reason(installed, &"ring_a").contains("ring_c"),
		"and the message names every pack in the ring, not just two of them")

	t.ok(not installed.packs.has(&"notapack"),
		"a folder with no pack.json is not a broken pack, it is not a pack")

	_cascade(t, installed)

	# The point of all of the above: none of it touched the working chain.
	t.eq(installed.order.size(), 3, "seven refusals and the three good packs still loaded")
	t.ok(installed.report().contains("OFF"), "the boot report lists what is off and why")

	var empty := PackSet.new()
	t.ok(empty.discover([NOWHERE] as Array[String]), "a folder that does not exist is not an error")
	t.eq(empty.order.size(), 0, "it just has no packs in it")


## Cascade: a pack whose dependency was refused is refused too, and inherits the reason.
## The author of the dependent pack did nothing wrong — their manifest is correct, their
## dependency is installed, and it is at a version they declared. Pointing them at their
## own manifest would waste their evening, so they get told the actual cause instead.
func _cascade(t: TestContext, installed: PackSet) -> void:
	var why := _reason(installed, &"needs_bad")
	t.ok(why.contains("too_new_core"), "a pack whose dependency is disabled is disabled too")
	t.ok(why.contains("is disabled"), "and inherits the reason rather than being blamed: " + why)
	t.ok(_reason(installed, &"child_ok").is_empty(), "nothing cascaded onto the good chain")


## The one edge in the graph that nobody declares. `core_version` on a manifest *is* the
## dependency on core, which is why `extends core:...` needs nothing in `depends` — and the
## cascade has to know that too, or a refused core leaves every pack enabled and each one
## fails later at resolution with "no enabled pack publishes `core:...`". That message sends
## an author to look at their own file for a problem that is nowhere near it.
##
## Unreachable in the shipped game, because a core that will not load is its own fatal path.
## Asserted anyway: the cascade should be true on its own terms rather than because nothing
## happens to exercise it.
func _refusing_core_takes_everything_with_it(t: TestContext) -> void:
	var installed := PackSet.new()
	installed.discover(["res://packs"] as Array[String])
	t.ok(installed.is_enabled(&"testpack"), "a pack that extends core loads normally")

	installed.refuse(&"core", "pretend the sky fell")
	var why := _reason(installed, &"testpack")
	t.ok(why.contains("`core` is disabled"), "and is disabled with core: " + why)
	t.ok(why.contains("sky fell"), "inheriting core's reason rather than being blamed itself")
	t.eq(installed.order.size(), 0, "with nothing at all left enabled")


func _duplicate_ids(t: TestContext) -> void:
	var installed := PackSet.new()
	installed.discover([DUPES] as Array[String])
	t.ok(not installed.is_enabled(&"twinned"), "two packs claiming one id — neither loads")
	var why := _reason(installed, &"twinned")
	t.ok(why.contains("first") and why.contains("second"),
		"and the message names both folders, since only a human can pick: " + why)


func _manifest_rules(t: TestContext) -> void:
	var pack := Pack.new()
	t.ok(not pack.load_from("res://tests/fixtures/packs/bad_manifest"), "a bad manifest fails")
	var e := pack.errors

	t.ok(_mentions(e, "is not a pack id"), "`Bad Manifest` is not a pack id")
	t.ok(_mentions(e, "`name` is required"), "a pack has to say what it is called")
	t.ok(_mentions(e, "one point oh"), "a version has to be a version")
	t.ok(_mentions(e, "^0.1"), "an unsupported core_version range is named")
	t.ok(_mentions(e, "`version` is required"), "a dependency without a range is refused")
	t.ok(_mentions(e, "factions"), "three factions is refused — core fixes the shape at two")

	var good := Pack.new()
	t.ok(good.load_from("res://tests/fixtures/packs/base_ok"), "a good manifest loads")
	t.eq(good.id, &"base_ok", "id")
	t.eq(good.version, "0.3.2", "version")
	t.eq(good.qualify("prop_crate"), "base_ok:prop_crate", "bare names qualify into the pack")
	t.eq(good.qualify("core:prop_crate"), "core:prop_crate", "qualified ones are left alone")

	var child := Pack.new()
	child.load_from("res://tests/fixtures/packs/child_ok")
	t.ok(child.depends_on(&"base_ok"), "a declared dependency is visible to the extends resolver")
	t.ok(not child.depends_on(&"core"), "an undeclared one is not")

	# Unknown fields load anyway with a warning — FORMAT-SPEC §10. A pack written for a
	# later core should degrade, not die.
	var future := Pack.new()
	t.ok(future.load_from("res://tests/fixtures/packs/grandchild_ok"), "an unknown field still loads")
	t.ok(_mentions(future.warnings, "mystery_field"), "and says it ignored it")


func _reason(installed: PackSet, id: StringName) -> String:
	return installed.disabled.get(id, "")


func _mentions(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false
