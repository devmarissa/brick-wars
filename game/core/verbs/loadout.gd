class_name Loadout
extends RefCounted
## What a soldier is carrying, and therefore what they can do. CORE-SPEC §2, FORMAT-SPEC §7.
##
## `CHECKLIST` §4 states the shape in five words: **classes pick slots, packs fill them.** A class
## declares the archetype slots it goes into the field with — a rifle slot, a tool slot, something
## thrown — and a `kit` says which asset is in each one. An era pack writes its own classes naming
## its own weapons, and the core never learns what a Lee-Enfield is.
##
## ### The payoff: what a soldier can do is derived, never declared
##
## A class does not list verbs and could not if it wanted to. It lists slots; each slot already says
## which verbs dispatch it; so `verbs()` is the union of those, worked out rather than authored.
##
## That means a rifleman can `fire` because he carries something in `ranged_slow`, and can `dig`
## because the entrenching tool he carries is in `melee_light`, which C4's registry review put under
## both `melee` and `dig`. Nobody wrote "riflemen can dig" anywhere. Take the shovel out of his kit
## and he stops being able to, in the same edit, without a second list to keep in step.
##
## ### What this is not
##
## No inventory UI, no weapon switching, no ammunition pooling between slots. A loadout is what you
## came out of the dugout with, which is all C4 needs and all `CHECKLIST` §4 asks for. Carrying
## things around — hauling a crate forward from a dump — is the `carry` verb and is C7's, because it
## has no purpose until there is a supply chain that makes the walk worth making.

## A class going into the field with nothing is almost certainly an authoring mistake rather than a
## pacifist, so it is refused. The message says which, because "empty loadout" on its own sends
## somebody looking in the wrong file.
const MIN_SLOTS := 1

var owner_id := ""                  ## the class asset this was built from
var slots: Array[String] = []       ## archetype slots carried, in the order declared
var kit: Dictionary = {}            ## String slot -> String asset id
var state: Dictionary = {}          ## String slot -> that item's own `{ rounds, ready_at, held }`
var errors: Array[String] = []


## Build a loadout from a class asset. `find` is anything with `get_asset(id) -> ResolvedAsset`,
## which in practice is the resolver — passed in rather than reached for, so a test can hand over a
## fixture world and the core never holds a pointer to the content system.
static func of(class_asset: ResolvedAsset, find: AssetResolver, verbs: VerbSet,
		registry: SlotSet) -> Loadout:
	var out := Loadout.new()
	if class_asset == null:
		out.errors.append("a loadout needs a class to be built from")
		return out
	out.owner_id = class_asset.id

	for entry in class_asset.data.get("loadout", []):
		var slot := String(entry)
		if not registry.has(slot):
			out.errors.append("%s carries `%s`, which is not a slot in the registry" % [
				out.owner_id, slot])
			continue
		if out.slots.has(slot):
			out.errors.append("%s carries `%s` twice — %s" % [out.owner_id, slot,
				"one slot is one thing in one pair of hands"])
			continue
		out.slots.append(slot)

	if out.slots.size() < MIN_SLOTS:
		out.errors.append("%s declares no `loadout` — %s" % [out.owner_id,
			"a class with nothing in its hands is an authoring mistake rather than a pacifist"])

	out._fill(class_asset, find, registry)
	return out


## Everything this soldier can do, derived from what is in their hands. Sorted, deduplicated, and
## never authored anywhere.
func verbs(set: VerbSet) -> Array[String]:
	var found: Array[String] = []
	for slot in slots:
		for verb in set.verbs_for(slot):
			if not found.has(verb):
				found.append(verb)
	found.sort()
	return found


## Whether this soldier can do a thing — and, when they cannot, it is because of what they are
## carrying rather than because of a permission somebody set.
func can(set: VerbSet, verb: String) -> bool:
	return verbs(set).has(verb)


## The asset filling a slot, or "" for a slot declared and not filled. Both are legal: a class may
## carry an empty tool slot that a mode or a resupply fills later.
func item(slot: String) -> String:
	return String(kit.get(slot, ""))


func is_valid() -> bool:
	return errors.is_empty()


func _fill(class_asset: ResolvedAsset, find: AssetResolver, registry: SlotSet) -> void:
	var declared: Dictionary = class_asset.data.get("kit", {})
	for key in declared:
		var slot := String(key)
		var id := String(declared[key])
		if not slots.has(slot):
			errors.append("%s puts `%s` in `%s`, which it does not carry" % [owner_id, id, slot])
			continue

		var found := find.get_asset(id) if find != null else null
		if found == null:
			errors.append("%s puts `%s` in `%s` and there is no such asset" % [owner_id, id, slot])
			continue
		# The check that makes the whole arrangement hold: an asset goes in the slot it declares, not
		# the slot somebody wanted it in. Without this a class could put a horse in a rifle slot and
		# the first thing to notice would be `fire` reading a stat block that has no `velocity`.
		var its_slot := String(found.data.get("slot", ""))
		if its_slot != slot:
			errors.append("%s puts `%s` in `%s`, but that asset is a `%s`" % [
				owner_id, id, slot, its_slot if its_slot != "" else "slotless thing"])
			continue

		kit[slot] = id
		state[slot] = {}
