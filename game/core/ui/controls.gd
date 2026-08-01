class_name Controls
extends RefCounted
## The input map, and the control philosophy it locks in. `CHECKLIST` §13, C4b.
##
## §13 states the rule and C4b is the moment to actually take it:
##
## > **Control philosophy lock**: Roblox-simple, one key per verb, no modifier combos.
##
## That decision is cheap to make against a vocabulary that was closed at C4 and expensive to make
## later against an already-bound keyboard, which is the whole reason C4b sits where it does. Ten
## verbs is a number a keyboard can hold one-each. Twenty is not, and the pressure to start binding
## `Shift+E` is exactly the pressure the closed vocabulary exists to resist — so if this map ever
## needs a modifier, the thing to question is the verb list rather than the map.
##
## ### Registered in code, not in `project.godot`
##
## Bindings live here rather than in the project file for two reasons. They are checkable — a test
## can assert that every live verb has a key and that no key does two jobs, which is not a thing you
## can assert about a `.godot` file anybody can hand-edit. And they are *rebindable*: §13 wants full
## key rebinding, and a map built at boot from a table is one a settings screen can rewrite, while
## one baked into the project file is one that needs a restart.
##
## ### One key per verb, and the verb list decides which keys exist
##
## `VERB_KEYS` is keyed by verb name, so a verb that does not exist cannot have a binding and a verb
## that exists without one is a hole a test finds. Reserved verbs are bound anyway — pressing them
## gets the dispatcher's refusal naming the milestone that owns it, which is far better than a key
## that does nothing and leaves the player wondering whether the game is broken.

## Movement and camera. Not verbs — these are how you get to where a verb is worth doing, and
## `ANIMATION-SPEC` treats them as states rather than actions for the same reason.
const MOVEMENT := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"sprint": [KEY_SHIFT],
	&"jump": [KEY_SPACE],
}

## One key per verb, in the vocabulary's own order. Every one of the ten, including the six that are
## reserved: a bound key that answers *"`enter` is declared and not built — C6 owns it"* teaches the
## player something, and an unbound one teaches them that the keyboard is unreliable.
const VERB_KEYS := {
	"fire": KEY_F,
	"throw": KEY_G,
	"dig": KEY_E,
	"build": KEY_B,
	"melee": KEY_V,
	"carry": KEY_C,
	"enter": KEY_R,
	"man": KEY_T,
	"interact": KEY_Q,
	"signal": KEY_Z,
}

## Camera and the things that are neither movement nor verbs.
const VIEW := {
	&"view_toggle": [KEY_TAB],
	&"release_mouse": [KEY_ESCAPE],
}

## Prefix on every verb action, so a verb called `fire` cannot collide with a movement action
## somebody later calls `fire`. Cheap, and the alternative is a name clash that presents as one of
## the two silently never firing.
const VERB_PREFIX := "verb_"


## Build the whole map. Idempotent — actions are cleared and rebuilt — so a settings screen can call
## it again after a rebind without restarting anything.
static func install() -> void:
	for name in MOVEMENT:
		_bind(StringName(name), MOVEMENT[name])
	for name in VIEW:
		_bind(StringName(name), VIEW[name])
	for verb in VERB_KEYS:
		_bind(action_for(String(verb)), [VERB_KEYS[verb]])


## The action name a verb is pressed through.
static func action_for(verb: String) -> StringName:
	return StringName(VERB_PREFIX + verb)


## Which verb, if any, was just pressed. Returns "" for none. Checked in vocabulary order so that
## two keys held at once resolve the same way every time rather than by dictionary iteration order,
## which is the sort of thing that is stable until it is not.
static func verb_pressed() -> String:
	for verb in VerbSet.VOCABULARY:
		if Input.is_action_just_pressed(action_for(String(verb))):
			return String(verb)
	return ""


## Movement as a direction on the ground plane, already normalised. Not camera-relative — the caller
## knows where it is looking and this does not.
static func wish() -> Vector3:
	var wish_dir := Vector3(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		0.0,
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	return wish_dir.normalized() if wish_dir.length() > 1.0 else wish_dir


static func sprinting() -> bool:
	return Input.is_action_pressed(&"sprint")


## Every key in the map, for the test that asserts none of them does two jobs. A keyboard where one
## key means two things is a keyboard where one of them is unreachable, and it is the failure a map
## this size acquires by accident rather than by decision.
static func all_keys() -> Array[int]:
	var out: Array[int] = []
	for name in MOVEMENT:
		for key in MOVEMENT[name]:
			out.append(int(key))
	for name in VIEW:
		for key in VIEW[name]:
			out.append(int(key))
	for verb in VERB_KEYS:
		out.append(int(VERB_KEYS[verb]))
	return out


static func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = int(key)
		InputMap.action_add_event(action, event)
