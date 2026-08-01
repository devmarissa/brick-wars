class_name Damage
extends RefCounted
## How much of a hit lands. CORE-SPEC §2 (combat maths), MATERIAL-SPEC.
##
## The line between this and C5 is worth stating before the first function, because it is the kind
## that blurs by accident: **C4 works out how much damage arrives; C5 decides what the thing on the
## receiving end does about it.** A rifle round carrying 95 kinetic against a plank is arithmetic
## and lives here. That plank then splintering, spalling, catching fire, dropping the wall above it
## or refusing a shovel is *material behaviour*, and `BUILD-ORDER` gives C5 that by name.
##
## Which is why nothing here reads `failure`, `fire`, `support_vertical` or `cohesion`, even though
## the material file has carried all four since C1 and it would be easy.
##
## ### Resistance already existed
##
## `MaterialSet.resist()` went in with the content pipeline, so damage types are not new work — they
## are a C1 promise nothing had called yet. A shot carries a type, the material resists it by a
## factor, and the six types come from `materials.json` rather than from a list in code, because a
## seventh damage type is a data change and an `enum` here would make it a code change.
##
## ### A soldier's health is the core's, and a vehicle's is the pack's
##
## `slots.json` says it plainly in `infantry`'s own note: *"core owns a soldier's movement and
## health, so a class asset is a loadout and a silhouette rather than a stat block."* So the number
## below is a constant and no pack can raise it — a mod that made its own soldiers tougher would be
## the end of the era system being fair. Vehicles are the other way: `health` is in their stat
## block, because a cart and a tank are supposed to differ and both are pack content.

## What a soldier has. One rifle round is 95 of it, which is the whole design: an unarmoured man is
## one hit from being out of the fight, and cover is the answer rather than a health pool.
const SOLDIER_HEALTH := 100.0

## What a hit that lands on nothing in particular is resisted by. 1.0 — full damage — so a missing
## material is loud in the numbers rather than silently halving everything.
const NO_RESISTANCE := 1.0


## Apply damage to something with health. Returns the new state rather than mutating, for the same
## reason `VerbFire` hands its weapon state back: C8 replays other people's shots and needs to
## decide whether to keep the result.
static func to_body(health: float, amount: float) -> Dictionary:
	var dealt := clampf(amount, 0.0, maxf(health, 0.0))
	var left := health - dealt
	return {
		"health": left,
		"dealt": dealt,
		# Overkill is kept rather than thrown away because C5 wants it: how hard a body was hit past
		# death is what decides whether it falls over or comes apart.
		"overkill": maxf(amount - dealt, 0.0),
		"killed": left <= 0.0 and health > 0.0,
	}


## What actually arrives at a material, after it resists. The type comes off the shot and the factor
## off the material file, and neither is known here.
static func to_material(materials: MaterialSet, material: StringName, amount: float,
		type: String) -> float:
	if materials == null or not materials.has(material):
		return amount * NO_RESISTANCE
	return amount * materials.resist(material, type)


## Area-effect falloff: what fraction of full damage lands `distance` from the centre of something
## with a `radius`. CORE-SPEC lists this under combat maths, so the *curve* is C4's even though the
## blast that will call it is C5's — the same split already drawn twice, at `EarthCrater` and at
## `fire`.
##
## Linear rather than inverse-square. Inverse-square is what physics does and it is the wrong shape
## for a game: it makes the middle metre lethal and everything past three metres irrelevant, so a
## grenade becomes a coin flip about exactly where it stopped rolling. Linear gives a falloff a
## player can learn and take cover from, which is what a blast radius is for.
static func falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	if distance <= 0.0:
		return 1.0
	return clampf(1.0 - distance / radius, 0.0, 1.0)


## Whether a damage type is one the game has. Checked against the material file rather than an
## `enum`, so adding a seventh is a data change — which is the whole point of the six being in
## `materials.json` in the first place.
static func is_a_type(materials: MaterialSet, type: String) -> bool:
	return materials != null and materials.damage_types.has(type)
