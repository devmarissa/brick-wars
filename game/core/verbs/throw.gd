class_name VerbThrow
extends RefCounted
## `throw` — send an object on a ballistic arc from the hand rather than from a barrel.
## CORE-SPEC §2, FORMAT-SPEC §7.
##
## **This verb is `partial`, and that status is not a hedge.** The flight is C4's and the detonation
## is C5's, so a grenade here leaves the hand, arcs, bounces off what it meets, runs its fuse down
## and then goes quiet. Nothing explodes. Calling that "live" would claim a blast that does not
## exist; calling it "reserved" would claim nothing works, when most of it does.
##
## It is the same split drawn twice already — `EarthCrater` is the earth's half of an explosion and
## not the explosion, and `fire` produces a shot and does not resolve what it runs into. Each time
## the line is in the same place: C4 gets the thing travelling, C5 gets what happens when it stops.
##
## ### The flight is the same maths as a bullet
##
## `Ballistics` does not know a grenade from a rifle round. What makes a thrown object feel thrown
## is `throw_velocity` — around 18 m/s against a rifle's 150 — and at that speed gravity dominates
## within a few metres, which is the whole arc. No separate lob code, no thrown-object trajectory
## mode. If a grenade ever needs one, the era boundary has a leak in it.

## What `explosive_thrown` requires, per the slot registry. `damage` and `radius` are carried by the
## thrown object and handed on untouched: C4 has no use for either, and C5 will.
const REQUIRED_STATS := ["damage", "radius", "fuse", "capacity"]

## How fast a thing leaves the hand when the asset does not say. `throw_velocity` is optional on the
## slot, so a pack may leave it out, and an arc has to come from somewhere.
const DEFAULT_THROW_VELOCITY := 18.0

## How much speed survives a bounce. The object's for now rather than the surface's — a grenade
## should ring off concrete and die in mud, and that is a material property, which is C5's.
const RESTITUTION := 0.42


## Throw one. `request` wants `stats`, `state` (`{ held, ready_at }`), `origin`, `aim`, `now`.
static func perform(request: Dictionary) -> Dictionary:
	var stats: Dictionary = request.get("stats", {})
	for stat in REQUIRED_STATS:
		if not stats.has(stat):
			return _no("this cannot be thrown — no `%s`, which `explosive_thrown` requires. %s" % [
				stat, "The validator should have refused the asset before it got here."])

	var state: Dictionary = request.get("state", {})
	var carried := int(stats["capacity"])
	var held := int(state.get("held", carried))
	var now := float(request.get("now", 0.0))
	var ready_at := float(state.get("ready_at", 0.0))

	if held <= 0:
		return _no("none left — you carried %d and have thrown them all" % carried)
	if now < ready_at:
		return _no("still recovering from the last one: %.2fs to go" % [ready_at - now])

	var aim: Vector3 = request.get("aim", Vector3.FORWARD)
	if aim.is_zero_approx():
		return _no("a throw needs somewhere to go")

	var speed := float(stats.get("throw_velocity", DEFAULT_THROW_VELOCITY))
	var fuse := float(stats["fuse"])

	return {
		"ok": true, "why": "", "moved_cm": 0,
		"thrown": {
			"origin": request.get("origin", Vector3.ZERO),
			"velocity": aim.normalized() * speed,
			"speed": speed,
			# Carried, not used. C5 reads both; C4 has no opinion about either, and dropping them
			# here would mean the blast had to go back to the asset for numbers the throw already had.
			"damage": float(stats["damage"]),
			"radius": float(stats["radius"]),
			"fuse": fuse,
			"restitution": RESTITUTION,
		},
		"state": { "held": held - 1, "ready_at": now + float(stats.get("cycle", 0.0)) },
	}


## Run the fuse down, one step at a time, bouncing off whatever it meets. Returns where the object
## is, how fast, and how much fuse is left.
##
## What it deliberately does not do is decide what happens at zero. A fuse that reaches the end here
## simply stops being counted, and `spent` says so — C5 is what turns that into a blast, and this
## returning `spent` rather than calling something is what keeps the two milestones apart.
static func fly(space: PhysicsDirectSpaceState3D, thrown: Dictionary, delta: float,
		ignore: Array[RID] = []) -> Dictionary:
	var at: Vector3 = thrown.get("origin", Vector3.ZERO)
	var moving: Vector3 = thrown.get("velocity", Vector3.ZERO)
	var fuse := float(thrown.get("fuse", 0.0)) - delta
	var bounced := int(thrown.get("bounces", 0))

	var step := Projectile.fly(space, at, moving, delta, ignore)
	if step["hit"]:
		# Resume off the surface rather than on it. A contact point is *on* the thing that was hit,
		# and a ray starting there begins inside it and finds nothing — so the grenade bounces once,
		# convincingly, and then falls through the floor. `Projectile.SKIN` is what stops that.
		at = Vector3(step["position"]) + Vector3(step["normal"]) * Projectile.SKIN
		moving = Projectile.bounce(step["velocity"], step["normal"],
			float(thrown.get("restitution", RESTITUTION)))
		bounced += 1
	else:
		at = step["position"]
		moving = step["velocity"]

	var out := thrown.duplicate()
	out["origin"] = at
	out["velocity"] = moving
	out["fuse"] = maxf(fuse, 0.0)
	out["bounces"] = bounced
	out["spent"] = fuse <= 0.0
	return out


static func _no(why: String) -> Dictionary:
	var out := Verbs.REFUSED.duplicate()
	out["why"] = why
	return out
