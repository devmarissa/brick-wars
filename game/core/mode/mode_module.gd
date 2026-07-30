extends Module
## Game modes — siege/skirmish/sandbox, phases, capture, respawn, win conditions
## (CORE-SPEC §2). The real mode system arrives in C7.
##
## Until then its only job is to put *something* on screen, because the rule that keeps a
## rebuild from killing the project is that there is never a fortnight without something
## you can run (BUILD-ORDER §2). At C0 that something was a wall built in code. At C1 it is
## the same wall, and nothing about it is in code any more — `sandbox.gd` reads a list of
## asset ids and the content pipeline does the rest.
##
## It depends on physics as well as content even though it never calls into physics: the
## bodies the builder makes are dynamic, and a world that spawns before gravity has been
## set is a world that falls at the wrong speed for one frame and then corrects. Cheap
## insurance, and the dependency is honest — the sandbox does need physics running.

const Sandbox := preload("res://core/mode/sandbox.gd")

var sandbox: Node = null


func module_name() -> StringName:
	return &"mode"


func module_depends() -> Array[StringName]:
	return [&"physics", &"content"]


func module_milestone() -> String:
	return "C7"


func module_ready() -> void:
	sandbox = Sandbox.new()
	sandbox.name = "Sandbox"
	add_child(sandbox)
	sandbox.build(use(&"content"))


func summary() -> String:
	return sandbox.report() if sandbox != null else "mode: nothing built"
