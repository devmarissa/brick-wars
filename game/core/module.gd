class_name Module
extends Node
## Base class for every core system.
##
## The old build was one 1,500-line `main.gd` where every weapon, vehicle and trench was
## hardcoded and everything could reach everything. It didn't start that way — it got there
## one reasonable-looking line at a time. So the boundary here is enforced rather than
## documented: a module reaches another module through `use()`, and `use()` refuses any
## module this one didn't declare in `depends()`.
##
## That refusal is the whole point. Declaring a dependency is a deliberate act you can see
## in a diff and argue about in review; reaching for a global is not.
##
## Modules are listed in `core/manifest.gd` and booted by `core/kernel.gd` in dependency
## order. What each one owns is fixed by CORE-SPEC §2 — that document decides the
## boundaries, this class enforces them.

var kernel: Kernel = null

## Name this module is known by. Must match its key in the manifest.
func module_name() -> StringName:
	return &""

## Modules this one is allowed to talk to, by name. Order is irrelevant; the kernel
## topologically sorts and refuses cycles.
func module_depends() -> Array[StringName]:
	return []

## Which milestone fills this in. Stubs say so honestly rather than pretending to be
## finished; the test runner prints the count of stubs so the skeleton can't be mistaken
## for a game.
func module_milestone() -> String:
	return "C0"

## True while this module is still a placeholder.
func module_is_stub() -> bool:
	return false

## Called on every module in dependency order, before any of them are ready. Set up
## your own state here; do not touch other modules yet — they may not be initialised.
func module_init() -> void:
	pass

## Called on every module in dependency order, after all of them are initialised. This
## is where cross-module work belongs.
func module_ready() -> void:
	pass

## Reach another module. Refuses anything not declared in `module_depends()`, which is
## what stops this from decaying back into one file where everything knows everything.
func use(other: StringName) -> Module:
	if not module_depends().has(other):
		push_error("%s used module '%s' without declaring it in module_depends(). %s" % [
			module_name(), other,
			"Add it to the depends list, or — better — ask whether the boundary is wrong."])
		return null
	return kernel.get_module(other)
