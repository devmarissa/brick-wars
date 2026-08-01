class_name Blast
extends RefCounted
## What an explosion does to everything near it. CORE-SPEC §2, `BUILD-ORDER` §1a and §1e,
## MATERIAL-SPEC §7.
##
## **Ported verbatim, constants included.** `BUILD-ORDER` §1a lists the blast under *KEEP — proven,
## port verbatim*, and §1e explains why in a sentence worth repeating: the risk in a rebuild is not
## losing code, it is losing feel you cannot describe. The old build's numbers were arrived at by
## somebody playing it until it felt right, and there is no derivation to re-derive. So the numbers
## below are copied from `archive/great_war_prototype/main.gd` and are not to be tidied.
##
## Several of them look arbitrary or wrong. Each has its reason written next to it, because the
## alternative is that the next person reads `0.55` as a magic number, "simplifies" it, and quietly
## deletes the thing eight scenarios in `blast-fixture/` exist to protect.
##
## ### What materials may and may not change
##
## MATERIAL-SPEC §7 draws the line and it is the line that keeps this file honest: materials change
## *what a blast does to each thing it touches* — scattering sandbags, punching brick, denting
## armour — but they **do not touch the impulse curve, the falloff, the shake or the timing**. So if
## reproducing the fixture ever requires reaching into one of those four, the material work has
## leaked in here and that is the error rather than the fixture being wrong.
##
## ### It reports rather than acts on everything
##
## `detonate` pushes bricks and returns a description of what it did. It does not shake the camera,
## knock the player about, or spawn VFX — it says how hard each of those should be, and the caller
## does them. That is what lets the fixture measure a blast with no camera and no player in the
## scene, and it is the same shape as `fire` producing a shot rather than resolving it.

## Above this, a blast shatters rather than shoves. The single most load-bearing number here: the
## fixture's `wall_light_charge` scenario runs at 18 power specifically to sit *below* it, and the
## difference between that scenario and `wall_standard_shell` at 42 **is** the feel being protected.
const SHATTER_POWER := 25.0

## How much of the computed force actually becomes brick velocity. Tuned by hand in the old build
## until a shell threw a sandbag wall the distance it should. There is no derivation.
const BRICK_IMPULSE := 0.55

## The closest a brick may be treated as being, in metres. Not a rounding — the force divides by
## distance, so without a floor a brick at the exact centre of a blast is launched at infinity. 0.7
## is roughly a brick's own width, which is as close as a brick's centre can honestly get.
const MIN_DISTANCE := 0.7

## How much of a brick's *vertical* offset becomes lift, and how much lift everything gets anyway.
## The `+ 0.5` is why a blast under a wall throws it up rather than only outward, and `absf` on the
## height difference is why something *below* the blast is also thrown up rather than driven down.
const VERTICAL_BIAS := 0.6
const VERTICAL_LIFT := 0.5

## Bricks outside the radius but within this fraction of it horizontally, and *above* the blast, are
## woken without being pushed.
##
## This looks like a bug and is the opposite of one. It is what makes a wall standing over a blast
## come down: the courses inside the radius are thrown out, and the courses above them — which the
## blast never touched — are asleep, and a sleeping body does not fall. Waking them lets gravity
## finish the job the explosion started, which is most of what "the wall collapsed" looks like.
const SECONDARY_WAKE := 0.75

## How far past the blast radius a person still feels it, in metres, and how the knock splits
## between outward and upward.
const KNOCK_REACH := 3.0
const KNOCK_OUT := 0.7
const KNOCK_UP := 0.5

## Camera shake: a standard shell is 42 power and shakes by 1, clamped so that nothing is
## imperceptible and nothing is unplayable, falling off to nothing at 45 m.
const SHAKE_REFERENCE := 42.0
const SHAKE_MIN := 0.2
const SHAKE_MAX := 1.4
const SHAKE_RANGE := 45.0

## How far out a crater actually cuts, as a fraction of the blast radius. The old carve loop skipped
## anything past this, and a crater exactly as wide as the blast reads as too big anyway — the
## blast's own edge barely moves a brick, so it should barely move earth.
const CRATER_FRACTION := 0.85

## One scoop of the old build's earth grid, in centimetres. Its field was stepped: 2.5 m cells, 0.8 m
## per scoop, integer heights. Ours is continuous centimetres on 0.5 m cells, so the *profile* is
## ported and the *quantum* comes with it — a crater made of 80 cm steps is what the reference
## numbers describe.
const SCOOP_CM := 80

## How the old profile turned power into scoops: `clampf(power / 22.0, 1.0, 3.0)`, tapering to the
## edge, with `+ 0.3` before rounding so the rim gets one scoop rather than none.
const SCOOP_POWER_DIVISOR := 22.0
const SCOOP_MIN := 1.0
const SCOOP_MAX := 3.0
const SCOOP_BIAS := 0.3

## Debris thrown up out of a crater: one brick per three old-grid cells of earth moved, capped at
## eight. Both numbers are the old build's.
const DEBRIS_PER_CELL := 3
const DEBRIS_CAP := 8

## One cell of the old build's earth grid, in cubic metres — 2.5 x 2.5 x 0.8. Only used to express
## a volume in the units the reference recorded, and it is the *only* reason this number is here.
const OLD_CELL_VOLUME := 5.0


