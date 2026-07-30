extends TestCase
## The `locomotion` block as the validator sees it. RIG-SPEC §5, FORMAT-SPEC §10.
##
## This case exists because for one commit the field was accepted and unchecked. `locomotion`
## went into `AssetRules.KNOWN_FIELDS` when the driver was written, which silenced the "not an
## asset field" warning and put nothing in its place, so a pack could write any garbage at all
## under that key and the only symptom was a creature that stood still. Every assertion below is
## a symptom that used to have no message attached to it.
##
## What is checked is the *message*, not the verdict, for the same reason `case_validator.gd`
## gives: `broken:misgaited` failing is worth very little. `broken:misgaited` failing with the
## file, the line, `stride is 0` and the sentence explaining that a stride of 0 is why the feet
## are skating is the difference between a five-minute fix and an afternoon.
##
## The fixture root is two packs on purpose. `broken` is wrong in six different ways and is
## expected to be refused whole; `warn` is odd enough to be worth a word and not wrong enough to
## refuse, and it has to still be loaded at the end. A warning that quietly cost a pack its place
## in the world would be a rule nobody could afford to trip.

const FIXTURES := "res://tests/fixtures/locomotion"

## Nothing in `broken` may survive, and nothing in `warn` may be taken down with it.
const REFUSED := ["broken:shapeless", "broken:typeless", "broken:legless", "broken:mislegged",
	"broken:misgaited", "broken:hopping"]
const KEPT := ["warn:wheeled_legs", "warn:late_phase"]


func case_name() -> String:
	return "locomotion_rules"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES)
	if world.is_empty():
		t.fail("core content data would not load, so nothing below means anything")
		return

	_scoped(t, world)
	_the_block_itself(t, world)
	_the_leg_table(t, world)
	_the_gait_numbers(t, world)
	_odd_but_loadable(t, world)


## Failure is scoped to the pack that caused it. This is the assertion that makes the rest of the
## file safe to add rules to: a new complaint in `broken` must never cost `warn` its place.
func _scoped(t: TestContext, world: Dictionary) -> void:
	var packs: PackSet = world["packs"]
	var resolver: AssetResolver = world["resolver"]
	t.ok(not packs.is_enabled(&"broken"), "a pack whose locomotion blocks are wrong is disabled")
	t.ok(packs.is_enabled(&"warn"), "and the pack beside it, which is merely odd, is not")
	for id in REFUSED:
		t.ok(not resolver.has(id), "%s was dropped" % id)
	for id in KEPT:
		t.ok(resolver.has(id), "%s stayed loaded" % id)


## The shape of the block, before any of its contents mean anything.
func _the_block_itself(t: TestContext, world: Dictionary) -> void:
	# A string where an object belongs. The natural mistake — the block's most interesting value
	# is its `type`, so writing the type alone reads as reasonable — and it is also the value that
	# would take the rules down with a script error on the way to reporting itself, which is why
	# the `typeof` guard comes before anything else touches the block.
	var shapeless := FixtureWorld.errors_about(world, "broken:shapeless")
	t.ok(shapeless.contains("should be an object with a `type` in it"),
		"a `locomotion` that is a string is refused: " + shapeless)
	t.ok(shapeless.contains("`legged`"), "and the message echoes what was written instead")

	var typeless := FixtureWorld.errors_about(world, "broken:typeless")
	t.ok(typeless.contains("needs a `type`"), "a block with no `type`: " + typeless)
	t.ok(typeless.contains("wheeled") and typeless.contains("legged")
			and typeless.contains("floating"),
		"and is handed the whole closed set rather than told to go and read the spec")

	# The unknown-field warning is emitted *before* the missing-`type` check bails out, and this is
	# the assertion that keeps it that way. An author who misremembered `lean_into_turn` as
	# `body_lean` gets told so on the same run they are told about the type.
	var misfield := FixtureWorld.warnings_about(world, "broken:typeless")
	t.ok(misfield.contains("`body_lean` is not a `locomotion` field"),
		"a misremembered field name is still reported when the block bails early: " + misfield)

	var hopping := FixtureWorld.errors_about(world, "broken:hopping")
	t.ok(hopping.contains("`hopping` is not a locomotion type"),
		"an invented type is refused: " + hopping)
	t.ok(hopping.contains("core's drivers are what run them"),
		"and is told why a pack cannot invent one")


