class_name AssetRules
extends RefCounted
## Everything FORMAT-SPEC §10 says about a whole asset, once its parts have been checked.
##
## The per-part rules next door answer "is this part legal". These answer the questions
## that only make sense about the assembled thing: is it mostly bricks, does it declare
## more colliders than the physics budget allows, is it the size an asset of its class is
## supposed to be, does it fill a slot the core actually has, and does it supply the numbers
## that slot needs to behave.
##
## The 70/30 rule and the part budgets are the two that look like taste and are not. A
## vehicle that is mostly cylinders has stopped being a brick vehicle, and an asset four
## times its class's part count is a frame-rate problem that arrives at the worst possible
## moment — in a hundred-player event, in someone else's pack.

const BLOCK_RATIO := 0.7
const MAX_COLLIDERS := 4

## What to point at when the complaint is about the document as a whole — a field that is
## missing has no line of its own, and `id` is the one field every asset file has. The line
## after it is where the missing one belonged, which is close enough to be useful and honest
## about being an anchor rather than the mistake itself.
const ANCHOR := "id"

const KNOWN_FIELDS := ["format", "id", "extends", "kind", "name", "class", "parts",
	"collider", "hollow", "destructible", "mass", "body", "slot", "stats", "anim", "cost",
	"locomotion", "seats", "tags"]

var errors: Array[String] = []
var warnings: Array[String] = []


func check(asset: ResolvedAsset, at: Callable, slots: SlotSet) -> void:
	var data := asset.data
	var kind := asset.kind()

	if kind == "":
		errors.append("%s — no `kind`. It is one of: %s (FORMAT-SPEC §6)" % [
			at.call("", ANCHOR), ", ".join(SlotSet.KINDS)])
	elif not SlotSet.KINDS.has(kind):
		errors.append("%s — `%s` is not a kind: %s. %s (FORMAT-SPEC §6)" % [
			at.call("", "kind"), kind, ", ".join(SlotSet.KINDS),
			"A new kind means new gameplay code, so it is a core change and not a pack one"])
	if asset.name() == "":
		warnings.append("%s — no `name`, so it will be listed by its id" % at.call("", ANCHOR))

	_check_parts_present(asset, at)
	_check_block_ratio(asset, at)
	_check_colliders(asset, at)
	_check_body(asset, at)
	_check_budget(asset, at, slots, kind)
	_check_slot(asset, at, slots, kind)

	for key in data:
		if not KNOWN_FIELDS.has(String(key)):
			warnings.append("%s — `%s` is not an asset field, so it is ignored" % [
				at.call("", String(key)), key])


## Part names have to be unique, because `parts~` patches by name and `parent` refers by
## name. Two parts called `wheel` make both of those ambiguous, and the way that shows up
## is a variant three packs downstream silently patching the wrong one.
func check_names(asset: ResolvedAsset, at: Callable) -> void:
	var seen: Dictionary = {}
	for part in asset.parts():
		if typeof(part) != TYPE_DICTIONARY or not part.has("name"):
			continue
		var name := String(part["name"])
		if seen.has(name):
			errors.append("%s — two parts are called `%s`. %s (FORMAT-SPEC §5)" % [
				at.call(name, "name"), name,
				"Names are how `parts~` and `parent` find a part, so they have to be unique"])
		seen[name] = true


func _check_parts_present(asset: ResolvedAsset, at: Callable) -> void:
	if not asset.data.has("parts"):
		errors.append("%s — no `parts`. An asset is a part table (FORMAT-SPEC §6)" % at.call("", ANCHOR))
		return
	if typeof(asset.data["parts"]) != TYPE_ARRAY:
		errors.append("%s — `parts` should be a list of part objects (FORMAT-SPEC §6)" % [
			at.call("", "parts")])
		return
	if asset.parts().is_empty():
		errors.append("%s — `parts` is empty, so there is nothing to build" % at.call("", "parts"))


