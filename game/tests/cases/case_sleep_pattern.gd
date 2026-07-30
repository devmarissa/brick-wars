extends TestCase
## The delayed-sleep pattern, which is the single most expensive thing the old build taught
## us and the easiest to lose in a refactor.
##
## Setting `sleeping = true` on a body that has not yet entered the physics space is
## silently discarded. Not warned about — discarded. So the obvious code (spawn a thousand
## bricks for a map, put them all to sleep) produces a thousand *awake* bricks, and the
## symptom is a frame rate that is fine in a test scene and terrible in a real map. Days
## went into finding that. `PhysicsModule.SLEEP_DELAY_TICKS` is the fix, and this is the
## test that stops someone deleting it because it "looks like a workaround".
##
## Both halves are checked in empty space with no ground under them, which makes the
## question unambiguous: an asleep brick is exactly where you left it, and an awake one has
## fallen. No thresholds, no settling, nothing to argue about.

const SPAWN := Vector3(0, 40, 0)
const BRICK := Vector3(1.0, 0.5, 0.5)
const COLOUR := Color("9a8a68")
const WATCH_TICKS := 30


func case_name() -> String:
	return "delayed sleep"


func run(t: TestContext) -> void:
	var kernel := t.boot_kernel({&"physics": CoreManifest.MODULES[&"physics"]})
	var physics := kernel.get_module(&"physics")
	if physics == null:
		t.fail("physics module did not boot")
		return

	var proper: RigidBody3D = physics.spawn_brick(SPAWN, BRICK, COLOUR, true)
	var naive: RigidBody3D = physics.spawn_brick(SPAWN + Vector3(4, 0, 0), BRICK, COLOUR)
	naive.sleeping = true    # the obvious way, and the wrong one

	t.ok(not proper.sleeping,
		"a brick asked to spawn asleep is still awake on the frame it spawns")

	await t.ticks(physics.SLEEP_DELAY_TICKS + 2)
	t.ok(proper.sleeping, "and is asleep a couple of ticks later, once it exists to physics")

	await t.ticks(WATCH_TICKS)
	t.near(proper.global_position.y, SPAWN.y, 0.01,
		"the properly-slept brick has not moved after half a second of gravity")
	t.ok(naive.global_position.y < SPAWN.y - 1.0,
		"the naively-slept brick fell — proving the immediate assignment was discarded, "
		+ "which is the entire reason SLEEP_DELAY_TICKS exists")
