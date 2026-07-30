class_name RigRules
extends RefCounted
## Everything RIG-SPEC §3 says about a part that is part of a rig, plus the one thing it says
## about the shape of the whole hierarchy.
##
## These checks used to live in `PartRules` alongside sizes and materials, which was fine
## while a joint was three fields nobody had built anything with. They moved out at C2 for two
## reasons. The first is that half of what a rig needs checking for is not a property of any
## one part — a cycle in `parent` is a property of the graph, and so is a leg whose foot is
## not actually attached to it — so there has to be something that sees the whole table at
## once. The second is that `PartRules` was six lines under the file-length cap.
##
## The rule these enforce hardest is that **limits are mandatory**. RIG-SPEC §3 states it and
## it is worth restating why: an unlimited joint is not a joint that can do more, it is a
## joint that will eventually be handed an angle by a solver and bend a leg backward through
## a body. Refusing at load, in the file, with the line number, is much cheaper than the
## screenshot somebody sends three weeks later.

## The closed set, exactly as RIG-SPEC §3 lists it. `fixed` is the default and is a rigid
## weld — it exists so a part can be carried by a parent without articulating, which is most
## of a rig by count: a soldier's helmet is fixed to their head.
const JOINT_TYPES := ["hinge", "ball", "slider", "fixed"]

const AXES := ["x", "y", "z"]

const KNOWN_JOINT_FIELDS := ["type", "axis", "limits", "rest", "pivot", "follow"]

## `slider` limits are a distance and everything else's are an angle, so they are checked
## against different bounds. A hinge asked to travel 400° is a typo for 40; a slider asked to
## travel 400 modules is forty metres of piston.
const ANGLE_LIMIT := 360.0
const TRAVEL_LIMIT := 200.0

## Same bound as `PartPlacement.MAX_PARENT_DEPTH`, and deliberately the same number: this is
## the check that reports a cycle in words, and that one is the runtime guard that stops a
## cycle from being a hang. Two guards, because a graph that is refused at load should never
## reach the placement code, and the placement code should not depend on that being true.
const MAX_DEPTH := PartPlacement.MAX_PARENT_DEPTH

var errors: Array[String] = []
var warnings: Array[String] = []


## `at` takes (part_name, field) and returns `file:line`, the same shape `AssetRules` uses.
func check(asset: ResolvedAsset, at: Callable) -> void:
	var names := asset.part_names()
	var by_name: Dictionary = {}
	for part in asset.parts():
		if typeof(part) == TYPE_DICTIONARY and part.has("name"):
			by_name[String(part["name"])] = part

	for part in asset.parts():
		if typeof(part) != TYPE_DICTIONARY:
			continue
		var part_name := String(part.get("name", ""))
		var label := "part `%s`" % part_name if part_name != "" else "an unnamed part"
		_check_parent(part, part_name, label, at, names)
		_check_joint(part, part_name, label, at)

	_check_graph(by_name, at)
	_check_body(asset, at)


## An articulated asset has to be one body. `body: "bricks"` gives every part its own rigid
## body, and a hierarchy of rigid bodies is not a rig — it is a pile that happens to be
## stacked in the shape of one. Refused rather than quietly corrected, because the two
## settings mean genuinely different things and guessing which one the author meant is how a
## wall stops collapsing one day for no reason anybody can find.
func _check_body(asset: ResolvedAsset, at: Callable) -> void:
	if not Rig.is_rigged(asset) or AssetBuilder.body_mode_of(asset) != "bricks":
		return
	errors.append("%s — %s: `body` is `bricks` and its parts have joints. %s (RIG-SPEC §3)" % [
		String(at.call("", "body")), asset.id,
		"An articulated thing is one body with a rig inside it; bricks come apart, which is the opposite"])


## A parent has to exist and a child has to be nameable. The second is not pedantry: a part
## with no name cannot be patched by `parts~`, cannot be a `parent` itself, and cannot be
## named by a leg's `root` or `foot` — so an unnamed part in the middle of a rig is a piece of
## the hierarchy that nothing downstream can ever refer to.
func _check_parent(part: Dictionary, part_name: String, label: String, at: Callable,
		names: Array[String]) -> void:
	if not part.has("parent"):
		return
	var parent := String(part["parent"])
	if not names.has(parent):
		errors.append("%s — %s: `parent` is `%s`, and no part in this asset is called that.%s" % [
			at.call(part_name, "parent"), label, parent, PartRules.suggest(parent, names)])
	elif part_name == "":
		errors.append("%s — %s: a parented part needs a `name` of its own (FORMAT-SPEC §5)" % [
			at.call(part_name, "parent"), label])
	elif parent == part_name:
		errors.append("%s — %s: is its own `parent` (RIG-SPEC §3)" % [
			at.call(part_name, "parent"), label])


func _check_joint(part: Dictionary, part_name: String, label: String, at: Callable) -> void:
	if not part.has("joint"):
		return
	var where := String(at.call(part_name, "joint"))
	if typeof(part["joint"]) != TYPE_DICTIONARY:
		errors.append("%s — %s: `joint` should be an object (RIG-SPEC §3)" % [where, label])
		return

	var joint: Dictionary = part["joint"]
	var type := String(joint.get("type", "fixed"))
	if not JOINT_TYPES.has(type):
		errors.append("%s — %s: `%s` is not a joint type: %s. %s (RIG-SPEC §3)" % [
			where, label, type, ", ".join(JOINT_TYPES),
			"Packs cannot invent one; core's solvers are what drive them"])
		return
	if not part.has("parent"):
		errors.append("%s — %s: a joint needs a `parent` to pivot from (RIG-SPEC §3)" % [
			where, label])

	for key in joint:
		if not KNOWN_JOINT_FIELDS.has(String(key)):
			warnings.append("%s — %s: `%s` is not a joint field, so it is ignored" % [
				where, label, key])
	_check_pivot(joint, where, label)
	if type == "fixed":
		return
	_check_limits(joint, type, where, label)
	# Compared without a `String()` cast on purpose: that constructor only takes string-ish
	# things, and the field this is checking is one an author got wrong — `"axis": [1, 0, 0]`
	# is the natural mistake, and casting it threw a script error on the way to reporting it.
	if type == "hinge" and not AXES.has(joint.get("axis", "")):
		errors.append("%s — %s: a hinge needs an `axis` of x, y or z to turn about (RIG-SPEC §3)" % [
			where, label])


