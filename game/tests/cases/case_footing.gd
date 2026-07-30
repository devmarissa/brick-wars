extends TestCase
## Foot planting and body tilt, checked against ground whose every height is known in
## advance. RIG-SPEC §4.
##
## The reason this case exists in the shape it does: planting is the part of the rig that
## fails *beautifully*. A leg that plants two centimetres into a slope, or a pelvis that
## stays level going uphill, produces a creature that moves smoothly and looks subtly wrong,
## and no screenshot will ever tell you which of the two it was. So none of it is judged by
## eye here. Every expected number below was worked out from `TestGround`'s constants by
## hand, and the interesting ones are the ones where the answer is *not* the ground height —
## the clamps, the caps and the drops, which is where the policy actually lives.
##
## `Footing` takes a probe rather than knowing about the ground, so the whole case runs
## against `TestGround.height_at` with no physics world at all. The last section is the
## exception and the point of it is to prove the two agree: a real downward raycast against
## the trimesh collider has to return the same surface the analytic function does, or every
## number above it is measured with a different ruler than the game uses.

const EPSILON := 0.0001

## A soldier's stance, near enough: the hip sits about 0.9 m up and the leg can chase the
## ground about 0.6 m from where the gait wanted the foot. Not read from any pack — these
## are the case's own numbers, so that a retune of `core:soldier` at #66 does not silently
## rewrite what this file is asserting.
const STAND := 0.9
const REACH := 0.6


func case_name() -> String:
	return "footing"


func run(t: TestContext) -> void:
	_planting(t)
	_out_of_range(t)
	_tilt(t)
	_yaw(t)
	_averaging(t)
	_standing_height(t)
	_support_count(t)
	await _against_real_physics(t)


## The probe every section but the last uses: `TestGround` as a pure function, answering the
## same three fields a raycast would. Off the map it misses, which is the honest answer —
## `height_at` keeps returning numbers out there and they mean nothing.
func _ground() -> Callable:
	return func(at: Vector3) -> Dictionary:
		if not TestGround.contains(at.x, at.z):
			return {"hit": false, "y": at.y, "normal": Vector3.UP}
		return {
			"hit": true,
			"y": TestGround.height_at(at.x, at.z),
			"normal": TestGround.normal_at(at.x, at.z),
		}


## Ground within reach: the foot goes exactly where the ground is, whatever the gait asked
## for, and reports how far it had to move.
func _planting(t: TestContext) -> void:
	var probe := _ground()

	var flat: Dictionary = Footing.plant(probe, Vector3(0.0, 0.5, 0.0), REACH)
	var flat_at: Vector3 = flat["position"]
	t.near(flat_at.y, 0.0, EPSILON, "a foot over flat ground lands on it, not where it was aimed")
	t.near(flat_at.x, 0.0, EPSILON, "and does not slide sideways getting there")
	t.ok(bool(flat["planted"]), "and counts as planted")
	t.near(float(flat["drop"]), 0.5, EPSILON, "having fallen the half metre it was held above")

	# Halfway up the ramp. The height is the easy half; the normal is the half a leg needs,
	# because the ankle is solved to it and a foot flat to the world on a hill floats at the
	# heel.
	var hill: Dictionary = Footing.plant(probe, Vector3(4.0, 1.0, 0.0), 0.8)
	t.near((hill["position"] as Vector3).y, 0.5, EPSILON, "and on the ramp it lands on the ramp")
	t.near(rad_to_deg((hill["normal"] as Vector3).angle_to(Vector3.UP)), 14.036, 0.01,
		"carrying the slope up to the ankle rather than a level normal")

	# The lip, which is the case a gradient cannot fake: two feet a metre apart, one up and
	# one down, and no single body height that satisfies both.
	var low: Dictionary = Footing.plant(probe, Vector3(-8.0, 0.45, 2.75), 0.5)
	var high: Dictionary = Footing.plant(probe, Vector3(-8.0, 0.45, 3.75), 0.5)
	t.near((low["position"] as Vector3).y, 0.0, EPSILON, "a foot short of the step stays down")
	t.near((high["position"] as Vector3).y, 0.4, EPSILON, "and one past it stands on top")
	t.ok(bool(low["planted"]) and bool(high["planted"]), "both of them planted")
	t.near(float(high["drop"]) - float(low["drop"]), -TestGround.LIP_RISE, EPSILON,
		"and the pair disagree by exactly the height of the step")


