extends TestCase
## What the driver hands back: where the body ends up, given where the feet landed. RIG-SPEC §4.
##
## `Locomotion.step` has two halves and this is the second one. The first plants the feet against
## the transform that came in — `case_driver.gd` — and then the body's height and orientation are
## derived from where they landed and handed to the caller. They are handed back rather than
## written because the caller owns the body: it is a physics object with a collider, and a driver
## that moved it directly would be a kinematic system arguing with a simulated one.
##
## The two policies here are the ones that read as a bug in something else when they are wrong.
## Body height uses only the feet that are DOWN, so a creature stepping over a ditch does not sink
## into it halfway through the stride; body tilt uses every foot, because a swinging foot's plant
## is still the ground it is travelling over. Getting the two the same way round produces a
## creature that walks smoothly and bobs into holes, and nobody looking at it would guess which of
## the two lines was at fault.
##
## `_never_drops_into_a_ditch` exists because mutation-testing found that line untested: swapping
## the stance feet for all of them left the whole suite green, since every other case here stands
## on ground where the two sets agree.

const FIXTURES := "res://tests/fixtures/rig"

const EPSILON := 0.0001

## `biped.json`'s reach — what is left of the leg once it is standing. `case_leg.gd` pins it.
const BIPED_REACH := 3.0 - 2.529822128


func case_name() -> String:
	return "body"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES)
	if world.is_empty():
		t.fail("the rig fixtures would not load, so nothing below means anything")
		return

	_beyond_reach(t, world)
	_never_drops_into_a_ditch(t, world)
	_the_body_follows_the_ground(t, world)
	_same_answer_every_time(t, world)


## Down in the bowl, whose floor is further below the rim than a biped's leg is long. The feet
## stop at full stretch rather than stretching into the hole — the failure that reads on screen
## as a creature impaled on the terrain — and the body comes down after them.
func _beyond_reach(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	var ground := FixtureWorld.test_ground()
	if loco == null:
		return

	# Placed so both soles sit near the bowl's centre, where it is about 0.7 m deep against a
	# reach of 0.47. Off-centre, one foot catches the shallow side and the creature is merely
	# taking a long step, which is a different assertion.
	var over := loco.step(Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.0, -3.2)), Vector3.ZERO,
		0.0, 0.1, ground)
	for leg in loco.legs:
		t.ok(not bool(leg.plant["planted"]),
			"a foot over a hollow deeper than its leg does not plant")
		t.near((leg.plant["position"] as Vector3).y, -BIPED_REACH, EPSILON,
			"it hangs at the bottom of its range instead")
	t.ok(bool(over["unsupported"]),
		"and the creature is reported as standing on nothing, which is the driver's cue to act")
	t.eq(int(over["planted"]), 2,
		"while still being in stance on both legs — the gait does not know about the hole")

	# Both feet at full stretch and equal, so the average and the lowest agree and the body ends
	# up exactly a reach below its origin.
	t.near(float(over["height"]), -BIPED_REACH, EPSILON,
		"so the body comes down to where the legs can still reach, rather than hovering")


## The cycle advances by distance travelled, not by time — the entire reason feet do not skate. A
## stride is the ground one foot covers between footfalls, so a creature that has covered one
## stride has advanced exactly one cycle.


