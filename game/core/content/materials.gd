class_name MaterialSet
extends RefCounted
## The sanctioned material set, loaded from `core/data/materials.json`. MATERIAL-SPEC.
##
## Every part names a material. It is required and there is no default, because a default
## is a silent decision about how something breaks, and how things break is the game.
##
## What this class does beyond reading the file: it folds each material's class defaults
## in underneath its own values, so callers never have to know that `sandbag` states two
## resistances and inherits four. And it derives mass — volume × density — which is the
## rule that makes a stone block heavy because stone is heavy rather than because somebody
## typed a number into a prop.
##
## Packs cannot add to the list. A pack derives a material only by `extends` on a core one,
## clamped ×0.5–×2.0, with class, failure and hardness inherited (MATERIAL-SPEC §8). That
## resolver is next door; this class is what it resolves against.

const CORE_PATH := "res://core/data/materials.json"

var id: StringName = &""
var materials: Dictionary = {}     ## StringName -> Dictionary, class defaults folded in
var classes: Dictionary = {}
var damage_types: Array[String] = []
var failure_modes: Array[String] = []
var hardness_tiers: Dictionary = {}
var pack_extends: Dictionary = {}
var errors: Array[String] = []


## Load and validate. `palette` is required: a material's default colour and its permitted
## overrides are palette names, and a material pointing at a colour that does not exist is
## a broken material, not a broken palette.
func load_core(palette: Palette, path := CORE_PATH) -> bool:
	errors.clear()
	materials.clear()

	var data := ContentLoader.read_object(path, errors)
	if data.is_empty():
		return false

	id = StringName(data.get("id", ""))
	classes = data.get("classes", {})
	hardness_tiers = data.get("hardness_tiers", {})
	pack_extends = data.get("pack_extends", {})

	var dt: Dictionary = data.get("damage_types", {})
	for d in dt.get("order", []):
		damage_types.append(String(d))
	for f in (data.get("failure_modes", {}) as Dictionary).get("order", []):
		failure_modes.append(String(f))

	if damage_types.is_empty():
		errors.append("%s: no `damage_types.order` — nothing can be resisted" % path)
		return false
	if classes.is_empty():
		errors.append("%s: no `classes` — class defaults are where most numbers live" % path)
		return false

	var entries: Variant = ContentLoader.require(data, "materials", path, TYPE_DICTIONARY, errors)
	if entries == null:
		return false

	for name in entries:
		_read_material(path, StringName(name), entries[name], palette)

	_check_transitions(path)
	return errors.is_empty()


func has(mat: StringName) -> bool:
	return materials.has(mat)


## The fully resolved material — its own values over its class's. Empty for an unknown
## one, and unknown materials are a validator refusal long before anything asks for one.
func get_def(mat: StringName) -> Dictionary:
	return materials.get(mat, {})


func names() -> Array[StringName]:
	return ContentLoader.sorted_names(materials.keys())


func names_in_class(cls: String) -> Array[StringName]:
	var out: Array = []
	for n in materials:
		if materials[n].get("class", "") == cls:
			out.append(n)
	return ContentLoader.sorted_names(out)


## Mass in kg. This is the whole of MATERIAL-SPEC §2's mass rule: nobody types a mass.
## `FORMAT-SPEC` §6's `mass` field overrides it for the rare part where derived mass is
## wrong — a hollow crate, an empty fuel drum — and that override is a thing an author
## has to write down and defend rather than the default state of the world.
func mass_for(mat: StringName, volume_m3: float) -> float:
	if not materials.has(mat):
		return 0.0
	return float(materials[mat].get("density", 0.0)) * volume_m3


## Damage taken, so lower is tougher. 0.15 means the material absorbs 85% of it.
func resist(mat: StringName, damage_type: String) -> float:
	if not materials.has(mat):
		return 1.0
	return float((materials[mat].get("resist", {}) as Dictionary).get(damage_type, 1.0))


## A tool works material where `tool_power >= hardness` (MATERIAL-SPEC §4).
func can_work(mat: StringName, tool_power: int) -> bool:
	if not materials.has(mat):
		return false
	return tool_power >= int(materials[mat].get("hardness", 99))


## What to say when it can't. The refusal message is the entire cost of tool gating and
## it is cheap to pay — never a silent no-op, never an animation that achieves nothing.
func refusal(mat: StringName, tool_power: int) -> String:
	if not materials.has(mat):
		return "there is no such material as '%s'" % mat
	var need := int(materials[mat].get("hardness", 99))
	var tools: Array = (hardness_tiers.get(str(need), {}) as Dictionary).get("worked_by", [])
	return "%s is hardness %d and your tool is %d — you need %s" % [
		mat, need, tool_power, " or ".join(PackedStringArray(tools))]


## Whether a part of this material may be painted this colour. Materials supply a default
## colour and constrain the overrides (FORMAT-SPEC §4b), which is what stops a pack from
## shipping pink concrete without core having to enumerate every wrong combination.
func allows_colour(mat: StringName, col: StringName) -> bool:
	if not materials.has(mat):
		return false
	return (materials[mat].get("colour_allow", []) as Array).has(String(col))


