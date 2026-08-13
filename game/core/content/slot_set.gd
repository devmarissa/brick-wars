class_name SlotSet
extends RefCounted
## The archetype slot registry and the part-count budgets. FORMAT-SPEC §7, ART-BIBLE §5.
##
## A slot is a promise about behaviour rather than a category: everything in `ranged_slow`
## is aimed, cycled and reloaded by the same core code, whether it is a musket, a bolt
## rifle or a crossbow. That is what makes eras data — a pack that fills an existing slot
## gets working gameplay without core learning anything about the era it came from.
##
## Core owns the field list for each slot. A pack that invents a stat gets a warning and
## the stat is ignored, which is the same rule as colours, materials and animation states
## and holds for the same reason: identity is a pack's to define, behaviour is not.
##
## The budgets live here too because they are asked the same question at the same moment —
## "is this asset allowed to be what it says it is" — and a second loader for two dozen
## numbers would be ceremony.

const SLOTS_PATH := "res://core/data/slots.json"
const BUDGETS_PATH := "res://core/data/budgets.json"

## Every `kind` in FORMAT-SPEC §6. Kept here rather than in the JSON because a new kind is
## a core change — it means new gameplay code — and a data file that could add one would
## imply otherwise.
const KINDS := ["prop", "structure", "weapon", "vehicle", "buildable", "character",
	"emplacement"]

var slots: Dictionary = {}          ## String slot -> { kind, requires, optional, note }
var slotless: Array[String] = []    ## kinds that fill no slot at all
var rows: Dictionary = {}           ## String class -> { min, max, kinds }
var errors: Array[String] = []


func load_core(slots_path := SLOTS_PATH, budgets_path := BUDGETS_PATH) -> bool:
	errors.clear()
	slots.clear()
	slotless.clear()
	rows.clear()
	_read_slots(slots_path)
	_read_budgets(budgets_path)
	return errors.is_empty()


func has(slot: String) -> bool:
	return slots.has(slot)


func kind_of(slot: String) -> String:
	return String((slots.get(slot, {}) as Dictionary).get("kind", ""))


func requires(slot: String) -> Array:
	return (slots.get(slot, {}) as Dictionary).get("requires", [])


func knows_stat(slot: String, stat: String) -> bool:
	var def: Dictionary = slots.get(slot, {})
	return (def.get("requires", []) as Array).has(stat) \
		or (def.get("optional", []) as Array).has(stat)


func takes_a_slot(kind: String) -> bool:
	return KINDS.has(kind) and not slotless.has(kind)


## Slot names for a kind, sorted — what an unknown slot's error message offers instead.
func slots_for(kind: String) -> Array[String]:
	var out: Array[String] = []
	for slot in slots:
		if kind_of(String(slot)) == kind:
			out.append(String(slot))
	out.sort()
	return out


## The part budget an asset is held to: its declared class if it named one, otherwise the
## widest envelope across every row its kind can be. The envelope still catches the
## four-hundred-part crate; declaring a class is how an author asks for the tight check.
func budget_for(kind: String, declared: String) -> Dictionary:
	if declared != "":
		if not rows.has(declared):
			return {}
		var row: Dictionary = rows[declared]
		# The row also has to *cover this kind*. Without this a vehicle could declare `large_prop`
		# and be measured against a prop's budget — which is not a near miss, it is being held to a
		# limit written for a different category of thing entirely. Found at C6 when the horse became
		# a mount and kept the prop class it had worn since C2, and nothing said a word.
		if not (row["kinds"] as Array).has(kind):
			return {}
		return { "min": row["min"], "max": row["max"], "class": declared, "declared": true }

	var lo := -1
	var hi := -1
	var names: Array[String] = []
	for name in rows:
		var row: Dictionary = rows[name]
		if not (row["kinds"] as Array).has(kind):
			continue
		names.append(String(name))
		lo = int(row["min"]) if lo < 0 else mini(lo, int(row["min"]))
		hi = maxi(hi, int(row["max"]))
	if hi < 0:
		return {}
	names.sort()
	return { "min": lo, "max": hi, "class": " or ".join(names), "declared": false }


func classes_for(kind: String) -> Array[String]:
	var out: Array[String] = []
	for name in rows:
		if ((rows[name] as Dictionary)["kinds"] as Array).has(kind):
			out.append(String(name))
	out.sort()
	return out


func _read_slots(path: String) -> void:
	var data := ContentLoader.read_object(path, errors)
	if data.is_empty():
		return

	for kind in data.get("slotless_kinds", []):
		slotless.append(String(kind))

	var table: Dictionary = data.get("slots", {})
	for key in table:
		var name := String(key)
		var entry: Variant = table[key]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: slot `%s` should be an object" % [path, name])
			continue
		var def: Dictionary = entry
		var kind := String(def.get("kind", ""))
		if not KINDS.has(kind):
			errors.append("%s: slot `%s` is for kind `%s`, which is not one of: %s" % [
				path, name, kind, ", ".join(KINDS)])
			continue
		if slotless.has(kind):
			errors.append("%s: slot `%s` is for kind `%s`, which fills no slot" % [
				path, name, kind])
			continue
		slots[name] = {
			"kind": kind,
			"requires": _string_list(def.get("requires", [])),
			"optional": _string_list(def.get("optional", [])),
			"note": String(def.get("note", "")),
		}

	if slots.is_empty():
		errors.append("%s: no slots — every gameplay asset has to fill one" % path)


func _read_budgets(path: String) -> void:
	var data := ContentLoader.read_object(path, errors)
	if data.is_empty():
		return

	var table: Dictionary = data.get("rows", {})
	for key in table:
		var name := String(key)
		var entry: Variant = table[key]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: budget row `%s` should be an object" % [path, name])
			continue
		var row: Dictionary = entry
		var lo := int(row.get("min", 0))
		var hi := int(row.get("max", 0))
		if lo <= 0 or hi < lo:
			errors.append("%s: budget row `%s` is %d–%d, which is not a range" % [
				path, name, lo, hi])
			continue
		var kinds := _string_list(row.get("kinds", []))
		for kind in kinds:
			if not KINDS.has(kind):
				errors.append("%s: budget row `%s` names kind `%s`, which does not exist" % [
					path, name, kind])
		rows[name] = { "min": lo, "max": hi, "kinds": kinds }

	# Every kind that can hold parts needs somewhere to be measured against, or an asset of
	# that kind is silently unbudgeted — which is exactly the state ART-BIBLE §5 exists to
	# stop, and it would go unnoticed because nothing would ever fail.
	for kind in KINDS:
		if classes_for(kind).is_empty():
			errors.append("%s: nothing budgets kind `%s`" % [path, kind])


static func _string_list(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(String(item))
	return out
