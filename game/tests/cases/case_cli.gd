extends TestCase
## The diagnostic command line, and the two questions it is there to answer.
##
## `--resolve` is the one FORMAT-SPEC §6 asks for by name, and it ships *with* the resolver
## rather than after it: without a provenance dump, `extends` is a feature where a field
## arrives from one of four documents and the only way to find out which is to open all
## four. The tests here are mostly about the dump being *readable* — a diagnostic nobody can
## parse at a glance is a diagnostic nobody runs.
##
## `--pack-root` is the one that proves the other half of the milestone. C1 is done when "a
## deliberately broken pack fails with a message that says exactly why, without taking
## anything else down with it", and both clauses of that need a real content set standing
## next to a broken one. `tests/fixtures/broken` is that pack root; this case boots the same
## roots the game boots, plus that one, and checks that the shipped packs came through
## untouched while the broken ones were disabled with reasons an author could act on.
##
## The parser tests come first and are dull on purpose. A mistyped flag that silently does
## nothing is indistinguishable from a clean result, which is the one failure mode a
## diagnostic tool cannot afford.

const BROKEN := "res://tests/fixtures/broken"
const SHIPPED: Array[String] = ["res://packs"]


func case_name() -> String:
	return "cli"


func run(t: TestContext) -> void:
	_parsing(t)
	_refusals(t)
	_a_broken_pack_takes_nothing_with_it(t)
	_the_provenance_dump(t)
	_the_rig_report(t)
	_the_milestones_own_two_files(t)


## C1's first two clauses, kept runnable. `core:table` was added to the game by writing one
## JSON file and nothing else, and `core:table_map` is that table plus a canvas sheet in five
## lines of `extends`. Asserting it here means the day either stops being true is the day the
## suite says so, rather than the day somebody re-reads BUILD-ORDER and wonders.
func _the_milestones_own_two_files(t: TestContext) -> void:
	var resolver: AssetResolver = _boot_with("")["resolver"]

	var table: ResolvedAsset = resolver.get_asset("core:table")
	t.ok(table != null, "a prop that is only a JSON file is in the game")
	if table == null:
		return

	var variant: ResolvedAsset = resolver.get_asset("core:table_map")
	t.ok(variant != null, "and so is the five-line variant of it")
	if variant == null:
		return

	var dump := variant.dump()
	t.ok(_row(dump, "parts[map].material").contains("core:table_map"),
		"the one part the variant adds is attributed to the variant")
	t.ok(_row(dump, "parts[top].material").contains("core:table"),
		"and the seven it inherited to the file that wrote them")
	t.ok(_row(dump, "class").contains("core:table"),
		"including the budget class, which a variant does not restate")


func _parsing(t: TestContext) -> void:
	var cli := CLI.new()
	cli.parse(PackedStringArray(["--resolve", "core:crate"]))
	t.eq(cli.resolve_id, "core:crate", "`--resolve` takes the value after it")
	t.ok(cli.wants_resolve(), "and that is what asks for a dump")
	t.eq(cli.errors.size(), 0, "with nothing to complain about")

	cli.parse(PackedStringArray(["--resolve", "core:barrel", "--part", "hoop"]))
	t.eq(cli.part_name, "hoop", "`--part` narrows it to one part")
	t.eq(cli.errors.size(), 0, "and pairs with `--resolve` without complaint")

	# Repeatable, and in the order given: two mod folders is the normal case, not the odd one.
	cli.parse(PackedStringArray(["--pack-root", "res://a", "--pack-root", "res://b"]))
	t.eq(cli.pack_roots, ["res://a", "res://b"] as Array[String], "`--pack-root` accumulates")

	# `tools/screenshot.sh`'s two, which live in this parser rather than in the screenshot
	# scene because a process has one command line. They were positional until this existed,
	# which meant a fumbled invocation wrote a picture to a file called `--rendering-driver`.
	cli.parse(PackedStringArray(["--shot", "docs/x.png", "--settle", "3"]))
	t.eq(cli.shot_path, "docs/x.png", "`--shot` takes a path")
	t.near(cli.settle_seconds, 3.0, 0.001, "`--settle` takes seconds")
	t.eq(cli.errors.size(), 0, "and neither is a complaint")

	cli.parse(PackedStringArray(["--settle", "soon"]))
	t.eq(cli.errors.size(), 1, "`--settle` refuses something that is not a number")

	cli.parse(PackedStringArray([]))
	t.ok(not cli.wants_resolve(), "no arguments asks for nothing")
	t.eq(cli.errors.size(), 0, "and is not an error — this is how the game normally starts")


