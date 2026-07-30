class_name GaitRules
extends RefCounted
## The `gaits` half of a `locomotion` block. RIG-SPEC §5.
##
## Split out of `LocomotionRules` because the two halves fail differently and the pair did not
## fit in one file. The legs half asks whether the block describes *this* asset — a `root` that
## names no part, a `foot` hanging off a different limb — and answers with the hierarchy. This
## half asks whether a set of numbers means what it says, and answers with arithmetic. They share
## nothing but the block they are handed and the line they blame, which is why this one needs no
## `ResolvedAsset` at all.
##
## The rule behind almost every error here: refuse the numbers the driver *reads and then quietly
## does nothing useful with*. `Gait.advance` returns 0 for a `stride` of 0, so the phase never
## advances, so every foot stays planted and the creature slides along the ground upright.
## `Gait.foot_cycle` clamps `duty` into [0.05, 0.95], so a `duty` of 5 is accepted and means a
## foot that never once leaves the ground. Neither writes a line to the log. Neither looks like
## the field that caused it. There is no screenshot that says "stride".

const KNOWN_FIELDS := ["name", "speed", "phases", "stride", "lift", "duty"]

var errors: Array[String] = []
var warnings: Array[String] = []


## `legs` is how many legs the table above declared, which is what `phases` has to be sized
## against. Zero means the leg table was itself unusable, and the size check is skipped rather
## than reported against a number that is already wrong.
func check(block: Dictionary, where: String, label: String, legs: int) -> void:
	var declared: Variant = block.get("gaits", [])
	if typeof(declared) != TYPE_ARRAY or (declared as Array).is_empty():
		errors.append("%s — %s: a `legged` thing needs a `gaits` array with at least one gait. %s" % [
			where, label,
			"With none, every speed resolves to no gait and it never takes a step (RIG-SPEC §5)"])
		return

	var gaits: Array = declared
	var previous := -INF
	var ordered := true
	for i in gaits.size():
		if typeof(gaits[i]) != TYPE_DICTIONARY:
			errors.append("%s — %s, gait %d: should be an object with a `name` and a `speed` (RIG-SPEC §5)" % [
				where, label, i + 1])
			continue
		var low := _one(gaits[i] as Dictionary, where, label, legs)
		if low < previous:
			ordered = false
		previous = low

	# `Gait._usable` sorts the table before blending, and its comment says the validator is what
	# says so — this is that. A warning, because the sort makes the order harmless; still worth
	# saying, because a table where `gallop` sits between `walk` and `trot` is one somebody will
	# read as the order the gaits happen in.
	if not ordered:
		warnings.append("%s — %s: `gaits` are not in ascending `speed` order. %s" % [
			where, label,
			"Core sorts them, so this changes nothing — but the file reads as though it did"])


## One gait. Returns the bottom of its speed range, for the ordering check above.
func _one(gait: Dictionary, where: String, label: String, legs: int) -> float:
	var name := String(gait.get("name", ""))
	var mine := "%s, gait `%s`" % [label, name] if name != "" else "%s, an unnamed gait" % label
	for key in gait:
		if not KNOWN_FIELDS.has(String(key)):
			warnings.append("%s — %s: `%s` is not a gait field, so it is ignored" % [
				where, mine, key])
	if name == "":
		errors.append("%s — %s: a gait needs a `name`. %s (RIG-SPEC §5)" % [
			where, mine,
			"It is what the driver reports and what anything reacting to a gait matches on"])

	var low := _speed(gait, where, mine)
	_phases(gait, where, mine, legs)
	_bound(gait, "stride", where, mine, false,
		"metres from footfall to footfall — at 0 the cycle never advances and the feet skate")
	_bound(gait, "lift", where, mine, true,
		"metres a foot clears the ground; 0 is a foot that drags, below 0 is one that digs in")
	_duty(gait, where, mine)
	return low


func _speed(gait: Dictionary, where: String, mine: String) -> float:
	var span: Variant = gait.get("speed", null)
	if typeof(span) != TYPE_ARRAY or (span as Array).size() != 2:
		errors.append("%s — %s: `speed` should be `[low, high]` in metres per second (RIG-SPEC §5)" % [
			where, mine])
		return 0.0
	var low := float((span as Array)[0])
	if low >= float((span as Array)[1]):
		errors.append("%s — %s: `speed` is %s, and the low end has to be below the high one. %s" % [
			where, mine, ResolvedAsset.value_text(span),
			"A range no speed is inside is a gait that never runs (RIG-SPEC §5)"])
	return low


## Sized to the leg count, and this matters in two places rather than one. `Locomotion.step`
## falls back to a leg's own `phase` for any leg past the end of the array, so a short table
## silently mixes two sources of timing; and `Gait._mix_phases` refuses to blend at all between
## two gaits whose arrays differ in length, so a gait change stops moving the legs it cannot
## pair up. Both are silent. Neither is what the author wrote the array for.
func _phases(gait: Dictionary, where: String, mine: String, legs: int) -> void:
	if not gait.has("phases") or legs <= 0:
		return
	var phases: Variant = gait["phases"]
	if typeof(phases) != TYPE_ARRAY:
		errors.append("%s — %s: `phases` should be an array of one offset per leg (RIG-SPEC §5)" % [
			where, mine])
		return
	if (phases as Array).size() != legs:
		errors.append("%s — %s: %d `phases` for a %d-leg creature. %s (RIG-SPEC §5)" % [
			where, mine, (phases as Array).size(), legs,
			"One offset per leg, in the order `legs` lists them"])


## `stride` must be above zero and `lift` merely not below it — a foot that clears nothing is a
## creature shuffling, which is a choice; a cycle that advances by nothing is a bug.
func _bound(gait: Dictionary, field: String, where: String, mine: String, zero_is_fine: bool,
		why: String) -> void:
	if not gait.has(field):
		return
	var value := float(gait[field])
	if value < 0.0 or (value == 0.0 and not zero_is_fine):
		errors.append("%s — %s: `%s` is %s. %s (RIG-SPEC §5)" % [
			where, mine, field, ResolvedAsset.value_text(gait[field]), why])


## A fraction of the cycle, so strictly inside 0 and 1.
func _duty(gait: Dictionary, where: String, mine: String) -> void:
	if not gait.has("duty"):
		return
	var duty := float(gait["duty"])
	if duty <= 0.0 or duty >= 1.0:
		errors.append("%s — %s: `duty` is %s, and it is the fraction of the cycle a foot is down. %s" % [
			where, mine, ResolvedAsset.value_text(gait["duty"]),
			"0.7 is a walk and 0.35 is a gallop; at 1 the foot never leaves the ground (RIG-SPEC §5)"])