## The leg table, which is a set of claims about this asset's own hierarchy.
func _the_leg_table(t: TestContext, world: Dictionary) -> void:
	# Both complaints on one run. An author who added `legs`, ran again, and only then discovered
	# `gaits` has been made to pay twice for one mistake.
	var legless := FixtureWorld.errors_about(world, "broken:legless")
	t.ok(legless.contains("needs a `legs` array"), "a legged thing with no legs: " + legless)
	t.ok(legless.contains("needs a `gaits` array"), "and no gaits, reported in the same pass")
	t.ok(legless.contains("never takes a step"),
		"with the symptom named, because the symptom is silence")

	var mislegged := FixtureWorld.errors_about(world, "broken:mislegged")
	t.ok(mislegged.contains("`root` is `thig`"), "a leg naming no part: " + mislegged)
	t.ok(mislegged.contains("Did you mean `thigh`?"), "and is offered the part it meant")
	t.ok(mislegged.contains("`root` and `foot` are both `thigh`"),
		"a leg that is one bone is not a leg")
	# The one that cannot be caught by reading the entry: `arm` exists, `thigh` exists, and the
	# pair is only wrong relative to the hierarchy. This is why the check walks `parent`.
	t.ok(mislegged.contains("`arm` is not below `thigh`"),
		"and a foot on a different limb is refused, which needs the hierarchy to see")


## The gait numbers — every one of them a value the driver reads and then quietly does nothing
## useful with, which is the category this half of the rules exists to catch.
func _the_gait_numbers(t: TestContext, world: Dictionary) -> void:
	var said := FixtureWorld.errors_about(world, "broken:misgaited")
	t.ok(said.contains("`stride` is 0"), "a stride of nothing is refused: " + said)
	t.ok(said.contains("the cycle never advances and the feet skate"),
		"and the message names the symptom, because no screenshot says `stride`")
	t.ok(said.contains("`duty` is 1.5"), "a duty outside 0 to 1 is refused")
	t.ok(said.contains("`lift` is -0.05"), "and a foot that digs into the ground")
	t.ok(said.contains("`speed` is [6, 2]"), "a speed range with its ends swapped")
	t.ok(said.contains("A range no speed is inside is a gait that never runs"),
		"which is a gait that never runs, and is told so")
	t.ok(said.contains("2 `phases` for a 1-leg creature"),
		"a phase list that does not match the leg count")
	t.ok(said.contains("a gait needs a `name`"), "and a gait nothing can refer to")
	t.ok(FixtureWorld.warnings_about(world, "broken:misgaited").contains("`bounce` is not a gait field"),
		"an invented gait field is a warning, not a refusal")


## Odd, said out loud, and still loaded.
func _odd_but_loadable(t: TestContext, world: Dictionary) -> void:
	var wheeled := FixtureWorld.warnings_about(world, "warn:wheeled_legs")
	t.ok(wheeled.contains("`type` is `wheeled`, so its `legs` and `gaits` are ignored"),
		"a leg table on a wheeled thing is a warning: " + wheeled)
	t.ok(FixtureWorld.errors_about(world, "warn:wheeled_legs").begins_with("(nothing"),
		"and nothing about it is refused — a pack mid-conversion still loads")

	var late := FixtureWorld.warnings_about(world, "warn:late_phase")
	t.ok(late.contains("`phase` is 1.25"), "a phase past one cycle is a warning: " + late)
	# The number it becomes, not just the range it broke. An author who wrote 1.25 meaning "a
	# quarter of a cycle after the one before" got that by accident; one who meant "one and a
	# quarter cycles" did not, and only the second of the two can tell from this line.
	t.ok(late.contains("It will be read as 0.25"),
		"and is told the number it turns into rather than only that it was out of range")
	# `Gait._usable` sorts the table and its comment says the validator is what says so. This is
	# the assertion that makes that comment true.
	t.ok(late.contains("not in ascending `speed` order"),
		"gaits written out of order are warned about, as `Gait._usable` promises")
	t.ok(late.contains("Core sorts them, so this changes nothing"),
		"and told it costs them nothing, so nobody goes looking for a bug")
	t.ok(FixtureWorld.errors_about(world, "warn:late_phase").begins_with("(nothing"),
		"neither of which refuses the asset")
