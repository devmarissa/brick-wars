class_name LocomotionRules
extends RefCounted
## Everything RIG-SPEC §5 says about a `locomotion` block, checked before anything drives one.
##
## This file exists because the field was accepted and unchecked. `locomotion` went into
## `AssetRules.KNOWN_FIELDS` when the driver was written, which stopped the "not an asset field"
## warning and put nothing in its place — so for one commit a pack could write any garbage at
## all under that key and the only symptom was a creature that stood still. That is the worst
## shape a content bug can have: the game boots, the pack loads, nothing says a word, and the
## thing simply does not move.
##
## The rules split into two halves that fail differently, and `GaitRules` is the other one. This
## half is about whether the block describes *this* asset — a `root` that names no part, a `foot`
## hanging off a different limb — and those are errors, because a leg the driver cannot resolve
## is a leg that holds its rest pose while its opposite number walks. `GaitRules` is about
## whether a set of numbers means what it says.
##
## ### What is deliberately *not* checked here
##
## RIG-SPEC's straight-leg complaint — "this leg is straight at rest, so which way its knee bends
## is a guess" — stays in `Leg._bend` and is not repeated here. It reads a *posed* rest pose:
## composed rotations down the chain, `pivot` offsets, and each joint driven to its own `rest`.
## The validator has a part table and no `Rig`, so the honest options were to reimplement pose
## composition against the day it drifts from the real one, or to check a proxy — "the upper
## joint declares no `rest`" — which is wrong for any leg bent by its authored `rotation` or by
## its offsets, and would print a warning at boot about a leg that is fine. Neither buys anything
## over the warning `Leg.measure` already emits with the leg's own name in it. Recorded in
## `DEVIATIONS-C2.md` rather than left as a silent gap.

## RIG-SPEC §5's block, field for field. Anything else is a typo or a field from a newer format,
## and either way it is ignored rather than obeyed.
const KNOWN_FIELDS := ["type", "legs", "gaits", "body_bob", "body_pitch", "lean_into_turn"]

const KNOWN_LEG_FIELDS := ["root", "foot", "phase"]

## What every message below is blamed on. `AssetValidator._collect` already puts the asset's id
## in front, so naming the block rather than the asset again is what keeps the line readable.
const LABEL := "`locomotion`"

## Same bound the hierarchy is checked against, for the same reason: this walk goes up `parent`
## links, and a cycle in them would otherwise be a hang here rather than an error there.
const MAX_DEPTH := PartPlacement.MAX_PARENT_DEPTH

var errors: Array[String] = []
var warnings: Array[String] = []


## `at` takes (part_name, field) and returns `file:line`, the same shape `RigRules` uses. Every
## message anchors on the block itself and names the leg or gait in its own text, because the
## interesting sub-fields are nested and `SourceLines` finds a field by name, not by path.
func check(asset: ResolvedAsset, at: Callable) -> void:
	if not asset.data.has("locomotion"):
		return
	var where := String(at.call("", "locomotion"))
	var declared: Variant = asset.data["locomotion"]
	if typeof(declared) != TYPE_DICTIONARY:
		errors.append("%s — %s: should be an object with a `type` in it, not `%s`. %s" % [
			where, LABEL, ResolvedAsset.value_text(declared), "RIG-SPEC §5 has the shape"])
		return

	var block: Dictionary = declared
	for key in block:
		if not KNOWN_FIELDS.has(String(key)):
			warnings.append("%s — %s: `%s` is not a `locomotion` field, so it is ignored" % [
				where, LABEL, key])

	var type := _check_type(block, where)
	if type == "":
		return
	if type != "legged":
		# Not an error: a `wheeled` thing with a leftover leg table is a pack mid-conversion, and
		# refusing it would stop a vehicle loading over a field nothing reads.
		if block.has("legs") or block.has("gaits"):
			warnings.append("%s — %s: `type` is `%s`, so its `legs` and `gaits` are ignored. %s" % [
				where, LABEL, type, "Only `legged` has a driver that reads them (RIG-SPEC §5)"])
		return

	var legs := _check_legs(asset, block, where)
	var gaits := GaitRules.new()
	gaits.check(block, where, LABEL, legs)
	errors.append_array(gaits.errors)
	warnings.append_array(gaits.warnings)


## The closed set. A pack cannot invent a type for the same reason it cannot invent a joint
## type: each one names a driver somebody in core has to have written, and an unknown type is a
## thing that loads and then never moves.
func _check_type(block: Dictionary, where: String) -> String:
	if not block.has("type"):
		errors.append("%s — %s: needs a `type`: %s (RIG-SPEC §5)" % [
			where, LABEL, ", ".join(Locomotion.TYPES)])
		return ""
	var type := String(block["type"])
	if not Locomotion.TYPES.has(type):
		errors.append("%s — %s: `%s` is not a locomotion type: %s. %s (RIG-SPEC §5)" % [
			where, LABEL, type, ", ".join(Locomotion.TYPES),
			"Packs cannot invent one; core's drivers are what run them"])
		return ""
	return type


