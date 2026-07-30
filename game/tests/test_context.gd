class_name TestContext
extends RefCounted
## What a test case is handed: somewhere to put nodes, a way to advance physics, and the
## four assertions worth having.
##
## No mocking, no fixtures-that-build-fixtures, no DSL. The old build's "tests" were a
## hardcoded sequence inside `main.gd` that possessed a tank, possessed a plane, and printed
## one line — it could only ever tell you "something still works", never *what*. The bar
## here is only that a failure names itself well enough that you don't have to open a
## debugger to know what broke.

var host: Node = null              ## add test scenes here; the runner frees them after
var failures: Array[String] = []
var checks := 0

var _tree: SceneTree = null


func _init(host_node: Node) -> void:
	host = host_node
	_tree = host_node.get_tree()


func ok(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func eq(got: Variant, want: Variant, what: String) -> void:
	checks += 1
	if got != want:
		failures.append("%s — got %s, wanted %s" % [what, got, want])


func near(got: float, want: float, epsilon: float, what: String) -> void:
	checks += 1
	if absf(got - want) > epsilon:
		failures.append("%s — got %s, wanted %s ± %s" % [what, got, want, epsilon])


func fail(why: String) -> void:
	checks += 1
	failures.append(why)


## Advance the physics simulation by `n` fixed steps. Everything about brick behaviour is
## measured in ticks rather than seconds on purpose: the physics step is fixed, the frame
## rate is not, and a test that waits on wall-clock time is a test that fails on a slow
## machine for no reason.
func ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


## Boot a kernel under `host` with whatever subset of the manifest the case needs. Cases
## take the smallest core they can get away with, so that a failure points at one module
## instead of at "the game". Returns the kernel even when boot fails, because half the
## kernel tests are about *how* it fails.
func boot_kernel(manifest: Dictionary) -> Kernel:
	var k := Kernel.new()
	k.name = "TestKernel"
	host.add_child(k)
	k.boot(manifest)
	return k


## Some assertions are about a guard firing, and a fired guard prints a Godot error. Call
## this first so the error in the log reads as the test working rather than the test
## breaking — an expected error nobody labelled is how CI output starts getting ignored.
func expect_error(why: String) -> void:
	print("      (expected error follows: %s)" % why)
