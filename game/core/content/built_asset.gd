class_name BuiltAsset
extends Node3D
## What comes out of the builder: the nodes for one asset, and the paper trail for them.
##
## Kept as a node rather than returned as a bare `Array` because the interesting facts about
## a built thing — which asset it came from, what it ended up weighing, whether it is one
## body or a stack of them — are things the rest of the game asks about at runtime, and a
## dictionary handed back at spawn time is a dictionary somebody has to keep.
##
## `bodies` is the list every system downstream actually works on. One entry for a crate,
## a hundred and fourteen for a wall.

var asset_id := ""
var kind := ""
var destructible := true

## Every rigid body this asset produced, in part order.
var bodies: Array[RigidBody3D] = []

## Total kilograms, derived (MATERIAL-SPEC §2) unless the asset overrode it.
var mass := 0.0

## Set when `mass` came from the file rather than from volume × density, so `--resolve`
## and the boot log can tell the difference between a number the world produced and a
## number somebody typed.
var mass_declared := false

## The bone hierarchy, for an asset that articulates, and `null` for everything else. This
## is what a locomotion driver, an animation state or a mounted rider poses; it holds meshes
## only, and moving it never moves a collider (RIG-SPEC §3).
var rig: Rig = null


func is_rigged() -> bool:
	return rig != null


func body_count() -> int:
	return bodies.size()


func awake_count() -> int:
	var awake := 0
	for body in bodies:
		if is_instance_valid(body) and not body.sleeping:
			awake += 1
	return awake


## The box every body of this asset fits inside, in this node's own space. Used by the camera
## framing in the screenshot tool and by anything that needs to know how big a thing is
## without caring what it is made of.
##
## Composed by walking down from each body rather than by asking every mesh for its global
## transform: a rigged asset's meshes are nested under bones, and `global_transform` on a node
## that is not in a scene tree yet is both an error in the log and an identity nobody wanted.
func aabb() -> AABB:
	var boxes: Array[AABB] = []
	for body in bodies:
		if is_instance_valid(body):
			_gather(body, body.transform, boxes)
	if boxes.is_empty():
		return AABB()
	var box := boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	return box


static func _gather(node: Node, so_far: Transform3D, boxes: Array[AABB]) -> void:
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var here: Transform3D = so_far * (child as Node3D).transform
		if child is MeshInstance3D:
			boxes.append(here * (child as MeshInstance3D).get_aabb())
		_gather(child, here, boxes)
