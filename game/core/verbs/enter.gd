class_name VerbEnter
extends RefCounted
## `enter` and `man` — taking a seat, and giving it up again. CORE-SPEC §2, C6.
##
## One file for two verbs, because they are one mechanism and the difference is what they are
## *allowed to sit in*. That difference was drawn at C4 when the vocabulary was closed, and it is
## worth restating because it looks like duplication until you say it out loud:
##
## > Distinct from `enter` because a crew station is a role rather than a ride: two soldiers on one
## > gun are loader and layer, and C6's hands-on-controls IK is what makes the distinction visible.
##
## So `enter` seats you in a thing that goes somewhere — a horse, a lorry, an aeroplane — and `man`
## puts you on a crew station on something that does not. The gun slots appear under both `fire` and
## `man` deliberately: manning a gun and firing it are different verbs on the same object.
##
## Which slots each verb accepts is not written here. It is in `verbs.json`, where a slot chooses
## its verbs, and this asks `VerbSet` — so adding a new kind of ridable thing is a data change and
## this file never hears about it.

## Both verbs answer to the same code; only the vocabulary lookup differs.
const RIDE := "enter"
const CREW := "man"


## Take a seat. `request` wants `seats` (a `Seats`), `who` (whatever is doing the sitting), `verbs`
## and `slot` so the vocabulary can be asked whether this verb reaches this kind of thing, plus
## optionally `role` to ask for a particular job and `at`/`from` to check reach.
static func perform(verb: String, request: Dictionary) -> Dictionary:
	var seats: Seats = request.get("seats")
	if seats == null:
		return _no("`%s` needs something with seats in it" % verb)
	if not seats.is_valid():
		return _no("that vehicle's seat table is broken: %s" % ", ".join(seats.errors))

	var set: VerbSet = request.get("verbs")
	var slot := String(request.get("slot", ""))
	if set != null and slot != "" and not set.verbs_for(slot).has(verb):
		# The check that keeps the two verbs honest: you do not `enter` a field gun or `man` a horse,
		# and neither rule is written here — the slot's own verb list says so.
		return _no("a `%s` is not something you `%s` — %s" % [slot, verb,
			"it answers to %s" % ", ".join(set.verbs_for(slot))
				if not set.verbs_for(slot).is_empty() else "nothing at all"])

	var who: Variant = request.get("who")
	if who == null:
		return _no("`%s` needs somebody to do it" % verb)
	if seats.seat_of(who) >= 0:
		return _no("already aboard, in the %s seat" % seats.role_of(seats.seat_of(who)))

	var reach := float(request.get("reach", 0.0))
	if reach > 0.0:
		var at: Vector3 = request.get("at", Vector3.ZERO)
		var from: Vector3 = request.get("from", Vector3.ZERO)
		if from.distance_to(at) > reach:
			return _no("too far away to climb aboard: %.1f m, and the reach is %.1f" % [
				from.distance_to(at), reach])

	var role := String(request.get("role", ""))
	var index := seats.free_seat(role)
	if index < 0:
		return _no("no free %s seat — %d of %d taken" % [
			role if role != "" else "", seats.occupied(), seats.count()])

	seats.take(index, who)
	return {
		"ok": true, "why": "", "moved_cm": 0,
		"seat": {
			"index": index,
			"role": seats.role_of(index),
			"eye": seats.eye_of(index),
			"controls": seats.controls_of(index),
			"driving": seats.role_of(index) == Seats.DRIVER,
		},
	}


## Get out. Its own function rather than a flag on `perform`, because "leave the seat you are in"
## takes different arguments from "find me a seat" and a verb that did both would need half of each.
static func leave(request: Dictionary) -> Dictionary:
	var seats: Seats = request.get("seats")
	var who: Variant = request.get("who")
	if seats == null or who == null:
		return _no("leaving a seat needs a seat and somebody in it")
	var index := seats.leave(who)
	if index < 0:
		return _no("not aboard anything, so there is nothing to get out of")
	return { "ok": true, "why": "", "moved_cm": 0,
		"seat": { "index": index, "role": seats.role_of(index), "driving": false } }


static func _no(why: String) -> Dictionary:
	var out := Verbs.REFUSED.duplicate()
	out["why"] = why
	return out
