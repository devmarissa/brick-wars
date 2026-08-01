class_name VerbMelee
extends RefCounted
## `melee` — strike at reach, resolved without a projectile. CORE-SPEC §2, FORMAT-SPEC §7.
##
## The cheapest proof that damage is not a property of projectiles. Everything `fire` learned about
## reading a weapon out of its stat block applies unchanged, and the only real difference is that
## the shot has no flight: a strike is a sweep of `reach` metres that happens now.
##
## It uses the *same* sweep a bullet does, which is worth being deliberate about rather than
## incidental. A melee system with its own hit detection is a melee system that disagrees with the
## gun about what counts as cover, and the disagreement surfaces as "I hit him through the sandbags
## with a shovel but not with a rifle". One sweep, two ranges.
##
## ### Why the shovel is the test weapon
##
## `melee_light`'s own note has read *"knife, shortsword, entrenching tool"* since C1, and
## `verbs.json` puts that slot under **both** `melee` and `dig`. `core:shovel` is the asset that
## makes the two-verbs-on-one-slot claim real rather than theoretical: the same object in the same
## slot digs a hole and hits people, which is why armies issued it.

## What `melee_light` and `melee_heavy` both require. Read off the slot rather than assumed, and
## checked here for the same reason `fire` checks its own: the validator should have refused a
## weapon missing one of these long before it reached a verb, and if it did not, this says so
## instead of reading a zero.
const REQUIRED_STATS := ["damage", "cycle", "reach"]


## Swing. `request` wants:
##
## - `stats` — the asset's stat block
## - `state` — `{ ready_at }`, the caller's to keep
## - `origin` / `aim` — where the swing starts and which way it goes
## - `now` — seconds on the caller's clock
## - `space` — the physics space to sweep, and `ignore` for the arm holding the tool
static func perform(request: Dictionary) -> Dictionary:
	var stats: Dictionary = request.get("stats", {})
	for stat in REQUIRED_STATS:
		if not stats.has(stat):
			return _no("this weapon has no `%s`, and its slot requires it. %s" % [
				stat, "The validator should have refused the asset before it got here."])

	var state: Dictionary = request.get("state", {})
	var now := float(request.get("now", 0.0))
	var ready_at := float(state.get("ready_at", 0.0))
	if now < ready_at:
		return _no("still recovering: %.2fs to go of %ss" % [ready_at - now, stats["cycle"]])

	var aim: Vector3 = request.get("aim", Vector3.FORWARD)
	if aim.is_zero_approx():
		return _no("a swing needs somewhere to go")

	# No ammunition and no seeded generator, which is the whole of what makes this cheaper than
	# firing: a swing has nothing to run out of and nothing to roll. Spread on a melee weapon would
	# be a miss the player did not cause, and the slots deliberately do not carry one.
	var origin: Vector3 = request.get("origin", Vector3.ZERO)
	var reach := float(stats["reach"])
	var to := origin + aim.normalized() * reach

	# Rebuilt rather than assigned. A `Dictionary` hands its values back untyped, and assigning a
	# plain `Array` to an `Array[RID]` is a *runtime* abort in GDScript rather than a parse error —
	# so this compiled, passed the suite (no test passed `ignore`), and died the first time Marissa
	# pressed V. The type annotation was the bug, not the caller.
	var ignore: Array[RID] = []
	for rid in request.get("ignore", []):
		ignore.append(rid)
	var found := Projectile.sweep(request.get("space"), origin, to, ignore)

	# A swing that connects with nothing still costs the time. Missing has to be punished or there
	# is no reason to ever stop swinging, and "the cycle only starts on a hit" is the rule that
	# turns melee into a button nobody lets go of.
	var after := { "ready_at": now + float(stats["cycle"]) }
	if not found["hit"]:
		return { "ok": true, "why": "", "moved_cm": 0, "state": after,
			"strike": { "hit": false, "reach": reach, "damage": 0.0,
				"position": to, "normal": Vector3.ZERO, "collider": null } }

	return {
		"ok": true, "why": "", "moved_cm": 0, "state": after,
		"strike": {
			"hit": true,
			"reach": reach,
			"damage": float(stats["damage"]),
			"position": found["position"],
			"normal": found["normal"],
			"collider": found["collider"],
		},
	}


static func _no(why: String) -> Dictionary:
	var out := Verbs.REFUSED.duplicate()
	out["why"] = why
	return out
