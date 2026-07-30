class_name Footing
extends RefCounted
## Where a foot actually lands, and what the body does about it. RIG-SPEC §4.
##
## This matters more in this game than in most, and RIG-SPEC says why in one sentence: the
## ground is constantly being dug up. A canned walk cycle is authored against a floor that
## holds still, and ours does not — somebody shelled it ten seconds ago. A hoof sliding
## through the lip of a fresh crater destroys the illusion instantly, and no amount of art
## budget fixes it, because the art was made before the crater existed.
##
## So the rule is: the leg's ideal foot position is a *suggestion*, the ground has the final
## say, and the body moves to keep the suggestion reachable.
##
## ### Nothing here knows what the ground is
##
## Every function takes a `probe` — a `Callable` that answers "what is under this point" and
## returns `{y, normal, hit}`. At C2 that is `TestGround.height_at`; at C3 it is the earth
## field; in a live match it is `raycast_probe`, which is a real downward cast against the
## physics world. The policy in this file is the same in all three, which is the point: the
## thing that decides how a creature stands should not be rewritten when the terrain is.
##
## Same discipline as `TwoBoneIK` and for the same reason — this is the code most likely to
## be wrong in a way that looks like a bad animation rather than like a bug, so it has to be
## checkable with numbers instead of by eye.

## The furthest a body will tilt to match the ground it is standing on, whatever `strength`
## says. A creature that matched the 39° face of a step would lie down on it; real animals
## keep their spine much closer to level than the terrain under them and take the difference
## up in their legs, which is what the legs are for.
const MAX_TILT := 35.0

## Below this the average of a set of normals is not a direction. It happens when a probe
## missed on every foot, and the honest answer then is "level", not whatever fell out of
## normalising a zero vector.
const FAINT := 0.0001


## Where one foot goes. `ideal` is where the gait wanted it; `reach` is how far up or down
## the leg can chase the ground from there before it is out of its own range.
##
## Returns:
##
##     position   Vector3   where to solve the leg to
##     normal     Vector3   the surface it is standing on, for the ankle
##     planted    bool      false when the ground was out of range or missing
##     drop       float     how far the foot moved from `ideal`, signed, down positive
##
## `reach` is a clamp rather than a refusal, and both directions matter. Below: a foot
## swinging out over a crater finds ground four metres down and must not chase it, or the leg
## stretches to a straight line pointing into a hole and the creature reads as impaled. Above:
## a foot that swings into the side of a step finds ground above its own hip, and planting
## there without a limit folds the leg through the body.
##
## An unplanted foot is answered rather than refused, exactly as the solver answers an
## unreachable target — `planted: false` is a fact the driver acts on, and a foot with no
## answer at all is a foot left wherever it was last frame, which reads as a limb that froze.
static func plant(probe: Callable, ideal: Vector3, reach: float) -> Dictionary:
	var under: Dictionary = probe.call(ideal)
	var hit := bool(under.get("hit", false))
	var y := float(under.get("y", ideal.y))
	var normal: Vector3 = under.get("normal", Vector3.UP)

	var floor_y := clampf(y, ideal.y - reach, ideal.y + reach)
	var planted := hit and is_equal_approx(floor_y, y)
	if not hit:
		# Nothing under the foot at all — off the edge of the world, or over a hole deeper
		# than the probe looked. The foot hangs at the bottom of its range with a level
		# ankle, which is what a leg reaching for ground that is not there does.
		floor_y = ideal.y - reach
		normal = Vector3.UP

	return {
		"position": Vector3(ideal.x, floor_y, ideal.z),
		"normal": normal.normalized() if normal.length_squared() > FAINT else Vector3.UP,
		"planted": planted,
		"drop": ideal.y - floor_y,
	}


