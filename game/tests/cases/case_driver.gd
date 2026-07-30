extends TestCase
## The locomotion driver, frame by frame: a rig, a `locomotion` block and some ground become a
## creature that walks. RIG-SPEC §4–§5.
##
## `Locomotion.step` has two halves, and this is the first: where the feet go and when. The
## second — what the body does about where they landed — is `case_body.gd`. What a leg *is*, before
## any of this runs, is `case_leg.gd`, measured off the rest pose.
##
## So this case is the cycle. Feet find ground nobody authored them against, the cycle advances by
## distance rather than by time so the feet do not skate, gaits hand over by speed, and a gallop
## takes the whole animal off the ground the way its `duty` says it should.
##
## None of it is judged by eye. Planting is the part of a rig that fails *beautifully*: a creature
## whose feet slide two centimetres per step looks perfectly smooth and is wrong, and there is no
## screenshot that says which of the half-dozen numbers involved was at fault. So the expected
## values here are worked out from `TestGround`'s constants and `biped.json`'s geometry by hand.
##
## One distinction worth stating because getting it backwards costs an hour: `step`'s `planted`
## count is how many legs are in the **stance phase of the gait**, not how many found ground.
## Ground contact is `unsupported`, which reads the plants themselves. A creature standing over a
## hole reports every leg planted and unsupported at the same time, and both are true.

const FIXTURES := "res://tests/fixtures/rig"

const EPSILON := 0.0001

## `biped.json`'s walk, straight out of the file: 1.2 m from footfall to footfall.
const WALK_STRIDE := 1.2


func case_name() -> String:
	return "driver"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root(FIXTURES)
	if world.is_empty():
		t.fail("the rig fixtures would not load, so nothing below means anything")
		return

	_standing_still(t, world)
	_no_skating(t, world)
	_a_planted_foot_stays_put(t, world)
	_gaits_hand_over_by_speed(t, world)
	_stance_and_swing(t, world)


## A biped standing on flat ground at its own origin — the case every number below is a departure
## from.
func _standing_still(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	var ground := FixtureWorld.test_ground()
	if loco == null:
		t.fail("core:biped would not set up, so this case is vacuous")
		return

	var still := loco.step(Transform3D.IDENTITY, Vector3.ZERO, 0.0, 0.1, ground)
	t.eq(String(still["gait"]), "walk", "a creature standing still holds its slowest gait")
	t.ok(not bool(still["blending"]), "and is not caught mid-transition")
	t.near(float(still["phase"]), 0.0, EPSILON, "with a phase that has not advanced, having not moved")
	# Not zero, and the number is the creature's own `stand`. Its bent legs put its soles above
	# its origin, so the body rides below them by exactly that much — which is `Footing.support`
	# doing its job, not the body sinking.
	t.near(float(still["height"]), loco.stand, EPSILON,
		"standing its own `stand` below its soles on flat ground")
	t.ok((still["basis"] as Basis).is_equal_approx(Basis.IDENTITY), "and level")
	t.eq(int(still["planted"]), 2, "with both legs in stance at the bottom of the cycle")
	t.ok(not bool(still["unsupported"]), "which is not a creature standing on nothing")

	for leg in loco.legs:
		t.near((leg.plant["position"] as Vector3).y, 0.0, EPSILON,
			"each foot lands on the ground rather than where the gait aimed it")
		t.ok(bool(leg.plant["planted"]), "and counts as planted")
		t.near(leg.strain, 0.0, EPSILON,
			"with the leg inside its declared limits, which is what `strain` reports")


## Down in the bowl, whose floor is further below the rim than a biped's leg is long. The feet
## stop at full stretch rather than stretching into the hole — the failure that reads on screen
## as a creature impaled on the terrain — and the body comes down after them.


## The cycle advances by distance travelled, not by time — the entire reason feet do not skate. A
## stride is the ground one foot covers between footfalls, so a creature that has covered one
## stride has advanced exactly one cycle.
func _no_skating(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	var ground := FixtureWorld.test_ground()
	if loco == null:
		return

	# Two metres a second for a tenth of a second is 0.2 m, and walk's stride is 1.2 m.
	var stepped := loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -2.0), 0.0, 0.1, ground)
	t.near(float(stepped["phase"]), 0.2 / WALK_STRIDE, EPSILON,
		"a sixth of a stride's worth of ground is a sixth of a cycle")

	# The same distance at twice the speed in half the time has to land on the same phase. A cycle
	# driven by time rather than by distance fails exactly here and looks fine doing it. Both
	# speeds are kept well inside the walk band: at the boundary the stride is being blended, and
	# then the two are not the same gait at all — which is how this assertion first went red.
	var slow := FixtureWorld.driver(world, "core:biped")
	var fast := FixtureWorld.driver(world, "core:biped")
	for i in 8:
		slow.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -1.0), 0.0, 0.1, ground)
		fast.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -2.0), 0.0, 0.05, ground)
	t.near(fast.phase, slow.phase, EPSILON,
		"the same ground covered at twice the speed in half the time is the same phase")
	t.near(slow.phase, 0.8 / WALK_STRIDE, EPSILON, "which is the ground covered over the stride")

	# A whole stride returns the cycle to where it started.
	var round_trip := FixtureWorld.driver(world, "core:biped")
	round_trip.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -WALK_STRIDE), 0.0, 1.0, ground)
	t.near(round_trip.phase, 0.0, EPSILON, "and one whole stride is one whole cycle, back to zero")


