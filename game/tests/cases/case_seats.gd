extends TestCase
## Seats, and the two verbs that fill them. C6, FORMAT-SPEC §7, CORE-SPEC §2.
##
## The horse's own file has carried a promise since C2:
##
## > `prop` rather than `vehicle`, and that is a deliberate under-claim. A horse IS a fast transport
## > vehicle with legs, and it should become one... **It changes kind at C6, when there is something
## > to sit on it.**
##
## There is now, so it did. `testpack:horse` is a `vehicle` in the `mount` slot — a **pack** asset
## filling a core slot with no core change, which is the horse test's actual claim and the reason
## `mount` has been in the registry since C1 with a note saying so.
##
## The other thing being tested is a distinction drawn at C4 and unenforceable until today: `enter`
## and `man` are different verbs because *a crew station is a role rather than a ride*. Neither
## file knows which is which — the slot's own verb list decides, so a mount answers to `enter` and a
## crewed gun answers to `man`, and adding a new kind of ridable thing is a data change.

const EPSILON := 0.0001


func case_name() -> String:
	return "seats"


func run(t: TestContext) -> void:
	var world := FixtureWorld.load_root("res://packs")
	if world.is_empty():
		t.fail("core content would not load, so nothing below means anything")
		return
	var set := VerbSet.new()
	var registry := SlotSet.new()
	if not (set.load_core() and registry.load_core()):
		t.fail("core data would not load")
		return
	var horse := FixtureWorld.asset(world, "testpack:horse")
	t.ok(horse != null, "`testpack:horse` exists")
	if horse == null:
		return

	_the_horse_kept_its_promise(t, horse, registry)
	_somebody_gets_on(t, set, horse)
	_and_the_two_verbs_are_not_interchangeable(t, set, horse)
	_a_seat_table_can_be_wrong(t)
	_a_vehicle_may_not_wear_a_props_budget(t, registry)


## The C2 promise, kept — and it is a *pack* asset filling a *core* slot.
func _the_horse_kept_its_promise(t: TestContext, horse: ResolvedAsset, registry: SlotSet) -> void:
	t.eq(String(horse.data.get("kind", "")), "vehicle", "the horse is a vehicle now")
	t.eq(String(horse.data.get("slot", "")), "mount", "in the slot that has named it since C1")
	t.eq(registry.kind_of("mount"), "vehicle", "and `mount` is a vehicle slot")
	t.ok(horse.id.begins_with("testpack:"),
		"out of a pack rather than core, which is the horse test's whole point")

	# The stat block agrees with the gait table. If it did not, a rider could ask for a speed the
	# legs have no gait for, and the horse would skate — the exact failure C2 spent a day on.
	var stats: Dictionary = horse.data.get("stats", {})
	var gaits: Array = (horse.data.get("locomotion", {}) as Dictionary).get("gaits", [])
	var fastest := 0.0
	for gait in gaits:
		fastest = maxf(fastest, float((gait as Dictionary)["speed"][1]))
	t.near(float(stats["max_speed"]), fastest, EPSILON,
		"and `max_speed` %.0f is the top of the gallop band rather than an invented number" % fastest)

	var seats := Seats.of(horse)
	t.ok(seats.is_valid(), "its seat table loads: %s" % [", ".join(seats.errors)])
	t.eq(seats.count(), 1, "one seat")
	t.eq(seats.role_of(0), Seats.DRIVER, "and a rider steers, so the seat is the driver's")
	t.ok(seats.eye_of(0).y > 1.5,
		"with the eye on its back at %.2f m rather than at its origin" % seats.eye_of(0).y)
	t.ok(not seats.controls_of(0).is_empty(),
		"and named controls for C6's IK to reach for: %s" % [", ".join(seats.controls_of(0))])


