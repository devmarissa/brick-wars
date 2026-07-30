extends Node
## Boot the game, wait for it to settle, save one frame, quit.
##
## Milestones get argued about from screenshots, so taking one should be a command rather
## than a thing you set up by hand each time and frame slightly differently. Run it through
## `tools/screenshot.sh` at the repo root.
##
## It boots the real `main.gd` — not a special screenshot-only scene — because a picture of
## a scene that only exists to be photographed proves nothing about the game.

const Main := preload("res://main.gd")

const DEFAULT_OUT := "docs/latest.png"
const DEFAULT_SETTLE := 4.0


func _ready() -> void:
	var out := DEFAULT_OUT
	var settle := DEFAULT_SETTLE
	var extra := OS.get_cmdline_user_args()
	if extra.size() > 0:
		out = extra[0]
	if extra.size() > 1:
		settle = float(extra[1])

	var game := Node.new()
	game.name = "Game"
	game.set_script(Main)
	add_child(game)

	# Wall-clock rather than ticks: this is waiting for the picture to stop changing, which
	# is a rendering question, not a physics one.
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(out)
	if error != OK:
		push_error("could not write %s (error %d)" % [out, error])
		get_tree().quit(1)
		return
	print("screenshot → %s  (%d × %d, after %.1f s)" % [
		out, image.get_width(), image.get_height(), settle])
	get_tree().quit()
