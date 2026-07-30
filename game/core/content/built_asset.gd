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


func body_count() -> int:
	return bodies.size()


func awake_count() -> int:
	var awake := 0
	for body in bodies:
		if is_instance_valid(body) and not body.sleeping:
			awake += 1
	return awake


## The box every body of this asset fits inside, in world space. Used by the camera
## framing in the screenshot tool and by anything that needs to know how big a thing is
## without caring what it is made of.
func aabb() -> AABB:
	var box := AABB()
	var first := true
	for body in bodies:
		if not is_instance_valid(body):
			continue
		for child in body.get_children():
			if not (child is MeshInstance3D):
				continue
			var mesh_instance: MeshInstance3D = child
			var world := mesh_instance.global_transform * mesh_instance.get_aabb()
			if first:
				box = world
				first = false
			else:
				box = box.merge(world)
	return box
