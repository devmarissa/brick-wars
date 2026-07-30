class_name Rig
extends RefCounted
## A part table with `parent` and `joint` on it, turned into something that can be posed.
## RIG-SPEC §3.
##
## The whole of the kinematic system is one idea: a bone is a `Node3D` whose origin sits at
## the joint it turns about, with the part's mesh hung off it at an offset. Pose a bone and
## everything below it comes along, because that is what a transform hierarchy does. There is
## no simulation here, no solver state, and nothing that has to tick — a rig that nobody poses
## costs exactly what a static asset costs.
##
## **A rig is not a collider.** RIG-SPEC §3 states it and this file is where it is true:
## `Rig` builds meshes and nothing else. Collision stays the one to four hand-fitted boxes the
## asset declared, sitting on the body, unmoved by any pose. A horse gets a body box and maybe
## a head box, not eight leg colliders — and the reason is not only cost. A rig that collided
## with itself is a rig that fights its own solver, and the fight is visible.
##
## ### Where the pivot goes, and why there is a node for it
##
## A part's `offset` is the centre of its box, but a leg does not hinge about the middle of the
## thigh. `joint.pivot` moves the turning point to the top of the bone, and this file arranges
## the nodes so that the bone node's *origin is the pivot*: the mesh hangs at `-pivot` inside
## it, and a child bone's rest transform is pre-composed to undo the parent's pivot. That
## costs one node per part rather than two, and it means posing a joint is assigning a basis
## rather than doing arithmetic at the call site — which is the difference between a solver
## that is wrong once here and a solver that is wrong in every caller.

## Bones are `Node3D`, so the pose of a whole creature is `bones.size()` transforms and no
## allocations per frame.
class Bone extends RefCounted:
	var name := ""
	var node: Node3D = null
	var part: Dictionary = {}
	var index := 0
	var parent := ""

	## The bone's orientation with nothing driving it, from the part's `rotation`.
	var rest := Basis.IDENTITY

	## Offset from the part's own origin to the joint, in metres. Zero for a welded part.
	var pivot := Vector3.ZERO

	var joint: Dictionary = {}

	func type() -> String:
		return String(joint.get("type", "fixed")) if not joint.is_empty() else "fixed"

	func articulates() -> bool:
		return type() != "fixed"

	## The length of the bone along its own -Z (ART-BIBLE §7), which is what a limb segment's
	## `size` reads as `[thickness, thickness, length]` for — the number a leg's IK needs, and
	## the one most easily got wrong by measuring a leg that was authored down Y instead.
	func length() -> float:
		return PartGeometry.size_m(part.get("size")).z


## Every part in the table, keyed by name, in the order they were declared.
var bones: Dictionary = {}
var order: Array[String] = []

## The node everything hangs off. Added to the body by the builder; never moved by a pose.
var root: Node3D = null

var asset_id := ""
var warnings: Array[String] = []


## True when the asset articulates — when any part declares a joint. A part table that only
## uses `parent` to place things relative to each other is not a rig, it is a convenience, and
## it stays on the flat path where the builder bakes its transforms and the physics engine
## never sees a hierarchy it does not need.
static func is_rigged(asset: ResolvedAsset) -> bool:
	for part in asset.parts():
		if typeof(part) == TYPE_DICTIONARY and part.has("joint"):
			return true
	return false


