extends TestCase
## Damage, and the sweep that decides whether a shot ever arrives. CORE-SPEC §2.
##
## The load-bearing assertion is the contiguity one, and it is the least obvious.
##
## A bullet at 150 m/s covers **2.5 m per frame** at 60 Hz. The natural way to fly one — move it,
## ask what is at the new spot — therefore misses a brick wall about six times out of seven, and
## misses it *intermittently*, depending on where in the step the wall happened to fall. That does
## not read as a missing sweep. It reads as flaky netcode, and it gets debugged for a week two
## milestones later. So flight produces segments that share their endpoints, and the test walks a
## whole trajectory asserting there is no gap anywhere in it for a wall to hide in.
##
## The other line worth stating is where C4 stops. **C4 works out how much damage arrives; C5
## decides what the thing on the receiving end does about it.** A round carrying 95 kinetic into a
## plank is arithmetic. The plank splintering, spalling, catching fire or dropping the wall above it
## is material behaviour, which `BUILD-ORDER` gives C5 by name — so nothing here reads `failure`,
## `fire`, `support_vertical` or `cohesion`, though the material file has carried all four since C1.

const EPSILON := 0.0001


func case_name() -> String:
	return "damage"


func run(t: TestContext) -> void:
	var materials := _materials()
	if materials == null:
		t.fail("core materials would not load, so nothing below means anything")
		return

	_a_soldier_is_one_hit(t, materials)
	_materials_resist_by_type(t, materials)
	_falloff_is_learnable(t)
	_a_step_is_a_segment_not_a_position(t)
	_nothing_gets_through_the_gaps(t)


## `slots.json`'s `infantry` note: *"core owns a soldier's movement and health."* So the number is a
## constant no pack can raise, and one rifle round very nearly ends the argument — which is the
## design rather than an accident. Cover is the answer to being shot at, not a health pool.
func _a_soldier_is_one_hit(t: TestContext, materials: MaterialSet) -> void:
	var hit := Damage.to_body(Damage.SOLDIER_HEALTH, 95.0)
	t.near(float(hit["health"]), 5.0, EPSILON, "a rifle round takes a soldier to 5 of 100")
	t.ok(not hit["killed"], "and does not quite finish him")
	t.near(float(hit["dealt"]), 95.0, EPSILON, "having dealt all 95")

	var second := Damage.to_body(float(hit["health"]), 95.0)
	t.ok(second["killed"], "the second one does")
	t.near(float(second["dealt"]), 5.0, EPSILON, "dealing only the 5 that was left")
	t.near(float(second["overkill"]), 90.0, EPSILON,
		"and keeping the 90 it went past, because C5 decides whether that is a fall or a come-apart")

	var already := Damage.to_body(0.0, 50.0)
	t.ok(not already["killed"], "something already dead is not killed again")
	t.near(float(already["health"]), 0.0, EPSILON, "and does not go further below zero")
	t.near(float(Damage.to_body(100.0, -20.0)["dealt"]), 0.0, EPSILON,
		"and negative damage is not healing in disguise")


## The six damage types came in with the content pipeline at C1 and nothing had called them until
## now. They live in `materials.json` rather than in an `enum` here, which is what makes a seventh a
## data change instead of a code change.
func _materials_resist_by_type(t: TestContext, materials: MaterialSet) -> void:
	for type in ["kinetic", "blast", "crushing", "cutting", "fire", "dig"]:
		t.ok(Damage.is_a_type(materials, type), "`%s` is a damage type the game has" % type)
	t.ok(not Damage.is_a_type(materials, "sonic"),
		"and one it does not have is not one, without anybody maintaining a list in code")

	# Same shot, two materials, and the difference is entirely the material file — the identical
	# claim `fire` makes about weapons, one layer down.
	var into_plank := Damage.to_material(materials, &"plank", 95.0, "kinetic")
	var into_stone := Damage.to_material(materials, &"hard_stone", 95.0, "kinetic")
	t.ok(into_plank > into_stone,
		"a rifle round does more to a plank than to hard stone: %.1f against %.1f" % [
			into_plank, into_stone])
	t.ok(into_plank > 0.0 and into_stone >= 0.0, "and both are real numbers rather than nothing")

	t.near(Damage.to_material(materials, &"nonexistent", 95.0, "kinetic"), 95.0, EPSILON,
		"a material nobody declared resists nothing, loudly, rather than silently halving it")


