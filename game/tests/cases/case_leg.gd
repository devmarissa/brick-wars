extends TestCase
## A leg, measured off the rest pose its author wrote. RIG-SPEC §4.
##
## Everything the driver knows about a leg it derived from the pose — how long each segment is,
## how far the foot can chase the ground, where the sole rests, and which way the knee points.
## None of it is a field, which is the design: a `bend` direction in the format would be one more
## thing to document, validate, and get silently wrong in a mod. So this case is arithmetic
## against `biped.json` and `quadruped.json` with a pencil, and those two fixtures are authored in
## whole modules and right angles for exactly that reason. Their `_derived` notes carry the same
## numbers asserted here, so a fixture edit that moves the geometry cannot quietly change what
## this file is measuring.
##
## The section that matters most is `_knees_and_hocks`. RIG-SPEC §4 spends a paragraph on the
## claim that a human knee and a horse's hock are the same code with no field between them, and
## that is the kind of claim which is either true or has been quietly false for a month. The two
## fixtures differ in one respect — which way their shins jog off the thigh — and the assertion
## is that the derived bend comes out opposite. Nothing else in the suite says that.
##
## What the driver does with these numbers frame by frame is `case_driver.gd`.

const FIXTURES := "res://tests/fixtures/rig"

## A tenth of a millimetre. Everything here is metres on a 0.1 m grid, so anything further apart
## than this is a different formula rather than a different rounding.
const EPSILON := 0.0001

## `biped.json`'s legs, straight out of the file: two 12-module bones, a 6-module foot, hip 24
## modules up.
const BIPED_SPAN := 3.0
const BIPED_HIP := 2.4


func case_name() -> String:
	return "leg"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES)
	if world.is_empty():
		t.fail("the rig fixtures would not load, so nothing below means anything")
		return
	t.ok((world["validator"] as AssetValidator).refused.is_empty(),
		"the fixtures are valid content: " + _refusals(world))

	_measured_off_the_rest_pose(t, world)
	_the_whole_creature(t, world)
	_knees_and_hocks(t, world)
	_nothing_to_drive(t, world)


