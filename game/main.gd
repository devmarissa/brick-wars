extends Node
## The entire boot sequence. It is meant to stay this short.
##
## The old build's `main.gd` was 1,500 lines because it started as the place where things
## got wired up and then became the place where things got *done*. This one is only allowed
## to do three things: make the kernel, boot it, and say loudly what happened. Anything
## that looks like gameplay belongs in a module — and if it doesn't fit in a module, that
## is a CORE-SPEC §2 conversation, not a reason to put it here.

const BOOT_FAILED := 3   ## exit code, so a broken boot is distinguishable from a test failure

var kernel: Kernel = null


func _ready() -> void:
	kernel = Kernel.new()
	kernel.name = "Kernel"
	add_child(kernel)

	if not kernel.boot():
		push_error("BOOT FAILED: " + kernel.boot_error)
		print("BOOT FAILED: ", kernel.boot_error)
		get_tree().quit(BOOT_FAILED)
		return

	print("boot ok — %d modules, %d still stubs" % [
		kernel.order.size(), kernel.stub_names().size()])
	print("order: ", ", ".join(kernel.order))