## RIG-SPEC §3 says joints pivot at the child's origin and that no pivot is off-grid. The
## first half of that is not workable on its own and this field is the consequence.
##
## A part's origin is the centre of its box (`PartGeometry.mesh_for`), so a leg bone hinging
## at its origin hinges about its own middle — and a leg that bends in the middle of the thigh
## is not a leg. There is nowhere else to put the correction: a part is its own bone *and* its
## own geometry here, with no separate node to offset one from the other.
##
## So `pivot` is an offset from the part's origin, in whole modules like every other distance
## in the format, which keeps the guarantee that actually matters — pivots land on the grid —
## while making a knee possible. Added at C2 and written into RIG-SPEC §3 in the same pass.
func _check_pivot(joint: Dictionary, where: String, label: String) -> void:
	if not joint.has("pivot"):
		return
	var pivot: Variant = joint["pivot"]
	if typeof(pivot) != TYPE_ARRAY or (pivot as Array).size() != 3:
		errors.append("%s — %s: `pivot` should be three whole modules from the part's own origin. %s" % [
			where, label, "It is where the joint turns — a leg's is at the top of the bone (RIG-SPEC §3)"])
		return
	for n in pivot:
		if not is_equal_approx(float(n), roundf(float(n))):
			errors.append("%s — %s: `pivot` is %s, and a pivot is on the grid. %s (RIG-SPEC §3)" % [
				where, label, ResolvedAsset.value_text(pivot),
				"One module is 0.1 m, so half a module up a bone is not a place a joint can be"])
			return


func _check_limits(joint: Dictionary, type: String, where: String, label: String) -> void:
	if not joint.has("limits"):
		errors.append("%s — %s: a `%s` joint needs `limits`. %s (RIG-SPEC §3)" % [
			where, label, type,
			"An unlimited joint is how you get a leg bending backward through a body"])
		return

	var limits: Variant = joint["limits"]
	var travel := type == "slider"
	var unit := "whole modules of travel" if travel else "degrees"
	if typeof(limits) != TYPE_ARRAY or (limits as Array).size() != 2:
		errors.append("%s — %s: `limits` should be `[low, high]` in %s (RIG-SPEC §3)" % [
			where, label, unit])
		return

	var low := float(limits[0])
	var high := float(limits[1])
	if low >= high:
		errors.append("%s — %s: `limits` are %s, and the low one has to be below the high one" % [
			where, label, ResolvedAsset.value_text(limits)])
		return

	var bound := TRAVEL_LIMIT if travel else ANGLE_LIMIT
	if absf(low) > bound or absf(high) > bound:
		errors.append("%s — %s: `limits` are %s %s, which is past anything a %s does. %s" % [
			where, label, ResolvedAsset.value_text(limits), unit, type,
			"Check the units — a hinge is degrees, not radians (RIG-SPEC §3)"])
		return

	# `rest` is the pose the joint holds when nothing is driving it, so a rest outside the
	# limits is a joint whose idle position it is not allowed to be in. It reads on screen as
	# a limb that snaps somewhere the moment the creature stops moving.
	if joint.has("rest"):
		var rest := float(joint["rest"])
		if rest < low or rest > high:
			errors.append("%s — %s: `rest` is %s and the limits are %s. %s (RIG-SPEC §3)" % [
				where, label, ResolvedAsset.value_text(rest), ResolvedAsset.value_text(limits),
				"A joint cannot idle at a pose it is not allowed to reach"])


## The hierarchy as a whole: no cycles, and nothing buried deeper than the placement code can
## walk. Both are reported by naming the chain end to end, because "part `hoof_l` is in a
## loop" sends somebody looking at the hoof, and the mistake is nearly always one link up.
func _check_graph(by_name: Dictionary, at: Callable) -> void:
	for name in ContentLoader.sorted_names(by_name.keys()):
		var part_name := String(name)
		var walked: Array[String] = [part_name]
		var current: Dictionary = by_name[part_name]

		while current.has("parent"):
			var parent := String(current["parent"])
			if not by_name.has(parent):
				break                        # already reported as a missing parent
			if walked.has(parent):
				# Reported once, against the alphabetically first part in the loop, rather than
				# once per member: a three-part cycle is one mistake and three copies of it in
				# the boot log is three times the reading for no extra information.
				if part_name == ContentLoader.sorted_names(walked)[0]:
					errors.append("%s — part `%s`: `parent` runs in a loop — %s. %s (RIG-SPEC §3)" % [
						at.call(part_name, "parent"), part_name,
						" → ".join(walked) + " → " + parent,
						"A rig is a tree: every part has one parent and the chain ends somewhere"])
				break
			walked.append(parent)
			if walked.size() > MAX_DEPTH:
				errors.append("%s — part `%s`: more than %d levels of `parent` — %s. %s" % [
					at.call(part_name, "parent"), part_name, MAX_DEPTH, " → ".join(walked),
					"Deep chains cost a transform each and are nearly always a hierarchy that wants flattening (RIG-SPEC §3)"])
				break
			current = by_name[parent]