## The body's orientation, given what its feet are standing on.
##
## `strength` is the pack's `body_pitch` — 0 holds the body level to the world, 1 lays it flat
## along the ground. Neither end is what anything real does, which is why it is a number an
## author tunes rather than a behaviour the core picks: a tank-like quadruped wants more of
## it than a soldier does, and a soldier wants some, because a man walking up a hill leans.
##
## Yaw is preserved exactly. `forward` comes in as the direction the creature is travelling
## and is flattened against the new up rather than replaced, so tilting a body never turns it
## — a body that yawed when it crested a ridge would fight the steering every frame.
static func level(normals: Array, forward: Vector3, strength: float) -> Basis:
	var up := average(normals)
	var lean := clampf(strength, 0.0, 1.0)
	if lean > 0.0 and up.angle_to(Vector3.UP) > deg_to_rad(MAX_TILT):
		# Capped by shortening the slerp rather than by clamping the result, so a body on a
		# 60° face and one on a 40° face do not arrive at the same pose and stop responding
		# to the ground entirely.
		lean = minf(lean, deg_to_rad(MAX_TILT) / up.angle_to(Vector3.UP))
	return facing(forward, Vector3.UP.slerp(up, lean))


## The mean of a set of surface normals, or straight up when there is nothing to average.
## Summed and normalised rather than slerped pairwise: four feet on four faces of a bowl
## should answer "level", and that is what a sum does.
static func average(normals: Array) -> Vector3:
	var total := Vector3.ZERO
	for n in normals:
		total += (n as Vector3)
	return total.normalized() if total.length_squared() > FAINT else Vector3.UP


## A basis with a given up, facing as close to `forward` as that up allows. ART-BIBLE §7 puts
## facing down -Z, so `forward` is the direction travelled and the basis's Z is its opposite.
static func facing(forward: Vector3, up: Vector3) -> Basis:
	var raised := up.normalized() if up.length_squared() > FAINT else Vector3.UP
	var flat := forward - raised * raised.dot(forward)
	if flat.length_squared() <= FAINT:
		# Travelling straight up or down — a creature being dropped in, or one on a ladder.
		# Any facing is as good as any other and the one that must not happen is a NaN.
		flat = raised.cross(Vector3.RIGHT)
		if flat.length_squared() <= FAINT:
			flat = raised.cross(Vector3.BACK)

	var z_axis := -flat.normalized()
	var x_axis := raised.cross(z_axis).normalized()
	return Basis(x_axis, z_axis.cross(x_axis), z_axis)


## How high the body stands, given where its feet ended up.
##
## Two rules, and the second overrides the first. Stand `stand` metres above the average of
## the planted feet — the average, so a single foot in a rut does not drop the whole animal.
## Then come down far enough that the *lowest* foot is still inside `reach`, because a leg
## that cannot reach its own plant point is one that will be solved straight and skate.
##
## Coming down rather than splitting the difference is deliberate. A creature standing too
## low looks like it is crouching, which is a pose animals adopt; standing too high looks
## like it is hovering, which is not.
static func support(plants: Array, stand: float, reach: float) -> float:
	if plants.is_empty():
		return 0.0

	var total := 0.0
	var lowest := INF
	for entry in plants:
		var at: float = (entry as Dictionary).get("position", Vector3.ZERO).y
		total += at
		lowest = minf(lowest, at)
	return minf(total / plants.size() + stand, lowest + reach)


## True when the ground has moved out from under the creature far enough that the driver
## should do something about it rather than keep solving. One unplanted foot on a quadruped
## is a stride over a ditch; half of them is a creature standing on nothing.
static func unsupported(plants: Array) -> bool:
	if plants.is_empty():
		return true
	var down := 0
	for entry in plants:
		if bool((entry as Dictionary).get("planted", false)):
			down += 1
	return down * 2 < plants.size()


## A probe that casts straight down against the physics world — what the game uses once
## there is a world to cast against.
##
## `reach` is how far below the ideal position to look, and the cast starts `reach` *above*
## it so a foot that has ended up slightly inside a fresh crater lip still finds the surface
## it is inside rather than the one under the whole hill. `exclude` is the creature's own
## bodies: a leg that plants on its own collider stands on itself and rises off the ground a
## few centimetres every frame until it is in orbit.
static func raycast_probe(space: PhysicsDirectSpaceState3D, reach: float,
		exclude: Array[RID] = [], mask := 0xFFFFFFFF) -> Callable:
	return func(at: Vector3) -> Dictionary:
		var query := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * reach, at + Vector3.DOWN * reach, mask, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {"hit": false, "y": at.y - reach, "normal": Vector3.UP}
		return {
			"hit": true,
			"y": float((hit["position"] as Vector3).y),
			"normal": hit["normal"] as Vector3,
		}