## What `Leg.measure` derives from one leg. The guard at the top is the important part: `setup`
## returns false for a creature whose legs do not resolve, `step` then answers with an empty
## dictionary, and every assertion below it would pass while measuring nothing at all.
func _measured_off_the_rest_pose(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	if loco == null or loco.legs.size() != 2:
		t.fail("core:biped did not set up two legs, so the rest of this case is vacuous")
		return
	t.ok(loco.warnings.is_empty(),
		"a properly bent biped is measured without complaint: " + "\n".join(loco.warnings))
	t.eq(loco.type, "legged", "and reads its type off the block")

	var left := loco.legs[0]
	t.eq(",".join(left.chain), "thigh_l,shin_l,foot_l",
		"a leg is the chain of parents from its root down to its foot")
	t.near(left.upper, 1.2, EPSILON, "with the thigh as the upper bone of the IK pair")
	t.near(left.lower, 1.2, EPSILON, "the shin as the lower one")
	# Everything past the IK pair hangs and lags, which is what makes a horse read as a horse
	# rather than as a stick creature. `trail` is their total, and the pair is solved to where
	# the ankle must be for them to put the sole on the target.
	t.near(left.trail, 0.6, EPSILON, "and the foot passive below them, hanging")

	# The sole in the creature's own space. Every foot position the driver computes is this point
	# plus a gait offset, so if it is wrong nothing above it can be right.
	_vec(t, left.home, Vector3(-0.3, 0.0, -0.8), "the sole rests where the rest pose puts it")
	_vec(t, loco.legs[1].home, Vector3(0.3, 0.0, -0.8), "and the other one mirrors it")
	t.near(loco.legs[1].phase, 0.5, EPSILON, "carrying the pack's own phase offset")

	# "How much further can this leg straighten": the span less the straight-line distance from
	# hip to sole. The bend is what buys it, which is why a straight leg has none.
	t.near(left.reach, BIPED_SPAN - sqrt(6.4), EPSILON,
		"reach is what is left of the leg once it is standing")
	t.ok(left.reach > Leg.MIN_REACH * 2.0,
		"and a bent leg has real room, not the floor a straight one falls back to")
	t.near(left.drop, BIPED_SPAN - BIPED_HIP, EPSILON,
		"and its sole reaches this far below the body's own origin at full stretch")


## What `Locomotion._measure` derives from all of them at once.
func _the_whole_creature(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	if loco == null:
		return
	# The soles sit at the asset's own origin, so the body rides at its origin. An author retunes
	# a stance by moving bones rather than by writing the same number twice.
	t.near(loco.stand, 0.0, EPSILON, "a creature whose soles are at its origin stands on it")
	t.near(loco.drop, BIPED_SPAN - BIPED_HIP, EPSILON,
		"and may put its lowest foot that far below itself")

	# The quadruped's legs are deliberately unequal — forelegs drop 0.4, hind legs 0.6 — so this
	# line can tell a minimum from a maximum. The most constrained leg is the one that decides
	# how far the body may ride above the lowest foot.
	var horse := FixtureWorld.driver(world, "core:quadruped")
	if horse == null or horse.legs.size() != 4:
		t.fail("core:quadruped did not set up four legs")
		return
	t.near(horse.legs[0].drop, 0.4, EPSILON, "a foreleg gives up 0.4 of itself below the body")
	t.near(horse.legs[2].drop, 0.6, EPSILON, "a hind leg 0.6, because it is a different leg")
	t.near(horse.drop, 0.4, EPSILON, "and the creature's `drop` is the least of them, not the most")

	t.near(horse.stand, 0.0, EPSILON, "its stance is the mean of four soles, all of them at zero")
	t.near(horse.legs[0].reach, 2.8 - sqrt(6.12), EPSILON, "a foreleg reaches by its own geometry")
	t.near(horse.legs[2].reach, 2.6 - sqrt(4.16), EPSILON, "and a hind leg by its own, which differs")
	_vec(t, horse.legs[0].home, Vector3(-0.3, 0.0, -1.5), "a forefoot rests ahead of the body")
	_vec(t, horse.legs[2].home, Vector3(-0.3, 0.0, 0.5), "and a hind foot behind it")


## RIG-SPEC §4's paragraph, as a handful of assertions. A human knee points forward and a horse's
## hock points backward; the difference costs no field, and this is the only place in the suite
## that says so.
func _knees_and_hocks(t: TestContext, world: Dictionary) -> void:
	var biped := FixtureWorld.driver(world, "core:biped")
	var horse := FixtureWorld.driver(world, "core:quadruped")
	if biped == null or horse == null:
		t.fail("both fixtures are needed to compare a knee with a hock")
		return

	var knee := biped.legs[0].bend
	t.ok(knee.z < 0.0, "a knee bent forward at rest reads as bending forward: %s" % knee)
	t.ok(knee.dot(Vector3.FORWARD) > 0.99, "and almost exactly forward, not merely forward-ish")
	t.near(knee.length(), 1.0, EPSILON, "with a unit direction, which the solver requires")

	var fore := horse.legs[0].bend
	var hock := horse.legs[2].bend
	t.ok(fore.z < 0.0, "the same creature's forelegs bend forward too: %s" % fore)
	t.ok(hock.z > 0.0, "and its hind legs backward, which is what a hock is: %s" % hock)
	t.ok(fore.dot(hock) < -0.98,
		"two opposite directions, read off two rest poses by one function with no field between them")

	# A matched pair must agree, or the creature bends one knee inward and the other outward.
	t.ok(horse.legs[0].bend.dot(horse.legs[1].bend) > 0.999,
		"and a matched pair of legs bends the same way as each other")
	t.ok(horse.legs[2].bend.dot(horse.legs[3].bend) > 0.999, "as does the pair behind them")


## The ways there is nothing much to drive. Each is a fact about the data rather than a failure
## here: the validator has already said whatever there was to say in words, and a creature with
## no driver holds its rest pose, which is a pose.
func _nothing_to_drive(t: TestContext, world: Dictionary) -> void:
	# A leg drawn straight at rest has said nothing about which way it bends. It still runs —
	# badly, forward, at the floor of its reach — rather than freezing, and it says so in words
	# that name the fix. This is the complaint `LocomotionRules` deliberately does not duplicate,
	# because only a posed rig can see it: the pose is composed rotations, pivots and `rest`
	# angles, none of which the validator has.
	var straight := FixtureWorld.driver(world, "core:straight")
	if straight == null:
		t.fail("core:straight would not set up")
		return
	var said := "\n".join(straight.warnings)
	t.eq(straight.legs.size(), 2, "a straight leg is still a leg the driver will run")
	t.ok(said.contains("straight at rest"), "but it is complained about: " + said)
	t.ok(said.contains("give its upper joint a `rest` angle"),
		"and the complaint names the fix rather than only the symptom")
	t.ok(straight.legs[0].bend.is_equal_approx(Vector3.FORWARD),
		"with the bend falling back to forward rather than to a zero vector")
	t.near(straight.legs[0].reach, Leg.MIN_REACH, EPSILON,
		"and reach bottoming out at its floor rather than going negative")

	# The same fixture's other job. Its soles rest 0.4 m below its own origin, which is the only
	# creature here for which `stand` is not 0 — and 0 is a number a sign error and a
	# sum-instead-of-a-mean both produce, so without this line `_measure` was untested. Found by
	# breaking the line and watching the suite stay green.
	t.near(straight.stand, 0.4, EPSILON,
		"a creature whose soles hang below its origin stands that far above them")

	# No block at all, which is most assets. `core:leg` is rigged and declares no `locomotion`.
	var plain := Locomotion.new()
	var asset := FixtureWorld.asset(world, "core:leg")
	t.ok(Locomotion.declared(asset).is_empty(), "an asset with no `locomotion` declares none")
	t.ok(not plain.setup(FixtureWorld.rig(world, "core:leg"), Locomotion.declared(asset)),
		"so there is nothing to drive, and `setup` says so rather than inventing legs")
	t.eq(plain.step(Transform3D.IDENTITY, Vector3.ZERO, 0.0, 0.1, FixtureWorld.flat_ground()).size(), 0,
		"and a step on a driver with no legs answers with nothing")

	# A chain that is not a chain. Checked here as well as in the validator because the driver
	# must not depend on having been validated — it is handed blocks by the CLI and by tests too.
	var broken := Locomotion.new()
	var warnings_before := broken.warnings.size()
	t.ok(not broken.setup(FixtureWorld.rig(world, "core:biped"), {
			"type": "legged",
			"legs": [{"root": "thigh_l", "foot": "pelvis"}],
			"gaits": [{"name": "walk", "speed": [0, 3], "stride": 1.2, "lift": 0.1}],
		}),
		"a `foot` that is not below its `root` leaves no legs to drive")
	t.ok(broken.warnings.size() > warnings_before,
		"and says so: " + "\n".join(broken.warnings))


func _vec(t: TestContext, got: Vector3, want: Vector3, what: String) -> void:
	t.ok(got.distance_to(want) < EPSILON, "%s — got %s, wanted %s" % [what, got, want])


func _refusals(world: Dictionary) -> String:
	var said := ""
	for problem in (world["validator"] as AssetValidator).errors:
		said += "\n    " + String(problem)
	return said if said != "" else "(nothing was refused)"
