class_name PlaySetup
extends RefCounted
## Handing the world to a person. C4b.
##
## Its own file because it is its own concern, and because `sandbox.gd` went past the 300-line cap
## the moment this landed in it. The seam is real rather than a trim: everything in `sandbox.gd`
## builds a *world* — ground, props, light, two creatures walking a circle — and everything here is
## about there being somebody in it. The sandbox has been photographed for three milestones with
## nobody playing it, and it still is whenever `--shot` is passed.
##
## What this does not do is decide anything about how play works. The body is `Walker`, built at C2.
## The kit is `Loadout`, built at C4. The keys are `Controls` and the view is `CameraRig`. This
## assembles those four and gets out of the way, which is why it is sixty lines and why it should
## stay that way.

## Who the player is. A class rather than a bare body — `core:rifleman` is `core:soldier` plus the
## kit that decides which verbs do anything when a key is pressed.
const PLAYER_CLASS := "core:rifleman"

## Where they start: on the open ground east of the trench, facing it, so the first thing in view is
## the thing C3 built and the second is somewhere to dig.
const PLAYER_START := Vector2(3.0, 2.0)

## Dropped from a few centimetres up rather than placed exactly, the same as every other body in the
## sandbox — settling onto the ground is more reliable than being positioned on it.
const DROP_HEIGHT := 0.12


## C4b: a soldier the player drives, carrying the kit C4 made real.
##
## `core:rifleman` rather than `core:soldier`, because a class is a soldier plus a loadout and the
## loadout is what decides which verbs do anything. Spawned outside `walkers` on purpose — that list
## is the demo's, and a player whose body was being steered round a circle by the demo would be a
## very confusing first ten seconds.
static func attach(world: Node3D, content: Module, earth: EarthTerrain) -> Player:
	var set := VerbSet.new()
	var registry := SlotSet.new()
	if not (set.load_core() and registry.load_core()):
		push_error("play: core verb data would not load, so there is nothing to play with")
		return null
	var asset: ResolvedAsset = content.resolver.get_asset(PLAYER_CLASS)
	if asset == null:
		push_error("play: no `%s` to play as" % PLAYER_CLASS)
		return null

	var body := Walker.of(asset, content.materials, content.palette)
	for problem in body.warnings:
		push_warning("play: %s: %s" % [PLAYER_CLASS, problem])
	body.position = _standing_on(earth, PLAYER_START)
	world.add_child(body)

	var kit := Loadout.of(asset, content.resolver, set, registry)
	for problem in kit.errors:
		push_warning("play: loadout: %s" % problem)

	_put_it_in_his_hands(body, kit, content)

	var rig := CameraRig.of([body.get_rid()])
	world.add_child(rig)

	var player := Player.of(body, rig, kit, set, content.resolver)
	player.earth = earth
	world.add_child(player)
	_control_hint(world, kit, set)
	player.said_label = _said_label(world)
	# Not captured on launch. A game that takes the mouse the instant its window opens is a game you
	# cannot alt-tab away from before you have decided you wanted to play it, and `Esc` releasing the
	# mouse is only half a round trip if nothing gives it back. Click to take it, Esc to give it up.
	return player


## One key per verb, printed on screen — because a bound key nobody knows about is an unbound key.
## This is the whole of C4b's UI and deliberately so: `CHECKLIST` §13's HUD framework, kill feed and
## scoreboard are the UI milestone's, and none of them is needed to answer "does this feel right".
static func _control_hint(world: Node3D, kit: Loadout, set: VerbSet) -> void:
	var lines := ["click to look · WASD move · Shift sprint · Space jump · Tab first/third · Esc free mouse"]
	var row := ""
	for verb in VerbSet.VOCABULARY:
		var key := OS.get_keycode_string(int(Controls.VERB_KEYS[verb]))
		var mark := "" if kit.can(set, String(verb)) else " (—)"
		row += "%s %s%s   " % [key, verb, mark]
	lines.append(row.strip_edges())
	lines.append("(—) is a verb you are not carrying the kit for, or one a later milestone owns.")

	var label := Label.new()
	label.name = "Controls"
	label.text = "\n".join(lines)
	label.position = Vector2(16.0, 16.0)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.86))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("outline_size", 4)
	var layer := CanvasLayer.new()
	layer.name = "PlayerUI"
	layer.add_child(label)
	world.add_child(layer)