## Build the bone hierarchy. `mesh_for` takes (part, index) and returns a `MeshInstance3D`
## already sized, oriented and coloured — the builder keeps that, because shading is a palette
## question and this file has no opinion about colour.
##
## Parts arrive in declaration order and a child may be declared before its parent, so the
## nodes are made first and parented second. Refusing out-of-order tables would be a rule
## about text editors rather than about rigs.
func build(asset: ResolvedAsset, mesh_for: Callable) -> Node3D:
	asset_id = asset.id
	root = Node3D.new()
	root.name = "rig"

	var parts := asset.parts()
	for i in parts.size():
		if typeof(parts[i]) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = parts[i]
		var bone := Bone.new()
		bone.name = String(part.get("name", "part_%d" % i))
		bone.part = part
		bone.index = i
		bone.parent = String(part.get("parent", ""))
		bone.rest = PartGeometry.rotation_basis(part.get("rotation"))
		bone.joint = part["joint"] if typeof(part.get("joint")) == TYPE_DICTIONARY else {}
		bone.pivot = PartGeometry.offset_m(bone.joint.get("pivot", [0, 0, 0]))

		bone.node = Node3D.new()
		bone.node.name = bone.name
		var mesh: MeshInstance3D = mesh_for.call(part, i)
		# The mesh sits at `-pivot` *in the bone's own frame*, which is what puts the part's
		# centre back where its `offset` said it was once the bone has been placed at the pivot.
		mesh.transform = Transform3D(mesh.basis, mesh.position - bone.pivot)
		bone.node.add_child(mesh)

		bones[bone.name] = bone
		order.append(bone.name)

	for name in order:
		var bone: Bone = bones[name]
		var host := root
		var correction := Vector3.ZERO
		if bone.parent != "" and bones.has(bone.parent):
			var above: Bone = bones[bone.parent]
			host = above.node
			# The child's `offset` is measured from the parent's *centre*, and the parent node
			# stands at the parent's *pivot*. One subtraction reconciles the two, done once at
			# build rather than every frame.
			correction = -above.pivot
		elif bone.parent != "":
			warnings.append("%s: part `%s` is parented to `%s`, which is not a part of it" % [
				asset_id, bone.name, bone.parent])

		var offset := PartGeometry.offset_m(bone.part.get("offset"))
		bone.node.transform = Transform3D(bone.rest, correction + offset + bone.rest * bone.pivot)
		host.add_child(bone.node)

	rest_pose()
	return root


## Put every joint back where the file says it idles. `rest` is in the joint's own units —
## degrees about a hinge's axis, modules along a slider — and defaults to zero, which is the
## pose the part's `rotation` already describes.
func rest_pose() -> void:
	for name in order:
		var bone: Bone = bones[name]
		if bone.articulates() and bone.joint.has("rest"):
			_drive(bone, float(bone.joint["rest"]))
		else:
			_drive(bone, 0.0)


## Turn a hinge or run a slider, in the units its limits are written in. Clamped to those
## limits, because a joint that can be driven past them is a joint whose limits are a comment.
## Returns what was actually applied, so a caller that cares can see it was held back.
func drive(name: String, amount: float) -> float:
	if not bones.has(name):
		return 0.0
	var bone: Bone = bones[name]
	if not bone.articulates():
		return 0.0
	return _drive(bone, clampf(amount, limit_low(name), limit_high(name)))


## Point a bone from one world-space point at another — how an IK-solved limb is applied.
##
## Deliberately unclamped, and this is the one place the rig does not police its own limits.
## The solver answers a geometry question and the answer is a direction, not an angle about a
## named axis, so clamping it here would mean decomposing a basis into a joint's units on
## every bone every frame in order to fight the thing that just computed it. The check that
## replaces it is `strained()`: the driver asks whether the solved pose is inside the declared
## range and can lower the body, shorten the stride or refuse the target — a correction made
## where the information is, rather than a silent snap made here.
func aim(name: String, from: Vector3, to: Vector3, bend: Vector3) -> void:
	if not bones.has(name):
		return
	var bone: Bone = bones[name]
	# The solver works in the asset's own space; a bone's transform is relative to its parent.
	# Undoing the chain above it is what keeps a hoof pointing at the ground rather than at
	# wherever the shoulder happens to be facing. Composed by walking the bones rather than by
	# asking for a global transform, so this answers the same on a rig that is not in a scene
	# tree yet — which is how every test and the `--rig` inspector look at one.
	bone.node.basis = space_basis(bone.parent).inverse() * TwoBoneIK.bone_basis(from, to, bend)


## How far past its limits a bone has been posed, in the joint's own units, or 0 when it is
## inside them. The counterpart to `aim` being unclamped.
func strained(name: String) -> float:
	if not bones.has(name):
		return 0.0
	var bone: Bone = bones[name]
	if not bone.articulates():
		return 0.0
	var at := driven(name)
	return maxf(0.0, maxf(limit_low(name) - at, at - limit_high(name)))


