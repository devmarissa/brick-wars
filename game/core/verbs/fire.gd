class_name VerbFire
extends RefCounted
## `fire` — loose a projectile from a readied weapon, at a cost in ammunition and time.
## CORE-SPEC §2, FORMAT-SPEC §7.
##
## C4's done-condition in one file: *a weapon defined in data fires, and a bow and a rifle are the
## same code path.* Nothing here is allowed to know which it is holding. Everything that makes a
## bolt rifle feel unlike a bow — how long between shots, how many rounds before reloading, how far
## off true it can go, how fast it leaves — is read out of the asset's `stats` block, and the block
## is the one `slots.json` already declared for `ranged_slow` back at C1.
##
## ### The weapon's state is the caller's, not ours
##
## Rounds remaining and the cycle clock live in a `state` dictionary the caller keeps and passes
## back in. That is not laziness about where state belongs — it is what makes this callable from a
## test, from a bot, and from C8's replay of somebody else's shot without any of them having to
## own a weapon object. The loadout system decides where the dictionary lives; this decides what
## is in it.
##
## ### What it does not do
##
## Nothing is hit. `fire` produces a shot — an origin, a velocity, a damage figure — and the
## resolution of what that shot runs into is the damage model's, which is the next thing in C4.
## The split is the same one drawn at C3 between `EarthCrater` and the blast, and it is drawn here
## for the same reason: a verb that also resolved its own consequences would be the file every
## future weapon has to be threaded through.

## What a weapon's clock is measured against. Seconds, and supplied by the caller, because the two
## callers that matter disagree about what time it is: a live game uses the frame clock and C8's
## replay uses the tick the shot was recorded at.
const REQUIRED_STATS := ["damage", "velocity", "cycle", "capacity", "reload", "spread"]


## Take the shot. `request` wants:
##
## - `stats` — the asset's stat block, straight out of the pack file
## - `state` — `{ rounds, ready_at }`, the caller's to keep; absent means a full, ready weapon
## - `origin` / `aim` — where it leaves from and where it is pointed
## - `now` — seconds on whatever clock the caller is keeping
## - `rng` — a seeded generator, so the same shot reproduces on a machine that did not roll it
static func perform(request: Dictionary) -> Dictionary:
	var stats: Dictionary = request.get("stats", {})
	for stat in REQUIRED_STATS:
		if not stats.has(stat):
			return _no("this weapon has no `%s`, and `ranged_slow` requires it. %s" % [
				stat, "The validator should have refused the asset before it got here."])

	var state: Dictionary = request.get("state", {})
	var capacity := int(stats["capacity"])
	var rounds := int(state.get("rounds", capacity))
	var now := float(request.get("now", 0.0))
	var ready_at := float(state.get("ready_at", 0.0))

	if rounds <= 0:
		return _no("empty — %d round(s) of %d left, and reloading takes %ss" % [
			rounds, capacity, stats["reload"]])
	if now < ready_at:
		return _no("still cycling: %.2fs to go of %ss" % [ready_at - now, stats["cycle"]])

	var aim: Vector3 = request.get("aim", Vector3.FORWARD)
	if aim.is_zero_approx():
		return _no("a shot needs somewhere to go")

	var rng: RandomNumberGenerator = request.get("rng")
	if rng == null:
		return _no("fire needs a seeded generator — %s" % [
			"a shot that cannot be reproduced on another machine is a desync waiting for C8"])

	var speed := float(stats["velocity"])
	var velocity := Ballistics.launch(aim, speed, float(stats["spread"]), rng)

	return {
		"ok": true, "why": "", "moved_cm": 0,
		"shot": {
			"origin": request.get("origin", Vector3.ZERO),
			"velocity": velocity,
			"speed": speed,
			"damage": float(stats["damage"]),
		},
		# Handed back rather than mutated in place, so a caller replaying a shot can decide whether
		# to keep the result. `ready_at` is the cycle, not the reload: running dry is discovered by
		# the next shot being refused, which is what a bolt-action actually feels like.
		"state": { "rounds": rounds - 1, "ready_at": now + float(stats["cycle"]) },
	}


## Put rounds back in. Separate from firing because reloading is a different length of time and a
## different animation, and because a weapon that silently refilled itself when it ran dry would
## make `capacity` a decoration.
##
## Called `refill` rather than `reload` because `reload` is already a method on `GDScript` — the
## engine's own "re-read this script from disk" — and `VerbFire.reload(...)` silently resolves to
## that instead of to this. It fails at runtime with a message about argument counts that has
## nothing to do with weapons. Found by the crash guard in `check.sh` the day it was added.
static func refill(stats: Dictionary, state: Dictionary, now: float) -> Dictionary:
	var capacity := int(stats.get("capacity", 0))
	return { "rounds": capacity, "ready_at": now + float(stats.get("reload", 0.0)) }


static func _no(why: String) -> Dictionary:
	var out := Verbs.REFUSED.duplicate()
	out["why"] = why
	return out