## The start position, lifted onto whatever the ground turned out to be.
static func _standing_on(earth: EarthTerrain, at: Vector2) -> Vector3:
	if earth == null:
		return Vector3(at.x, DROP_HEIGHT, at.y)
	return Vector3(at.x, DROP_HEIGHT + earth.field.height_at(at.x, at.y), at.y)


## The player's two lines for the boot log, or nothing at all when nobody is playing. Everything in
## them is derived — what is in his hands comes off the loadout, and what he can do comes off the
## slots those things are in. Neither is written down anywhere.
static func report(player: Player) -> Array[String]:
	if player == null:
		return []
	var carried: Array[String] = []
	for slot in player.loadout.slots:
		carried.append("%s in %s" % [player.loadout.item(slot), slot])
	return [
		"  player: %s carrying %s" % [player.walker.asset_id,
			", ".join(carried) if not carried.is_empty() else "nothing"],
		"  can: %s" % ", ".join(player.loadout.verbs(player.verbs)),
	]


## Hang the kit off the soldier. C4b.
##
## Marissa's first run: *"i dont see any tools so idk about the controls working."* The loadout was
## real, the verbs read it, and the boot log listed all three items — and none of them existed as
## anything you could look at, because `Loadout` is data and nothing had ever drawn it. A soldier
## holding an invisible rifle is indistinguishable from a soldier holding nothing, which made every
## key press unfalsifiable.
##
## Visual only, deliberately. `AssetBuilder` returns physics bodies, and a rigid body parented to a
## moving bone fights the physics engine for control of its own transform — so the meshes are lifted
## out and the bodies dropped. A held weapon does not need to be collided with; it needs to be seen.
##
## Where it sits on the hand is approximate and is meant to be. Grip alignment is an *animation*
## problem — `ANIMATION-SPEC` reserves the hold poses, and C6's hands-on-controls IK is what puts a
## hand somewhere precisely. Getting it exactly right here would be building that early and by eye.
static func _put_it_in_his_hands(body: Walker, kit: Loadout, content: Module) -> void:
	if body.rig == null:
		return
	# Right hand for the weapon he leads with, left for the next thing down. More than two carried
	# items and the rest ride along invisibly, which is honest until there is a sling to put them on.
	var hands := ["hand_r", "hand_l"]
	for i in kit.slots.size():
		if i >= hands.size():
			return
		var bone := body.rig.bone(hands[i])
		if bone == null or bone.node == null:
			continue
		var asset: ResolvedAsset = content.resolver.get_asset(kit.item(String(kit.slots[i])))
		if asset == null:
			continue
		var held := _meshes_of(asset, content)
		if held == null:
			continue
		held.name = "held_%s" % kit.slots[i]
		# Forward out of the fist and rotated to lie along the arm rather than across it. Both
		# numbers are eyeballed; see above.
		held.position = Vector3(0.0, -0.05, -0.12)
		held.rotation = Vector3(deg_to_rad(-80.0), 0.0, 0.0)
		bone.node.add_child(held)


## An asset as geometry and nothing else: built the normal way, then stripped of everything that
## would have made it a physical object.
static func _meshes_of(asset: ResolvedAsset, content: Module) -> Node3D:
	var built := AssetBuilder.new().build(asset, content.materials, content.palette)
	if built == null:
		return null
	var holder := Node3D.new()
	_lift_meshes(built, holder)
	built.queue_free()
	return holder if holder.get_child_count() > 0 else null


static func _lift_meshes(from: Node, into: Node3D) -> void:
	for child in from.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			var kept := MeshInstance3D.new()
			kept.mesh = mesh.mesh
			kept.material_override = mesh.material_override
			kept.transform = mesh.transform
			into.add_child(kept)
		else:
			_lift_meshes(child, into)


## The line that says what just happened. One of `PRODUCTION.md`'s six steps a verb owes — input,
## animation, sound, VFX, camera, UI — and the only one C4b can honestly deliver, but it is the one
## that turns "the keys do not work" into "dig — that is bedrock".
static func _said_label(world: Node3D) -> Label:
	var label := Label.new()
	label.name = "Said"
	label.position = Vector2(16.0, 96.0)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	var layer := CanvasLayer.new()
	layer.name = "SaidUI"
	layer.add_child(label)
	world.add_child(layer)
	return label
