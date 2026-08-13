class_name VerbBuild
extends RefCounted
## `build` — place a buildable, paying for it out of the ground you are standing on.
## CORE-SPEC §2, FORMAT-SPEC §7, EARTH-SPEC §4.
##
## Reserved to C5 at C4, on an argument worth restating because this is the commit that pays it off:
## *placing a sandbag wall is a couple of hours' work, and a sandbag wall that does not topple
## sideways where a clay one slumps is a prop with a placement cost.* C5 gave sandbag its
## `support_lateral` of 8 and clay its 35, so a parapet now comes apart into bags where a bank
## slumps as a mass — and the thing being placed is a buildable rather than scenery.
##
## ### The cost is earth, and it comes out of the ground under your feet
##
## `cost.spoil` is not an abstract resource. It is spade-bites of actual field, carved out of the
## cells around where the wall is going, which is the loop EARTH-SPEC §4 has been building toward
## since C3: *digging produces spoil, spoil is what a parapet is made of.* The hole and the wall are
## the same act seen from two sides, and they are the same act in the code too — this calls the same
## `EarthField.carve` that `dig` does.
##
## That also makes the cost self-limiting in a way no resource counter would be. Build on bedrock
## and there is nothing to fill the bags with; build on a hillside and the hole you leave is cover
## for whoever comes the other way.
##
## ### What it does not do
##
## It does not build the thing. `perform` says *yes, here, and this much earth went into it*, and
## the caller instantiates the asset — the same shape as `fire` producing a shot and `throw`
## producing a grenade. A verb that also spawned its own scenery would be the file every future
## buildable has to be threaded through.

## What `cost.spoil` is counted in: one spade-bite, the same `VerbDig.MAX_BITE_CM` a soldier moves
## in one go. So `spoil: 4` is four bites — a minute's digging, which is about what a section of
## sandbag wall costs and is the only unit that makes the two verbs comparable.
const SPOIL_UNIT_CM := VerbDig.MAX_BITE_CM

## How far out the earth may be taken from, in cells. You fill bags from around your feet, not from
## across the trench — and spreading it is what leaves a shallow scrape rather than a pit that the
## wall then falls into.
const GATHER_CELLS := 2

## The most that may be taken out of any one cell while gathering, in centimetres. Without it the
## first cell is dug to bedrock and the rest are untouched.
const PER_CELL_CM := 20


## Place one. `request` wants `stats` and `cost` off the asset, `field`, `cell`, `now`, `state`, and
## optionally `terrain` to wake the settle queue where the earth was taken from.
static func perform(request: Dictionary) -> Dictionary:
	var stats: Dictionary = request.get("stats", {})
	if not stats.has("build_time"):
		return _no("this has no `build_time`, and every buildable slot requires one. %s" % [
			"The validator should have refused the asset before it got here."])

	var field: EarthField = request.get("field")
	if field == null:
		return _no("build needs ground to stand it on and to take the earth out of")

	var state: Dictionary = request.get("state", {})
	var now := float(request.get("now", 0.0))
	var ready_at := float(state.get("ready_at", 0.0))
	if now < ready_at:
		return _no("still building: %.2fs to go of %ss" % [ready_at - now, stats["build_time"]])

	var cost: Dictionary = request.get("cost", {})
	var bites := int(cost.get("spoil", 0))
	var cell: Vector2i = request.get("cell", Vector2i.ZERO)

	# Take the earth first, and refuse if it is not there. Placing the wall and then discovering the
	# ground was bedrock would leave a wall nobody paid for.
	var wanted := bites * SPOIL_UNIT_CM
	var dug := _gather(field, cell, wanted, request.get("terrain"))
	var taken := int(dug["taken"])
	if taken < wanted:
		# Put back exactly what was taken, cell by cell. Returning the right *total* to the wrong
		# cells would conserve volume and still leave the ground a different shape than it found it,
		# which is a half-done action wearing a conservation check as a disguise.
		_return(field, dug["from"])
		return _no("not enough earth here to fill %d bag(s) — %s" % [bites,
			"found %d cm of the %d needed. Bedrock, or already dug out." % [taken, wanted]])

	return {
		"ok": true, "why": "", "moved_cm": taken,
		"placed": {
			"cell": cell,
			"at": EarthGrid.centre_of(cell),
			"height_cm": field.surface_cm(cell),
			"spoil_cm": taken,
		},
		"state": { "ready_at": now + float(stats["build_time"]) },
	}


## Take `wanted` centimetres out of the ground around `cell`, a little from each. Returns the total
## found — less than asked for over bedrock — **and a record of which cell gave what**, because a
## gather that has to be undone must be undone exactly.
##
## Spirals outward by ring so the nearest ground goes first: you fill bags from your feet outward,
## and taking evenly across a wide area would scrape a saucer instead of a scrape.
static func _gather(field: EarthField, cell: Vector2i, wanted: int, terrain) -> Dictionary:
	var taken := 0
	var from: Dictionary = {}
	for ring in range(0, GATHER_CELLS + 1):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue                      # already covered by an inner ring
				if taken >= wanted:
					return { "taken": taken, "from": from }
				var at := cell + Vector2i(dx, dz)
				var got := field.carve(at, mini(PER_CELL_CM, wanted - taken))
				if got > 0:
					taken += got
					from[at] = got
					if terrain != null:
						terrain.touch(at)
	return { "taken": taken, "from": from }


## Undo a partial gather, cell for cell, when the cost could not be met.
##
## Each cell gets back exactly what it gave. Returning the right *total* to the wrong cells would
## satisfy a conservation check and still leave the ground a different shape than it found it —
## which is a half-done action wearing a passing test as a disguise, and it is what the first
## version of this did.
static func _return(field: EarthField, from: Dictionary) -> void:
	for at in from:
		field.deposit(at, int(from[at]))


static func _no(why: String) -> Dictionary:
	var out := Verbs.REFUSED.duplicate()
	out["why"] = why
	return out
