extends TestCase
## The kernel: boot order, the dependency guard, and the three ways a manifest can be wrong.
##
## This is the case that earns its keep twice. C1 needs exactly this algorithm again for
## pack `extends` chains (FORMAT-SPEC §6), and the cheapest possible place to get the shape
## wrong is here, against thirteen modules we wrote, rather than there, against a workshop
## full of packs written by people who will not read the error message.

const CYCLE_A := "res://tests/fixtures/cycle_a_module.gd"
const CYCLE_B := "res://tests/fixtures/cycle_b_module.gd"
const LONELY := "res://tests/fixtures/lonely_module.gd"
const MISNAMED := "res://tests/fixtures/misnamed_module.gd"


func case_name() -> String:
	return "module graph"


func run(t: TestContext) -> void:
	_full_boot(t)
	_determinism(t)
	_boundary_guard(t)
	_bad_manifests(t)


func _full_boot(t: TestContext) -> void:
	var k := t.boot_kernel(CoreManifest.MODULES)
	t.eq(k.boot_error, "", "full manifest boots")
	t.eq(k.order.size(), CoreManifest.MODULES.size(), "every module in the boot order")

	# Dependency order is the only ordering promise the kernel makes to a module author.
	var at := {}
	for i in k.order.size():
		at[k.order[i]] = i
	for name in k.modules:
		for dep in k.modules[name].module_depends():
			t.ok(at[dep] < at[name], "%s starts before %s that depends on it" % [dep, name])

	t.eq(k.stub_names().size(), 10, "ten modules still honestly declare themselves stubs")


## Two kernels, same manifest, same order — every time, on every machine.
##
## `Array[StringName].sort()` does not give you this: StringName compares by pointer, so
## sorting names produces allocation order. The first boot of this kernel printed
## "vfx, audio, net, ai, ..." and looked plausible enough to keep. Hence this test.
func _determinism(t: TestContext) -> void:
	var a := t.boot_kernel(CoreManifest.MODULES)
	var b := t.boot_kernel(CoreManifest.MODULES)
	t.eq(", ".join(a.order), ", ".join(b.order), "boot order is identical between runs")

	var independent: Array[String] = ["ai", "audio", "combat", "earth", "net", "physics"]
	var got: Array[String] = []
	for i in mini(independent.size(), a.order.size()):
		got.append(String(a.order[i]))
	t.eq(got, independent, "modules with no dependencies start in alphabetical order")


## The anti-`main.gd` mechanism. `ui` declares `physics` and nothing else.
func _boundary_guard(t: TestContext) -> void:
	var k := t.boot_kernel(CoreManifest.MODULES)
	var ui := k.get_module(&"ui")
	t.ok(ui.use(&"physics") != null, "a declared dependency resolves")

	t.expect_error("ui reaching for a module it never declared")
	t.ok(ui.use(&"earth") == null, "an undeclared dependency is refused")


func _bad_manifests(t: TestContext) -> void:
	t.expect_error("a dependency cycle")
	var cyclic := t.boot_kernel({&"cycle_a": CYCLE_A, &"cycle_b": CYCLE_B})
	t.ok(cyclic.boot_error.contains("cycle"), "a cycle is caught: " + cyclic.boot_error)
	t.ok(cyclic.boot_error.contains("cycle_a") and cyclic.boot_error.contains("cycle_b"),
		"the cycle report names both modules involved")

	t.expect_error("a dependency that is not in the manifest")
	var lonely := t.boot_kernel({&"lonely": LONELY})
	t.ok(lonely.boot_error.contains("not in the manifest"),
		"a missing dependency is caught: " + lonely.boot_error)

	t.expect_error("a module whose name disagrees with the manifest")
	var misnamed := t.boot_kernel({&"misnamed": MISNAMED})
	t.ok(misnamed.boot_error.contains("calls itself"),
		"a name mismatch is caught: " + misnamed.boot_error)

	t.expect_error("a manifest entry pointing at nothing")
	var ghost := t.boot_kernel({&"ghost": "res://core/ghost/ghost_module.gd"})
	t.ok(ghost.boot_error.contains("does not exist"),
		"a missing file is caught: " + ghost.boot_error)