func _read_material(path: String, name: StringName, entry: Variant, palette: Palette) -> void:
	var where := "%s: material `%s`" % [path, name]
	if typeof(entry) != TYPE_DICTIONARY:
		errors.append("%s: should be an object" % where)
		return

	var cls := String(entry.get("class", ""))
	if not classes.has(cls):
		errors.append("%s: class `%s` is not one of %s" % [
			where, cls, str(ContentLoader.sorted_names(classes.keys()))])
		return

	var def := _fold_class_defaults(cls, entry)

	for key in ["density", "hardness", "integrity", "work_rate"]:
		ContentLoader.require(def, key, where, TYPE_FLOAT, errors)

	var hardness := int(def.get("hardness", -1))
	if not hardness_tiers.has(str(hardness)):
		errors.append("%s: hardness %d has no tier — tiers are 0 to 5 (MATERIAL-SPEC §4)" % [
			where, hardness])

	for key in ["failure", "failure_then"]:
		if def.has(key) and not failure_modes.has(String(def[key])):
			errors.append("%s: `%s` is `%s`, which is not a failure mode. %s" % [
				where, key, def[key], str(failure_modes)])

	_check_resist(where, cls, def)
	_check_fire(where, def)
	_check_colour(where, def, palette)

	if def.get("surface", null) == null:
		errors.append("%s: class `%s` supplies no surface defaults, so this material %s" % [
			where, cls, "has to state its own `surface`"])

	materials[name] = def


## Class defaults underneath, the material's own values on top. `resist` merges key by key
## so a material can override one damage type without restating five — `sandbag` says
## kinetic and blast and inherits the rest of fabric.
func _fold_class_defaults(cls: String, entry: Dictionary) -> Dictionary:
	var defaults: Dictionary = classes[cls]
	var def := entry.duplicate(true)

	for key in ["spall", "surface"]:
		if not def.has(key) and defaults.get(key, null) != null:
			def[key] = defaults[key]
	if def.get("surface", null) == null and defaults.get("surface", null) != null:
		def["surface"] = defaults["surface"]

	var merged: Dictionary = {}
	var class_resist: Variant = defaults.get("resist", null)
	if class_resist != null:
		merged = (class_resist as Dictionary).duplicate()
	for d in (def.get("resist", {}) as Dictionary):
		merged[d] = def["resist"][d]
	def["resist"] = merged
	return def


func _check_resist(where: String, cls: String, def: Dictionary) -> void:
	var r: Dictionary = def.get("resist", {})
	for d in r:
		if not damage_types.has(String(d)):
			errors.append("%s: resists `%s`, which is not a damage type. %s" % [
				where, d, str(damage_types)])
	if classes[cls].get("resist", null) != null:
		return
	# A class with no resistance row of its own — `other` — has to state all six. Better
	# than inventing a sixth row of MATERIAL-SPEC §3's table that nobody specified.
	var missing: Array[String] = []
	for d in damage_types:
		if not r.has(d):
			missing.append(d)
	if not missing.is_empty():
		errors.append("%s: class `%s` has no default resistances, so all six %s. Missing %s" % [
			where, cls, "have to be stated here", str(missing)])


func _check_fire(where: String, def: Dictionary) -> void:
	var flam := float(def.get("flammability", 0.0))
	var fire: Variant = def.get("fire", null)
	if flam > 0.0 and fire == null:
		errors.append("%s: flammability %.2f but no `fire` block — %s" % [
			where, flam, "how fast, how long, how far, and what it leaves"])
		return
	if fire == null:
		return
	if flam <= 0.0:
		errors.append("%s: has a `fire` block but flammability 0, so it never burns" % where)
	var on_burnt := String((fire as Dictionary).get("on_burnt", ""))
	if not ["ash", "charred", "gone"].has(on_burnt):
		errors.append("%s: `on_burnt` is `%s` — expected ash, charred or gone" % [
			where, on_burnt])


func _check_colour(where: String, def: Dictionary, palette: Palette) -> void:
	var col := StringName(def.get("colour", ""))
	if col == &"":
		errors.append("%s: no default `colour`" % where)
	elif not palette.has(col):
		errors.append("%s: default colour `%s` is not in the palette" % [where, col])

	var allow: Array = def.get("colour_allow", [])
	if allow.is_empty():
		errors.append("%s: no `colour_allow` — a material with no permitted colours %s" % [
			where, "can never be painted, including its own default"])
		return
	for c in allow:
		if not palette.has(StringName(c)):
			errors.append("%s: `colour_allow` names `%s`, not in the palette" % [where, c])
	if col != &"" and not allow.has(String(col)):
		errors.append("%s: default colour `%s` is not in its own `colour_allow`" % [where, col])


## `fire.becomes` and `fills_to` name other materials, and they are checked after the whole
## list is read because `timber` becoming `charred_timber` is a forward reference.
##
## That one mapping is load-bearing. MATERIAL-SPEC §6's siege mine is: prop a chalk gallery
## with timber, burn the props, and `charred_timber`'s support_vertical of 20 no longer
## holds the span, so the wall above comes down. If `becomes` does not resolve, that whole
## sequence silently stops being a thing the game can do.
func _check_transitions(path: String) -> void:
	for name in materials:
		var def: Dictionary = materials[name]
		var where := "%s: material `%s`" % [path, name]
		var becomes: Variant = (def.get("fire", {}) as Dictionary).get("becomes", null)
		if becomes != null and not materials.has(StringName(becomes)):
			errors.append("%s: burns into `%s`, which is not a material" % [where, becomes])
		var fills: Variant = def.get("fills_to", null)
		if fills != null and not materials.has(StringName(fills)):
			errors.append("%s: fills to `%s`, which is not a material" % [where, fills])