## Body height is taken from the feet that are DOWN, and never from one mid-swing. A swinging
## foot's plant is the ground under it, which is the right thing to tilt to and the wrong thing to
## stand on: a creature stepping over a ditch must not drop into it halfway through the stride.
##
## This section exists because mutation-testing found the policy line untested — swapping the
## stance feet for all of them left the suite green, since every other case here stands on ground
## where the two agree. So the creature is walked across the steepest part of the bowl's wall,
## where the swing carries one foot up to half a metre below the other.


## The no-skating claim in world space, against a body that is actually moving — which is the only
## place it can be checked, and the reason it went unchecked for so long.
##
## `_no_skating` above tests the *cycle*: one stride of ground is one turn of the phase. That is
## necessary and it is not sufficient. A foot can advance its phase perfectly and still drag along
## the ground, because what matters is the distance the stance carries it *relative to the body*
## versus the distance the body covers underneath it. Those two were not equal: the stance travelled
## a full `stride` while the body covered `duty * stride`, so every planted foot slid backward by
## `(1 - duty) * stride` — 0.32 m a step for a soldier at a walk. The cycle test passed throughout.
##
## What made it findable was measuring it: 0.00714 m of world slide per frame against a body
## covering 0.01667, which is exactly `speed * (1/duty - 1) * dt`. Matching a predicted number
## rather than "looks like it moves a bit" is what turned it from a suspicion into a one-line fix.
func _a_planted_foot_stays_put(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	if loco == null:
		return
	# Flat ground, so any movement of a planted foot is the gait's doing and not the terrain's.
	var ground := FixtureWorld.flat_ground()
	var speed := 1.0
	var dt := 1.0 / 60.0
	var at := Transform3D.IDENTITY

	var worst := 0.0
	var samples := 0
	var previous := Vector3.INF
	var was_stance := false
	for i in 200:
		at.origin += Vector3(0.0, 0.0, -speed * dt)
		loco.step(at, Vector3(0.0, 0.0, -speed), 0.0, dt, ground)
		var leg := loco.legs[0]
		if leg.stance and was_stance and previous != Vector3.INF:
			var moved: Vector3 = (leg.plant["position"] as Vector3) - previous
			worst = maxf(worst, Vector2(moved.x, moved.z).length())
			samples += 1
		was_stance = leg.stance
		previous = leg.plant["position"]

	t.ok(samples > 60, "the foot spent a good part of the run planted: %d frames" % samples)
	_and_especially_while_turning(t, world)
	# A tenth of a millimetre a frame. The body covers 16.7 mm in that time, so anything above
	# this is the foot being dragged rather than a rounding error in the lerp.
	t.ok(worst < 0.0001,
		"and while planted it does not move in world space: %.5f m per frame at worst" % worst)


## Which gait a speed calls for, and the band two of them blend across. `biped.json`'s ranges
## touch rather than overlap, which is the case `Gait._band` blends across a tenth of the
## narrower of the two rather than snapping.
func _gaits_hand_over_by_speed(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:biped")
	if loco == null:
		return
	var ground := FixtureWorld.test_ground()

	var slow: Dictionary = loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -1.0), 0.0, 0.1, ground)
	t.eq(String(slow["gait"]), "walk", "a metre a second is a walk")
	t.ok(not bool(slow["blending"]), "well clear of the transition")

	# Walk tops out at 3 and run starts there, so the band is 3 ± 0.15 — a tenth of the narrower
	# range, straddling the boundary. Dead on 3.0 is halfway through it.
	var changing: Dictionary = loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -3.0), 0.0, 0.1,
		ground)
	t.ok(bool(changing["blending"]), "at the boundary the two gaits are being mixed")

	var quick: Dictionary = loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -6.0), 0.0, 0.1,
		ground)
	t.eq(String(quick["gait"]), "run", "six metres a second is a run")
	t.ok(not bool(quick["blending"]), "past the transition rather than stuck in it")

	# Mid-blend the stride is between the two, which is what stops a gait change being a visible
	# hitch in the step length.
	t.near(float(loco.gait["stride"]), 2.0, EPSILON, "a run's stride is its own")
	loco.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -3.0), 0.0, 0.1, ground)
	t.near(float(loco.gait["stride"]), 1.6, EPSILON,
		"and halfway through the band it is half of each")


