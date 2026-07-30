extends TestCase
## The two-bone solver and the gait engine, checked as the arithmetic they are.
##
## Neither of these touches a node, a pack or a part table, and that is the reason they are
## testable at all. They are also the pieces most likely to be wrong in a way nobody sees
## until a horse is on screen skating, so `case_geometry.gd`'s discipline applies here for the
## same reason: no loader, no fixtures, no scene. Three vectors and two lengths in, a knee out.
##
## What the rig does with the answers — building the hierarchy, posing it, keeping the
## colliders out of it — is `case_rig.gd`, which needs the whole loader to say anything.

## A tenth of a millimetre. The lengths here are order 1 m, so anything this far apart is a
## different formula rather than a different rounding.
const EPSILON := 0.0001

## RIG-SPEC §5's own example, verbatim, minus the leg table it does not need. Written out
## rather than loaded so that a change to the spec's example is a deliberate edit here too.
const GAITS := [
	{"name": "walk", "speed": [0, 4], "phases": [0.0, 0.5, 0.25, 0.75],
		"stride": 1.2, "lift": 0.25, "duty": 0.7},
	{"name": "trot", "speed": [4, 9], "phases": [0.0, 0.5, 0.5, 0.0],
		"stride": 2.0, "lift": 0.45, "duty": 0.5},
	{"name": "gallop", "speed": [9, 20], "phases": [0.0, 0.1, 0.5, 0.6],
		"stride": 3.4, "lift": 0.8, "duty": 0.35},
]


func case_name() -> String:
	return "locomotion"


func run(t: TestContext) -> void:
	_reaches(t)
	_cannot_reach(t)
	_bends_the_way_it_is_told(t)
	_same_answer_every_time(t)
	_gait_for_speed(t)
	_gait_blends(t)
	_foot_cycle(t)


## The whole contract of the solver in three lines: the upper bone is its own length, the
## lower bone is its own length, and the tip is on the target. Checked at several targets
## rather than one, because the law of cosines has a way of being right at 90° and nowhere
## else.
func _reaches(t: TestContext) -> void:
	var upper := 0.6
	var lower := 0.6
	for target in [Vector3(0, -1, 0), Vector3(0.3, -0.8, 0.2), Vector3(-0.9, 0, 0),
			Vector3(0, 0, -1.1)]:
		var out := TwoBoneIK.solve(Vector3.ZERO, target, upper, lower, Vector3.BACK)
		var joint: Vector3 = out["joint"]
		var end: Vector3 = out["end"]
		t.near(joint.length(), upper, EPSILON, "the upper bone keeps its length to %v" % target)
		t.near(joint.distance_to(end), lower, EPSILON, "and so does the lower one")
		t.ok(end.distance_to(target) < EPSILON, "and the tip lands on the target at %v" % target)
		t.ok(bool(out["reached"]), "and it reports having reached it")
		t.near(float(out["strain"]), 0.0, EPSILON, "with nothing strained")

	# Bones of unequal length is the ordinary case — a thigh is longer than a shin — and it is
	# the one where an implementation that assumed symmetry passes everything above.
	var uneven := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -1.0, 0), 0.7, 0.4, Vector3.BACK)
	var knee: Vector3 = uneven["joint"]
	t.near(knee.length(), 0.7, EPSILON, "an upper bone longer than its lower keeps its length")
	t.near(knee.distance_to(uneven["end"]), 0.4, EPSILON, "and the short one keeps its")


## A target out of range is answered, not refused. The locomotion driver lowers the body when
## it sees `reached: false`, and a solver that returned nothing would leave the limb in
## whatever pose it held last — which reads as a leg that froze rather than as one that is
## stretching for ground somebody just shelled out from under it.
func _cannot_reach(t: TestContext) -> void:
	var far := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -2.0, 0), 0.6, 0.6, Vector3.BACK)
	t.ok(not bool(far["reached"]), "a target past full reach is not reached")
	t.near(float(far["strain"]), 0.8, EPSILON, "and the shortfall is reported in metres")
	var end: Vector3 = far["end"]
	t.ok(end.normalized().distance_to(Vector3.DOWN) < EPSILON,
		"and the limb still points at it rather than somewhere convenient")
	t.ok(end.length() < 1.2, "held a hair back from straight, so the knee has a plane to bend in")

	# The other end of the same degeneracy, and the one a leg actually hits: the ground comes
	# up under it faster than the body comes down, and the two bones fold flat.
	var near_in := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -0.2, 0), 0.9, 0.3, Vector3.BACK)
	t.ok(not bool(near_in["reached"]), "nor is a target inside the fold")
	t.near(float(near_in["strain"]), 0.4, EPSILON, "and that shortfall is reported too")

	# A target sitting exactly on the root has no direction at all, and the limb still has to
	# go somewhere deliberate rather than somewhere left over.
	var atop := TwoBoneIK.solve(Vector3.ZERO, Vector3.ZERO, 0.6, 0.6, Vector3.BACK)
	var atop_joint: Vector3 = atop["joint"]
	t.ok(is_finite(atop_joint.x) and is_finite(atop_joint.y) and is_finite(atop_joint.z),
		"a target on the root produces a pose rather than a NaN")


