class_name RigReport
extends RefCounted
## What `--rig <asset>` prints: a rig's bones, and every number the locomotion driver derived
## from its rest pose. RIG-SPEC §3–§5.
##
## `--resolve` answers "where did this field come from", which is the question you have when a
## value is wrong. This answers a different one: "what did the game make of it". Almost nothing
## the driver runs on is written in the file. A leg's reach, its bend direction, how far the body
## can drop, where the sole rests — all of it is *derived*, and an author who has just moved a
## bone two modules has no way to see what that did except by playing the game and squinting.
##
## The authoring loop this exists for is specific. `offset` has to be a whole number of modules,
## and a bone pivots half its own length along its own axis, so any rotation that is not a
## multiple of 90° puts a joint at an irrational offset and there is no legal `offset` that
## reconnects the chain. The way round it is to author the skeleton axis-aligned and bend it with
## `rest` angles, which are plain degrees on a joint and constrained by nothing — but then the
## rest pose is trigonometry the author cannot do in their head, and the numbers that matter most
## (is the sole on the ground? does the knee bend forward?) are exactly the derived ones. So the
## loop is: set a `rest` angle, run this, read `stand` and `bend`, adjust. It was written to
## author `core:soldier` and it is the reason that was an afternoon rather than a week.
##
## Printed rather than asserted, on purpose. This is an instrument, not a gate — `case_leg.gd`
## is where these numbers are held to values somebody worked out with a pencil.

## Columns wide enough for the longest bone name any shipped asset has, and no wider. A dump that
## wraps in an 80-column terminal is a dump nobody reads twice.
const NAME_WIDTH := 18


## The whole report, or a sentence saying why there is none. `built` may be null — an asset with
## no joints has no rig, which is a fact about it rather than a failure, and most assets are that.
static func of(asset: ResolvedAsset, built: BuiltAsset) -> String:
	var lines: Array[String] = ["%s   (%s)" % [asset.id, asset.path]]
	if built == null or built.rig == null:
		lines.append("")
		lines.append("no rig — no part of this asset declares a `joint`, so it is baked flat.")
		lines.append("`--resolve %s` is the dump you want for one of those." % asset.id)
		return "\n".join(lines)

	var rig := built.rig
	lines.append("")
	lines.append(_bones(rig))
	for warning in rig.warnings:
		lines.append("  rig: " + warning)

	var block := Locomotion.declared(asset)
	if block.is_empty():
		lines.append("")
		lines.append("no `locomotion` — this rig is posed by something else, or by nothing yet.")
		return "\n".join(lines)

	var loco := Locomotion.new()
	var driven := loco.setup(rig, block)
	lines.append("")
	lines.append(_locomotion(loco, block, driven))
	return "\n".join(lines)


## The hierarchy, indented by depth, with each bone's own length and what its joint may do. The
## joint column is where the two mistakes live that cost the most time: a `fixed` joint on
## something meant to bend, and limits that do not contain the `rest` the file also asked for.
static func _bones(rig: Rig) -> String:
	var out: Array[String] = ["bones — %d, in declaration order" % rig.order.size()]
	for name in rig.order:
		var bone: Rig.Bone = rig.bone(name)
		var depth := 0
		var at := bone.parent
		while at != "" and rig.has(at) and depth < 8:
			depth += 1
			at = (rig.bone(at) as Rig.Bone).parent
		var label := "  " + "  ".repeat(depth) + name
		out.append("%s %s  length %5.3f m   joint %s" % [
			label, ".".repeat(maxi(1, NAME_WIDTH + 2 * depth - label.length() + 2)),
			bone.length(), _joint(bone)])
	return "\n".join(out)


static func _joint(bone: Rig.Bone) -> String:
	if bone.joint.is_empty():
		return "—"
	var type := String(bone.joint.get("type", "fixed"))
	if not bone.articulates():
		return type
	var limits: Variant = bone.joint.get("limits", [])
	var span := ResolvedAsset.value_text(limits)
	var rest := ResolvedAsset.value_text(bone.joint.get("rest", 0))
	return "%s %s about %s, rest %s" % [
		type, span, String(bone.joint.get("axis", "—")), rest]