## Every one of these prints a complaint rather than doing nothing quietly.
func _refusals(t: TestContext) -> void:
	var cli := CLI.new()

	cli.parse(PackedStringArray(["--resolev", "core:crate"]))
	t.eq(cli.errors.size(), 1, "a mistyped flag is refused, not ignored")
	t.ok(_mentions(cli.errors, "--resolev"), "and quoted back: " + "; ".join(cli.errors))
	t.ok(_mentions(cli.errors, "--resolve"), "next to the ones that do exist")

	cli.parse(PackedStringArray(["--resolve"]))
	t.eq(cli.errors.size(), 1, "a flag with its value missing is refused")
	t.ok(_mentions(cli.errors, "needs a value"), "saying so: " + "; ".join(cli.errors))

	cli.parse(PackedStringArray(["core:crate"]))
	t.eq(cli.errors.size(), 1, "a bare value nothing was expecting is refused")

	cli.parse(PackedStringArray(["--part", "hoop"]))
	t.eq(cli.errors.size(), 1, "`--part` alone has nothing to narrow")
	t.ok(_mentions(cli.errors, "--resolve"), "and says what it wanted: " + "; ".join(cli.errors))


## The milestone's own sentence, asserted. Both halves, in one content set.
func _a_broken_pack_takes_nothing_with_it(t: TestContext) -> void:
	var world := _boot_with(BROKEN)
	var packs: PackSet = world["packs"]

	t.ok(packs.disabled.has(&"brokenpack"), "the pack with four bad fields is disabled")
	t.ok(packs.disabled.has(&"orphanpack"), "so is the one extending an asset nobody has")

	# "says exactly why" — the file, the line, the value and the rule, for each of the four.
	var why := String(packs.disabled.get(&"brokenpack", ""))
	t.ok(why.contains("bad_barrel.json"), "the reason names the file: " + why)
	t.ok(why.contains("stainless_steel"), "and the material that does not exist")
	t.ok(why.contains("hot_pink"), "and the colour that is not in the palette")
	t.ok(why.contains("15°"), "and the rotation rule, in the units the author typed")
	t.ok(why.contains("whole number of modules"), "and the size rule")
	t.ok(why.contains("FORMAT-SPEC") and why.contains("MATERIAL-SPEC"),
		"each citing the spec it comes from, so the rule can be argued with")

	# All four at once, rather than one per run. An author fixing a pack four runs at a time
	# stops reading the messages by the third one.
	t.ok(why.count("bad_barrel.json") >= 4, "all four problems are reported together")

	var orphan := String(packs.disabled.get(&"orphanpack", ""))
	t.ok(orphan.contains("core:crate_of_holding"), "the missing base is named: " + orphan)
	t.ok(orphan.contains("orphanpack:orphan"), "and so is the asset that wanted it")

	# "without taking anything else down with it" — the shipped world, unchanged.
	t.ok(packs.is_enabled(&"core"), "core loaded anyway")
	t.ok(packs.is_enabled(&"testpack"), "and so did the pack that depends on core")
	t.eq(packs.order.size(), 2, "exactly the two that ship are enabled")

	# Against the same boot without the broken root, rather than against a number written
	# here. A literal would have to be edited every time content is added, and the day it is
	# edited carelessly is the day it stops meaning "the cascade ate nothing".
	var resolver: AssetResolver = world["resolver"]
	var clean: AssetResolver = _boot_with("")["resolver"]
	t.eq(resolver.resolved.size(), clean.resolved.size(),
		"and every shipped asset resolved — exactly as many as with no broken root at all")
	t.ok(resolver.get_asset("core:wall_sandbag") != null, "including the wall")
	t.ok(resolver.get_asset("testpack:crate_reinforced") != null,
		"and the cross-pack variant, which is the one a cascade would have eaten")
	t.ok(resolver.get_asset("brokenpack:bad_barrel") == null,
		"while nothing from a disabled pack is reachable")


## What `--resolve` actually prints. `core:crate_ammo` is the interesting case: it is five
## lines of `extends` on top of `core:crate`, which is exactly the situation where "where did
## this field come from" is a real question.
func _the_provenance_dump(t: TestContext) -> void:
	var world := _boot_with("")
	var resolver: AssetResolver = world["resolver"]
	var ammo: ResolvedAsset = resolver.get_asset("core:crate_ammo")
	t.ok(ammo != null, "the variant resolved")
	if ammo == null:
		return

	var dump := ammo.dump()
	t.ok(dump.begins_with("core:crate_ammo"), "the dump opens with what it is about")
	t.ok(dump.contains("core:crate → core:crate_ammo"), "then the whole chain, base first")

	# The two halves of an inherited asset, side by side. This is the entire point: a reader
	# should be able to see which document to open without opening either.
	t.ok(_row(dump, "parts[band_upper].size").contains("core:crate_ammo"),
		"a field the variant added is attributed to the variant")
	t.ok(_row(dump, "parts[floor].size").contains("core:crate"),
		"and an inherited one to the document that wrote it")
	t.ok(_row(dump, "mass").contains("core:crate_ammo"),
		"including the declared mass, which overrides an inherited one")

	# Containers are dropped. A `parts` row would print the whole table on one line and
	# attribute it to whichever document declared the list first, which reads as a flat lie
	# sitting directly above the per-part rows that say otherwise.
	t.eq(_row(dump, "parts"), "", "the `parts` container itself does not get a row")
	t.eq(_row(dump, "parts[floor]"), "", "nor does a part as a whole")

	# One part, in FORMAT-SPEC §6's own column layout — and the defaulted fields next to the
	# authored ones, which is the half an author would otherwise have to remember to check.
	var barrel: ResolvedAsset = resolver.get_asset("core:barrel")
	t.ok(barrel != null, "the barrel resolved")
	if barrel == null:
		return
	var hoop := barrel.dump_part("hoop")
	t.ok(_row(hoop, "material").contains("core:barrel"), "a part dump attributes what was set")
	t.ok(_row(hoop, "jitter").contains("core (default)"),
		"and says `core (default)` for what nobody wrote — jitter is forced to 0 on a cylinder")
	t.ok(_row(hoop, "colour").contains("core (default)"),
		"and for the colour that came from the material rather than the part")

	t.ok(barrel.dump_part("no_such_part").contains("hoop"),
		"asking for a part that is not there lists the ones that are")


