extends TestCase
## The validator: every rule FORMAT-SPEC §10 can enforce today, and the refusals it writes.
##
## The fixture root is four packs. `core` and `good` are clean and have to stay loaded no
## matter what else is in the folder. `broken` holds one asset per rule, all of them at once,
## because a validator that stops at the first mistake is one people fix their pack against
## at a rate of one message per run — and they give up around the third. `heir` is valid in
## itself and built on `broken`, which is the part that is easy to get wrong: a variant of an
## asset that was not allowed to exist must not stay loaded because it was fine on its own.
##
## This half is the *rules*: what gets refused, and whether the message is worth reading. What a
## refusal then costs — which packs go down with it, and which rules the validator admits it is
## not running at all — is `case_refusal.gd`. The two were one file until C2 pushed it two lines
## past the cap, and the seam is real: one asks "is this content legal", the other asks "and what
## happens to the world when it is not".
##
## What is being checked is the message as much as the verdict. `broken:typo` failing is not
## worth much; `broken:typo` failing with the file, the line, the offending word and `Did you
## mean \`steel\`?` is the difference between a workshop that stays coherent and one that
## turns into a colour-clashing mess in a month.

const FIXTURES := "res://tests/fixtures/validate"
const FIXTURES_CORE := "res://tests/fixtures/validate_core"

const GOOD := ["core:prop_crate", "good:prop_barrel", "good:rifle_service",
	"good:crate_banded", "good:prop_sign"]


func case_name() -> String:
	return "validator"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES)
	if world.is_empty():
		t.fail("core content data would not load, so nothing below means anything")
		return

	_the_good_ones_load(t, world)
	_part_rules(t, world)
	_rig_rules(t, world)
	_asset_rules(t, world)
	_warnings_load_anyway(t, world)
	_defaults(t, world)


func _the_good_ones_load(t: TestContext, world: Dictionary) -> void:
	var packs: PackSet = world["packs"]
	t.ok(packs.is_enabled(&"core"), "core is not refused by its own rules")
	t.ok(packs.is_enabled(&"good"), "nor is the pack that follows them")
	for id in GOOD:
		t.ok((world["resolver"] as AssetResolver).has(id), "%s survived validation" % id)


func _part_rules(t: TestContext, world: Dictionary) -> void:
	var hexed := _about(world, "broken:hexed")
	t.ok(hexed.contains("#ff8800") and hexed.contains("hex colour"),
		"a hex colour is refused: " + hexed)
	t.ok(hexed.contains("hexed.json:"), "and the message carries a file and a line")

	t.ok(_about(world, "broken:unpainted").contains("no `material`"),
		"a part with no material: " + _about(world, "broken:unpainted"))
	# The suggestion is the whole point of the rule. `stell` and `steel` are the same word at
	# a glance, and finding that by eye in a forty-part vehicle is an evening.
	t.ok(_about(world, "broken:typo").contains("Did you mean `steel`?"),
		"a near-miss material is named and corrected: " + _about(world, "broken:typo"))
	t.ok(_about(world, "broken:offgrid").contains("whole number of modules"),
		"an off-grid size: " + _about(world, "broken:offgrid"))
	t.ok(_about(world, "broken:torus").contains("not one of the five primitives"),
		"a shape outside the five: " + _about(world, "broken:torus"))

	var hinged := _about(world, "broken:hinged")
	t.ok(hinged.contains("needs `limits`"), "a joint with no limits: " + hinged)
	t.ok(hinged.contains("leg bending backward"), "and says what that costs")

	var colour := _about(world, "broken:wrongcolour")
	t.ok(colour.contains("may not be gunmetal"), "a colour its material forbids: " + colour)
	t.ok(colour.contains("wood, wood2"), "and it is told which ones it can have")


## The three RigRules checks that are about more than one field at a time. They were the last
## of the rig rules to get a fixture, and the reason is instructive: each of them is invisible
## in the part you are looking at. `body` sits on the asset and the joint sits on a part; a
## cycle is nowhere at all until the whole table is laid out; and an off-grid pivot looks fine
## next to an offset that is off-grid in exactly the same way and legal.
func _rig_rules(t: TestContext, world: Dictionary) -> void:
	# A hinge whose `axis` is a vector rather than a letter — the natural mistake, because every
	# other direction in the format is three numbers. It is also the value that used to take the
	# validator down with a script error on its way to reporting itself.
	t.ok(_about(world, "broken:hinged").contains("an `axis` of x, y or z"),
		"a hinge with no usable axis: " + _about(world, "broken:hinged"))

	var bricked := _about(world, "broken:bricked")
	t.ok(bricked.contains("`body` is `bricks` and its parts have joints"),
		"an articulated asset that also wanted to come apart: " + bricked)
	t.ok(bricked.contains("bricks come apart, which is the opposite"),
		"and is told which of the two it has to pick")
	t.ok(bricked.contains("`pivot` is [0, 1.5, 0]") and bricked.contains("on the grid"),
		"a pivot half a module up a bone: " + bricked)

	# Named end to end, and named against the first part alphabetically rather than once per
	# member: three copies of one mistake in the boot log is three times the reading.
	var looped := _about(world, "broken:looped")
	t.ok(looped.contains("foot → knee → hip → foot"),
		"a parent cycle is reported as the whole ring: " + looped)
	t.ok(looped.contains("part `foot`") and not looped.contains("part `knee`"),
		"once, against one part, not once per link")