## `bend` is the way the knee points, and it is the whole of the difference between a human
## knee and a horse's hock. Getting it wrong is comically obvious on screen, which is the best
## kind of wrong — but only once something is on screen, so it is pinned here.
func _bends_the_way_it_is_told(t: TestContext) -> void:
	var forward := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -1, 0), 0.6, 0.6, Vector3.FORWARD)
	var backward := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -1, 0), 0.6, 0.6, Vector3.BACK)
	var knee: Vector3 = forward["joint"]
	var hock: Vector3 = backward["joint"]
	t.ok(knee.z < 0.0, "a knee told to point forward points forward, which is -Z (ART-BIBLE §7)")
	t.ok(hock.z > 0.0, "and a hock told the other way points the other way")
	t.near(knee.y, hock.y, EPSILON, "at the same height, because only the plane changed")

	# The hint is rarely square to the limb — an author writes "forward" and the leg is
	# wherever the creature put it — so the part lying along the limb is dropped rather than
	# shearing the answer.
	var skewed := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -1, 0), 0.6, 0.6,
		Vector3(0, -3, 1).normalized())
	var skewed_joint: Vector3 = skewed["joint"]
	t.near(skewed_joint.length(), 0.6, EPSILON, "a bend hint at an angle still solves cleanly")
	t.ok(skewed_joint.z > 0.0, "and bends the way the part of the hint across the limb pointed")

	# A hint pointing straight down the limb leaves nothing to build a plane from, and any
	# perpendicular will do so long as it is the *same* one next frame.
	var degenerate := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -1, 0), 0.6, 0.6, Vector3.DOWN)
	var again := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -1, 0), 0.6, 0.6, Vector3.DOWN)
	t.eq(degenerate["joint"], again["joint"], "a hint along the limb still picks a stable plane")

	t.near(TwoBoneIK.interior_angle(Vector3.ZERO, Vector3(0, -0.6, 0), Vector3(0, -1.2, 0)),
		PI, EPSILON, "a straight limb's interior angle is π")
	t.near(TwoBoneIK.interior_angle(Vector3.ZERO, Vector3(0, -0.6, 0), Vector3.ZERO),
		0.0, EPSILON, "and a fully folded one's is nothing")

	# ART-BIBLE §7 fixes facing at -Z, so a bone points down its own -Z and a limb segment's
	# `size` reads `[thickness, thickness, length]` exactly as a gun barrel's does.
	var basis := TwoBoneIK.bone_basis(Vector3.ZERO, Vector3(0, -1, 0), Vector3.BACK)
	t.ok((basis * Vector3.FORWARD).distance_to(Vector3.DOWN) < EPSILON,
		"a bone aimed downward points its own -Z downward")
	t.near(basis.determinant(), 1.0, EPSILON,
		"and the basis is a rotation, not a shear — a sheared bone is fatter at one end")


## Two clients solving the same leg have to get the same leg. This is why the solver is
## closed-form rather than iterative: an iterative one converges somewhere slightly different
## depending on where it started, and the difference would be one more thing the netcode had
## to carry (RIG-SPEC §9).
func _same_answer_every_time(t: TestContext) -> void:
	var a := TwoBoneIK.solve(Vector3(1, 2, 3), Vector3(1.2, 1.4, 3.1), 0.4, 0.5, Vector3.BACK)
	var b := TwoBoneIK.solve(Vector3(1, 2, 3), Vector3(1.2, 1.4, 3.1), 0.4, 0.5, Vector3.BACK)
	t.eq(a["joint"], b["joint"], "the same inputs give a bit-identical knee")
	t.eq(a["end"], b["end"], "and a bit-identical foot")


