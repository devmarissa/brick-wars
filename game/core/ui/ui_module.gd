extends Module
## The HUD framework — HUD elements, menus, map, scoreboard. Packs theme it, they don't
## rebuild it (CORE-SPEC §2). The real thing arrives alongside the modes in C7.
##
## At C0 it shows the two numbers that tell you the skeleton is alive: how many bricks
## exist and how many are still moving. When the second one reaches zero and stays there,
## the sleep discipline is working.

const REFRESH_SECONDS := 0.2

var label: Label = null

var _acc := 0.0
var _physics: Module = null


func module_name() -> StringName:
	return &"ui"


func module_depends() -> Array[StringName]:
	return [&"physics"]


func module_milestone() -> String:
	return "C7"


func module_ready() -> void:
	_physics = use(&"physics")
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(12, 8)
	layer.add_child(label)


func _process(dt: float) -> void:
	if label == null or _physics == null:
		return
	_acc += dt
	if _acc < REFRESH_SECONDS:
		return
	_acc = 0.0
	label.text = "BRICK WARS — C2 rigs\nbricks %d · awake %d · %d fps" % [
		_physics.count_bricks(), _physics.count_awake(), Engine.get_frames_per_second()]
