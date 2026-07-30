extends TestCase
## Two of C0's four done-conditions, measured rather than eyeballed: a world spawns, and
## the bricks in it fall and then stop.
##
## "Then stop" is the half that matters. Bricks falling is free; bricks *settling* is the
## thing that decides whether a battlefield with ten thousand of them costs anything to
## have sitting there. If this case ever starts failing, the frame rate has already died
## and this is the reason.

const Greybox := preload("res://core/mode/greybox.gd")

## 3 full courses of 10 + 3 staggered courses of 9, two bricks deep. The staggered courses
## are short on purpose (see Greybox._add_wall) — spelled out rather than derived from the
## same constants the code uses, because a test that recomputes the thing it is checking
## agrees with any bug you write into it.
const EXPECTED_BRICKS := 114        # (3 × 10 + 3 × 9) × 2
const SETTLE_LIMIT_TICKS := 480     # 8 seconds at 60 Hz — generous; it takes about two
const CHECK_EVERY := 10


func case_name() -> String:
	return "bricks fall + settle"


func run(t: TestContext) -> void:
	var kernel := t.boot_kernel({&"physics": CoreManifest.MODULES[&"physics"]})
	var physics := kernel.get_module(&"physics")
	if physics == null:
		t.fail("physics module did not boot, nothing else in this case can mean anything")
		return

	var world := Greybox.new()
	t.host.add_child(world)
	var bricks: Array = world.build(physics)

	t.eq(bricks.size(), EXPECTED_BRICKS, "the grey box wall spawns the bricks it claims to")
	t.eq(physics.count_bricks(), EXPECTED_BRICKS, "physics agrees about how many exist")

	var start_y: Array[float] = []
	for b in bricks:
		start_y.append(b.global_position.y)

	# They are dropped from just above rest, so movement should be visible almost at once.
	await t.ticks(6)
	var moved := 0
	for i in bricks.size():
		if bricks[i].global_position.y < start_y[i] - 0.001:
			moved += 1
	t.ok(moved > 0, "bricks actually fall — %d of %d moved within 6 ticks" % [moved, bricks.size()])

	var ticks_taken := 0
	while ticks_taken < SETTLE_LIMIT_TICKS and physics.count_awake() > 0:
		await t.ticks(CHECK_EVERY)
		ticks_taken += CHECK_EVERY

	t.eq(physics.count_awake(), 0,
		"the whole wall is asleep within %.1f s" % (float(SETTLE_LIMIT_TICKS) / 60.0))
	print("        settled in %.2f s of simulated time" % (float(ticks_taken) / 60.0))

	# A brick under the floor means collision is not doing its job, and a brick fifty metres
	# away means the drop is exploding the wall instead of settling it. Either one turns
	# every later measurement into noise, so both are checked here rather than assumed.
	var below := 0
	var scattered := 0
	for b in bricks:
		if b.global_position.y < -0.5:
			below += 1
		if absf(b.global_position.x) > 20.0 or absf(b.global_position.z) > 20.0:
			scattered += 1
	t.eq(below, 0, "no brick fell through the ground")
	t.eq(scattered, 0, "no brick was flung off the plate — the wall settles, it doesn't burst")
