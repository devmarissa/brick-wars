extends Module
## Game modes — siege/skirmish/sandbox, phases, capture, respawn, win conditions
## (CORE-SPEC §2). The real mode system arrives in C7.
##
## At C0 its only job is to put *something* on screen, because the rule that keeps a
## rebuild from killing the project is that there is never a fortnight without something
## you can run (BUILD-ORDER §2). That something is the grey box below.

const Greybox := preload("res://core/mode/greybox.gd")

var greybox: Node = null


func module_name() -> StringName:
	return &"mode"


func module_depends() -> Array[StringName]:
	return [&"physics"]


func module_milestone() -> String:
	return "C7"


func module_ready() -> void:
	greybox = Greybox.new()
	greybox.name = "Greybox"
	add_child(greybox)
	greybox.build(use(&"physics"))