## Which gait a speed calls for, and the hand-over between them. The ranges in RIG-SPEC §5's
## example merely touch, so this is also the case where a naive "last gait whose range has
## started" would snap.
func _gait_for_speed(t: TestContext) -> void:
	t.eq(String(Gait.for_speed(GAITS, 0.0)["name"]), "walk", "standing still holds the slowest gait")
	t.eq(String(Gait.for_speed(GAITS, 2.0)["name"]), "walk", "and so does a walking pace")
	t.eq(String(Gait.for_speed(GAITS, 6.0)["name"]), "trot", "the middle of a range is that gait")
	t.eq(String(Gait.for_speed(GAITS, 15.0)["name"]), "gallop", "and the top one is the top one")
	t.eq(String(Gait.for_speed(GAITS, 100.0)["name"]), "gallop",
		"a speed past every range is the fastest gait rather than nothing")

	var walking := Gait.for_speed(GAITS, 2.0)
	t.near(float(walking["stride"]), 1.2, EPSILON, "an unblended gait is its own numbers — stride")
	t.near(float(walking["duty"]), 0.7, EPSILON, "and duty")
	t.ok(not bool(walking["blending"]), "and says it is not blending")

	# `duty` is optional and defaults to the safe end: a gallop with a walk's duty looks
	# laboured, and a walk with a gallop's looks like the creature is skating.
	var plain := Gait.for_speed([{"name": "amble", "speed": [0, 5], "stride": 1.0}], 1.0)
	t.near(float(plain["duty"]), Gait.DEFAULT_DUTY, EPSILON, "a gait with no duty gets the default")
	t.ok(Gait.for_speed([], 1.0).is_empty(), "and a creature with no gaits declared gets nothing")

	# Out of order is a warning upstream, not an error, so the blend has to sort for itself or
	# `walk → gallop → trot` transitions the wrong way.
	var shuffled := [GAITS[2], GAITS[0], GAITS[1]]
	t.eq(String(Gait.for_speed(shuffled, 2.0)["name"]), "walk",
		"gaits declared out of order are still walked in speed order")


## The transition itself, which is the part that is invisible until it is wrong and then is
## the only thing anybody looks at.
func _gait_blends(t: TestContext) -> void:
	var mid := Gait.for_speed(GAITS, 4.0)
	t.ok(bool(mid["blending"]), "the middle of the walk/trot hand-over is a blend")
	t.near(float(mid["stride"]), 1.6, 0.001, "and its stride is halfway between the two")
	t.near(float(mid["duty"]), 0.6, 0.001, "as is its duty")

	# The whole point of doing it this way: nothing jumps at the boundary. The old index rule
	# handed over at the start of the trot's range while the band straddled it, which left a
	# 0.4 m step in the stride at exactly the speed everybody walks at.
	var below := float(Gait.for_speed(GAITS, 4.19)["stride"])
	var above := float(Gait.for_speed(GAITS, 4.21)["stride"])
	t.ok(absf(above - below) < 0.02, "and the stride is continuous across the hand-over")
	t.ok(not bool(Gait.for_speed(GAITS, 4.5)["blending"]), "past the band it is one gait again")

	# Overlapping ranges are the real mechanism — an author who writes walk [0, 4] and trot
	# [3, 9] has said "take a whole unit of speed to change gait", which is more control than
	# any dedicated field would give.
	var declared := [
		{"name": "walk", "speed": [0, 4], "stride": 1.0, "phases": [0.0]},
		{"name": "trot", "speed": [3, 9], "stride": 3.0, "phases": [0.0]},
	]
	t.near(float(Gait.for_speed(declared, 3.5)["stride"]), 2.0, 0.001,
		"a declared overlap blends across the whole of it")
	t.ok(bool(Gait.for_speed(declared, 3.5)["blending"]), "and says so")
	t.near(float(Gait.for_speed(declared, 2.0)["stride"]), 1.0, EPSILON,
		"and below the overlap nothing is blended")

	# Phases are positions on a circle, so they take the short way round. A straight lerp here
	# is a leg that visibly reverses for the length of a gait change, which is the one thing a
	# gait change is not allowed to look like.
	var around := [
		{"name": "a", "speed": [0, 4], "stride": 1.0, "phases": [0.9]},
		{"name": "b", "speed": [4, 8], "stride": 1.0, "phases": [0.1]},
	]
	var phases: Array = Gait.for_speed(around, 3.9)["phases"]
	t.near(float(phases[0]), 0.95, 0.001,
		"0.9 blending a quarter of the way to 0.1 goes forward to 0.95, not back to 0.7")


