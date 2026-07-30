class_name PartRules
extends RefCounted
## Everything FORMAT-SPEC §5 says about one part, checked and then filled in.
##
## Two jobs, deliberately in one place. It refuses a part that breaks a rule — off-grid
## sizes, an unknown material, a colour the material does not permit, a shape outside the
## five, a joint with no limits — and for a part that passes, it writes in the defaults the
## author left out, so everything downstream reads a complete part and no builder ever has
## to know that `shape` was optional.
##
## They belong together because the defaults are only safe once the checks have passed: a
## colour defaulted from a material that does not exist is a colour of nothing, and a
## `jitter` forced to zero on a shape nobody recognised is a decision made about a part that
## should not load at all.
##
## Every message names the file, the line, and the rule. The file is the one that *wrote*
## the value, which after an `extends` chain is often not the asset being validated.

const SHAPES := ["block", "wedge", "corner_wedge", "cylinder", "sphere"]
const JOINT_TYPES := ["hinge", "ball", "slider", "fixed"]
const NAME_PATTERN := "^[a-z][a-z0-9_]*$"

## ART-BIBLE §3: 0.0 machined, 0.04–0.08 built by soldiers, 0.10–0.15 natural or ruined.
## The cap is above the top of that range and not far above it — jitter is a texture, and a
## part that wanders a third of its own width has stopped being on the grid at all.
const JITTER_MAX := 0.25

## ART-BIBLE §1: blocks are axis-aligned or deliberately angled, and a deliberate angle is
## a multiple of 15°. Primitives and rigged parts may use any integer degree.
const BLOCK_ROTATION_STEP := 15

const VECTOR_FIELDS := ["offset", "size", "rotation"]
const KNOWN_FIELDS := ["name", "shape", "offset", "rotation", "size", "material", "colour",
	"jitter", "parent", "joint", "mass", "anim"]

var errors: Array[String] = []
var warnings: Array[String] = []


## Check one part and fill in its defaults in place. `at` is a callable taking (field) and
## returning `file:line` for wherever that field was actually written.
func check(part: Dictionary, label: String, at: Callable, names: Array[String],
		materials: MaterialSet, palette: Palette) -> void:
	var shape := String(part.get("shape", "block"))
	if not SHAPES.has(shape):
		errors.append("%s — %s: `%s` is not one of the five primitives: %s. %s" % [
			at.call("shape"), label, shape, ", ".join(SHAPES),
			"The list is closed; adding to it is a design review (ART-BIBLE §1b)."])
		shape = "block"

	if part.has("name") and not _is_name(String(part["name"])):
		errors.append("%s — %s: `%s` is not a usable part name — %s (FORMAT-SPEC §8)" % [
			at.call("name"), label, part["name"], "lowercase letters, digits and underscores"])

	for field in VECTOR_FIELDS:
		if part.has(field):
			_check_vector(part, field, label, at)
	if not part.has("offset"):
		errors.append("%s — %s: no `offset` (FORMAT-SPEC §5: required, in modules)" % [
			at.call(""), label])
	if not part.has("size"):
		errors.append("%s — %s: no `size` (FORMAT-SPEC §5: required, in modules)" % [
			at.call(""), label])
	else:
		_check_size(part, label, at)
		_check_round(part, shape, label, at)
	_check_rotation(part, shape, label, at)

	var material := _check_material(part, label, at, materials)
	_check_colour(part, label, at, material, materials, palette)
	_check_jitter(part, shape, label, at)
	_check_parent(part, label, at, names)
	_check_joint(part, label, at)

	for key in part:
		if not KNOWN_FIELDS.has(String(key)):
			warnings.append("%s — %s: `%s` is not a part field, so it is ignored" % [
				at.call(String(key)), label, key])

	_apply_defaults(part, shape, material, materials)


## The defaults from FORMAT-SPEC §5's table, written in so nothing downstream has to know
## which fields were optional. `jitter` is the interesting one: it is not defaulted to zero
## on a primitive, it is *forced* to zero, because a jittered cylinder is a machined thing
## that has stopped reading as machined (ART-BIBLE §1b).
func _apply_defaults(part: Dictionary, shape: String, material: StringName,
		materials: MaterialSet) -> void:
	part["shape"] = shape
	if not part.has("rotation"):
		part["rotation"] = [0, 0, 0]
	if shape == "block":
		if not part.has("jitter"):
			part["jitter"] = 0.0
	else:
		part["jitter"] = 0.0
	if not part.has("colour") and materials.has(material):
		part["colour"] = String(materials.get_def(material).get("colour", ""))


