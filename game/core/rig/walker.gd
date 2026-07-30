class_name Walker
extends CharacterBody3D
## A creature that walks: an asset's rig, driven by `Locomotion`, on a body that physics owns.
## RIG-SPEC §4, BUILD-ORDER C2.
##
## This is the thing C2's done-condition is written about — *a soldier defined entirely in data
## walks, sprints and jumps over uneven ground with feet that plant correctly* — and it is the
## piece that makes the rest of the milestone visible rather than merely tested. It is also
## deliberately thin. Everything about how a leg moves lives in `Locomotion`; everything about how
## a body moves lives here; and the two meet across one call per frame.
##
## ### Why the body and the rig are separate things
##
## `Locomotion.step` hands back a height and an orientation instead of writing them, because the
## body is a physics object with a collider and a solver that moved it directly would be a
## kinematic system arguing with a simulated one. So this class honours that split literally: the
## `CharacterBody3D` is moved by `move_and_slide` against the world, and the *rig* — the meshes,
## nothing else — is then placed at the height the feet imply. When the two agree, which is most
## of the time on level ground, the offset is zero and nothing looks unusual. When they disagree,
## which is a foot down a shell hole, the collider stays a sane shape while the creature visibly
## crouches into it. That is the right way round: a capsule that deformed every time a foot found
## a dip would make the body's own collisions unpredictable, and unpredictable collision is worse
## than a visual approximation.
##
## The order inside `_physics_process` is the same order `step`'s docstring insists on, one level
## up: move the body first, then pose the rig against where it ended up. Posing first costs a
## frame of lag and reads as skating.
##
## ### The numbers below are tuned, not ported
##
## BUILD-ORDER §1b is explicit that the old build's WALK 12 / SPRINT 22 do not come across. They
## were set before there was foot planting to feel them alongside, and a speed that felt right
## against a creature whose feet slid is not a speed that feels right against one whose feet
## plant. These are metres per second against `TestGround`, and they are a first pass by
## definition — the gait table in `core:soldier` has to agree with them, so retuning either means
## looking at both.

## Metres per second. A walk is a walk; the sprint is a little over twice it, which is where the
## soldier's `sprint` gait takes over from `walk` at 2.6.
const WALK_SPEED := 2.2
const SPRINT_SPEED := 5.4

## Metres per second per second. Braking is harder than accelerating, because a creature that
## coasts to a stop reads as being on ice, and this game's ground is mud.
const ACCELERATION := 14.0
const BRAKING := 20.0

## Up is 6 m/s against 22 m/s² of gravity, which is a little over 0.8 m of clearance — enough to
## get onto the lip of a crater rather than over a wall. Gravity is well above the real 9.8, for
## the usual reason: real gravity at this scale reads as the moon.
const JUMP_SPEED := 6.0
const GRAVITY := 22.0

## Radians per second the body turns toward where it is going. Fast enough not to feel like a
## vehicle, slow enough that the lean into a turn has something to lean about.
const TURN_RATE := 9.0

## How far below a foot's ideal position to look for ground, beyond what the leg can actually
## reach. The probe has to see further than the leg does or `Footing.plant` never learns that the
## ground is out of range and the foot hangs in the air with `hit` false instead.
const PROBE_MARGIN := 0.4

## Below this a `wish` is not asking for anything, and the facing falls back to travel.
const DEADZONE := 0.1

## Below this the creature is standing still as far as the gait engine is concerned. Without it a
## floating-point dribble of velocity keeps the cycle creeping while the creature looks stopped.
const STILL := 0.05

var asset_id := ""
var rig: Rig = null
var locomotion := Locomotion.new()
var warnings: Array[String] = []

## What is being asked of it, in world XZ, length at most 1. Set by whoever is driving — real
## input, a test, or the sandbox's demo path. Kept as plain state rather than read from `Input`
## here, because a controller that reads the keyboard cannot be tested without one.
var wish := Vector2.ZERO
var sprinting := false
var jump_wanted := false

