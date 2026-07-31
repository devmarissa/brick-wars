extends Node
## Runs every case and prints one machine-readable line at the end.
##
## `TEST_DONE` is the same sentinel the old build printed, kept deliberately: it is what
## `tools/check.sh` greps for and what the pre-push hook refuses on. The difference is that
## the old one printed two numbers from a scripted joyride through the map, and this one
## reports named cases with named failures.
##
## Cases are listed, not discovered, for the same reason modules are (`core/manifest.gd`):
## a test joining the suite should be visible in a diff. A test that silently stops running
## because a filename changed is worse than no test.

const CASES := [
	"res://tests/cases/case_jolt_config.gd",
	"res://tests/cases/case_module_graph.gd",
	"res://tests/cases/case_content_data.gd",
	"res://tests/cases/case_pack_order.gd",
	"res://tests/cases/case_extends.gd",
	"res://tests/cases/case_validator.gd",
	"res://tests/cases/case_refusal.gd",
	"res://tests/cases/case_geometry.gd",
	"res://tests/cases/case_builder.gd",
	"res://tests/cases/case_ground.gd",
	"res://tests/cases/case_earth_field.gd",
	"res://tests/cases/case_earth_mesh.gd",
	"res://tests/cases/case_earth_settle.gd",
	"res://tests/cases/case_c3_done.gd",
	"res://tests/cases/case_verbs.gd",
	"res://tests/cases/case_dig.gd",
	"res://tests/cases/case_fire.gd",
	"res://tests/cases/case_footing.gd",
	"res://tests/cases/case_locomotion.gd",
	"res://tests/cases/case_locomotion_rules.gd",
	"res://tests/cases/case_leg.gd",
	"res://tests/cases/case_driver.gd",
	"res://tests/cases/case_body.gd",
	"res://tests/cases/case_walker.gd",
	"res://tests/cases/case_rig.gd",
	"res://tests/cases/case_cli.gd",
	"res://tests/cases/case_bricks_fall.gd",
	"res://tests/cases/case_sleep_pattern.gd",
]

const EXIT_OK := 0
const EXIT_FAILED := 1


func _ready() -> void:
	await _run_all()


func _run_all() -> void:
	print("BRICK WARS test suite — Godot %s, %s" % [
		Engine.get_version_info().string, DisplayServer.get_name()])
	print("")

	var passed := 0
	var failed := 0
	var checks := 0

	for path in CASES:
		var script: GDScript = load(path)
		# A case that won't even parse must count as a failure and let the suite finish.
		# The first version of this loop called `new()` regardless, which threw, which
		# killed the coroutine before `quit()` — so a typo in one test file turned CI from
		# "one red line" into "hangs until the timeout kills it", which is a much worse
		# thing to be greeted by.
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  %-22s did not load — see the parse error above" % path.get_file())
			continue
		var case: TestCase = script.new()
		var t := TestContext.new(self)
		var started := Time.get_ticks_msec()

		await case.run(t)

		var ms := Time.get_ticks_msec() - started
		checks += t.checks
		if t.failures.is_empty():
			passed += 1
			print("  ok    %-22s %d checks, %d ms" % [case.case_name(), t.checks, ms])
		else:
			failed += 1
			print("  FAIL  %-22s %d checks, %d ms" % [case.case_name(), t.checks, ms])
			for f in t.failures:
				print("          - " + f)
		_clear_children()

	print("")
	print("TEST_DONE cases=%d passed=%d failed=%d checks=%d" % [
		CASES.size(), passed, failed, checks])
	get_tree().quit(EXIT_FAILED if failed > 0 else EXIT_OK)


## Cases build worlds. Between cases there must be nothing left of the last one, or a test
## passes because of something a previous test spawned — which is the failure mode that
## makes a suite worse than useless, because it fails only when you reorder it.
func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