## Where a foot is at a point in its cycle. Stance is the one curve here that must be a
## straight line: a planted foot travels backward at exactly the speed the body travels
## forward, and any easing at all is a foot sliding on the ground.
func _foot_cycle(t: TestContext) -> void:
	var stride := 1.2
	var duty := 0.6
	var down: Vector3 = Gait.foot_cycle(0.0, stride, 0.25, duty)["offset"]
	var flat: Vector3 = Gait.foot_cycle(duty * 0.5, stride, 0.25, duty)["offset"]
	var up: Vector3 = Gait.foot_cycle(duty * 0.999, stride, 0.25, duty)["offset"]

	# The stance travels `duty * stride` relative to the body, not `stride`, because that is how
	# far the body itself moves while the foot is down — and a foot that travels any other
	# distance is a foot dragging along the ground. 0.6 x 1.2 / 2 = 0.36.
	t.near(down.z, -0.36, EPSILON, "a foot that has just landed is ahead of the body, at -Z")
	t.near(up.z, 0.36, 0.005, "and leaves the ground behind it, by the distance the body covered")
	t.near(flat.z, 0.0, EPSILON, "and is under the body halfway through")
	t.near(flat.z, (down.z + up.z) * 0.5, 0.005, "exactly halfway, because stance is linear")
	t.near(down.y, 0.0, EPSILON, "and it is on the ground for all of it")
	t.ok(bool(Gait.foot_cycle(0.3, stride, 0.25, duty)["planted"]), "and reports being planted")

	var swing: Dictionary = Gait.foot_cycle(duty + (1.0 - duty) * 0.5, stride, 0.25, duty)
	var lifted: Vector3 = swing["offset"]
	t.near(lifted.y, 0.25, EPSILON, "the top of the swing clears the ground by the declared lift")
	t.near(lifted.z, 0.0, EPSILON, "and is above the middle of the stride")
	t.ok(not bool(swing["planted"]), "and is not planted")

	var landing: Vector3 = Gait.foot_cycle(0.999, stride, 0.25, duty)["offset"]
	t.ok(landing.distance_to(down) < 0.01, "and the cycle closes where it opened, without a jump")
	t.ok(Vector3(Gait.foot_cycle(1.3, stride, 0.25, duty)["offset"]).distance_to(
		Vector3(Gait.foot_cycle(0.3, stride, 0.25, duty)["offset"])) < EPSILON,
		"and a phase past one is the same place as the phase it wraps to")

	# The no-skating property, stated as the arithmetic it is: a creature that has covered one
	# stride's worth of ground has advanced exactly one cycle, so the foot it put down is the
	# foot it picks up.
	t.near(Gait.advance(stride, stride, 1.0), 1.0, EPSILON,
		"travelling one stride advances exactly one cycle")
	t.near(Gait.advance(3.0, 1.5, 0.5), 1.0, EPSILON, "and it scales with speed and time")
	t.near(Gait.advance(-3.0, 1.5, 0.5), 1.0, EPSILON, "reversing is still a cycle, not a negative one")
	t.near(Gait.advance(3.0, 0.0, 0.5), 0.0, EPSILON,
		"and a stride of nothing advances nothing rather than dividing by it")

	# And the other half of not skating, which `advance` alone does not give: over the stance the
	# foot has to travel backward relative to the body by exactly what the body travels forward.
	# One cycle is one stride of ground, so the body covers `duty * stride` while the foot is down.
	var travelled := up.z - down.z
	t.near(travelled, duty * stride, 0.005,
		"a planted foot travels back by exactly the ground the body covers while it is down")
	# Again at another stride and another duty, so the line above is a formula rather than one
	# arithmetic coincidence. The phase has to be sampled just inside *this* duty, not the one
	# above it — reusing the outer `duty` here sampled the swing instead and read 0.897.
	var other_duty := 0.5
	var other_stride := 2.0
	t.near(Vector3(Gait.foot_cycle(other_duty * 0.999, other_stride, 0.2, other_duty)["offset"]).z
			- Vector3(Gait.foot_cycle(0.0, other_stride, 0.2, other_duty)["offset"]).z,
		other_duty * other_stride, 0.01,
		"which holds at another stride and another duty, rather than by coincidence")
