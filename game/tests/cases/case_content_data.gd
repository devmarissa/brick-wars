extends TestCase
## The two core data files and the registries that read them. CORE-SPEC §3, MATERIAL-SPEC,
## ART-BIBLE §2.
##
## Two halves, and the second one is the important half. The first checks that
## `palette.json` and `materials.json` load and mean what they say. The second feeds the
## registries deliberately broken fixtures and checks that each specific mistake is caught
## and *named* — because every one of those mistakes is one a pack author will make next
## year, and a validator that only says "invalid" is a validator that gets worked around
## rather than fixed.
##
## Anything asserted here about core's own data is asserted because it is load-bearing
## somewhere else: sandbag's inherited resistances are the class-folding rule, timber
## becoming charred_timber is MATERIAL-SPEC §6's siege mine, and the count of exempt
## colours is the project-health number that says whether the palette law still means
## anything.

const BAD_PALETTE := "res://tests/fixtures/bad_palette.json"
const BAD_MATERIALS := "res://tests/fixtures/bad_materials.json"
const BAD_SYNTAX := "res://tests/fixtures/bad_syntax.json"
const NOT_AN_OBJECT := "res://tests/fixtures/not_an_object.json"
const MISSING := "res://tests/fixtures/no_such_file.json"


func case_name() -> String:
	return "content data"


func run(t: TestContext) -> void:
	var palette := Palette.new()
	var materials := MaterialSet.new()

	_core_palette(t, palette)
	_core_materials(t, palette, materials)
	_derived_values(t, materials)
	_loader(t)
	_broken_palette(t)
	_broken_materials(t, palette)


func _core_palette(t: TestContext, palette: Palette) -> void:
	var ok := palette.load_core()
	t.eq(", ".join(palette.errors), "", "the core palette loads clean")
	t.ok(ok, "load_core reports success")
	t.eq(palette.colours.size(), 20, "twenty colours, as ART-BIBLE §2 says")

	# Not a round number for its own sake: this is the number that says whether the
	# saturation law is a law or a suggestion. If it climbs, the law needs rewriting
	# rather than exempting.
	t.eq(palette.exempt_names(), [&"clay", &"skin", &"tan", &"webbing", &"wood", &"wood2"] as Array[StringName],
		"six colours are excused a law, by name and in order")

	for name in palette.exempt_names():
		t.ok(palette.why_exempt(name).length() > 20, "%s explains itself" % name)

	t.ok(palette.is_exempt(&"skin", "saturation") and palette.is_exempt(&"skin", "value"),
		"skin is the one entry excused both laws")
	t.ok(not palette.is_exempt(&"mud", "saturation"), "mud needs no excuse")

	t.near(palette.colour(&"mud").s, 0.319, 0.001, "Godot's own saturation matches the file's")
	t.eq(palette.use_of(&"webbing"), "webbing, packs, straps", "every colour states its use")
	t.ok(not palette.has(&"pack"), "ART-BIBLE's `PACK` is `webbing` here — no colour called pack")

	t.expect_error("asking for a colour that does not exist")
	t.eq(palette.colour(&"hotpink"), Color.MAGENTA,
		"a missing colour is magenta, the one hue the laws forbid")

	t.eq(palette.faction.get("count"), 2, "core fixes the faction count, packs pick the colours")
	t.eq(palette.faction.get("allowed_on"), ["soldier", "vehicle"],
		"faction colour is only ever on soldiers and vehicles")