## What a joint is currently driven to, in its own units, measured back off the node rather
## than remembered — so a bone posed by `aim` reports an angle the same way one posed by
## `drive` does, and a test can check either without knowing which was used.
func driven(name: String) -> float:
	if not bones.has(name):
		return 0.0
	var bone: Bone = bones[name]
	if bone.type() == "slider":
		var travel := bone.node.position - _rest_position(bone)
		return travel.length() / PartGeometry.MODULE * signf(travel.dot(_axis(bone)))
	return rad_to_deg(_twist(bone.rest.inverse() * bone.node.basis, _axis(bone)))


func limit_low(name: String) -> float:
	return _limit(name, 0, -180.0)


func limit_high(name: String) -> float:
	return _limit(name, 1, 180.0)


func has(name: String) -> bool:
	return bones.has(name)


func bone(name: String) -> Bone:
	return bones[name] if bones.has(name) else null


## Where a bone's origin — its joint — sits in the asset's own space, with the current pose
## applied. What a leg's IK is solved from.
func joint_position(name: String) -> Vector3:
	if not bones.has(name):
		return Vector3.ZERO
	var node: Node3D = (bones[name] as Bone).node
	var out := Vector3.ZERO
	while node != null and node != root:
		out = node.transform * out
		node = node.get_parent() as Node3D
	return out


func _drive(bone: Bone, amount: float) -> float:
	if bone.type() == "slider":
		bone.node.position = _rest_position(bone) + _axis(bone) * amount * PartGeometry.MODULE
	else:
		bone.node.basis = bone.rest * Basis(_axis(bone), deg_to_rad(amount))
	return amount


## A hinge names its axis; a ball turns about whatever it is aimed at and a slider defaults to
## running along the bone. `-Z` is forward everywhere in this game (ART-BIBLE §7), so a piston
## with no axis written on it travels the way the part points.
func _axis(bone: Bone) -> Vector3:
	var named: Variant = bone.joint.get("axis", "")
	match named if typeof(named) == TYPE_STRING else "":
		"x": return Vector3.RIGHT
		"y": return Vector3.UP
		"z": return Vector3.BACK
		_: return Vector3.BACK if bone.type() == "slider" else Vector3.RIGHT


## The rotation about `axis` contained in a turn, and only that — the twist half of a
## swing-twist split. A bone posed by `drive` is a pure twist and this returns exactly what
## was asked for; a bone posed by `aim` has swung as well, and this answers the part of it the
## joint's limits are actually written about instead of an Euler angle whose value depends on
## which order the axes were unpacked in.
static func _twist(turn: Basis, axis: Vector3) -> float:
	var q := turn.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(q.x, q.y, q.z).dot(axis), q.w)


## A bone's orientation in the asset's own space, composed from the chain above it, the named
## bone included. Public because a bone's *tip* is `joint_position` plus this basis's -Z times
## the bone's length, and where a leg's foot rests is what `Locomotion` measures a creature's
## whole stance from. Walked rather than read off `global_transform`, as `joint_position` is.
func space_basis(name: String) -> Basis:
	var out := Basis.IDENTITY
	var at := name
	var depth := 0
	while at != "" and bones.has(at) and depth <= PartPlacement.MAX_PARENT_DEPTH:
		var bone: Bone = bones[at]
		out = bone.node.basis * out
		at = bone.parent
		depth += 1
	return out


func _rest_position(bone: Bone) -> Vector3:
	var correction := Vector3.ZERO
	if bone.parent != "" and bones.has(bone.parent):
		correction = -(bones[bone.parent] as Bone).pivot
	return correction + PartGeometry.offset_m(bone.part.get("offset")) + bone.rest * bone.pivot


func _limit(name: String, at: int, fallback: float) -> float:
	if not bones.has(name):
		return fallback
	var limits: Variant = (bones[name] as Bone).joint.get("limits")
	if typeof(limits) != TYPE_ARRAY or (limits as Array).size() != 2:
		return fallback
	return float((limits as Array)[at])