## `duty` is the fraction of the cycle a foot spends down, and RIG-SPEC §5 makes a specific claim
## about it: at a walk's duty a creature always has a foot on the ground, and at a gallop's the
## whole animal is briefly airborne. Both halves are asserted, because without the second one
## `duty` could be any number at all and nobody would notice.


## `duty` is the fraction of the cycle a foot spends down, and RIG-SPEC §5 makes a specific claim
## about it: at a walk's duty a creature always has a foot on the ground, and at a gallop's the
## whole animal is briefly airborne. Both halves are asserted, because without the second one
## `duty` could be any number at all and nobody would notice.
func _stance_and_swing(t: TestContext, world: Dictionary) -> void:
	var walking := FixtureWorld.driver(world, "core:biped")
	if walking == null:
		return
	var ground := FixtureWorld.test_ground()
	var least := 99
	var most := 0
	for i in 60:
		var out: Dictionary = walking.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -1.5), 0.0,
			0.05, ground)
		least = mini(least, int(out["planted"]))
		most = maxi(most, int(out["planted"]))
	t.ok(least >= 1, "a walking biped always has a foot down — its duty of 0.7 guarantees it")
	t.eq(most, 2, "and has both down at the bottom of the cycle")
	t.eq(least, 1, "while the legs genuinely alternate rather than both staying planted")

	# A gallop at duty 0.35. Four legs, and there has to be a moment with none of them down.
	var galloping := FixtureWorld.driver(world, "core:quadruped")
	if galloping == null:
		return
	var airborne := false
	var grounded := 0
	for i in 120:
		var out: Dictionary = galloping.step(Transform3D.IDENTITY, Vector3(0.0, 0.0, -14.0), 0.0,
			0.02, ground)
		if int(out["planted"]) == 0:
			airborne = true
		grounded = maxi(grounded, int(out["planted"]))
	t.eq(String(galloping.gait.get("name", "")), "gallop", "fourteen metres a second is a gallop")
	t.ok(airborne, "and a gallop takes the whole animal off the ground, as its duty says it must")
	t.ok(grounded >= 2, "while still putting most of its feet down somewhere in the cycle")


## The body's height and orientation come back from `step` rather than being written to anything,
## because the caller owns the body: it is a physics object with a collider, and a driver that
## moved it directly would be a kinematic system arguing with a simulated one.


## The same claim while the creature turns, which is where it was false for the whole milestone.
##
## Walking in a straight line hides this completely: the stance carries a foot backward relative
## to the body by exactly what the body covers forward, so the two cancel and a planted foot sits
## still without anything having to hold it there. Turning, they do not cancel — the ideal foot
## position is derived from the body and sweeps around with it — and a planted hoof scrubs
## sideways by most of a body-length per stride. Marissa saw it in the sandbox before any test
## did, because the demo walks its creatures in circles and every straight-line test passed.
##
## `Leg.anchor` is the fix: latch the world position at the footfall, hold it until the lift.
func _and_especially_while_turning(t: TestContext, world: Dictionary) -> void:
	var loco := FixtureWorld.driver(world, "core:quadruped")
	if loco == null:
		return
	var ground := FixtureWorld.flat_ground()
	var at := Transform3D.IDENTITY
	var yaw := 0.0
	var worst := 0.0
	var seen := 0
	var previous: Dictionary = {}
	for i in 240:
		yaw += 0.9 / 60.0            # the sandbox demo's own turn rate
		at.basis = Basis(Vector3.UP, yaw)
		at.origin += (at.basis * Vector3(0.0, 0.0, -2.0)) / 60.0
		loco.step(at, at.basis * Vector3(0.0, 0.0, -2.0), 0.9, 1.0 / 60.0, ground)
		for n in loco.legs.size():
			var leg := loco.legs[n]
			var here := Vector2((leg.plant["position"] as Vector3).x,
				(leg.plant["position"] as Vector3).z)
			if leg.stance and previous.has(n):
				worst = maxf(worst, here.distance_to(previous[n] as Vector2))
				seen += 1
			if leg.stance:
				previous[n] = here
			else:
				previous.erase(n)

	t.ok(seen > 200, "there were planted frames to measure across the turn: %d" % seen)
	# It was 0.022 m per frame against a body covering 0.033 — two thirds of the creature's own
	# travel, scrubbed across the ground by every foot that was supposed to be still.
	t.near(worst, 0.0, 0.0001,
		"a foot planted through a turn does not move at all: %.5f m per frame" % worst)
