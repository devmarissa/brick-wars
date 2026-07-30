extends TestCase
## The three proven physics values (BUILD-ORDER §1a).
##
## These are not preferences. They came out of the old build after real time spent finding
## them, and they are the reason a thousand bricks are affordable and a settled wall stays
## settled. A drift in any of them shows up as "the game feels wrong now" weeks later, by
## which point nobody thinks to open a `.godot` file — so it is a test, and it is the first
## one, because if this is wrong nothing measured after it means anything.

const REQUIRED := {
	"physics/3d/physics_engine": "Jolt Physics",
	"physics/3d/default_gravity": 20.0,
	"physics/jolt_physics_3d/simulation/sleep_velocity_threshold": 0.35,
}


func case_name() -> String:
	return "jolt config"


func run(t: TestContext) -> void:
	for key in REQUIRED:
		t.eq(ProjectSettings.get_setting(key, null), REQUIRED[key],
			"project setting %s" % key)

	# And that the physics module agrees, since it is the thing that will actually refuse
	# to run — a check nothing enforces at runtime is a comment with extra steps.
	var kernel := t.boot_kernel({&"physics": CoreManifest.MODULES[&"physics"]})
	var physics := kernel.get_module(&"physics")
	t.ok(physics != null, "physics module boots on its own")
	if physics == null:
		return
	t.ok(physics.settings_ok, "physics module accepts the settings: " + physics.settings_problem)