## Linear rather than inverse-square, and the reason is a game reason rather than a physics one.
func _falloff_is_learnable(t: TestContext) -> void:
	t.near(Damage.falloff(0.0, 8.0), 1.0, EPSILON, "at the centre of a blast, all of it")
	t.near(Damage.falloff(4.0, 8.0), 0.5, EPSILON, "halfway out, half")
	t.near(Damage.falloff(8.0, 8.0), 0.0, EPSILON, "at the edge, none")
	t.near(Damage.falloff(20.0, 8.0), 0.0, EPSILON, "and past it, still none rather than negative")
	t.near(Damage.falloff(1.0, 0.0), 0.0, EPSILON, "a blast with no radius does nothing")

	# The property that makes it learnable: equal steps out cost equal damage. Inverse-square would
	# make the first metre worth more than the next four, so a grenade becomes a coin flip about
	# exactly where it stopped rolling rather than a thing to take cover from.
	var first := Damage.falloff(1.0, 10.0) - Damage.falloff(2.0, 10.0)
	var later := Damage.falloff(7.0, 10.0) - Damage.falloff(8.0, 10.0)
	t.near(first, later, EPSILON,
		"a metre of cover is worth the same wherever you take it: %.3f against %.3f" % [first, later])


## A step is a segment. The thing a position-only model throws away.
func _a_step_is_a_segment_not_a_position(t: TestContext) -> void:
	var step := Projectile.advance(Vector3.ZERO, Vector3(0.0, 0.0, -150.0), 1.0 / 60.0)
	t.near(float(step["length"]), 2.5, 0.01,
		"at 150 m/s a round covers 2.5 m in one frame — which is why this is a sweep")
	t.ok(Vector3(step["from"]).is_equal_approx(Vector3.ZERO), "the step knows where it started")
	t.ok(Vector3(step["velocity"]).y < 0.0, "and gravity has begun taking the velocity down")

	# An arrow is slower and still far too fast for a position check: 0.9 m a frame skips a plank
	# most of the time. The sweep is how hit detection works, not an optimisation for fast rounds.
	var arrow := Projectile.advance(Vector3.ZERO, Vector3(0.0, 0.0, -55.0), 1.0 / 60.0)
	t.ok(float(arrow["length"]) > 0.9,
		"and an arrow still covers %.2f m, which is three planks' worth" % arrow["length"])


## The assertion the whole approach rests on, and the one that is invisible in any single call:
## walk a full trajectory and check there is no gap anywhere in it.
func _nothing_gets_through_the_gaps(t: TestContext) -> void:
	var at := Vector3(0.0, 1.5, 0.0)
	var moving := Vector3(0.0, 0.0, -150.0)
	var covered := 0.0
	var breaks := 0
	var longest := 0.0

	for frame in 40:
		var pieces := Projectile.segments(at, moving, 1.0 / 60.0)
		t.ok(not pieces.is_empty(), "frame %d produces at least one segment" % frame)
		# Within a frame: each piece starts exactly where the last one ended.
		for i in pieces.size():
			var piece: Dictionary = pieces[i]
			longest = maxf(longest, float(piece["length"]))
			covered += float(piece["length"])
			if i > 0 and not Vector3((pieces[i - 1] as Dictionary)["to"]).is_equal_approx(
					Vector3(piece["from"])):
				breaks += 1
		# Across frames: the next frame is launched from exactly where this one finished, so the
		# join between two frames is no different from a join inside one.
		var last: Dictionary = pieces[pieces.size() - 1]
		if not Vector3((pieces[0] as Dictionary)["from"]).is_equal_approx(at):
			breaks += 1
		at = last["to"]
		moving = last["velocity"]

	t.eq(breaks, 0, "no gap anywhere along 40 frames of flight for a wall to hide in")
	t.ok(longest <= Projectile.MAX_SEGMENT + EPSILON,
		"and no single segment is longer than the cap: %.2f m" % longest)
	t.ok(covered > 90.0, "which covered %.0f m of ground" % covered)

	# A hitch is the case the cap exists for. A tenth of a second at 150 m/s is a 15 m step, and one
	# 15 m question to the physics engine is a different question from six 2.5 m ones.
	var hitched := Projectile.segments(Vector3.ZERO, Vector3(0.0, 0.0, -150.0), 0.1)
	t.ok(hitched.size() >= 4, "a hitched frame is cut into %d pieces rather than asked as one" % hitched.size())
	for piece in hitched:
		t.ok(float(piece["length"]) <= Projectile.MAX_SEGMENT + EPSILON,
			"each of them inside the cap")

	# And with no world to ask, a sweep misses rather than inventing a hit.
	var nowhere := Projectile.sweep(null, Vector3.ZERO, Vector3(0.0, 0.0, -10.0))
	t.ok(not nowhere["hit"], "sweeping with no physics space finds nothing rather than crashing")
	t.ok(Vector3(nowhere["position"]).is_equal_approx(Vector3(0.0, 0.0, -10.0)),
		"and reports the far end, so a caller can keep flying without checking for an empty result")


func _materials() -> MaterialSet:
	var palette := Palette.new()
	if not palette.load_core():
		return null
	var materials := MaterialSet.new()
	return materials if materials.load_core(palette) else null