func _check_vector(part: Dictionary, field: String, label: String, at: Callable) -> void:
	var value: Variant = part[field]
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		errors.append("%s — %s: `%s` should be three numbers, `[x, y, z]` (FORMAT-SPEC §3)" % [
			at.call(field), label, field])
		return
	for n in value:
		if typeof(n) != TYPE_INT and not (typeof(n) == TYPE_FLOAT and is_equal_approx(
				float(n), roundf(float(n)))):
			errors.append("%s — %s: `%s` is %s and every one is a whole number of modules. %s" % [
				at.call(field), label, field, ResolvedAsset.value_text(value),
				"One module is 0.1 m, so a 0.4 m box is 4 (FORMAT-SPEC §3)."])
			return


func _check_size(part: Dictionary, label: String, at: Callable) -> void:
	var size: Variant = part["size"]
	if typeof(size) != TYPE_ARRAY or (size as Array).size() != 3:
		return
	for n in size:
		if float(n) <= 0.0:
			errors.append("%s — %s: `size` is %s, and a part has to have a size (FORMAT-SPEC §5)" % [
				at.call("size"), label, ResolvedAsset.value_text(size)])
			return


## FORMAT-SPEC §5: a cylinder is `[diameter, diameter, length]` and a sphere `[d, d, d]`.
## The geometry takes the diameter from x alone, so a cylinder whose y disagrees renders at a
## size nobody wrote — silently, and a silently wrong size is the kind of thing an author
## chases for an hour before checking the one field they were sure of.
func _check_round(part: Dictionary, shape: String, label: String, at: Callable) -> void:
	if shape != "cylinder" and shape != "sphere":
		return
	var size: Variant = part["size"]
	if typeof(size) != TYPE_ARRAY or (size as Array).size() != 3:
		return
	var axes: Array = size
	var round_enough := is_equal_approx(float(axes[0]), float(axes[1]))
	if shape == "sphere":
		round_enough = round_enough and is_equal_approx(float(axes[0]), float(axes[2]))
	if round_enough:
		return
	errors.append("%s — %s: `size` is %s, and a %s is %s. %s (FORMAT-SPEC §5)" % [
		at.call("size"), label, ResolvedAsset.value_text(size), shape,
		"`[d, d, length]`, its length along -Z" if shape == "cylinder" else "`[d, d, d]`",
		"An ellipse is not one of the five primitives, so the odd axis would be ignored"])


func _check_rotation(part: Dictionary, shape: String, label: String, at: Callable) -> void:
	if not part.has("rotation") or shape != "block" or part.has("parent"):
		return
	var rot: Variant = part["rotation"]
	if typeof(rot) != TYPE_ARRAY or (rot as Array).size() != 3:
		return
	for n in rot:
		if int(roundf(float(n))) % BLOCK_ROTATION_STEP != 0:
			errors.append("%s — %s: `rotation` is %s, and a block turns in steps of %d°. %s" % [
				at.call("rotation"), label, ResolvedAsset.value_text(rot),
				BLOCK_ROTATION_STEP,
				"An angle is a design statement, not a modelling accident (FORMAT-SPEC §3)."])
			return


func _check_material(part: Dictionary, label: String, at: Callable,
		materials: MaterialSet) -> StringName:
	if not part.has("material"):
		# The one field with no default anywhere in the format, on purpose: a default here is
		# a silent decision about how the thing breaks, and how things break is the game.
		errors.append("%s — %s: no `material`. %s (FORMAT-SPEC §4b)" % [
			at.call(""), label,
			"Every part carries one and there is no default, so a stone wall never behaves like timber"])
		return &""

	var material := StringName(String(part["material"]))
	if not materials.has(material):
		errors.append("%s — %s: `%s` is not a material.%s (MATERIAL-SPEC §5)" % [
			at.call("material"), label, material,
			_suggest(String(material), materials.names())])
		return &""
	return material


func _check_colour(part: Dictionary, label: String, at: Callable, material: StringName,
		materials: MaterialSet, palette: Palette) -> void:
	if not part.has("colour"):
		return
	var colour := String(part["colour"])

	if colour.begins_with("#") or colour.is_valid_html_color():
		errors.append("%s — %s: `%s` is a hex colour. %s (FORMAT-SPEC §4)" % [
			at.call("colour"), label, colour,
			"Colours are palette names, so the palette stays the game's colour identity"])
		return
	if not palette.has(StringName(colour)):
		errors.append("%s — %s: `%s` is not in the palette.%s (ART-BIBLE §2)" % [
			at.call("colour"), label, colour, _suggest(colour, palette.names())])
		return
	if material == &"":
		return
	if not materials.allows_colour(material, StringName(colour)):
		var allowed: Array = materials.get_def(material).get("colour_allow", [])
		errors.append("%s — %s: `%s` may not be %s. It can be: %s. %s (FORMAT-SPEC §4b)" % [
			at.call("colour"), label, material, colour, ", ".join(PackedStringArray(allowed)),
			"A material constrains its own colours so sandbags look like sandbags everywhere"])