## The three ways a foot fails to find ground, which are the three the driver has to act on.
func _out_of_range(t: TestContext) -> void:
	var probe := _ground()

	# Below: swinging out over the bowl with a soldier's reach. The floor is 0.8 m down and
	# the leg is good for 0.6, so it hangs at the bottom of its range rather than stretching
	# into the hole — the failure that reads as a creature impaled on the terrain.
	var over := Footing.plant(probe, Vector3(-5.0, 0.0, -4.0), REACH)
	t.near((over["position"] as Vector3).y, -REACH, EPSILON,
		"a foot over a hollow deeper than its leg stops at full stretch")
	t.ok(not bool(over["planted"]), "and says it did not plant, rather than pretending")
	t.near(float(over["drop"]), REACH, EPSILON, "with the drop reported as the whole of its reach")

	# The same hollow with a longer leg reaches the bottom, which is what makes the line
	# above about `reach` and not about the bowl.
	var reaching := Footing.plant(probe, Vector3(-5.0, 0.0, -4.0), 1.0)
	t.near((reaching["position"] as Vector3).y, -TestGround.BOWL_DEPTH, EPSILON,
		"a longer leg finds the floor of the same hollow")
	t.ok(bool(reaching["planted"]), "and plants on it")

	# Above: a foot swinging into the face of a step finds ground above its own hip. Planting
	# there without a limit folds the leg up through the body.
	var into_step := Footing.plant(probe, Vector3(-8.0, 0.0, 3.75), 0.2)
	t.near((into_step["position"] as Vector3).y, 0.2, EPSILON,
		"a foot that finds ground above its own range stops at the top of it")
	t.ok(not bool(into_step["planted"]), "and is unplanted there too — the clamp cuts both ways")
	t.near(float(into_step["drop"]), -0.2, EPSILON, "with a negative drop, because it rose")

	# Nothing under it at all.
	var off_map := Footing.plant(probe, Vector3(20.0, 0.5, 0.0), REACH)
	t.near((off_map["position"] as Vector3).y, 0.5 - REACH, EPSILON,
		"a foot off the edge of the world hangs at the bottom of its range")
	t.ok(not bool(off_map["planted"]), "unplanted")
	t.ok((off_map["normal"] as Vector3).is_equal_approx(Vector3.UP),
		"with a level ankle, because there is no surface to match")


## Body tilt: `strength` is the author's dial, and both ends of it have to behave.
func _tilt(t: TestContext) -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	var slope := TestGround.normal_at(4.0, 0.0)

	var level := Footing.level([Vector3.UP, Vector3.UP], forward, 0.5)
	t.ok(level.is_equal_approx(Basis.IDENTITY),
		"flat ground and a forward of -Z is the identity, tilt strength notwithstanding")

	var ignored := Footing.level([slope, slope], forward, 0.0)
	t.near(rad_to_deg(ignored.y.angle_to(Vector3.UP)), 0.0, 0.01,
		"strength 0 holds the body level to the world however steep the ground is")

	var matched := Footing.level([slope, slope], forward, 1.0)
	t.near(rad_to_deg(matched.y.angle_to(Vector3.UP)), 14.036, 0.01,
		"strength 1 lays it flat along the ground")
	t.ok(matched.y.is_equal_approx(slope.normalized()),
		"exactly along it, rather than approximately")

	var half := Footing.level([slope, slope], forward, 0.5)
	t.near(rad_to_deg(half.y.angle_to(Vector3.UP)), 7.018, 0.01,
		"and half of it is half the angle, not half of some component")

	# The cap. The lip's face is 38.66°, past MAX_TILT, and a creature that matched it would
	# be lying on the step. Capped by shortening the interpolation, so the pose still
	# responds to the ground instead of sticking at the limit.
	var steep := TestGround.normal_at(-8.0, 3.25)
	var capped := Footing.level([steep], forward, 1.0)
	t.near(rad_to_deg(capped.y.angle_to(Vector3.UP)), Footing.MAX_TILT, 0.01,
		"a face steeper than MAX_TILT tilts the body only that far")
	t.ok(capped.y.angle_to(Vector3.UP) < steep.angle_to(Vector3.UP),
		"which is less than the ground under it, which is the whole point of a cap")

	# A basis with a bad up is a creature that renders inside out, so orthonormality is
	# checked rather than assumed anywhere a basis is built by hand.
	for b in [level, matched, half, capped]:
		var basis: Basis = b
		t.near(basis.determinant(), 1.0, 0.001, "and every basis it returns is right-handed")