func _somebody_gets_on(t: TestContext, set: VerbSet, horse: ResolvedAsset) -> void:
	var seats := Seats.of(horse)
	var rider := "rider"
	var got := Verbs.dispatch(set, "enter", {
		"seats": seats, "who": rider, "verbs": set, "slot": "mount" })
	t.ok(got["ok"], "a rider gets on: %s" % got["why"])
	var seat: Dictionary = got["seat"]
	t.ok(seat["driving"], "and is driving, because the seat they took is the driver's")
	t.eq(seats.occupied(), 1, "the horse has somebody on it")

	t.ok(not Verbs.dispatch(set, "enter", {
		"seats": seats, "who": rider, "verbs": set, "slot": "mount" })["ok"],
		"the same rider cannot mount twice")
	var second := Verbs.dispatch(set, "enter", {
		"seats": seats, "who": "another", "verbs": set, "slot": "mount" })
	t.ok(not second["ok"], "and a second rider finds no free seat")
	t.ok(String(second["why"]).contains("no free"), "saying so: %s" % second["why"])

	# Reach, when the caller asks for it. A rider across the field is not getting on.
	var far := Seats.of(horse)
	var away := Verbs.dispatch(set, "enter", {
		"seats": far, "who": rider, "verbs": set, "slot": "mount",
		"reach": 2.0, "at": Vector3.ZERO, "from": Vector3(9, 0, 0) })
	t.ok(not away["ok"], "somebody nine metres away cannot climb on")
	t.ok(String(away["why"]).contains("too far"), "and is told why: %s" % away["why"])

	var off := VerbEnter.leave({ "seats": seats, "who": rider })
	t.ok(off["ok"], "getting off works")
	t.eq(seats.occupied(), 0, "and frees the seat")
	t.ok(not VerbEnter.leave({ "seats": seats, "who": rider })["ok"],
		"getting off twice does not")


## The C4 distinction, enforced by data rather than by either verb's code.
func _and_the_two_verbs_are_not_interchangeable(t: TestContext, set: VerbSet,
		horse: ResolvedAsset) -> void:
	var seats := Seats.of(horse)
	var crewed := Verbs.dispatch(set, "man", {
		"seats": seats, "who": "gunner", "verbs": set, "slot": "mount" })
	t.ok(not crewed["ok"], "you do not `man` a horse")
	t.ok(String(crewed["why"]).contains("enter"),
		"and the refusal names what it does answer to: %s" % crewed["why"])

	var ridden := Verbs.dispatch(set, "enter", {
		"seats": seats, "who": "rider", "verbs": set, "slot": "gun_crewed" })
	t.ok(not ridden["ok"], "and you do not `enter` a field gun")
	t.ok(String(ridden["why"]).contains("man"), "symmetrically: %s" % ridden["why"])

	# Neither rule is in either verb's file. `verbs.json` says which slots each reaches, so a new
	# kind of ridable thing is a data change and this code never hears about it.
	t.eq(",".join(set.verbs_for("mount")), "enter", "a mount offers `enter` and nothing else")
	t.eq(",".join(set.verbs_for("gun_crewed")), "fire,man",
		"and a crewed gun offers `man` — and `fire`, because working it and firing it differ")


func _a_seat_table_can_be_wrong(t: TestContext) -> void:
	var two := ResolvedAsset.new()
	two.id = "test:tandem"
	two.data = { "seats": [ {"role": "driver"}, {"role": "driver"} ] }
	var doubled := Seats.of(two)
	t.ok(not doubled.is_valid(), "two seats claiming to drive is refused")
	t.ok(doubled.errors[0].contains("not a seating arrangement"),
		"because that is not a seating arrangement: %s" % doubled.errors[0])

	var nameless := ResolvedAsset.new()
	nameless.id = "test:bench"
	nameless.data = { "seats": [ {"eye": [0, 10, 0]} ] }
	t.ok(not Seats.of(nameless).is_valid(), "and a seat with no role is refused")

	# A vehicle with no seats at all is legal — a towed gun limber is a vehicle nobody sits in — so
	# this is empty rather than invalid, which is a different thing and worth being explicit about.
	var towed := ResolvedAsset.new()
	towed.id = "test:limber"
	towed.data = { "kind": "vehicle" }
	var none := Seats.of(towed)
	t.ok(none.is_valid(), "a vehicle with no seats is legal — a towed limber is nobody's ride")
	t.eq(none.free_seat(), -1, "and simply has nowhere to sit")


## Found by this increment rather than looked for: the horse wore `large_prop` from C2, became a
## vehicle, and **nothing complained**. `budget_for` accepted any named row without checking the row
## covered the kind — so a vehicle was being measured against a limit written for props.
func _a_vehicle_may_not_wear_a_props_budget(t: TestContext, registry: SlotSet) -> void:
	t.ok(registry.budget_for("vehicle", "large_prop").is_empty(),
		"a vehicle declaring a prop's budget class is refused")
	t.ok(registry.budget_for("prop", "large_prop").has("max"), "while a prop declaring it is fine")
	t.ok(registry.classes_for("vehicle").has("mount"),
		"and there is a row a horse actually fits: %s" % [", ".join(registry.classes_for("vehicle"))])

	# `vehicle_light` starts at 30 because it was written for a jeep. A quadruped needing 30 parts
	# would be a quadruped nobody could afford forty of, which is why `mount` exists as its own row.
	var mount := registry.budget_for("vehicle", "mount")
	t.ok(int(mount["min"]) < 30, "a mount runs %d–%d rather than a light vehicle's 30–50" % [
		mount["min"], mount["max"]])
