class_name VerbSet
extends RefCounted
## The interaction vocabulary: ten verbs, closed, core-owned. CORE-SPEC §2.
##
## > **Packs cannot define new verbs.** A pack wanting one is a core change request.
##
## That rule is not tidiness. A finite verb list is what keeps two other things finite: the
## animation state machine, which has to have a state for every action a body can be in
## (`ANIMATION-SPEC`), and the netcode's action encoding, which has to fit an action in a packet
## (C8). Both of those degrade quietly rather than loudly when the list grows — the state machine
## gains a fallback pose, the encoding gains a string — so the constraint is enforced at the one
## place a new verb could enter.
##
## ### Why the names are in code and the detail is in data
##
## `VOCABULARY` is a `const` here and `verbs.json` may not add to it or omit from it. This is the
## same split `SlotSet` makes with `KINDS`, for the same stated reason: a data file that *could*
## add a verb would imply a pack may, and a pack may not. The JSON carries what each verb is, which
## milestone owns it, and which archetype slots dispatch it — all things worth arguing about in a
## diff — while the list itself is a core change.
##
## ### A slot chooses its verbs, so a pack never names one
##
## There is no `verb` field on an asset, and deliberately so. A weapon declares its slot, and the
## slot decides what can be done with it. So a pack picks `ranged_slow` and thereby picks `fire`,
## and the question "what if a pack invents a verb" never arises at the content layer — there is
## nowhere to write one down. The refusal below catches the other direction: core data naming a
## verb that does not exist.
##
## A slot may appear under more than one verb, which is not a modelling failure. An entrenching
## tool is `melee_light`, and it both digs a hole and hits people; that is why it was issued.

const VERBS_PATH := "res://core/data/verbs.json"

## The vocabulary, closed. Ten verbs, in the order CORE-SPEC §2 lists them. Adding to this array is
## a core change and should be argued for in the diff that does it.
const VOCABULARY := ["fire", "throw", "dig", "build", "melee", "carry", "enter", "man",
	"interact", "signal"]

## What a verb's `status` may be. `partial` is a real state and not a hedge: `throw` has a live
## flight and a detonation C5 owns, and calling that either "live" or "reserved" would be a lie in
## one direction or the other.
const STATUSES := ["live", "partial", "reserved"]

var verbs: Dictionary = {}          ## String verb -> { status, milestone, what, slots, note }
var errors: Array[String] = []


func load_core(path := VERBS_PATH) -> bool:
	errors.clear()
	verbs.clear()
	_read(path)
	return errors.is_empty()


func has(verb: String) -> bool:
	return verbs.has(verb)


## True while the core will actually carry this verb out. `partial` counts as live — the verb runs,
## some of what it leads to does not — and the milestone note is where that is spelled out.
func is_live(verb: String) -> bool:
	var status := status_of(verb)
	return status == "live" or status == "partial"


func status_of(verb: String) -> String:
	return String((verbs.get(verb, {}) as Dictionary).get("status", ""))


func milestone_of(verb: String) -> String:
	return String((verbs.get(verb, {}) as Dictionary).get("milestone", ""))


func slots_for(verb: String) -> Array:
	return (verbs.get(verb, {}) as Dictionary).get("slots", [])


## Every verb an asset in this slot can dispatch, sorted. The lookup that matters at the content
## layer, and the reason an asset needs no `verb` field of its own.
func verbs_for(slot: String) -> Array[String]:
	var out: Array[String] = []
	for verb in verbs:
		if (slots_for(String(verb)) as Array).has(slot):
			out.append(String(verb))
	out.sort()
	return out


func live_names() -> Array[String]:
	var out: Array[String] = []
	for verb in VOCABULARY:
		if is_live(String(verb)):
			out.append(String(verb))
	return out


## Check the vocabulary against the slot registry: every slot a verb claims has to exist, and every
## slot that a soldier could pick up or climb into has to be reachable by some verb.
##
## The second half is the one worth having. A weapon slot no verb dispatches is an asset a pack can
## author, that the validator will accept, that fills a slot the core knows — and that nothing can
## ever do anything with. Nothing fails; it simply does not work, which is the most expensive kind
## of wrong.
func check_against(slots: SlotSet) -> Array[String]:
	var found: Array[String] = []
	for verb in VOCABULARY:
		for slot in slots_for(String(verb)):
			if not slots.has(String(slot)):
				found.append("verbs.json: `%s` names slot `%s`, which is not in the registry" % [
					verb, slot])

	for slot in slots.slots:
		var name := String(slot)
		var kind := slots.kind_of(name)
		# Characters are the actor rather than the object, and buildables are reached through
		# `build`, which is reserved — so both are exempt from needing a *live* verb, but not from
		# needing one at all.
		if kind == "character":
			continue
		if verbs_for(name).is_empty():
			found.append("slot `%s` (%s) is dispatched by no verb — nothing could ever use it" % [
				name, kind])
	return found


func _read(path: String) -> void:
	var data := ContentLoader.read_object(path, errors)
	if data.is_empty():
		return

	var table: Dictionary = data.get("verbs", {})
	for key in table:
		var name := String(key)
		if not VOCABULARY.has(name):
			errors.append("%s: `%s` is not a verb. The vocabulary is fixed: %s" % [
				path, name, ", ".join(VOCABULARY)])
			continue
		var entry: Variant = table[key]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: verb `%s` should be an object" % [path, name])
			continue
		var def: Dictionary = entry
		var status := String(def.get("status", ""))
		if not STATUSES.has(status):
			errors.append("%s: verb `%s` is `%s`, which is not one of: %s" % [
				path, name, status, ", ".join(STATUSES)])
			continue
		if String(def.get("milestone", "")) == "":
			errors.append("%s: verb `%s` names no milestone — a reserved verb with no owner %s" % [
				path, name, "is a gap, which is the thing this file exists to make visible"])
			continue
		verbs[name] = {
			"status": status,
			"milestone": String(def.get("milestone", "")),
			"what": String(def.get("what", "")),
			"slots": _string_list(def.get("slots", [])),
			"note": String(def.get("note", "")),
		}

	for verb in VOCABULARY:
		if not verbs.has(String(verb)):
			errors.append("%s: the vocabulary has `%s` and this file does not describe it" % [
				path, verb])


static func _string_list(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(String(item))
	return out
