extends TestCase
## The world going quiet again. C5's done-condition, last clause.
##
## *"...and the world is back to zero awake bodies within seconds."*
##
## Easy to read past, and it is a correctness claim rather than a performance one. A siege that
## never reaches zero is a siege whose frame budget is spent on rubble nobody is looking at, and
## the failure is gradual — it does not break, it just gets worse for twenty minutes.
##
## The rule that actually delivers it is the forced sleep, and the reason is specific: a brick
## wedged against two others can jitter *below* the speed anybody would call moving and *above* the
## threshold Jolt calls asleep, indefinitely. Nothing is visibly happening and it is not free. So
## the test that matters here is not "does debris get cleaned up" but "does a body that will never
## settle on its own get put to sleep anyway".

const EPSILON := 0.0001


func case_name() -> String:
	return "debris"


func run(t: TestContext) -> void:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	if not (palette.load_core() and materials.load_core(palette)):
		t.fail("core materials would not load, so nothing below means anything")
		return

	await _it_only_touches_what_it_was_given(t, materials, palette)
	await _a_body_that_will_not_settle_is_put_to_sleep(t, materials, palette)
	await _resting_debris_is_cleared_and_moving_debris_is_not(t, materials, palette)
	_the_cap_is_a_constant(t)


## The safety property, first: a cleanup policy that deleted things it was not given would be a far
## worse bug than a slow frame. A wall somebody built is theirs.
func _it_only_touches_what_it_was_given(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	var stage := _stage(t)
	var debris := Debris.of()
	stage.add_child(debris)

	var mine := Brick.spawn(stage, Vector3(0, 0.3, 0), Basis.IDENTITY, Vector3(0.5, 0.5, 0.5),
		&"mud", Vector3.ZERO, materials, palette)
	var theirs := Brick.spawn(stage, Vector3(2, 0.3, 0), Basis.IDENTITY, Vector3(0.5, 0.5, 0.5),
		&"mud", Vector3.ZERO, materials, palette)
	debris.track(mine)
	await t.ticks(4)

	t.eq(debris.tracking(), 1, "only the piece it was handed is tracked")
	debris.sweep()
	t.ok(is_instance_valid(theirs), "and a brick nobody handed it is untouched")
	t.ok(is_instance_valid(mine), "as is fresh debris, which has not outlived anything yet")

	stage.queue_free()


## The one that delivers the clause. A body held awake artificially is asleep after the timeout
## whatever the physics engine thinks.
func _a_body_that_will_not_settle_is_put_to_sleep(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	var stage := _stage(t)
	var debris := Debris.of()
	stage.add_child(debris)

	var restless := Brick.spawn(stage, Vector3(0, 0.3, 0), Basis.IDENTITY, Vector3(0.5, 0.5, 0.5),
		&"mud", Vector3.ZERO, materials, palette)
	debris.track(restless)
	await t.ticks(4)

	# Held awake on purpose, which is what a wedged brick does to itself for free.
	restless.sleeping = false
	debris._clock += Debris.FORCE_SLEEP_AFTER * 0.5
	debris.sweep()
	t.ok(not restless.sleeping,
		"a body awake for half the grace period is left alone — a real collapse takes seconds")
	t.eq(debris.forced, 0, "and nothing has been forced yet")

	debris._clock += Debris.FORCE_SLEEP_AFTER
	debris.sweep()
	t.ok(restless.sleeping, "but one still awake past the grace period is put to sleep")
	t.eq(debris.forced, 1, "and says that it had to")
	t.eq(debris.awake_count(), 0, "so the world reaches zero awake bodies, which is the clause")

	stage.queue_free()


## The lifetime runs from when a piece *stopped*, not from when it was made. Debris that vanished
## mid-flight is the single most noticeable way a cleanup policy announces itself.
func _resting_debris_is_cleared_and_moving_debris_is_not(t: TestContext, materials: MaterialSet,
		palette: Palette) -> void:
	var stage := _stage(t)
	var debris := Debris.of()
	stage.add_child(debris)

	var flying := Brick.spawn(stage, Vector3(0, 6.0, 0), Basis.IDENTITY, Vector3(0.5, 0.5, 0.5),
		&"mud", Vector3(0, 4.0, 0), materials, palette)
	debris.track(flying)
	await t.ticks(4)

	# Old enough to be culled if birth were the clock, and still in the air.
	debris._clock += Debris.LIFETIME * 2.0
	flying.sleeping = false
	debris.sweep()
	t.ok(is_instance_valid(flying),
		"debris older than its lifetime but still moving is not culled — it would vanish mid-air")
	t.eq(debris.culled, 0, "nothing cleared yet")

	# Now let it rest, and start the clock that actually counts.
	flying.sleeping = true
	debris.sweep()
	t.ok(is_instance_valid(flying), "the moment it stops, its lifetime begins rather than ends")
	debris._clock += Debris.LIFETIME + 1.0
	debris.sweep()
	await t.ticks(2)
	t.ok(not is_instance_valid(flying), "and once it has lain there long enough, it is cleared")
	t.eq(debris.culled, 1, "counted, so a report can say how much was tidied away")

	stage.queue_free()


## The cap is what turns "how long can a siege run" from a question into a constant.
func _the_cap_is_a_constant(t: TestContext) -> void:
	t.ok(Debris.CAP > 120,
		"the cap is above one heavy shell's worth of rubble (%d), or the aftermath of a single" % [
			Debris.CAP] + " blast would be eaten while somebody watched it")
	t.ok(Debris.LIFETIME > 10.0, "debris lies where it fell long enough to walk over and look at")
	t.ok(Debris.FORCE_SLEEP_AFTER > 5.0,
		"and a genuine collapse cascading through a structure is never cut short")
	t.ok(Debris.FORCE_SLEEP_AFTER < Debris.LIFETIME,
		"while everything is asleep well before anything is removed, so the world goes quiet" +
		" before it goes tidy")


func _stage(t: TestContext) -> Node3D:
	var stage := Node3D.new()
	t.host.add_child(stage)
	var pad := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	pad.add_child(shape)
	pad.position = Vector3(0.0, -0.5, 0.0)
	stage.add_child(pad)
	return stage