func _asset_rules(t: TestContext, world: Dictionary) -> void:
	var cylinders := _about(world, "broken:cylinders")
	t.ok(cylinders.contains("1 of 4 parts are blocks") and cylinders.contains("floor is 70%"),
		"under the block ratio: " + cylinders)

	var armoured := _about(world, "broken:armoured")
	t.ok(armoured.contains("5 colliders") and armoured.contains("cap is 4"),
		"a fifth collider: " + armoured)
	t.ok(armoured.contains("Colliders are always blocks"), "and a collider that is not a block")

	t.ok(_about(world, "broken:beam").contains("`ranged_beam` is not a slot"),
		"a slot core does not have: " + _about(world, "broken:beam"))
	t.ok(_about(world, "broken:beam").contains("ranged_slow"),
		"and the message lists the slots a weapon can fill")

	var vague := _about(world, "broken:vague")
	t.ok(vague.contains("spread is missing"), "a slot's required stat left out: " + vague)

	# FORMAT-SPEC §5's size convention for the round two. The geometry reads a diameter off x
	# alone, so a mismatched y is a part that renders at a size nobody wrote — and a size that
	# is silently wrong is the field an author checks last, because they were sure of it.
	var ellipse := _about(world, "broken:ellipse")
	t.ok(ellipse.contains("a cylinder is `[d, d, length]`"),
		"a cylinder that is not round: " + ellipse)
	t.ok(ellipse.contains("not one of the five primitives"), "and it is told why there is no ellipse")

	# `body` is not in §6's table — the spec has nothing to say about body granularity and it
	# decides whether a wall falls down or tips over, so an unknown value is refused rather
	# than defaulted to whichever of the two the author did not mean.
	var bodied := _about(world, "broken:bodied")
	t.ok(bodied.contains("`body` is `loose`") and bodied.contains("single, bricks"),
		"an invented body mode: " + bodied)
	t.ok(bodied.contains("brick by brick"), "and is told what the other setting buys")

	var swollen := _about(world, "broken:swollen")
	t.ok(swollen.contains("12 parts") and swollen.contains("small_prop runs 3–8"),
		"over the part budget for its class: " + swollen)


## Warnings load anyway — the rule that keeps the validator worth having. A pack refused for
## a spelling mistake in an optional field is a pack whose author stops shipping.
func _warnings_load_anyway(t: TestContext, world: Dictionary) -> void:
	var validator: AssetValidator = world["validator"]
	t.ok((world["resolver"] as AssetResolver).has("good:prop_sign"),
		"the asset with four things wrong with it and no rule broken still loaded")

	var said := ""
	for warning in validator.warnings:
		if String(warning).begins_with("good:prop_sign"):
			said += String(warning) + "\n"
	t.ok(said.contains("`zoom` is not an asset field"), "an unknown asset field warns: " + said)
	t.ok(said.contains("`wobble` is not a part field"), "so does an unknown part field")
	t.ok(said.contains("no `name`, so it will be listed by its id"), "so does a missing name")
	t.ok(said.contains("no `format`"), "and so does a document with no format version")


## The defaults the validator writes in once a part has passed. Everything downstream reads
## a complete part, so `shape` and `rotation` are never optional by the time a builder sees
## them — and `jitter` on a primitive is zero whatever the author put there.
func _defaults(t: TestContext, world: Dictionary) -> void:
	var barrel: ResolvedAsset = (world["resolver"] as AssetResolver).get_asset("good:prop_barrel")
	if barrel == null:
		t.fail("good:prop_barrel did not resolve")
		return
	var lid := _part(barrel, "lid")
	t.eq(String(lid.get("shape", "")), "block", "an undeclared shape is written in as a block")
	t.eq(ResolvedAsset.value_text(lid.get("rotation")), "[0, 0, 0]", "and rotation as none")
	t.eq(float(lid.get("jitter", -1.0)), 0.0, "and jitter as zero")
	t.eq(String(lid.get("colour", "")), "wood", "and colour from the material, not from grey")

	var bung := _part(barrel, "bung")
	t.eq(float(bung.get("jitter", -1.0)), 0.0, "a primitive's jitter is zero regardless")

	# The dump is what `--resolve` prints, and a defaulted field appearing in it as
	# `core (default)` is the difference between answering "where did this come from" and
	# leaving somebody to guess.
	t.ok(barrel.dump_part("lid").contains("← core (default)"),
		"and a defaulted field says so in the provenance dump")


## Everything said about one asset, run together — the messages are checked by content and
## an assertion per line would break every time one of them is reworded.
func _about(world: Dictionary, id: String) -> String:
	var said := ""
	for problem in (world["validator"] as AssetValidator).errors:
		if String(problem).begins_with(id + " —"):
			said += String(problem) + "\n"
	return said if said != "" else "(nothing was said about %s)" % id


func _part(asset: ResolvedAsset, part_name: String) -> Dictionary:
	for part in asset.parts():
		if typeof(part) == TYPE_DICTIONARY and String(part.get("name", "")) == part_name:
			return part
	return {}