## What the driver said last frame, for tests and for anything that wants to react to a gait.
var last: Dictionary = {}

var _yaw := 0.0
var _reach := 1.0
var _exclude: Array[RID] = []


## Build an asset and make a walker of it, or a walker with a complaint and no rig. Never null:
## a creature that will not walk still has to be something the caller can add to the scene and
## see, because "nothing appeared" is the least debuggable outcome there is.
static func of(asset: ResolvedAsset, materials: MaterialSet, palette: Palette) -> Walker:
	var walker := Walker.new()
	walker.name = "walker_" + asset.id.replace(":", "_")
	walker.asset_id = asset.id

	var built := AssetBuilder.new().build(asset, materials, palette)
	if built.rig == null:
		walker.warnings.append(("%s has no rig, so there is nothing to pose — a walker needs"
			+ " parts with `joint`s (RIG-SPEC §3)") % asset.id)
		built.queue_free()
		return walker

	# The meshes come across and the `RigidBody3D` the builder wrapped them in does not. A
	# character is moved by a controller; a rigid body would be a second thing moving it, and the
	# two would spend every frame disagreeing about where the creature is.
	var root := built.rig.root
	root.get_parent().remove_child(root)
	walker.add_child(root)
	walker.rig = built.rig
	walker.warnings.append_array(built.rig.warnings)

	for shape in _colliders(asset):
		walker.add_child(shape)
	built.queue_free()

	walker._check_stance(asset)
	if not walker.locomotion.setup(walker.rig, Locomotion.declared(asset)):
		walker.warnings.append(("%s has a rig but nothing to drive it — no `legged` locomotion"
			+ " block resolved to real legs (RIG-SPEC §5)") % asset.id)
	walker.warnings.append_array(walker.locomotion.warnings)
	walker._measure()
	return walker


## The asset's own declared collision boxes, which for a character is the whole of its collision.
## RIG-SPEC §3: a rig is not a collider. A soldier gets the two or three boxes its file names, not
## a shape per bone — partly for cost, mostly because a rig that collides with itself fights its
## own solver and the fight is visible.
static func _colliders(asset: ResolvedAsset) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	var declared: Variant = asset.data.get("collider")
	if typeof(declared) != TYPE_ARRAY:
		return out
	for entry in declared as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var box: Dictionary = entry
		var shape := CollisionShape3D.new()
		shape.shape = PartGeometry.box_shape(PartGeometry.size_m(box.get("size")))
		shape.position = PartGeometry.offset_m(box.get("offset"))
		out.append(shape)
	return out


func _ready() -> void:
	_exclude = [get_rid()]


func _physics_process(delta: float) -> void:
	var turned := _move(delta)
	_pose(delta, turned / maxf(delta, 0.0001))


## The body: accelerate toward what was asked for, fall, jump, and turn to face the way it is
## going. Returns how far it yawed this frame, which the pose half needs in order to lean.
func _move(delta: float) -> float:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var target := Vector3(wish.x, 0.0, wish.y).limit_length(1.0) * _target_speed()
	var rate := ACCELERATION if target.length_squared() > flat.length_squared() else BRAKING
	flat = flat.move_toward(target, rate * delta)

	velocity = Vector3(flat.x, velocity.y - GRAVITY * delta, flat.z)
	if jump_wanted and is_on_floor():
		velocity.y = JUMP_SPEED
	jump_wanted = false
	move_and_slide()

	# Facing follows what it is *trying* to do, and only falls back to where it is actually going
	# when it is not trying to do anything.
	#
	# It was the other way round — facing followed travel — on the reasoning that a creature
	# shoved sideways by a slope should turn to where it is really headed. That is true of a
	# slope and disastrous on contact. `move_and_slide` deflects velocity along whatever it
	# touches, so the instant two creatures brush, the deflected direction swings hard and the
	# facing chases it: the demo needs 0.86° of turn per frame and contact was driving the full
	# 8.59° cap, ten times over, for as long as they were touching. That is the springing-apart.
	# A blocked creature should keep facing where it wants to go, which is what a person does.
	var was := _yaw
	if wish.length() > DEADZONE:
		_yaw = _turn_toward(atan2(-wish.x, -wish.y), delta)
	elif flat.length() > STILL:
		_yaw = _turn_toward(atan2(-flat.x, -flat.z), delta)
	rotation.y = _yaw
	return angle_difference(was, _yaw)