## Everything the driver worked out for itself. `stand` and `drop` first, because they are the
## two that decide whether the creature is standing on the ground or hovering above it.
static func _locomotion(loco: Locomotion, block: Dictionary, driven: bool) -> String:
	var out: Array[String] = ["locomotion — type `%s`" % loco.type]
	if not driven:
		out.append("  nothing to drive: this type has no leg driver, or no leg resolved to a chain.")
		for warning in loco.warnings:
			out.append("  " + warning)
		return "\n".join(out)

	out.append("  stand %6.3f m  — how high the body rides above its feet on the level" % loco.stand)
	out.append("  drop  %6.3f m  — how far below itself it may put the lowest foot" % loco.drop)
	out.append("  bob %.3f · pitch %.2f · lean %.2f" % [
		loco.body_bob, loco.body_pitch, loco.lean_into_turn])

	out.append("")
	out.append("legs — %d" % loco.legs.size())
	for i in loco.legs.size():
		var leg := loco.legs[i]
		out.append("  %d. %s" % [i + 1, " → ".join(leg.chain)])
		out.append("     upper %5.3f  lower %5.3f  trail %5.3f  span %5.3f" % [
			leg.upper, leg.lower, leg.trail, leg.upper + leg.lower + leg.trail])
		# The two that are never written down anywhere and are the whole reason for this tool.
		out.append("     sole  %s   reach %5.3f   drop %5.3f" % [
			_vec(leg.home), leg.reach, leg.drop])
		out.append("     bend  %s   %s" % [_vec(leg.bend), _bend_reads_as(leg)])
		if is_equal_approx(leg.reach, Leg.MIN_REACH):
			out.append("     ^ reach is at its floor, so this leg was authored straight —"
				+ " give its knee a `rest` angle")

	for warning in loco.warnings:
		out.append("  " + warning)

	out.append("")
	out.append(_gaits(loco, block))
	return "\n".join(out)


## Which way the knee travels, in words. The vector is the answer; this is the sanity check, and
## it is the line that catches a hind leg authored like a foreleg — a horse whose hocks bend the
## wrong way reads as broken long before anybody can say which number did it.
static func _bend_reads_as(leg: Leg) -> String:
	if absf(leg.bend.z) < 0.5:
		return "(sideways — unusual; a knee or a hock bends fore or aft)"
	return "(forward, like a knee)" if leg.bend.z < 0.0 else "(backward, like a hock)"


## The gait table as core reads it, sorted the way `Gait._usable` sorts it rather than the way the
## file lists it, because that is the order transitions actually happen in.
static func _gaits(loco: Locomotion, block: Dictionary) -> String:
	var out: Array[String] = ["gaits — %d, in the order core will blend them" % loco.gaits.size()]
	var declared: Variant = block.get("gaits", [])
	var count := (declared as Array).size() if typeof(declared) == TYPE_ARRAY else 0
	var seen: Array[String] = []
	for step in 200:
		# Walked by asking `Gait.for_speed` rather than by re-sorting the table here: the answer
		# a report gives has to be the answer the driver gives, and two sorts can disagree.
		var gait := Gait.for_speed(loco.gaits, step * 0.25)
		if gait.is_empty():
			break
		var name := String(gait["name"])
		if seen.has(name) or bool(gait["blending"]):
			continue
		seen.append(name)
		out.append("  %-10s stride %5.3f m  lift %5.3f m  duty %4.2f  phases %s" % [
			name, float(gait["stride"]), float(gait["lift"]), float(gait["duty"]),
			ResolvedAsset.value_text(gait["phases"])])
	if seen.size() < count:
		out.append("  (%d gait(s) never come up between 0 and 50 m/s — check their `speed` ranges)"
			% (count - seen.size()))
	return "\n".join(out)


static func _vec(v: Vector3) -> String:
	return "(%6.3f, %6.3f, %6.3f)" % [v.x, v.y, v.z]
