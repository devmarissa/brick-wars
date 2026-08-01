class_name Projectile
extends RefCounted
## A shot, moving. CORE-SPEC §2 (hit detection).
##
## ### Why this is a sweep and not a position
##
## The obvious way to fly a bullet is to move it each frame and ask what is at the new spot. At a
## rifle's 150 m/s and 60 Hz that is **2.5 metres per frame**, so the obvious way passes straight
## through a brick wall, a sandbag revetment and the soldier behind them without touching any of
## them. It does not do this reliably, either: it depends on where in the step the wall happened to
## be, so it looks like flaky netcode rather than like a missing sweep.
##
## So a step produces a *segment* — where the round was, where it now is — and the world is asked
## what lies between. The arc is the same arithmetic `Ballistics` already does; the only thing
## added here is that consecutive segments share their endpoints, with no gap for anything to hide
## in. `case_damage.gd` asserts exactly that, because it is the property the whole approach rests
## on and it is invisible in any single call.
##
## ### Slow things need this too
##
## An arrow at 55 m/s covers 0.9 m a frame, which still skips a 0.3 m plank about two thirds of the
## time. The sweep is not a fast-projectile optimisation; it is how hit detection works, and the
## rifle is only the case where the bug would have been obvious.
##
## ### State stays with the caller
##
## Same shape as `VerbFire`: nothing is stored here. A caller keeps a position and a velocity and
## hands them back, which is what lets a test, a bot and C8's replay of somebody else's shot all
## drive the identical code without any of them owning an object.

## How far off a surface a bouncing object resumes, in metres.
##
## Not a fudge factor — a necessary one, and the bug it fixes is worth naming because everybody
## writes it once. A sweep that hits reports the contact point, which is *on* the surface. Resume
## the next sweep from exactly there and the ray begins inside the thing it just hit, finds nothing,
## and the object passes through the floor it had just bounced off. The symptom is a grenade that
## bounces once, convincingly, and then falls through the world.
##
## So a bounce resumes a couple of centimetres along the normal. Small enough that nothing can be
## seen floating; large enough to be outside any tolerance the physics engine has.
const SKIN := 0.02

## Longest a single step may be, in metres, before it is split. A step is normally a frame, but a
## frame is not guaranteed — a hitch, a debugger pause or a low-end machine can hand over a tenth of
## a second, and at 150 m/s that is a 15 m segment through however many walls. Splitting keeps the
## question the physics engine is asked the same size regardless of how the frame went.
const MAX_SEGMENT := 4.0


## Advance one step along the arc. Returns where the round now is and how fast it is going, plus the
## segment it crossed to get there — which is the part that matters, and the part a position-only
## model throws away.
static func advance(origin: Vector3, velocity: Vector3, delta: float,
		gravity := Ballistics.GRAVITY) -> Dictionary:
	var to := origin + velocity * delta - Vector3.UP * (0.5 * gravity * delta * delta)
	return {
		"from": origin,
		"to": to,
		"velocity": velocity - Vector3.UP * (gravity * delta),
		"length": origin.distance_to(to),
	}


## The same step, cut into pieces no longer than `MAX_SEGMENT`. Every piece begins where the last
## one ended, so there is no gap anywhere along the flight for a wall to slip through.
static func segments(origin: Vector3, velocity: Vector3, delta: float,
		gravity := Ballistics.GRAVITY) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if delta <= 0.0:
		return out

	var whole := advance(origin, velocity, delta, gravity)
	var pieces := maxi(1, int(ceil(float(whole["length"]) / MAX_SEGMENT)))
	var at: Vector3 = origin
	var moving: Vector3 = velocity
	var slice := delta / float(pieces)
	for i in pieces:
		var step := advance(at, moving, slice, gravity)
		out.append(step)
		at = step["to"]
		moving = step["velocity"]
	return out


## Ask the world what is between two points. Returns the standard hit shape whether or not anything
## was there, so a caller never has to check for an empty dictionary before reading a field.
##
## `ignore` is the shooter. A round that spawns inside the rifle of the man firing it and instantly
## hits him is the first bug anybody writing this has, and it reads in play as "my gun is broken".
static func sweep(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		ignore: Array[RID] = []) -> Dictionary:
	var miss := { "hit": false, "position": to, "normal": Vector3.ZERO, "collider": null }
	if space == null or from.is_equal_approx(to):
		return miss

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = ignore
	# Bodies only. Areas are triggers and trigger volumes are not cover — a round that stopped on a
	# capture zone would be a very confusing afternoon.
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var found := space.intersect_ray(query)
	if found.is_empty():
		return miss
	return {
		"hit": true,
		"position": found.get("position", to),
		"normal": found.get("normal", Vector3.ZERO),
		"collider": found.get("collider"),
	}


## Fly a step and stop at whatever it runs into. The two halves above, in the order every caller
## wants them, so nobody re-implements the loop and forgets to carry the velocity forward.
static func fly(space: PhysicsDirectSpaceState3D, origin: Vector3, velocity: Vector3,
		delta: float, ignore: Array[RID] = [],
		gravity := Ballistics.GRAVITY) -> Dictionary:
	var at := origin
	var moving := velocity
	for step in segments(origin, velocity, delta, gravity):
		var found := sweep(space, step["from"], step["to"], ignore)
		if found["hit"]:
			return { "hit": true, "position": found["position"], "normal": found["normal"],
				"collider": found["collider"], "velocity": moving, "travelled": origin.distance_to(
					found["position"]) }
		at = step["to"]
		moving = step["velocity"]
	return { "hit": false, "position": at, "normal": Vector3.ZERO, "collider": null,
		"velocity": moving, "travelled": origin.distance_to(at) }


## Come off a surface. A thrown thing that stops dead where it lands is a thrown thing nobody can
## use around a corner, and bouncing is most of what makes a grenade a tactical object rather than
## a slow bullet — it is how you get one into a dugout you cannot see into.
##
## `restitution` is how much speed survives, and the tangential component is damped harder than the
## normal one because a grenade rolling forever is worse than one that stops too soon. Both numbers
## are the *object's* rather than the surface's for now; making them a material property is C5's,
## alongside everything else about what a surface does when something arrives at it.
static func bounce(velocity: Vector3, normal: Vector3, restitution: float,
		friction := 0.6) -> Vector3:
	if normal.is_zero_approx():
		return velocity
	var unit := normal.normalized()
	var into := velocity.dot(unit)
	# Already leaving: do not flip a velocity that is not arriving, or a grazing contact reverses a
	# throw that was on its way past.
	if into >= 0.0:
		return velocity
	var straight := unit * into
	var along := velocity - straight
	return along * (1.0 - friction) - straight * restitution