func _check_jitter(part: Dictionary, shape: String, label: String, at: Callable) -> void:
	if not part.has("jitter"):
		return
	var jitter := float(part["jitter"])
	if jitter < 0.0 or jitter > JITTER_MAX:
		errors.append("%s — %s: `jitter` is %s, and it runs 0 to %s. %s (ART-BIBLE §3)" % [
			at.call("jitter"), label, ResolvedAsset.value_text(jitter),
			ResolvedAsset.value_text(JITTER_MAX),
			"0 machined, 0.04–0.08 built by hand, 0.10–0.15 rubble"])
	elif jitter > 0.0 and shape != "block":
		# Forced to zero rather than refused, because the part is otherwise fine and the rule
		# is about how it reads. A jittered box beside a clean cylinder is what tells a player
		# "sandbag" from "gun", and that contrast is worth protecting silently.
		warnings.append("%s — %s: jitter does not apply to a %s, so it is 0 (ART-BIBLE §1b)" % [
			at.call("jitter"), label, shape])


func _check_parent(part: Dictionary, label: String, at: Callable,
		names: Array[String]) -> void:
	if not part.has("parent"):
		return
	var parent := String(part["parent"])
	if not names.has(parent):
		errors.append("%s — %s: `parent` is `%s`, and no part in this asset is called that.%s" % [
			at.call("parent"), label, parent, _suggest(parent, names)])
	elif not part.has("name"):
		errors.append("%s — %s: a parented part needs a `name` of its own (FORMAT-SPEC §5)" % [
			at.call("parent"), label])


func _check_joint(part: Dictionary, label: String, at: Callable) -> void:
	if not part.has("joint"):
		return
	if typeof(part["joint"]) != TYPE_DICTIONARY:
		errors.append("%s — %s: `joint` should be an object (RIG-SPEC §3)" % [
			at.call("joint"), label])
		return
	var joint: Dictionary = part["joint"]
	var type := String(joint.get("type", "fixed"))

	if not JOINT_TYPES.has(type):
		errors.append("%s — %s: `%s` is not a joint type: %s. %s (RIG-SPEC §3)" % [
			at.call("joint"), label, type, ", ".join(JOINT_TYPES),
			"Packs cannot invent one; core's solvers are what drive them"])
		return
	if not part.has("parent"):
		errors.append("%s — %s: a joint needs a `parent` to pivot from (RIG-SPEC §3)" % [
			at.call("joint"), label])
	if type == "fixed":
		return

	if not joint.has("limits"):
		errors.append("%s — %s: a `%s` joint needs `limits`. %s (RIG-SPEC §3)" % [
			at.call("joint"), label, type,
			"An unlimited joint is how you get a leg bending backwards through a body"])
		return
	var limits: Variant = joint["limits"]
	if typeof(limits) != TYPE_ARRAY or (limits as Array).size() != 2:
		errors.append("%s — %s: `limits` should be `[low, high]` in degrees (RIG-SPEC §3)" % [
			at.call("joint"), label])
	elif float(limits[0]) >= float(limits[1]):
		errors.append("%s — %s: `limits` are %s, and the low one has to be below the high one" % [
			at.call("joint"), label, ResolvedAsset.value_text(limits)])
	if type == "hinge" and not joint.has("axis"):
		errors.append("%s — %s: a hinge needs an `axis` to turn about (RIG-SPEC §3)" % [
			at.call("joint"), label])


static var _name_re := RegEx.create_from_string(NAME_PATTERN)


static func _is_name(text: String) -> bool:
	return _name_re != null and _name_re.search(text) != null


## ` Did you mean `steel`?` — or nothing, when nothing is close. A near-miss on a name is
## the commonest mistake in a hand-written pack and the one that is most maddening to find
## by eye, because `stell` and `steel` look identical at a glance.
static func _suggest(wrong: String, among: Array) -> String:
	var best := ""
	var score := 0.72
	for candidate in among:
		var text := String(candidate)
		var s := wrong.similarity(text)
		if s > score:
			score = s
			best = text
	return "" if best == "" else " Did you mean `%s`?" % best