func _core_materials(t: TestContext, palette: Palette, materials: MaterialSet) -> void:
	var ok := materials.load_core(palette)
	t.eq("\n".join(materials.errors), "", "the core material set loads clean")
	t.ok(ok, "load_core reports success")

	# MATERIAL-SPEC §5's tables total thirty; ice, glass and water are named under "Other"
	# and pointed at EARTH-SPEC §8, which has no numbers for them. They are authored here
	# and flagged. The real count is thirty-three and the spec sentence wants amending.
	t.eq(materials.materials.size(), 33, "thirty-three materials")
	var by_class := {}
	for cls in ["earth", "stone", "wood", "metal", "fabric", "other"]:
		by_class[cls] = materials.names_in_class(cls).size()
	t.eq(by_class, {"earth": 9, "stone": 6, "wood": 4, "metal": 5, "fabric": 6, "other": 3},
		"class counts match MATERIAL-SPEC §5")

	t.eq(materials.names_in_class("wood"),
		[&"charred_timber", &"log", &"plank", &"timber"] as Array[StringName],
		"names come back alphabetical, not in interned-pointer order")

	# Class folding: sandbag states two resistances and inherits four from fabric.
	var sandbag := materials.get_def(&"sandbag")
	t.near(materials.resist(&"sandbag", "kinetic"), 0.20, 0.001, "sandbag's own kinetic value wins")
	t.near(materials.resist(&"sandbag", "blast"), 0.25, 0.001, "sandbag's own blast value wins")
	t.near(materials.resist(&"sandbag", "cutting"), 2.50, 0.001, "cutting comes from the fabric class")
	t.near(materials.resist(&"sandbag", "fire"), 2.20, 0.001, "fire comes from the fabric class")
	t.eq(sandbag.get("surface", {}).get("footstep"), "soft", "so does the surface block")
	t.near(float(materials.get_def(&"concrete").get("spall", 0.0)), 0.85, 0.001,
		"concrete's own spall overrides the stone class default")

	# MATERIAL-SPEC §6's siege mine in one assertion: prop a chalk gallery with timber,
	# burn the props, and what is left cannot hold the span.
	t.eq(String(materials.get_def(&"timber").get("fire", {}).get("becomes", "")), "charred_timber",
		"timber burns into charred timber")
	t.ok(float(materials.get_def(&"charred_timber").get("support_vertical", 99))
		< float(materials.get_def(&"timber").get("support_vertical", 0)),
		"and charred timber holds less than timber did, which is the whole point")
	t.eq(String(materials.get_def(&"sandbag").get("fire", {}).get("becomes", "")), "sand",
		"a burnt sandbag leaves its fill behind")

	# Rope and wire carry tension only. Null rather than zero, because zero says "a wall
	# that holds nothing" and null says "not a wall".
	t.eq(materials.get_def(&"rope").get("support_vertical"), null, "rope has no compressive support")
	t.ok(materials.get_def(&"rope").get("tension_only", false), "it is marked tension-only instead")

	for name in [&"ice", &"glass", &"water"]:
		t.ok(materials.get_def(name).get("authored_here", false),
			"%s is flagged as authored here, not taken from a spec that has no numbers" % name)


func _derived_values(t: TestContext, materials: MaterialSet) -> void:
	# Nobody types a mass. A stone block is heavy because stone is heavy.
	t.near(materials.mass_for(&"hard_stone", 0.016), 43.2, 0.01, "mass is volume × density")
	t.near(materials.mass_for(&"canvas", 0.016), 4.8, 0.01, "and the same rule makes canvas light")
	t.eq(materials.mass_for(&"unobtanium", 1.0), 0.0, "an unknown material has no mass")

	t.ok(not materials.can_work(&"chalk", 1), "a shovel does not cut chalk")
	t.ok(materials.can_work(&"chalk", 2), "a pick does")
	t.ok(materials.refusal(&"chalk", 1).contains("hardness 2"),
		"and the refusal says what it would take: " + materials.refusal(&"chalk", 1))

	t.ok(materials.allows_colour(&"concrete", &"grey"), "concrete may be grey")
	t.ok(not materials.allows_colour(&"concrete", &"skin"), "concrete may not be skin-coloured")