## Tilting must never steer. A body that yawed as it crested a ridge would fight the driver
## every frame, and the drift is small enough per frame to look like bad input rather than
## like a bug in here.
func _yaw(t: TestContext) -> void:
	var travelling := Vector3(1.0, 0.0, 0.0)
	var slope := TestGround.normal_at(4.0, 0.0)
	var tilted := Footing.level([slope], travelling, 1.0)

	var heading := -tilted.z
	t.ok(Vector2(heading.x, heading.z).normalized().is_equal_approx(Vector2(1.0, 0.0)),
		"a body tilted onto a slope still faces the way it was travelling")
	t.ok(heading.y > 0.0, "and its nose comes up, because it is walking uphill")
	t.near(heading.dot(slope), 0.0, EPSILON, "with facing flattened against the new up, not into it")

	# Straight up is the degenerate input — a creature being dropped in, or on a ladder. Any
	# facing is as good as any other; the one that must not come back is a NaN.
	var vertical := Footing.facing(Vector3.UP, Vector3.UP)
	t.near(vertical.determinant(), 1.0, 0.001,
		"travelling straight up gives some valid facing rather than a hole in the transform")
	t.ok(vertical.y.is_equal_approx(Vector3.UP), "with the up it was asked for")


func _averaging(t: TestContext) -> void:
	# Four feet on the four faces of a hollow: the ground under each is steep, the animal
	# standing in it is level. Summing gets this right; slerping pairwise does not.
	var rim := 1.5
	var around: Array = []
	for offset in [Vector2(rim, 0.0), Vector2(-rim, 0.0), Vector2(0.0, rim), Vector2(0.0, -rim)]:
		around.append(TestGround.normal_at(-5.0 + offset.x, -4.0 + offset.y))
	t.ok(rad_to_deg((around[0] as Vector3).angle_to(Vector3.UP)) > 10.0,
		"the sides of the bowl are genuinely steep, so the next line is worth something")
	t.near(rad_to_deg(Footing.average(around).angle_to(Vector3.UP)), 0.0, 0.01,
		"and a creature standing across all four of them is level")

	t.ok(Footing.average([]).is_equal_approx(Vector3.UP),
		"nothing to average is answered `up`, not with a normalised zero")
	t.ok(Footing.average([Vector3.UP, Vector3.DOWN]).is_equal_approx(Vector3.UP),
		"and so is a set that cancels")