## `--rig`, which is the instrument `core:soldier` was authored with. What it prints is
## everything the rig system *derived*, and none of that is written in the file: a leg pivots
## half its own length along its own axis and `offset` must be whole modules, so a soldier is
## authored axis-aligned and bent by `rest` angles — and then the numbers that decide whether it
## works (is the sole on the ground? does the knee bend forward?) are trigonometry nobody does in
## their head. Asserted here because a flag with no test is a flag that quietly stops printing.
func _the_rig_report(t: TestContext) -> void:
	var world := _boot_with("")
	var soldier: ResolvedAsset = (world["resolver"] as AssetResolver).get_asset("core:soldier")
	t.ok(soldier != null, "the soldier resolved — 15 parts, `kind` character, `slot` infantry")
	if soldier == null:
		return

	var built := AssetBuilder.new().build(soldier, world["materials"], world["palette"])
	var report := RigReport.of(soldier, built)
	t.ok(report.begins_with("core:soldier"), "the report opens with what it is about")
	t.ok(report.contains("bones — 15"), "and counts the bones: " + report.get_slice("\n", 2))
	t.ok(report.contains("thigh_l → shin_l → foot_l"),
		"names each leg as the chain the solver will run on")
	t.ok(report.contains("hinge [-40, 120] about x, rest 24"),
		"prints each joint with the limits and the rest angle it idles at")

	# The line the authoring loop is for. A soldier standing at its own origin has `stand` at
	# zero, and a knee that bends the wrong way is the failure that reads as a broken creature
	# long before anybody can say which number did it.
	t.ok(report.contains("(forward, like a knee)"),
		"and says in words which way the knee bends, not only as a vector")
	t.ok(not report.contains("like a hock"), "which for a soldier is not backward")
	t.ok(not report.contains("reach is at its floor"),
		"with no leg left straight enough for its reach to bottom out")

	# An asset with no joints has no rig, which is most of them. Saying so and naming the flag
	# that *would* help is the difference between a dead end and a redirect.
	var crate: ResolvedAsset = (world["resolver"] as AssetResolver).get_asset("core:crate")
	var flat := RigReport.of(crate, AssetBuilder.new().build(crate, world["materials"],
		world["palette"]))
	t.ok(flat.contains("no rig"), "an asset with no joints is told it has no rig")
	t.ok(flat.contains("--resolve core:crate"), "and pointed at the dump that does apply to it")

	var cli := CLI.new()
	cli.parse(PackedStringArray(["--rig", "core:soldier"]))
	t.ok(cli.errors.is_empty() and cli.wants_rig(), "`--rig <asset>` parses")
	t.eq(cli.rig_id, "core:soldier", "and carries the id it was given")
	t.ok(CLI.usage().contains("--rig"), "and the usage line mentions it")


## Boot the shipped pack roots, optionally with one more — the same call the content module
## makes, so this cannot pass against a path the game does not use.
func _boot_with(extra_root: String) -> Dictionary:
	var roots := SHIPPED.duplicate()
	if extra_root != "":
		roots.append(extra_root)

	var packs := PackSet.new()
	packs.discover(roots)
	var index := AssetIndex.new()
	index.scan(packs)
	var resolver := AssetResolver.new()
	resolver.resolve_all(index, packs)

	var palette := Palette.new()
	palette.load_core()
	var materials := MaterialSet.new()
	materials.load_core(palette)
	var slots := SlotSet.new()
	slots.load_core()
	var validator := AssetValidator.new()
	validator.validate_all(resolver, index, packs, materials, palette, slots)

	return { "packs": packs, "index": index, "resolver": resolver,
		"materials": materials, "palette": palette }


## One line of a dump by its leading label, or "" if there isn't one. Matching on the label
## alone would find `parts` inside `parts[floor].size`, so the label has to end the column.
static func _row(dump: String, label: String) -> String:
	for line in dump.split("\n"):
		var text := String(line)
		if text.begins_with(label) and text.substr(label.length()).begins_with(" "):
			return text
	return ""


static func _mentions(problems: Array[String], word: String) -> bool:
	for problem in problems:
		if problem.contains(word):
			return true
	return false