## ART-BIBLE §1b: at least 70% of any asset's parts are blocks. The primitives exist to make
## a gun barrel read as a gun barrel, not to turn the game into generic low-poly.
func _check_block_ratio(asset: ResolvedAsset, at: Callable) -> void:
	var parts := asset.parts()
	if parts.is_empty():
		return
	var blocks := 0
	for part in parts:
		if typeof(part) == TYPE_DICTIONARY and String(part.get("shape", "block")) == "block":
			blocks += 1
	var ratio := float(blocks) / float(parts.size())
	if ratio < BLOCK_RATIO:
		errors.append("%s — %d of %d parts are blocks (%d%%), and the floor is %d%%. %s" % [
			at.call("", "parts"), blocks, parts.size(), int(roundf(ratio * 100.0)),
			int(BLOCK_RATIO * 100.0),
			"A vehicle that is mostly cylinders has stopped being a brick vehicle (ART-BIBLE §1b)."])


## Colliders are declared, never derived, always blocks, and capped at four. This is the
## compound-collider lesson from the tank written into the format so it cannot be repeated:
## a hull that collides as its forty visual parts is forty convex shapes in the broad phase
## for a thing a player experiences as one box.
func _check_colliders(asset: ResolvedAsset, at: Callable) -> void:
	if not asset.data.has("collider"):
		# With none declared, the builder fits a single box around the whole asset. That is the
		# right default — the alternative is a crate a player walks through — but it is a bad
		# thing to do silently: an envelope around a crate is the crate, and an envelope around
		# a rifle is a box of air with a rifle somewhere inside it. Only `single` assets are
		# affected; a stack of bricks collides as its bricks and needs nothing declared.
		if AssetBuilder.body_mode_of(asset) == "single":
			warnings.append("%s — no `collider`, so one box is fitted round the whole asset. %s" % [
				at.call("", ANCHOR),
				"That is right for a crate and wrong for anything with a barrel or a gap in it (FORMAT-SPEC §6)"])
		return
	var list: Variant = asset.data["collider"]
	if typeof(list) != TYPE_ARRAY:
		errors.append("%s — `collider` should be a list (FORMAT-SPEC §6)" % at.call("", "collider"))
		return

	var colliders: Array = list
	if colliders.size() > MAX_COLLIDERS:
		errors.append("%s — %d colliders, and the cap is %d. %s (FORMAT-SPEC §6)" % [
			at.call("", "collider"), colliders.size(), MAX_COLLIDERS,
			"Hand-fit a compound of at most four boxes; a shape per visual part is what this rule exists to stop"])

	for i in colliders.size():
		var where := "%s — collider %d" % [at.call("", "collider"), i + 1]
		if typeof(colliders[i]) != TYPE_DICTIONARY:
			errors.append("%s: should be an object with an `offset` and a `size`" % where)
			continue
		var collider: Dictionary = colliders[i]
		var shape := String(collider.get("shape", "block"))
		if shape != "block":
			errors.append("%s: is a `%s`. %s (ART-BIBLE §1b)" % [where, shape,
				"Colliders are always blocks — a visual primitive does not imply a matching collider"])
		for field in ["offset", "size"]:
			if not collider.has(field):
				errors.append("%s: no `%s`" % [where, field])
			elif typeof(collider[field]) != TYPE_ARRAY or (collider[field] as Array).size() != 3:
				errors.append("%s: `%s` should be three whole modules" % [where, field])


## Whether the asset is one rigid body or one body per part. Not in FORMAT-SPEC §6's table
## yet — the spec has nothing to say about body granularity, and a wall has to come apart or
## it is a slab that tips over in one piece. An unknown value is refused rather than quietly
## defaulted, because both settings look fine standing still and differ only under fire.
func _check_body(asset: ResolvedAsset, at: Callable) -> void:
	if not asset.data.has("body"):
		return
	var mode := String(asset.data["body"])
	if AssetBuilder.BODY_MODES.has(mode):
		return
	errors.append("%s — `body` is `%s`, and it is one of: %s. %s" % [
		at.call("", "body"), mode, ", ".join(AssetBuilder.BODY_MODES),
		"`single` is one body colliding as its declared boxes; `bricks` is a body per part, which is what lets a wall come down brick by brick"])