## How high the body rides. Two rules, and the second one wins.
func _standing_height(t: TestContext) -> void:
	var probe := _ground()
	var on_flat := [
		Footing.plant(probe, Vector3(0.0, 0.5, 0.0), REACH),
		Footing.plant(probe, Vector3(0.6, 0.5, 0.0), REACH),
	]
	t.near(Footing.support(on_flat, STAND, 1.0), STAND, EPSILON,
		"on level ground the body stands its own height above its feet")

	# One foot down in the bowl. The average would put the hip at 0.5, which leaves the low
	# foot 1.3 m below it and out of range — so the body comes down until it is not.
	var straddling_bowl := [
		Footing.plant(probe, Vector3(-5.0, 0.0, -4.0), 1.0),
		Footing.plant(probe, Vector3(-1.0, 0.0, -4.0), 1.0),
	]
	t.near(Footing.support(straddling_bowl, STAND, 1.0), 0.2, EPSILON,
		"with one foot in a hollow it crouches until the low leg can still reach")
	t.ok(Footing.support(straddling_bowl, STAND, 1.0) < STAND - 0.4,
		"which is well below the average, and downward — crouching reads, hovering does not")

	# Straddling the step, where the average is fine and the reach is the binding constraint
	# by a hair. Worth its own line because it is the case a naive average passes.
	var straddling_step := [
		Footing.plant(probe, Vector3(-8.0, 0.45, 2.75), 0.5),
		Footing.plant(probe, Vector3(-8.0, 0.45, 3.75), 0.5),
	]
	t.near(Footing.support(straddling_step, STAND, 1.0), 1.0, EPSILON,
		"and on a step the lower foot sets the height, at exactly full reach")

	t.near(Footing.support([], STAND, 1.0), 0.0, EPSILON, "no feet at all is not a crash")


## When the driver should stop solving and do something else. Half is the threshold, and
## the two halves are different animals, so both are stated.
func _support_count(t: TestContext) -> void:
	var down := {"planted": true, "position": Vector3.ZERO}
	var air := {"planted": false, "position": Vector3.ZERO}

	t.ok(Footing.unsupported([]), "a creature with no feet is standing on nothing by definition")
	t.ok(not Footing.unsupported([down, air, down, air]),
		"a quadruped with two legs down is mid-stride, not falling")
	t.ok(Footing.unsupported([down, air, air, air]),
		"one of four is a creature that has walked off something")
	t.ok(not Footing.unsupported([down, air]),
		"and a biped with one foot down is doing what bipeds do")
	t.ok(Footing.unsupported([air, air]), "both feet off is not")


## The one section that needs a world. Everything above is measured against `height_at`;
## the game will measure against a raycast. If those two disagree the tests are correct and
## the game is wrong, which is the worst way round for it to be.
func _against_real_physics(t: TestContext) -> void:
	var ground := TestGround.make()
	t.host.add_child(ground)
	await t.ticks(2)

	var space := ground.get_world_3d().direct_space_state
	var probe := Footing.raycast_probe(space, 2.0)

	var on_ramp: Dictionary = probe.call(Vector3(4.0, 0.5, 0.0))
	t.ok(bool(on_ramp["hit"]), "a downward cast finds the trimesh collider")
	t.near(float(on_ramp["y"]), TestGround.height_at(4.0, 0.0), 0.001,
		"at the height the analytic surface says it is")
	t.near(rad_to_deg((on_ramp["normal"] as Vector3).angle_to(TestGround.normal_at(4.0, 0.0))),
		0.0, 0.5, "facing the way the analytic surface says it faces")

	# Cast from below the surface rather than above it: the ray starts `reach` above the
	# point it was given, so a foot that has ended up slightly inside the ground still finds
	# the ground rather than missing everything and reporting a hole.
	var buried: Dictionary = probe.call(Vector3(4.0, 0.45, 0.0))
	t.ok(bool(buried["hit"]), "and a foot a little way inside the surface still finds it")

	var nothing: Dictionary = probe.call(Vector3(20.0, 0.5, 0.0))
	t.ok(not bool(nothing["hit"]), "past the edge of the map it misses, and says so")
	t.near(float(nothing["y"]), 0.5 - 2.0, EPSILON, "answering the bottom of its own range")

	# And the whole thing end to end: plant a foot through the physics probe and get the same
	# answer the analytic one gave at the top of this file.
	var planted := Footing.plant(probe, Vector3(4.0, 1.0, 0.0), 0.8)
	t.near((planted["position"] as Vector3).y, 0.5, 0.001,
		"so planting against physics lands where planting against the function did")
	t.ok(bool(planted["planted"]), "and plants")
