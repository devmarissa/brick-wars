extends TestCase
## Two of C0's four done-conditions, measured rather than eyeballed: a world spawns, and
## the bricks in it fall and then stop.
##
## "Then stop" is the half that matters. Bricks falling is free; bricks *settling* is the
## thing that decides whether a battlefield with ten thousand of them costs anything to
## have sitting there. If this case ever starts failing, the frame rate has already died
## and this is the reason.
##
## What changed at C1 is where the wall comes from. It used to be three constants and a
## nested loop in `greybox.gd`; it is now `packs/core/wall_sandbag.json`, read, resolved,
## validated and built by the same pipeline a workshop upload goes through. The numbers
## below are unchanged on purpose — same hundred and fourteen bricks, same settle budget —
## so if this case still passes, the format bought the whole of C0 back.

const Sandbox := preload("res://core/mode/sandbox.gd")

const WALL := "core:wall_sandbag"

## Six courses: three full ones of 10 and three staggered ones of 9, two bricks deep. The
## staggered courses are short on purpose — real masonry ends them short rather than hanging
## the last brick over nothing. Spelled out rather than counted off the file, because a test
## that recomputes the thing it is checking agrees with any mistake in it.
const EXPECTED_BRICKS := 114        # (3 × 10 + 3 × 9) × 2
const SETTLE_LIMIT_TICKS := 480     # 8 seconds at 60 Hz — generous; it takes about two
const CHECK_EVERY := 10


func case_name() -> String:
	return "bricks fall + settle"


func run(t: TestContext) -> void:
	var kernel := t.boot_kernel({
		&"physics": CoreManifest.MODULES[&"physics"],
		&"content": CoreManifest.MODULES[&"content"],
	})
	var physics := kernel.get_module(&"physics")
	var content := kernel.get_module(&"content")
	if physics == null or content == null:
		t.fail("physics and content did not both boot, so nothing else here can mean anything")
		return

	t.host.add_child(Sandbox.make_ground())

	var wall: BuiltAsset = Sandbox.build_asset(content, WALL)
	if wall == null:
		t.fail("`%s` did not build — the pack is disabled or the asset was renamed" % WALL)
		return
	# The same drop the sandbox uses: just above rest, so it settles rather than explodes.
	wall.position = Vector3(0.0, Sandbox.DROP_HEIGHT, 0.0)
	t.host.add_child(wall)

	var bricks := wall.bodies
	t.eq(bricks.size(), EXPECTED_BRICKS, "the wall in the JSON file spawns the bricks it claims to")
	t.eq(physics.count_bricks(), EXPECTED_BRICKS, "physics agrees about how many exist")

	# A structure is a stack of bodies, not one slab — which is the only reason a wall can
	# come apart. If `body` ever stops defaulting to bricks for structures, the count above
	# reads 1 and this line is what says why.
	t.eq(AssetBuilder.body_mode_of(content.resolver.get_asset(WALL)), "bricks",
		"and a structure comes apart into them rather than standing as one slab")

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