func _check_budget(asset: ResolvedAsset, at: Callable, slots: SlotSet, kind: String) -> void:
	var parts := asset.parts()
	if parts.is_empty() or not SlotSet.KINDS.has(kind):
		return

	var declared := String(asset.data.get("class", ""))
	var budget := slots.budget_for(kind, declared)
	if budget.is_empty():
		errors.append("%s — `%s` is not a part budget for a %s. It is one of: %s (ART-BIBLE §5)" % [
			at.call("", "class"), declared, kind, ", ".join(slots.classes_for(kind))])
		return

	var count := parts.size()
	if count > int(budget["max"]):
		errors.append("%s — %d parts, and a %s runs %d–%d. %s (ART-BIBLE §5)" % [
			at.call("", "parts"), count, budget["class"], budget["min"], budget["max"],
			"Detail goes into form, not decoration: remove a greeble and improve the outline"])
	elif count < int(budget["min"]) and budget["declared"]:
		# Under budget is a note, not a refusal. A two-part sign is minimal, and minimal is a
		# legitimate thing for an asset to be; the spec only refuses exceeding it.
		warnings.append("%s — %d parts, and a %s usually runs %d–%d (ART-BIBLE §5)" % [
			at.call("", "parts"), count, budget["class"], budget["min"], budget["max"]])


## FORMAT-SPEC §7. A slot is a promise about behaviour, so filling one that does not exist
## is an asset that nothing in core knows how to operate, and omitting a stat the slot needs
## is a weapon that fires at an unspecified rate.
func _check_slot(asset: ResolvedAsset, at: Callable, slots: SlotSet, kind: String) -> void:
	var slot := String(asset.data.get("slot", ""))
	if not slots.takes_a_slot(kind):
		if slot != "":
			warnings.append("%s — a %s fills no slot, so `slot` is ignored (FORMAT-SPEC §7)" % [
				at.call("", "slot"), kind])
		return

	if slot == "":
		errors.append("%s — no `slot`. A %s fills one of: %s (FORMAT-SPEC §7)" % [
			at.call("", ANCHOR), kind, ", ".join(slots.slots_for(kind))])
		return
	if not slots.has(slot):
		errors.append("%s — `%s` is not a slot. A %s fills one of: %s (FORMAT-SPEC §7)" % [
			at.call("", "slot"), slot, kind, ", ".join(slots.slots_for(kind))])
		return
	if slots.kind_of(slot) != kind:
		errors.append("%s — `%s` is a %s slot and this is a %s. %s" % [
			at.call("", "slot"), slot, slots.kind_of(slot), kind,
			"A %s fills one of: %s (FORMAT-SPEC §7)" % [kind, ", ".join(slots.slots_for(kind))]])
		return

	var stats: Dictionary = asset.data.get("stats", {}) if \
		typeof(asset.data.get("stats")) == TYPE_DICTIONARY else {}
	var missing: Array[String] = []
	for stat in slots.requires(slot):
		if not stats.has(String(stat)):
			missing.append(String(stat))
	if not missing.is_empty():
		errors.append("%s — `%s` needs %s, and %s missing. %s (FORMAT-SPEC §7)" % [
			at.call("", "stats"), slot, ", ".join(slots.requires(slot)),
			"%s is" % missing[0] if missing.size() == 1 else "%s are" % ", ".join(missing),
			"Core owns the field list for a slot, because core is what operates it"])

	# An invented stat is a warning and is ignored, not a refusal — the pack still works, it
	# just does not do the thing its author thought it was asking for, and saying so is how
	# they find out before their players do.
	for key in stats:
		if not slots.knows_stat(slot, String(key)):
			warnings.append("%s — `%s` is not a stat of `%s`, so it is ignored (FORMAT-SPEC §7)" % [
				at.call("", "stats"), key, slot])
