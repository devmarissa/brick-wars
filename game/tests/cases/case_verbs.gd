extends TestCase
## The interaction vocabulary: closed, core-owned, and reachable from every slot that needs it.
## CORE-SPEC §2, `verbs.json`.
##
## Two claims here are load-bearing for milestones that have not been built yet, which is why they
## are tested now rather than when they start mattering.
##
## **The vocabulary is closed.** CORE-SPEC: *"Packs cannot define new verbs. A pack wanting one is a
## core change request."* That constraint is what keeps the animation state machine finite
## (`ANIMATION-SPEC` has to have a state per action) and the netcode's action encoding finite (C8
## has to fit an action in a packet). Both degrade quietly rather than loudly when the list grows,
## so the refusal is tested at the one place a verb could enter.
##
## **Every usable slot is reachable by some verb.** A weapon slot no verb dispatches is an asset a
## pack can author, that the validator accepts, that fills a slot the core knows — and that nothing
## can ever do. Nothing fails. It simply does not work, which is the most expensive kind of wrong,
## and it is the failure mode a registry written before the system that uses it invites.

const FIXTURES := "res://tests/fixtures/verbs/"


func case_name() -> String:
	return "verbs"


func run(t: TestContext) -> void:
	var slots := SlotSet.new()
	if not slots.load_core():
		t.fail("the slot registry would not load, so nothing below means anything")
		return

	var set := VerbSet.new()
	t.ok(set.load_core(), "the core vocabulary loads: %s" % [", ".join(set.errors)])

	_the_ten(t, set)
	_which_ones_are_live(t, set)
	_a_slot_chooses_its_verbs(t, set)
	_nothing_is_unreachable(t, set, slots)
	_the_vocabulary_is_closed(t)


## Ten verbs, all described, each with an owner. The `milestone` field is not bookkeeping: a verb
## reserved to nobody is indistinguishable from a verb nobody has thought about, and the whole point
## of declaring the list up front is that the second kind cannot hide in it.
func _the_ten(t: TestContext, set: VerbSet) -> void:
	t.eq(VerbSet.VOCABULARY.size(), 10, "the vocabulary is ten verbs")
	t.eq(set.verbs.size(), 10, "and every one of them is described")
	for verb in VerbSet.VOCABULARY:
		var name := String(verb)
		t.ok(set.has(name), "`%s` is in the vocabulary" % name)
		t.ok(VerbSet.STATUSES.has(set.status_of(name)),
			"with a real status: %s is `%s`" % [name, set.status_of(name)])
		t.ok(set.milestone_of(name) != "", "and a milestone that owns it: %s" % set.milestone_of(name))


## What the core actually carries out, against what it only promises — and this literal is the point
## of the test rather than an incidental detail of it.
##
## A verb's status flips in the same diff that builds it and never ahead of it. The list below is
## therefore a running claim about HEAD rather than about the plan. Same device as
## `case_module_graph`'s stub literal, and it is here for the same reason — a data file that says a
## verb works when nothing carries it out is the drift the status field exists to catch, and it is
## exactly the drift that nothing else would notice.
func _which_ones_are_live(t: TestContext, set: VerbSet) -> void:
	t.eq(",".join(set.live_names()), "fire,throw,dig,build,melee",
		"exactly these verbs do something at HEAD")

	# Everything else, against the milestone that owns it. C4's own three sit here too, and moving
	# one of them out of this list is what building it looks like.
	t.eq(set.status_of("throw"), "partial",
		"`throw` is the one that is neither — it flies here and detonates in C5")
	t.ok(set.is_live("throw"), "and partial counts as live, because the verb does happen")

	for pair in [["enter", "C6"], ["man", "C6"], ["carry", "C7"], ["interact", "C7"],
			["signal", "C7"]]:
		var verb: String = pair[0]
		t.eq(set.status_of(verb), "reserved", "`%s` is declared and not built" % verb)
		t.eq(set.milestone_of(verb), String(pair[1]), "and %s owns it" % pair[1])


## The mechanism that makes "packs cannot define new verbs" true without anyone enforcing it: there
## is no `verb` field on an asset at all. A pack declares a slot, and the slot decides what can be
## done with the thing. So the question never reaches the content layer.
func _a_slot_chooses_its_verbs(t: TestContext, set: VerbSet) -> void:
	t.eq(",".join(set.verbs_for("ranged_slow")), "fire",
		"a bolt rifle is in `ranged_slow`, so the verb it offers is `fire` — nobody wrote that down")
	t.eq(",".join(set.verbs_for("explosive_thrown")), "throw", "a grenade offers `throw`")

	# Two verbs on one slot, which is the case that would have been designed away by anyone tidying.
	t.eq(",".join(set.verbs_for("melee_light")), "dig,melee",
		"an entrenching tool digs a hole and hits people, and it was issued because it does both")
	t.eq(",".join(set.verbs_for("gun_fixed")), "fire,man",
		"and manning a gun is a different verb from firing it, on the same object")

	t.ok(set.verbs_for("infantry").is_empty(),
		"a soldier offers no verbs — a character is who does the verb, not what it is done to")


## The check worth having: nothing in the registry is stranded. Run against the real core files,
## because a disagreement between two core files is not caught by either one on its own.
func _nothing_is_unreachable(t: TestContext, set: VerbSet, slots: SlotSet) -> void:
	var found := set.check_against(slots)
	t.ok(found.is_empty(),
		"every slot a verb names exists, and every usable slot has a verb: %s" % [
			"\n  ".join(found)])

	var wrong := VerbSet.new()
	wrong.load_core(FIXTURES + "unknown_slot.json")
	t.ok(_said(wrong.check_against(slots), "trebuchet"),
		"a verb dispatched by a slot the registry never heard of is caught")


## The refusals. Each has a fixture that is wrong on purpose, because a rule with no failing case is
## a comment.
func _the_vocabulary_is_closed(t: TestContext) -> void:
	var invented := VerbSet.new()
	t.ok(not invented.load_core(FIXTURES + "invented.json"),
		"an eleventh verb is refused rather than merged")
	t.ok(_said(invented.errors, "sprint"), "by name, so the author knows which one")
	t.ok(_said(invented.errors, "vocabulary is fixed"),
		"and told that this is a core change request rather than a typo")
	t.ok(not invented.has("sprint"), "and it does not end up in the vocabulary anyway")

	var status := VerbSet.new()
	t.ok(not status.load_core(FIXTURES + "bad_status.json"),
		"a status outside live/partial/reserved is refused")
	t.ok(_said(status.errors, "someday"), "naming the word that reads like a plan and commits to nothing")

	var owner := VerbSet.new()
	t.ok(not owner.load_core(FIXTURES + "no_milestone.json"),
		"and a verb with no milestone is refused")
	t.ok(_said(owner.errors, "gap"), "because a verb reserved to nobody is a gap wearing a promise")

	# The other direction, which is the one a careless edit actually causes: silently dropping a
	# verb. The vocabulary is in code, so the file is checked against it rather than the reverse.
	t.ok(_said(status.errors, "signal"),
		"a file that describes only some of the ten is refused for the ones it left out")


func _said(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false