## The rig: one call into the driver, and then the meshes go where it says.
func _pose(delta: float, yaw_rate: float) -> void:
	if rig == null or locomotion.legs.is_empty():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < STILL:
		flat = Vector3.ZERO
	last = locomotion.step(
		Transform3D(Basis(Vector3.UP, _yaw), global_position), flat, yaw_rate, delta,
		Footing.raycast_probe(space, _reach, _exclude))
	if last.is_empty():
		return

	# The height comes back in world space and the rig is a child, so it is placed relative. The
	# basis likewise: it already contains the yaw the body has, and dividing that out leaves the
	# tilt onto the ground, which is the part the body is not carrying.
	var root := rig.root
	root.position = Vector3(0.0, float(last["height"]) - global_position.y, 0.0)
	root.basis = global_basis.inverse() * (last["basis"] as Basis)


func _target_speed() -> float:
	return SPRINT_SPEED if sprinting else WALK_SPEED


## Toward a heading the short way round, capped at `TURN_RATE`. `angle_difference` is what makes
## it the short way — lerping raw angles spins a creature the long way round whenever its heading
## crosses ±π, which is a full turn on the spot for a one-degree change of input.
func _turn_toward(heading: float, delta: float) -> float:
	var step := angle_difference(_yaw, heading)
	return _yaw + clampf(step, -TURN_RATE * delta, TURN_RATE * delta)


## A walker's collision has to reach down to where its feet are, and this is the check that says
## so out loud. `Locomotion.step` plants feet against the transform it is handed, which is the
## body's own — so a creature whose lowest collision box stops above its soles settles that far
## into the ground, and then every foot is asked to reach *upward* for a surface above its own
## ideal position and fails to. The symptom is a creature knee-deep in the floor with all four
## feet reported unplanted, and nothing about it points at the collider. `testpack:horse` shipped
## with exactly that and it took longer to find than it should have.
func _check_stance(asset: ResolvedAsset) -> void:
	var lowest := INF
	for shape in _colliders(asset):
		var box := shape.shape as BoxShape3D
		if box != null:
			lowest = minf(lowest, shape.position.y - box.size.y * 0.5)
	if lowest == INF or lowest <= STILL:
		return
	warnings.append(("%s's lowest collision box starts %.2f m above its origin, so it will settle"
		+ " that far into the ground and its feet will not reach. A walker's collision has to"
		+ " come down to its soles (RIG-SPEC §3)") % [asset.id, lowest])


## How far the probe looks, from the legs themselves. The longest leg's reach plus a margin: the
## margin is what lets `Footing.plant` distinguish "the ground is further down than this leg can
## go" from "there is no ground here at all", and those two want different behaviour.
func _measure() -> void:
	var furthest := 0.0
	for leg in locomotion.legs:
		furthest = maxf(furthest, leg.reach)
	_reach = furthest + PROBE_MARGIN


## What it is doing, for a boot log or a debug overlay. Deliberately one line: a creature that
## needs a paragraph to describe its state is a creature with too much state.
func report() -> String:
	if last.is_empty():
		return "%s: standing (no gait yet)" % asset_id
	return "%s: %s%s at %.1f m/s, %d foot%s down%s" % [
		asset_id, String(last["gait"]), " (blending)" if bool(last["blending"]) else "",
		Vector3(velocity.x, 0.0, velocity.z).length(), int(last["planted"]),
		"" if int(last["planted"]) == 1 else "s",
		", unsupported" if bool(last["unsupported"]) else ""]
