class_name TwoBoneIK
extends RefCounted
## Two bones, one target, an analytic answer. RIG-SPEC §4.
##
## This is the highest-value piece of core tech in the rig system, because one solver serves
## everything that bends: a horse's leg, a soldier's arm reaching a steering wheel, a foot
## planting on the lip of a crater somebody shelled ten seconds ago. There is exactly one
## implementation and every one of those goes through it.
##
## It is closed-form — the law of cosines, not an iterative solver. That matters for reasons
## beyond speed. An iterative solver converges to a slightly different answer depending on
## where it started, which means two clients watching the same horse would see two subtly
## different legs and the animation would be one more thing the netcode had to carry. This
## returns the same answer for the same inputs on every machine, every frame, with no state,
## which is what lets a kinematic rig replicate as a root transform and a handful of floats
## (RIG-SPEC §9).
##
## Nothing here knows about parts, packs, or Godot nodes. It takes three vectors and two
## lengths. That is deliberate: the solver is the piece most likely to be wrong in a way that
## is invisible on screen, so it has to be testable without building anything.

## How close to fully straight a solved limb is allowed to get, as a fraction of its reach.
##
## A limb at exactly full extension has no bend plane — the knee could be anywhere on a
## circle — so the direction it snaps to when the target moves a millimetre further is
## arbitrary, and that arbitrariness is visible as a knee that flicks. Holding a hair back
## from straight costs nothing anybody can see and removes the flick entirely.
const STRAIGHT_LIMIT := 0.999

## And the same at the other end: two bones folded flat against each other is the same
## degeneracy seen from the inside, and it is the pose a leg reaches when the ground comes up
## under it faster than the body does.
const FOLDED_LIMIT := 1.001


## Solve for the joint between two bones. Returns:
##
##     joint     Vector3   where the knee/elbow ends up
##     end       Vector3   where the tip actually lands, which is the target when it can reach
##     reached   bool      false when the target was outside the limb's range
##     strain    float     how far past its range it was asked to go, in metres, or 0
##
## `bend` is the direction the joint travels toward — the way a knee points, not the way it
## bends. Passing the body's forward vector for a human knee and its backward vector for a
## horse's hock is the whole of the difference between the two, and getting it wrong is
## immediately, comically obvious, which is the best kind of wrong.
##
## An unreachable target is answered rather than refused. A leg stretched toward ground that
## has been dug out from under it should point at that ground and come up short, because
## `reached: false` is a fact the caller wants — the locomotion driver lowers the body when
## it sees one — and a solver that returned nothing would leave the leg in whatever pose it
## held last, which reads as a limb that froze.
static func solve(root: Vector3, target: Vector3, upper: float, lower: float,
		bend: Vector3) -> Dictionary:
	var span := target - root
	var distance := span.length()
	var reach := upper + lower
	var fold := absf(upper - lower)

	# A target sitting exactly on the root has no direction at all, so there is no axis to
	# build the bend plane from. `bend` is the only direction still meaningful here, and using
	# it puts the limb somewhere deliberate instead of somewhere left over.
	var axis := span / distance if distance > 0.0001 else _fallback_axis(bend)

	var reached := true
	var strain := 0.0
	if distance > reach * STRAIGHT_LIMIT:
		strain = maxf(0.0, distance - reach)
		reached = strain <= 0.0
		distance = reach * STRAIGHT_LIMIT
	# `maxf(..., 0.0001)` in the comparison and not only in the assignment. Two bones of equal
	# length have no fold at all, so `fold` is zero, so a target sitting exactly on the root
	# fails `0 < 0` and falls through with `distance` still zero — and the law of cosines below
	# divides by it. It reads as a limb that vanishes, and the case is not exotic: it is a foot
	# target that lands on the hip for one frame while a creature is being placed.
	elif distance < maxf(fold * FOLDED_LIMIT, 0.0001):
		strain = maxf(0.0, fold - distance)
		reached = strain <= 0.0
		distance = maxf(fold * FOLDED_LIMIT, 0.0001)

	var end := root + axis * distance
	var plane := _bend_direction(axis, bend)

	# Law of cosines for the angle at the root, between the upper bone and the line to the
	# target. Clamped because a float that lands at 1.0000001 is `acos` returning NAN and a
	# limb that vanishes, and the inputs that produce it are the ordinary ones.
	var cosine := clampf(
		(upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance),
		-1.0, 1.0)
	var along := upper * cosine
	var across := upper * sqrt(maxf(0.0, 1.0 - cosine * cosine))

	return {
		"joint": root + axis * along + plane * across,
		"end": end,
		"reached": reached,
		"strain": strain,
	}


## Where the joint goes, as a unit vector perpendicular to the limb's line.
##
## `bend` is a hint rather than an instruction: an author writes "forward" and the limb may
## be pointing anywhere, so the component of the hint that lies along the limb is dropped and
## what remains is the bend plane. When nothing remains — the hint pointing straight down a
## leg that is also pointing straight down — any perpendicular will do, and the one chosen is
## the one that stays stable as the limb turns, because a bend plane that jumps between
## frames is a knee that snaps sideways for a frame and back again.
static func _bend_direction(axis: Vector3, bend: Vector3) -> Vector3:
	var flat := bend - axis * axis.dot(bend)
	if flat.length_squared() > 0.000001:
		return flat.normalized()
	var seed := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	return (seed - axis * axis.dot(seed)).normalized()


static func _fallback_axis(bend: Vector3) -> Vector3:
	return bend.normalized() if bend.length_squared() > 0.000001 else Vector3.DOWN


## The angle in radians between two bones meeting at a joint, for anything that needs to hold
## a solved pose against a declared joint limit. The solver itself does not clamp to limits —
## it answers the geometry question — and `Rig` is where the answer meets the part table.
static func interior_angle(root: Vector3, joint: Vector3, end: Vector3) -> float:
	var a := root - joint
	var b := end - joint
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
		return PI
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))


## A bone's orientation, given where it starts, where it ends, and which way the limb bends.
##
## ART-BIBLE §7 fixes facing at -Z, so a bone points down its own -Z and the part table's
## `size` reads `[thickness, thickness, length]` for a limb segment exactly as it does for a
## gun barrel. The bend direction becomes the bone's +Y, which is what stops a leg from
## spinning about its own length between frames while the foot stays put.
static func bone_basis(from: Vector3, to: Vector3, bend: Vector3) -> Basis:
	var along := to - from
	if along.length_squared() < 0.000001:
		return Basis.IDENTITY

	# Columns are the local X, Y and Z axes. The bone points down its own -Z, so its +Z axis
	# is the way it came from, and Y is handed the bend plane. X falls out of the other two,
	# then Y is rebuilt from X and Z — `bend` arrives as a hint and is rarely exactly square
	# to the bone, and a basis assembled from three not-quite-perpendicular vectors is a
	# sheared one, which shows up as a limb segment that is subtly fatter at one end.
	var z_axis := -along.normalized()
	var y_axis := _bend_direction(along.normalized(), bend)
	var x_axis := y_axis.cross(z_axis).normalized()
	return Basis(x_axis, z_axis.cross(x_axis).normalized(), z_axis)
