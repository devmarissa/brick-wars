class_name Verbs
extends RefCounted
## Dispatch: the one door every interaction goes through. CORE-SPEC §2.
##
## A verb is asked for by name, checked against the vocabulary, and either carried out or refused
## with a reason. Everything a soldier can do to the world arrives here, which is what makes the
## list in `VerbSet.VOCABULARY` worth being closed — a single door with ten keys is a thing you can
## reason about, animate, encode into a packet and replay. Ten doors is not.
##
## ### Refusing a reserved verb is a feature
##
## Six of the ten verbs are declared and unbuilt. Asking for one gets a refusal that names the
## milestone that owns it, rather than a silent no-op or a crash. That matters more than it sounds:
## the alternative is content authored against a verb that does nothing, which looks like working
## content until somebody plays it. The refusal is the difference between "not yet" and "broken",
## and the caller can tell them apart.
##
## ### What this does not do
##
## No input. Nothing here reads a key, and BUILD-ORDER schedules no input layer at C4 — the
## done-condition is *"a weapon defined in data fires"*, which a test can ask for directly. This is
## the same shape as C2, where `Walker` drove locomotion with nobody at the controls, and C3, where
## `DemoGround` dug a trench with no spade in anyone's hands.

## What a dispatch returns. Always these keys, always this shape, so a caller never has to ask
## whether a field is there before reading it.
const REFUSED := { "ok": false, "why": "", "moved_cm": 0 }


## Ask for a verb. `request` carries whatever that verb needs; what it needs is documented on the
## verb's own file, not here, because a dispatcher that knew every verb's arguments would be the
## 1,500-line `main.gd` this project exists to not rebuild.
static func dispatch(set: VerbSet, verb: String, request: Dictionary) -> Dictionary:
	if not set.has(verb):
		return _no("`%s` is not a verb. The vocabulary is fixed: %s" % [
			verb, ", ".join(VerbSet.VOCABULARY)])
	if not set.is_live(verb):
		return _no("`%s` is declared and not built — %s owns it. %s" % [
			verb, set.milestone_of(verb),
			"This is a refusal rather than a no-op so content authored against it fails loudly."])

	match verb:
		"dig":
			return VerbDig.perform(request)
		"fire":
			return VerbFire.perform(request)
		"melee":
			return VerbMelee.perform(request)
		"throw":
			return VerbThrow.perform(request)
		_:
			# Reachable only if a verb is marked live in `verbs.json` and nothing here carries it
			# out — which is the exact drift the status field exists to prevent, so it is loud.
			return _no("`%s` says it is live and dispatch has no arm for it. %s" % [
				verb, "One of `verbs.json` and `verbs.gd` is lying; they disagree."])


static func _no(why: String) -> Dictionary:
	var out := REFUSED.duplicate()
	out["why"] = why
	return out
