class_name Ballistics
extends RefCounted
## Where a projectile goes. CORE-SPEC §2 (combat maths).
##
## Arrows and bullets are the same arithmetic. The whole of C4's done-condition rests on that
## sentence being literally true rather than nearly true, so this file is written to make the
## alternative impossible: it takes a speed, a direction and a gravity, and it has no idea what
## launched it. The day it contains the word `rifle` or the word `bow`, the era boundary has failed
## and `VISION`'s bet — *"no `if weapon == "rifle"` in the core"* — has already been lost.
##
## What makes an arrow feel like an arrow and a bullet like a bullet is therefore **entirely** the
## numbers in the pack file. A bolt rifle leaves at 150 m/s and an arrow at 55, and over 40 m that
## is 0.7 m of drop against 5.3 m — a flat crack versus a lobbed arc — out of one formula that was
## never told which was which.
##
## ### Gravity is the world's, not the walker's
##
## 20 m/s², the world's. Not `Walker.GRAVITY`, which is 22 and deliberately
## snappier than the world because a character that falls at the world's rate reads as floaty. A
## soldier is allowed to disagree with physics about how it feels to jump; a bullet is not, because
## it shares the air with every brick and body that C5 is going to throw around, and two gravities
## in one trajectory space is the kind of thing nobody notices until a shell and its own debris
## land in different places.
##
## ### Determinism
##
## Spread takes a seeded generator rather than reaching for `randf()`. C8 has to reproduce a shot
## on a client that did not roll it, and a global RNG makes that impossible in a way that shows up
## as "hits sometimes disagree" two milestones after the cause. Same discipline as the earth's
## integer arithmetic, for the same reason, at a place where floats are otherwise fine.

## The world's gravity. A literal because a module is not a `class_name` and cannot be reached from
## here — but not an unchecked one: `physics_module.gd` refuses to boot unless the project's
## `physics/3d/default_gravity` is this number, and `case_fire.gd` asserts this constant against that
## same setting. So the two cannot drift apart without something going red, which is the property
## that mattered rather than where the number is written.
const GRAVITY := 20.0

## How many seconds a shot may be traced for before it is somebody else's problem. At a rifle's
## 150 m/s that is 900 m, which is past any playable area the spec contemplates.
const MAX_FLIGHT := 6.0


## Where a projectile is `t` seconds after launch. The whole of the model, and deliberately so:
## no drag term until something asks for one, because a drag coefficient nobody can feel is a
## number every pack author has to fill in and none of them can tune.
static func position_at(origin: Vector3, velocity: Vector3, t: float,
		gravity := GRAVITY) -> Vector3:
	return origin + velocity * t - Vector3.UP * (0.5 * gravity * t * t)


## How far a shot has fallen by the time it has gone `distance` metres, fired flat. The number that
## makes the difference between a rifle and a bow legible: same call, same gravity, and the answer
## comes out of the speed alone.
static func drop_at(speed: float, distance: float, gravity := GRAVITY) -> float:
	if speed <= 0.0 or distance <= 0.0:
		return 0.0
	var t := distance / speed
	return 0.5 * gravity * t * t


## The arc, sampled. For drawing a tracer, for a test to walk, and later for the sweep C5 will want
## when a projectile has to hit something between two frames rather than only at them.
static func arc(origin: Vector3, velocity: Vector3, seconds: float, steps: int,
		gravity := GRAVITY) -> PackedVector3Array:
	var out := PackedVector3Array()
	if steps <= 0:
		return out
	var span := minf(seconds, MAX_FLIGHT)
	for i in range(steps + 1):
		out.append(position_at(origin, velocity, span * float(i) / float(steps), gravity))
	return out


## Push an aim off true by up to `spread`, in radians, with a seeded generator.
##
## Round rather than square: rolling an independent yaw and pitch would put four times as much of
## the distribution in the corners as on the axes, so a weapon with 0.16 spread would miss further
## diagonally than horizontally for no reason anybody chose. The angle is picked, then the
## direction around the cone, which gives a disc.
static func scatter(aim: Vector3, spread: float, rng: RandomNumberGenerator) -> Vector3:
	var forward := aim.normalized()
	if spread <= 0.0 or forward.is_zero_approx():
		return forward

	# `sqrt` of a uniform roll, so shots land evenly across the disc rather than bunching at the
	# centre — the same correction as sampling a circle by area instead of by radius.
	var angle := spread * sqrt(rng.randf())
	var around := rng.randf() * TAU

	# Any axis not parallel to the aim will do; UP unless the shot is straight up or down, in which
	# case it is not and the fallback is.
	var side := Vector3.UP.cross(forward)
	if side.is_zero_approx():
		side = Vector3.RIGHT.cross(forward)
	side = side.normalized()

	var tilted := forward.rotated(side, angle)
	return tilted.rotated(forward, around).normalized()


## A launch velocity: a direction scattered by the weapon's spread, at the weapon's speed. The one
## place spread and muzzle velocity meet, so neither is applied twice.
static func launch(aim: Vector3, speed: float, spread: float,
		rng: RandomNumberGenerator) -> Vector3:
	return scatter(aim, spread, rng) * speed
