class_name Integrity
extends RefCounted
## Whether a thing is still standing on something. CORE-SPEC §2, MATERIAL-SPEC, C5.
##
## C5's done-condition: *"a wall collapses correctly when you take its base out."* That sounds like
## it should already work — the bricks are rigid bodies and gravity is a solved problem — and it does
## not, for a reason that is easy to miss and impossible to un-see afterwards.
##
## **A sleeping body does not fall.** C0's sleep discipline is what makes thousands of bricks
## affordable: a settled wall goes to sleep and stops costing anything. Take a brick out of the
## bottom course and the courses above it are still asleep, and the physics engine has no reason to
## reconsider them, so they hang in the air over the hole. The wall does not collapse. It waits.
##
## The blast already solved its half of this with `Blast.SECONDARY_WAKE`, which wakes bricks above a
## detonation without pushing them. This is the general case: *anything* that removes support has to
## tell what was resting on it. Digging the ground out from under a wall, shooting a prop away,
## burning a pit prop in a tunnel — the trigger differs and the consequence is identical.
##
## ### Why cohesion decides how far it spreads
##
## Waking the brick directly above is not enough. A wall is a load path, and pulling one brick out
## of the bottom of a stone arch does nothing at all while pulling one out of a sandbag stack brings
## down everything over it. That difference is `cohesion` in the material file: masonry at 65 and
## stone at 80 redistribute load around a gap, sandbags at 5 do not.
##
## So the reach scales *inversely* with cohesion — a low-cohesion stack has to be told about a much
## wider neighbourhood, because it has no way to carry the load around the hole itself. That reads
## backwards until you say it out loud: **the weaker the material, the further the news travels.**
##
## ### What this deliberately is not
##
## Not a truss solver. MATERIAL-SPEC gives `support_vertical` and `support_lateral` as numbers and
## C5's done-condition asks for a wall that comes down when its base goes, not for a structure that
## can be proven safe. What is here is the load *question* — is anything still under me — asked of
## the bodies that already exist, and answered by letting gravity have its way.

## How far above a removal to look for things that were resting on it, in metres, before cohesion
## scales it. A little over one brick course, so the immediate neighbours always hear about it.
const BASE_REACH := 0.8

## The widest and narrowest that reach may become. A perfectly cohesive material still has to tell
## the brick directly on top of it; a perfectly incohesive one still must not wake the whole map.
const MIN_REACH := 0.6
const MAX_REACH := 6.0

## Cohesion at or above this carries its own load around a gap, so the news barely spreads.
## Masonry is 65 and hard stone is 80; sandbag is 5 and loose earth lower still.
const COHESIVE := 70.0

## How wide a column to consider, as a fraction of the reach. Load travels down, so what a removal
## affects is mostly directly above it rather than beside it.
const COLUMN_FRACTION := 0.75


## Tell whatever was standing on this spot that it no longer is.
##
## Returns how many bodies were woken, which is worth having: a removal that wakes nothing either
## happened in mid-air or found a structure that was already awake, and both are things a caller
## occasionally wants to know.
static func support_removed(tree: SceneTree, at: Vector3, material: StringName,
		materials: MaterialSet) -> int:
	if tree == null:
		return 0
	var reach := reach_for(material, materials)
	var woken := 0
	for node in Brick.all(tree):
		var brick := node as RigidBody3D
		if brick == null or not brick.sleeping:
			continue
		var away: Vector3 = brick.global_position - at
		# Above, and roughly over the hole. Something *beside* the gap was never being held up by
		# what was in it.
		if away.y <= 0.0 or away.y > reach:
			continue
		if Vector2(away.x, away.z).length() > reach * COLUMN_FRACTION:
			continue
		brick.sleeping = false
		woken += 1
	return woken


## How far the news of a removal travels through this material, in metres.
##
## Inversely with cohesion, which is the counter-intuitive part and the correct one: a cohesive
## material carries load around a gap and barely notices, an incohesive one has nothing holding it
## together and everything above the hole is immediately unsupported.
static func reach_for(material: StringName, materials: MaterialSet) -> float:
	var cohesion := cohesion_of(material, materials)
	var looseness := clampf(1.0 - cohesion / COHESIVE, 0.0, 1.0)
	return clampf(BASE_REACH + looseness * MAX_REACH, MIN_REACH, MAX_REACH)


static func cohesion_of(material: StringName, materials: MaterialSet) -> float:
	if materials == null or not materials.has(material):
		return 0.0
	return float(materials.get_def(material).get("cohesion", 0.0))


## Whether a stack of this material comes apart into pieces or moves as a mass.
##
## `support_lateral` is the number: sandbag is 8, clay is 35, masonry 45, steel 85. A material that
## cannot hold sideways has nothing keeping its units together once the ground under them moves, so
## the stack topples — which is what a sandbag parapet does. One that can holds together and the
## whole face slumps instead, which is what a clay bank does.
##
## MATERIAL-SPEC's own distinction, and C5's done-condition names exactly this pair.
static func topples(material: StringName, materials: MaterialSet) -> bool:
	return lateral_of(material, materials) < LOOSE_LATERAL


## Below this a material has no meaningful sideways strength. Between sandbag's 8 and clay's 35,
## because those two are the pair the done-condition is written about.
const LOOSE_LATERAL := 20.0


static func lateral_of(material: StringName, materials: MaterialSet) -> float:
	if materials == null or not materials.has(material):
		return 0.0
	return float(materials.get_def(material).get("support_lateral", 0.0))
