class_name Palette
extends RefCounted
## The game's colour identity, loaded from `core/data/palette.json` and enforced.
##
## ART-BIBLE §2's rule is that no asset introduces a new colour. That rule is worth exactly
## as much as the code that refuses one, so: parts name a colour from this list or they
## take the default their material supplies, and a hex literal in a pack is a refusal.
##
## The laws — saturation under 0.35, value between `#1a1a16` and `#a5a5a5` — are checked
## against this file itself at load. Seven of the twenty core colours break one, which is
## why exemptions exist and why an exemption has to carry a reason. A limit that the data
## it governs quietly ignores is not a limit; a limit with seven named exceptions is a
## limit and a short argument you can read.
##
## Packs cannot add colours here. What they get is faction colours, whose *shape* core
## fixes — exactly two factions, one colour and one shadow each, only ever on soldiers and
## vehicles — so that faction-readability code is written once and never touched again.

const CORE_PATH := "res://core/data/palette.json"
const LAWS := ["saturation", "value"]

var id: StringName = &""
var colours: Dictionary = {}      ## StringName -> Color
var uses: Dictionary = {}         ## StringName -> String, what the colour is for
var exemptions: Dictionary = {}   ## StringName -> { laws: Array[String], why: String }
var law: Dictionary = {}
var faction: Dictionary = {}
var reserved: Dictionary = {}
var errors: Array[String] = []


## Load and validate the core palette. Returns false having filled `errors` — every
## problem at once, not the first one.
func load_core(path := CORE_PATH) -> bool:
	errors.clear()
	colours.clear()
	uses.clear()
	exemptions.clear()

	var data := ContentLoader.read_object(path, errors)
	if data.is_empty():
		return false

	id = StringName(data.get("id", ""))
	law = data.get("law", {})
	faction = data.get("faction", {})
	reserved = data.get("reserved", {})

	if law.is_empty():
		errors.append("%s: no `law` block — the palette laws are what this file is for" % path)
		return false

	var entries: Variant = ContentLoader.require(data, "colours", path, TYPE_DICTIONARY, errors)
	if entries == null:
		return false

	for name in entries:
		_read_colour(path, StringName(name), entries[name])

	if colours.is_empty() and errors.is_empty():
		errors.append("%s: the palette is empty" % path)

	return errors.is_empty()


func has(name: StringName) -> bool:
	return colours.has(name)


## The colour, or magenta. Magenta is deliberate: it is the one hue the palette laws
## forbid outright, so a missing colour is visible from across the room rather than being
## a slightly-wrong brown among forty other browns.
func colour(name: StringName) -> Color:
	if not colours.has(name):
		push_error("no colour named '%s' in the palette. %s" % [
			name, "Add it to core/data/palette.json in a review, with a name and a use."])
		return Color.MAGENTA
	return colours[name]


func use_of(name: StringName) -> String:
	return uses.get(name, "")


## Alphabetical, via ContentLoader.sorted_names — `Array[StringName].sort()` sorts by
## interned pointer, not by text.
func names() -> Array[StringName]:
	return ContentLoader.sorted_names(colours.keys())


func is_exempt(name: StringName, which: String) -> bool:
	if not exemptions.has(name):
		return false
	return (exemptions[name]["laws"] as Array).has(which)


func why_exempt(name: StringName) -> String:
	if not exemptions.has(name):
		return ""
	return exemptions[name]["why"]


## Every colour that had to be let off a law, alphabetically. The number of these is a
## project health signal: one or two is a palette with character, and half the file is a
## law that needs rewriting rather than exempting.
func exempt_names() -> Array[StringName]:
	return ContentLoader.sorted_names(exemptions.keys())


func _read_colour(path: String, name: StringName, entry: Variant) -> void:
	var where := "%s: colour `%s`" % [path, name]
	if typeof(entry) != TYPE_DICTIONARY:
		errors.append("%s: should be an object with a `hex` and a `use`" % where)
		return

	var hex: Variant = ContentLoader.require(entry, "hex", where, TYPE_STRING, errors)
	if hex == null:
		return
	if not _is_hex(hex):
		errors.append("%s: `%s` is not a colour — expected `#rrggbb`" % [where, hex])
		return

	var c := Color(hex)
	var broken := _laws_broken(c)
	var claimed: Array = []
	var why := ""

	if entry.has("exempt"):
		if typeof(entry["exempt"]) != TYPE_ARRAY:
			errors.append("%s: `exempt` should be a list of law names, %s" % [
				where, str(LAWS)])
			return
		claimed = entry["exempt"]
		why = String(entry.get("why", ""))
		for l in claimed:
			if not LAWS.has(String(l)):
				errors.append("%s: exempt from `%s`, which is not a law. Laws are %s" % [
					where, l, str(LAWS)])
		if law.get("exempt_requires_why", true) and why.strip_edges() == "":
			errors.append("%s: exempt from %s with no `why`. %s" % [where, str(claimed),
				"An exception nobody had to justify is just a limit that does not apply."])

	for l in broken:
		if not claimed.has(l):
			errors.append("%s: breaks the %s law (%s) and claims no exemption. %s" % [
				where, l, _measured(c, l),
				"Repaint it, or exempt it and say why."])

	for l in claimed:
		if not broken.has(String(l)):
			errors.append("%s: exempt from the %s law but does not break it (%s). %s" % [
				where, l, _measured(c, String(l)),
				"Stale exemptions are how a law stops meaning anything."])

	colours[name] = c
	uses[name] = String(entry.get("use", ""))
	if not claimed.is_empty():
		exemptions[name] = { "laws": claimed, "why": why }


func _laws_broken(c: Color) -> Array[String]:
	var out: Array[String] = []
	if c.s > float(law.get("saturation_max", 1.0)) + 0.0005:
		out.append("saturation")
	var v_max := float(law.get("value_max", 1.0))
	var v_min := float(law.get("value_min", 0.0))
	if c.v > v_max + 0.0005 or c.v < v_min - 0.0005:
		out.append("value")
	return out


func _measured(c: Color, which: String) -> String:
	if which == "saturation":
		return "%.3f against a limit of %.3f" % [c.s, float(law.get("saturation_max", 1.0))]
	return "%.3f against a range of %.3f to %.3f" % [
		c.v, float(law.get("value_min", 0.0)), float(law.get("value_max", 1.0))]


func _is_hex(s: String) -> bool:
	if s.length() != 7 or not s.begins_with("#"):
		return false
	for i in range(1, 7):
		if not s[i].is_valid_hex_number():
			return false
	return true