## Body height is taken from the feet that are DOWN, and never from one mid-swing. A swinging
## foot's plant is the ground under it, which is the right thing to tilt to and the wrong thing to
## stand on: a creature stepping over a ditch must not drop into it halfway through the stride.
##
## This section exists because mutation-testing found the policy line untested — swapping the
## stance feet for all of them left the suite green, since every other case here stands on ground
## where the two agree. So the creature is walked across the steepest part of the bowl's wall,
## where the swing carries one foot up to half a metre below the other.
func _never_drops_into_a_ditch(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	if loco == null:
		return
	var ground := FixtureWorld.test_ground()

	# On the bowl's wall at its steepest, and held 0.4 m down so both feet stay inside their reach
	# — a foot that cannot reach clamps, and then this would be measuring the clamp instead.
	var at := Transform3D(Basis.IDENTITY, Vector3(-5.0, -0.4, -1.7))
	var worst := 0.0
	var lowest_gap := 0.0
	for i in 50:
		var out: Dictionary = loco.step(at, Vector3(0.0, 0.0, -1.5), 0.0, 0.04, ground)
		var down := INF
		var up := INF
		for leg in loco.legs:
			var y: float = (leg.plant["position"] as Vector3).y
			if leg.stance:
				down = minf(down, y)
			else:
				up = minf(up, y)
		if down == INF:
			continue
		# How far below the lowest planted foot the body ended up, and how much lower a swinging
		# foot was than that planted one. The first must stay inside the bob; the second is what
		# makes the first worth asserting.
		worst = maxf(worst, down - float(out["height"]))
		if up != INF:
			lowest_gap = maxf(lowest_gap, down - up)

	t.ok(lowest_gap > 0.1,
		"the swing really does put a foot well below the planted one here: %.3f m" % lowest_gap)
	# `body_bob` is 0.06, so the bob is ±0.03. Anything past that is the driver having stood on a
	# foot that was in the air.
	t.ok(worst <= 0.031,
		"and the body never sinks below the foot it is standing on: %.3f m at worst" % worst)


## Which gait a speed calls for, and the band two of them blend across. `biped.json`'s ranges
## touch rather than overlap, which is the case `Gait._band` blends across a tenth of the
## narrower of the two rather than snapping.


## The body's height and orientation come back from `step` rather than being written to anything,
## because the caller owns the body: it is a physics object with a collider, and a driver that
## moved it directly would be a kinematic system arguing with a simulated one.
func _the_body_follows_the_ground(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	if loco == null:
		return
	var ground := FixtureWorld.test_ground()

	# Up the ramp, whose rise is a quarter: at x = 4 the surface is half a metre up. The body has
	# to come up with it and tilt part of the way onto it, because `body_pitch` is 0.1 and not 1.
	var on_ramp: Dictionary = loco.step(Transform3D(Basis.IDENTITY, Vector3(4.0, 0.5, 0.0)),
		Vector3(0.0, 0.0, -1.0), 0.0, 0.1, ground)
	t.ok(float(on_ramp["height"]) > 0.3,
		"walking up a slope raises the body with it: %s" % on_ramp["height"])
	var tilt := rad_to_deg((on_ramp["basis"] as Basis).y.angle_to(Vector3.UP))
	t.ok(tilt > 0.5 and tilt < 14.036,
		"and tilts it part of the way onto the slope rather than all of it: %s degrees" % tilt)
	t.near((on_ramp["basis"] as Basis).determinant(), 1.0, 0.001,
		"with a right-handed basis, because a bad up renders a creature inside out")

	# Turning banks the body, and the bank is capped: past about MAX_LEAN a creature reads as
	# falling over rather than as leaning.
	var hard := loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -4.0), 40.0, 0.1, ground)
	var roll := rad_to_deg((hard["basis"] as Basis).x.angle_to(Vector3.RIGHT))
	t.ok(roll <= Locomotion.MAX_LEAN + 0.001,
		"a violent turn leans the body no further than MAX_LEAN: %s degrees" % roll)
	t.ok(roll > 1.0, "but it does lean, rather than the cap swallowing the whole effect")

	var straight_on := loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -4.0), 0.0, 0.1, ground)
	t.near(rad_to_deg((straight_on["basis"] as Basis).x.angle_to(Vector3.RIGHT)), 0.0, 0.001,
		"and running straight does not lean at all")


## RIG-SPEC §9 plans to replicate a creature as a root transform and a handful of floats, which
## only works if the same inputs give the same pose on every machine. Nothing in the driver is
## simulated, and this is the assertion that keeps it that way.


## RIG-SPEC §9 plans to replicate a creature as a root transform and a handful of floats, which
## only works if the same inputs give the same pose on every machine. Nothing in the driver is
## simulated, and this is the assertion that keeps it that way.
func _same_answer_every_time(t: TestContext, world: Dictionary) -> void:
	var first := FixtureWorld.driver(world, "core:quadruped")
	var second := FixtureWorld.driver(world, "core:quadruped")
	if first == null or second == null:
		return
	var ground := FixtureWorld.test_ground()

	var at := Transform3D(Basis.IDENTITY, Vector3(3.0, 0.4, 0.5))
	var motion := Vector3(0.4, 0.0, -5.0)
	var last_a: Dictionary = {}
	var last_b: Dictionary = {}
	for i in 20:
		last_a = first.step(at, motion, 0.3, 1.0 / 60.0, ground)
		last_b = second.step(at, motion, 0.3, 1.0 / 60.0, ground)

	t.near(float(last_a["height"]), float(last_b["height"]), EPSILON,
		"twenty frames in, two drivers given the same input agree on the body height")
	t.near(float(last_a["phase"]), float(last_b["phase"]), EPSILON, "and on the phase")
	t.near(float(last_a["strain"]), float(last_b["strain"]), EPSILON, "and on the strain")
	t.ok((last_a["basis"] as Basis).is_equal_approx(last_b["basis"] as Basis),
		"and on the orientation")
	for i in first.legs.size():
		t.ok(first.legs[i].hang.is_equal_approx(second.legs[i].hang),
			"including each leg's hang, the one piece of state that survives a frame")