## The leg table, and whether it describes this asset. Returns how many legs were declared,
## which is what a gait's `phases` has to be sized against — 0 when the table is unusable, which
## stops `GaitRules` reporting a size mismatch against a number that is itself wrong.
func _check_legs(asset: ResolvedAsset, block: Dictionary, where: String) -> int:
	var declared: Variant = block.get("legs", [])
	if typeof(declared) != TYPE_ARRAY or (declared as Array).is_empty():
		errors.append("%s — %s: a `legged` thing needs a `legs` array with at least one leg. %s" % [
			where, LABEL,
			"Each names the part it hangs from and the part that touches the ground (RIG-SPEC §5)"])
		return 0

	var by_name: Dictionary = {}
	for part in asset.parts():
		if typeof(part) == TYPE_DICTIONARY and part.has("name"):
			by_name[String(part["name"])] = part
	var names := asset.part_names()

	var legs: Array = declared
	for i in legs.size():
		var mine := "%s, leg %d" % [LABEL, i + 1]
		if typeof(legs[i]) != TYPE_DICTIONARY:
			errors.append("%s — %s: should be an object with `root` and `foot` (RIG-SPEC §5)" % [
				where, mine])
			continue
		_check_leg(legs[i] as Dictionary, mine, where, by_name, names)
	return legs.size()


func _check_leg(leg: Dictionary, mine: String, where: String, by_name: Dictionary,
		names: Array[String]) -> void:
	for key in leg:
		if not KNOWN_LEG_FIELDS.has(String(key)):
			warnings.append("%s — %s: `%s` is not a leg field, so it is ignored" % [
				where, mine, key])

	var root := String(leg.get("root", ""))
	var foot := String(leg.get("foot", ""))
	var found := true
	for pair in [["root", root], ["foot", foot]]:
		var field := String(pair[0])
		var part_name := String(pair[1])
		if part_name == "":
			errors.append("%s — %s: needs a `%s` naming one of this asset's parts (RIG-SPEC §5)" % [
				where, mine, field])
			found = false
		elif not by_name.has(part_name):
			errors.append("%s — %s: `%s` is `%s`, and no named part in this asset is called that.%s" % [
				where, mine, field, part_name, PartRules.suggest(part_name, names)])
			found = false
	if found:
		_check_chain(root, foot, mine, where, by_name)

	# Wrapped rather than refused: `Leg.measure` runs it through `fposmod`, so 1.25 loads and
	# means 0.25. Said out loud with the number it becomes, because an author who wrote 1.25
	# meaning "a quarter of a cycle after the one before" got that by accident, and one who
	# meant "one and a quarter cycles" did not get it at all.
	if leg.has("phase"):
		var phase := float(leg["phase"])
		if phase < 0.0 or phase >= 1.0:
			warnings.append("%s — %s: `phase` is %s, and a phase is a fraction of one cycle in [0, 1). %s" % [
				where, mine, ResolvedAsset.value_text(leg["phase"]),
				"It will be read as %s" % ResolvedAsset.value_text(fposmod(phase, 1.0))])


## The chain is what the solver runs on, so a `foot` that is not below its `root` is not a leg —
## it is two limbs the driver would try to bend into one. Walked here rather than through
## `Leg.chain_between`, which needs a built `Rig` and there is none at load.
func _check_chain(root: String, foot: String, mine: String, where: String,
		by_name: Dictionary) -> void:
	if root == foot:
		errors.append("%s — %s: `root` and `foot` are both `%s`. %s (RIG-SPEC §4)" % [
			where, mine, root,
			"A leg needs two bones at least — one to swing from the hip and one to bend at the knee"])
	elif not _descends(by_name, foot, root):
		errors.append("%s — %s: `%s` is not below `%s` in the hierarchy. %s (RIG-SPEC §4)" % [
			where, mine, foot, root,
			"A leg is one chain of `parent` links running from the root down to the foot"])


## Whether `foot` is reachable from `root` by walking up `parent` links. Upward, because a part
## knows its parent and not its children — exactly as `Leg.chain_between` does it.
func _descends(by_name: Dictionary, foot: String, root: String) -> bool:
	var at := foot
	var depth := 0
	while by_name.has(at) and depth <= MAX_DEPTH:
		var part: Dictionary = by_name[at]
		if not part.has("parent"):
			return false
		var parent := String(part["parent"])
		if parent == root:
			return true
		at = parent
		depth += 1
	return false
