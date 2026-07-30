extends Node
## The entire boot sequence. It is meant to stay this short.
##
## The old build's `main.gd` was 1,500 lines because it started as the place where things
## got wired up and then became the place where things got *done*. This one is only allowed
## to do three things: make the kernel, boot it, and say loudly what happened. Anything
## that looks like gameplay belongs in a module — and if it doesn't fit in a module, that
## is a CORE-SPEC §2 conversation, not a reason to put it here.

const BOOT_FAILED := 3   ## exit code, so a broken boot is distinguishable from a test failure
const CLI_FAILED := 4    ## and a question the game could not answer from either of those


var kernel: Kernel = null


func _ready() -> void:
	var cli := CLI.shared()
	for problem in cli.errors:
		print("argument: ", problem)
	if not cli.errors.is_empty():
		get_tree().quit(CLI_FAILED)
		return

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

	# In boot order, so what a module says arrives after whatever it was built on top of.
	for name in kernel.order:
		var module := kernel.get_module(StringName(name))
		if module == null:
			continue
		var said := module.summary()
		if said != "":
			print(said)

	# Last, and only if asked. A `--resolve` dump arrives *after* the boot log on purpose:
	# the most common reason a field came from somewhere surprising is that a pack above it
	# got disabled, and that is three lines up rather than in the dump.
	if cli.wants_resolve():
		var content := kernel.get_module(&"content")
		if content == null:
			print("--resolve: the content module did not boot, so nothing is resolved")
			get_tree().quit(CLI_FAILED)
			return
		print("")
		print(cli.resolve_report(content))
		get_tree().quit(0 if cli.resolve_ok else CLI_FAILED)
