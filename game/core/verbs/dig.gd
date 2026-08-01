class_name VerbDig
extends RefCounted
## `dig` — cut earth out of the ground and pile it where it can be stood behind.
## CORE-SPEC §2, EARTH-SPEC §4.
##
## The first live verb, and deliberately not a weapon. A vocabulary whose only working members shot
## things would never have been tested for the thing it is actually for: VISION's era table puts
## **DIG** in the first column of every era from the siege ramp to the IED hole, and the whole
## architectural bet is that those are one verb with different kit.
##
## It is also nearly free, because C3 already did the work. Cutting is `EarthField.carve`, the spoil
## is `deposit`, the collapse is the settle queue, and the replay is the event log. What this file
## adds is the *rule* about where the spoil goes, which is the part that was implicit in C3's demo
## and had to become explicit the moment something other than a scripted trench did the digging.
##
## ### Spoil goes somewhere, and the caller says where
##
## §4: *"material removed has to go somewhere. Digging is not deletion."* A dig that dropped its
## spoil on the floor of its own hole would conserve volume and dig nothing. So the request names a
## `spoil` cell, and the refusals below are about that cell being a place the earth could plausibly
## have been thrown — adjacent, and not the hole itself.
##
## Throwing spoil is a real constraint and not bookkeeping: it is why a trench comes with a parapet
## on the side you dug from, why that parapet is disturbed ground that stands at a shallower angle
## than what it was cut out of, and why digging in makes cover as a side effect of making a hole.

## The most any tool may take in one bite, in centimetres. A **ceiling**, not the bite itself: the
## bite is `dig_cm` off the tool's own stat block, added to `melee_light` and `melee_heavy` by C4's
## registry review, and this is the number a pack may not exceed however keen its shovel is.
##
## The cap is not arbitrary tidiness. A spade-full rather than a mining operation is what puts
## digging on a clock — a caller wanting a metre asks four times — and it is what lets the settle
## queue slump *between* bites instead of all at once after them, which is the difference between
## earth moving and earth teleporting.
const MAX_BITE_CM := 25

## How far the spoil may be thrown, in cells. One, because a soldier with a shovel throws earth to
## the side of the hole and not across the road.
const MAX_THROW_CELLS := 1


## Cut, and pile what came out. Returns the standard dispatch shape; `moved_cm` is the volume
## actually shifted, which is less than asked for when the cut reaches bedrock.
##
## `request` wants: `field` (EarthField), `cell` (Vector2i), `spoil` (Vector2i), `depth_cm` (int),
## and optionally `terrain` (EarthTerrain) to wake the settle queue and remesh. Without `terrain`
## the ground still changes and simply does not slump yet, which is the right behaviour for a
## headless caller and is how the tests use it.
static func perform(request: Dictionary) -> Dictionary:
	var field: EarthField = request.get("field")
	if field == null:
		return _no("dig needs a field to dig in")

	var cell: Vector2i = request.get("cell", Vector2i.ZERO)
	var spoil: Vector2i = request.get("spoil", Vector2i.ZERO)

	# The tool decides how much comes out, when there is one. `dig_cm` is what makes an entrenching
	# tool a tool as well as a weapon, and it is why `dig` did not need a slot of its own — see
	# `DEVIATIONS-C4.md` B6. A caller with no tool names the depth itself, which is how the demo
	# ground and the tests dig with nobody holding anything.
	var stats: Dictionary = request.get("stats", {})
	var depth_cm := int(stats["dig_cm"]) if stats.has("dig_cm") \
		else int(request.get("depth_cm", 0))

	if depth_cm <= 0:
		return _no("dig asked for %d cm — a dig that removes nothing is a deposit %s" % [
			depth_cm, "wearing the wrong name, and `build` is the verb for that"])
	if depth_cm > MAX_BITE_CM:
		return _no("dig asked for %d cm in one bite and the most any tool may take is %d. %s" % [
			depth_cm, MAX_BITE_CM,
			"Ask repeatedly — that is what puts digging on a clock and lets the ground slump between bites."])
	if spoil == cell:
		return _no("dig would throw its spoil into the hole it just cut, which digs nothing")

	var away := spoil - cell
	if absi(away.x) > MAX_THROW_CELLS or absi(away.y) > MAX_THROW_CELLS:
		return _no("dig would throw spoil %d cell(s) away and a shovel reaches %d" % [
			maxi(absi(away.x), absi(away.y)), MAX_THROW_CELLS])

	# Carve first and deposit exactly what came out, rather than what was asked for. A cut that
	# reaches bedrock moves less than requested, and depositing the request instead of the result
	# would create earth out of nothing — the same conservation bug C3 tested for, arriving through
	# a different door.
	var moved := field.carve(cell, depth_cm)
	if moved <= 0:
		return _no("there is nothing left to dig at (%d, %d) — that is bedrock" % [cell.x, cell.y])
	field.deposit(spoil, moved)

	var terrain: EarthTerrain = request.get("terrain")
	if terrain != null:
		terrain.touch(cell)
		terrain.touch(spoil)

	return { "ok": true, "why": "", "moved_cm": moved }


static func _no(why: String) -> Dictionary:
	var out := Verbs.REFUSED.duplicate()
	out["why"] = why
	return out
