class_name Player
extends Node
## Hands on it. C4b.
##
## The milestone the plan did not have. C0–C8 build verbs, combat, destruction, vehicles, modes and
## netcode, and none of them builds a thing that reads a key — so three things Marissa has asked
## about have been sitting at `[~]` since C2 waiting on a milestone that did not exist. This is it,
## and it is deliberately the smallest thing that answers them: drive the body C2 built, point the
## camera C4b added, and press the verbs C4 made real.
##
## ### It owns nothing
##
## `Walker` already moves a body and poses a rig. `Verbs` already refuses or carries out an action.
## `Loadout` already knows what is in the soldier's hands and therefore what he can do. This file is
## the fifty lines that turn a key into an argument for one of them, and if it ever grows a rule
## about *how* something works rather than *that the player asked for it*, the rule is in the wrong
## file.
##
## The clearest symptom of getting that wrong would be this file knowing what a rifle is. It does
## not: `fire` looks up whatever is in the `ranged_slow` slot of whatever class was spawned, and a
## bow works because a bow is what the class was carrying.

## How far in front of the soldier he digs, in metres. A spade's length — you dig at your feet and
## slightly ahead, and the spoil goes one cell further out so the parapet builds on the far lip
## rather than under you.
const DIG_AHEAD := 1.1

## Where a shot leaves from, relative to the body. Eye height and slightly forward, so a round does
## not begin inside the soldier's own collider and instantly hit him — the first bug anybody writing
## this has, and one the shooter's own RID being excluded also guards.
const MUZZLE_HEIGHT := 1.5

var walker: Walker = null
var camera: CameraRig = null
var loadout: Loadout = null
var earth: EarthTerrain = null
var verbs: VerbSet = null
var resolver: AssetResolver = null

## Seconds since the world came up. The clock every verb's cycle is measured against, kept here
## because `VerbFire` deliberately does not keep one — the two callers that matter disagree about
## what time it is, and a live game uses the frame clock.
var clock := 0.0

## What the player last did, for the HUD line. The cheapest possible acknowledgment, and
## `PRODUCTION.md` is right that a verb owes the full chain — input, animation, sound, VFX, camera,
## UI — so this is one of six and the other five are later milestones'.
var said := ""

## Where `said` is shown. Set by `PlaySetup`; nothing breaks without one.
var said_label: Label = null

var _rng := RandomNumberGenerator.new()
var _was_first_person := false
var _thrown: Array[Dictionary] = []


static func of(body: Walker, rig: CameraRig, kit: Loadout, set: VerbSet,
		find: AssetResolver) -> Player:
	var player := Player.new()
	player.name = "Player"
	player.walker = body
	player.camera = rig
	player.loadout = kit
	player.verbs = set
	player.resolver = find
	player._rng.seed = 1
	return player


func _physics_process(delta: float) -> void:
	clock += delta
	if walker == null or camera == null:
		return

	_drive()
	camera.follow(walker.global_position)
	_step_thrown(delta)
	_show_or_hide_the_body()
	if said_label != null:
		said_label.text = said

	var asked := Controls.verb_pressed()
	if asked != "":
		_do(asked)


## Movement, camera-relative. The camera owns what "forward" means because the camera is what the
## player is looking through; the walker owns everything about how the body gets there.
func _drive() -> void:
	var wish := camera.facing() * Controls.wish()
	walker.wish = Vector2(wish.x, wish.z)
	walker.sprinting = Controls.sprinting()
	if Input.is_action_just_pressed(&"jump"):
		walker.jump_wanted = true


## One key, one verb, one dispatch. Everything below is about assembling arguments — none of it is
## about what a verb does, which is the whole point of there being a dispatcher.
func _do(verb: String) -> void:
	var slot := _slot_for(verb)
	var stats := _stats(slot)
	var aim := -camera.global_transform.basis.z
	var origin := walker.global_position + Vector3.UP * MUZZLE_HEIGHT

	var request := {
		"stats": stats, "state": loadout.state.get(slot, {}), "now": clock,
		"origin": origin, "aim": aim, "rng": _rng,
		"space": walker.get_world_3d().direct_space_state, "ignore": [walker.get_rid()],
	}
	if verb == "dig":
		_add_dig_target(request, aim)

	var got: Dictionary = Verbs.dispatch(verbs, verb, request)
	# A verb that aborted mid-way returns null rather than a refusal, and reading `ok` off that is a
	# second error on top of the first — which is how one bug filled the log with two.
	if got == null or not got.has("ok"):
		said = "%s — the verb itself failed; see the error above" % verb
		return
	if got.has("state") and slot != "":
		loadout.state[slot] = got["state"]
	if verb == "throw" and got["ok"]:
		_thrown.append(got["thrown"])
	said = "%s — %s" % [verb, "ok" if got["ok"] else got["why"]]


## Where the spade goes: the cell in front of the soldier, with the spoil one further out. Nothing
## about this is a rule the verb does not already enforce — `VerbDig` refuses spoil thrown into its
## own hole or across the road, and this is only choosing which legal pair of cells to ask for.
func _add_dig_target(request: Dictionary, aim: Vector3) -> void:
	if earth == null:
		return
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	var at := walker.global_position + flat * DIG_AHEAD
	var cell := EarthGrid.cell_at(at.x, at.z)
	var beyond := EarthGrid.cell_at(at.x + flat.x * EarthGrid.CELL_M,
		at.z + flat.z * EarthGrid.CELL_M)
	if beyond == cell:
		beyond = cell + Vector2i(1, 0)
	request["field"] = earth.field
	request["terrain"] = earth
	request["cell"] = cell
	request["spoil"] = beyond


## Grenades in the air. C4 flies them and C5 will do something when the fuse ends; until then they
## are dropped from the list, which is the same "goes quiet" the tests assert.
func _step_thrown(delta: float) -> void:
	if _thrown.is_empty():
		return
	var space := walker.get_world_3d().direct_space_state
	var still_flying: Array[Dictionary] = []
	for grenade in _thrown:
		var moved := VerbThrow.fly(space, grenade, delta, [walker.get_rid()])
		if not moved["spent"]:
			still_flying.append(moved)
	_thrown = still_flying


func in_flight() -> int:
	return _thrown.size()


## Which slot a verb comes out of, for this soldier. Asked of the loadout rather than known here —
## the same lookup that makes "what can he do" derived makes "what is he holding when he does it"
## derived too.
func _slot_for(verb: String) -> String:
	for slot in loadout.slots:
		if verbs.verbs_for(slot).has(verb):
			return slot
	return ""


func _stats(slot: String) -> Dictionary:
	if slot == "" or resolver == null:
		return {}
	var found := resolver.get_asset(loadout.item(slot))
	return found.data.get("stats", {}) if found != null else {}


## In first person, do not draw the man you are looking out of. Marissa asked for it after her first
## run, and she is right: from behind the eyes his own shoulders and helmet fill the middle of the
## screen, which reads as a bug rather than as a body.
##
## The whole body goes, including what is in his hands — so first person currently shows no weapon
## either. That is the honest version of what C4b can do. A first-person **viewmodel** is a separate
## thing: a second, differently-proportioned pair of arms and a weapon posed for the camera rather
## than for the world, which is animation work `ANIMATION-SPEC` has states reserved for and which no
## milestone has built. Half-doing it here would mean a weapon floating at the wrong scale in the
## wrong place, which is worse than none.
func _show_or_hide_the_body() -> void:
	if camera.first_person == _was_first_person:
		return
	_was_first_person = camera.first_person
	if walker.rig != null and walker.rig.root != null:
		walker.rig.root.visible = not camera.first_person