## Set something off. Returns what happened, for the caller to act on and the fixture to measure.
##
## `at` is the centre, `radius` the reach in metres, `power` the strength on the same scale the old
## build used — 42 is a standard shell, 18 a light charge, 80 a heavy one point blank.
static func detonate(tree: SceneTree, at: Vector3, radius: float, power: float,
		observer := Vector3.INF) -> Dictionary:
	var pushed := 0
	var woken := 0
	var fastest := 0.0

	for node in Brick.all(tree):
		var brick := node as RigidBody3D
		if brick == null:
			continue
		var away: Vector3 = brick.global_position - at
		var distance := away.length()

		if distance <= radius:
			brick.sleeping = false
			var force := power * (1.0 - distance / radius)
			var inverse := 1.0 / maxf(distance, MIN_DISTANCE)
			# Copied exactly. The horizontal terms scale with the offset and the vertical one uses
			# the *absolute* height difference plus a constant, which is what makes a charge under a
			# wall lift it rather than press it down.
			var kick := Vector3(
				away.x * inverse * force,
				(absf(away.y) * inverse * VERTICAL_BIAS + VERTICAL_LIFT) * force,
				away.z * inverse * force) * BRICK_IMPULSE
			brick.linear_velocity += kick
			fastest = maxf(fastest, brick.linear_velocity.length())
			pushed += 1
		elif Vector2(away.x, away.z).length() < radius * SECONDARY_WAKE and away.y > 0.0:
			# Woken, not pushed — see `SECONDARY_WAKE`. This is the line that makes a wall come down
			# instead of hanging in the air with its bottom courses gone.
			brick.sleeping = false
			woken += 1

	return {
		"point": at, "radius": radius, "power": power,
		"shatters": power >= SHATTER_POWER,
		"bricks_pushed": pushed,
		"bricks_woken": woken,
		"peak_speed": fastest,
		"shake": shake_at(power, at, observer),
		"knock": knock_at(power, radius, at, observer),
	}


## How hard the camera should shake for somebody standing at `observer`. Returns 0 when nobody is.
static func shake_at(power: float, at: Vector3, observer: Vector3) -> float:
	if observer == Vector3.INF:
		return 0.0
	var away := observer.distance_to(at)
	return clampf(power / SHAKE_REFERENCE, SHAKE_MIN, SHAKE_MAX) \
		* clampf(1.0 - away / SHAKE_RANGE, 0.0, 1.0)


## How hard somebody at `observer` is thrown, as a velocity to add. Outward and up, and nothing at
## all past the blast's reach plus `KNOCK_REACH`.
static func knock_at(power: float, radius: float, at: Vector3, observer: Vector3) -> Vector3:
	if observer == Vector3.INF:
		return Vector3.ZERO
	var away: Vector3 = observer - at
	var distance := away.length()
	var reach := radius + KNOCK_REACH
	if distance >= reach:
		return Vector3.ZERO
	var force := power * (1.0 - distance / reach)
	return away.normalized() * force * KNOCK_OUT + Vector3.UP * force * KNOCK_UP


## The earth's half, and only above the shatter threshold — a charge that merely shoves does not dig.
## Returns the volume moved in column-centimetres and the debris that came out of it.
##
## `EarthCrater` already does the digging; what this adds is the old build's rule about *when* a
## blast is heavy enough to dig at all, and how much of what comes out is thrown into the air as
## loose bricks rather than heaped on the rim.
static func crater(field: EarthField, settle: EarthSettle, at: Vector3, radius: float,
		power: float) -> Dictionary:
	if field == null or power < SHATTER_POWER:
		return { "moved_cm": 0, "debris": 0, "old_cells": 0 }

	# The old profile, cell for cell, on the new grid. Not `EarthCrater.form`: that shapes a smooth
	# cone from EARTH-SPEC §4's prose, and this is the shape the *fixture* recorded. Where the two
	# disagree the fixture wins, because it is the thing being reproduced. `DEVIATIONS-C5.md` A1.
	var centre := EarthGrid.cell_at(at.x, at.z)
	var reach := int(ceil(radius / EarthGrid.CELL_M)) + 1
	var scale := clampf(power / SCOOP_POWER_DIVISOR, SCOOP_MIN, SCOOP_MAX)
	var moved := 0
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var away := sqrt(float(dx * dx + dz * dz)) * EarthGrid.CELL_M
			if away > radius * CRATER_FRACTION:
				continue
			var scoops := int(round((1.0 - away / radius) * scale + SCOOP_BIAS))
			if scoops <= 0:
				continue
			var cell := centre + Vector2i(dx, dz)
			moved += field.carve(cell, scoops * SCOOP_CM)
			if settle != null:
				settle.disturb(cell)

	var as_old_cells := int(round(
		moved * EarthGrid.CELL_M * EarthGrid.CELL_M * 0.01 / OLD_CELL_VOLUME))
	return {
		"moved_cm": moved,
		"old_cells": as_old_cells,
		"debris": mini(DEBRIS_CAP, as_old_cells / DEBRIS_PER_CELL + 1) if moved > 0 else 0,
	}