## The loader's job is the error message. These are the three failures a hand-written pack
## actually produces, and each one has to say which file and what was wrong with it.
func _loader(t: TestContext) -> void:
	var errors: Array[String] = []

	ContentLoader.read_json(MISSING, errors)
	t.ok(_mentions(errors, "does not exist"), "a missing file says so")

	# A missing comma, which is what a hand-written pack actually gets wrong. Godot reports
	# the line zero-based and does not quote it; both are corrected in the loader, and the
	# fixture is built so that getting either wrong points at the wrong line of JSON.
	errors.clear()
	ContentLoader.read_json(BAD_SYNTAX, errors)
	t.ok(_mentions(errors, "bad_syntax.json:6"), "a parse failure names the file and the line")
	t.ok(_mentions(errors, "\"stone\""), "and quotes that line underneath, so nobody has to count")

	errors.clear()
	var obj := ContentLoader.read_object(NOT_AN_OBJECT, errors)
	t.ok(obj.is_empty(), "a top-level array is refused")
	t.ok(_mentions(errors, "it has to be an object"),
		"with the commonest hand-written mistake named: " + "; ".join(errors))

	# `1900` arrives from JSON as an int and must be accepted for a float field; `"1900"`
	# must not, because silent coercion is how a typo becomes a physics value.
	errors.clear()
	t.eq(ContentLoader.require({"n": 1900}, "n", "x", TYPE_FLOAT, errors), 1900,
		"an integer satisfies a number field")
	t.eq(ContentLoader.require({"n": "1900"}, "n", "x", TYPE_FLOAT, errors), null,
		"a quoted number does not")
	t.ok(_mentions(errors, "found a string"), "and the type error says what it found instead")

	# `_`-prefixed keys are the file-wide comment convention; JSON has none.
	var stripped: Dictionary = ContentLoader.strip_comments(
		{"_": ["a note"], "keep": {"_note": 1, "inner": 2}})
	t.eq(stripped, {"keep": {"inner": 2}}, "documentation keys are stripped recursively")

	t.eq(ContentLoader.sorted_names([&"zulu", &"alpha", &"mike"]),
		[&"alpha", &"mike", &"zulu"] as Array[StringName], "names sort by text, not by pointer")


func _broken_palette(t: TestContext) -> void:
	var bad := Palette.new()
	t.ok(not bad.load_core(BAD_PALETTE), "a broken palette fails to load")
	var e := bad.errors

	t.ok(_mentions(e, "`loud`") and _mentions(e, "claims no exemption"),
		"a colour over the saturation line with no exemption is refused")
	t.ok(_mentions(e, "`too_dark`"), "so is one under the value floor")
	t.ok(_mentions(e, "does not break it"),
		"and so is a stale exemption — that is how a law stops meaning anything")
	t.ok(_mentions(e, "no `why`"), "an exemption nobody justified is refused")
	t.ok(_mentions(e, "which is not a law"), "an exemption from an invented law is refused")
	t.ok(_mentions(e, "is not a colour"), "a hex string that is not hex is refused")

	# Every problem in one pass. Finding out about six mistakes one run at a time is how a
	# format gets a reputation.
	t.ok(e.size() >= 6, "all of them reported together, not one per run — %d errors" % e.size())


func _broken_materials(t: TestContext, palette: Palette) -> void:
	var bad := MaterialSet.new()
	t.ok(not bad.load_core(palette, BAD_MATERIALS), "a broken material set fails to load")
	var e := bad.errors

	t.ok(_mentions(e, "`ghost_class`") and _mentions(e, "is not one of"),
		"a material in a class that does not exist is refused")
	t.ok(_mentions(e, "`no_density`") and _mentions(e, "is required"),
		"a missing required field is named")
	t.ok(_mentions(e, "`string_density`"), "a quoted number is not a number")
	t.ok(_mentions(e, "not in the palette"), "a colour that does not exist is refused")
	t.ok(_mentions(e, "not in its own `colour_allow`"),
		"a material that cannot be painted its own default colour is refused")
	t.ok(_mentions(e, "which is not a failure mode"), "an invented failure mode is refused")
	t.ok(_mentions(e, "has no tier"), "a hardness outside 0–5 is refused")
	t.ok(_mentions(e, "no `fire` block"), "flammable with no fire block is refused")
	t.ok(_mentions(e, "`on_burnt` is `vaporised`"), "an invented burn residue is refused")
	t.ok(_mentions(e, "which is not a material"), "burning into a material that does not exist is refused")
	t.ok(_mentions(e, "not a damage type"), "resisting something that cannot be dealt is refused")
	t.ok(_mentions(e, "have to be stated here"),
		"a class with no default resistances makes its materials state all six")
	t.ok(_mentions(e, "`surface`"), "and state their own surface")


func _mentions(errors: Array[String], fragment: String) -> bool:
	for e in errors:
		if e.contains(fragment):
			return true
	return false
