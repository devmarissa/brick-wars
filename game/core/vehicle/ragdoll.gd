class_name Ragdoll
extends RefCounted
## A rig, let go of. RIG-SPEC §1–§3, C6.
##
## The last clause of RIG-SPEC's own opening sentence, which is the whole rig system stated as one
## test:
##
## > A modder, using only data files, can add a horse that walks, trots and gallops with correctly
## > articulated two-bone legs, plants its feet on dug-up uneven ground, can be mounted and ridden,
## > **and ragdolls when killed** — without a single line of core code.
##
## Walks, trots and gallops: C2. Plants its feet on dug-up ground: C2 and C3. Mounted and ridden:
## earlier this milestone. This is the last one.
##
## ### It is a conversion, not a mode
##
## A rig is kinematic — a transform hierarchy driven by code, costing nothing and replicating as a
## handful of floats (RIG-SPEC §2). A ragdoll is physical: real bodies, real joints, gravity doing
## the work. There is no in-between and nothing toggles. The creature is driven right up until the
## moment it is not, and then it is a pile of jointed bodies standing exactly where its last pose
## put them.
##
## That "exactly" is the whole quality bar. A ragdoll that spawns its bodies from the *rest* pose
## rather than the posed one snaps — the creature flicks to a T-pose for one frame and then falls,
## and everybody sees it. So every body is built at the bone's current **world** transform, which is
## where the animation left it.
##
## ### Local-only, and that is a licence
##
## RIG-SPEC's table says `Ragdoll on death | physical, local-only`. Nothing here is replicated: two
## clients watching the same horse die will see it land differently, and that is *allowed*. It buys
## a lot — no determinism requirement, no seeded anything, no budget on the wire — and it is the
## reason a ragdoll can be physical at all in a game aiming at 100v100.
##
## ### The budget it was measured against
##
## RIG-SPEC §2 set the per-object cap at 20 physical constraints, and said plainly what the number
## was reasoned from: *"the horse's 14 joints are kinematic and do not spend this budget at all...
## What 14 bounds is what a ragdoll of the horse would cost."* This is the milestone where that
## sentence stops being hypothetical, so `convert` refuses to exceed the cap rather than discovering
## it at 100v100.

## RIG-SPEC §2's per-object cap on physical constraints, measured against the horse's 14 joints.
const MAX_CONSTRAINTS := 20

## How much a ragdoll's joints resist, in radians of swing and twist. Loose enough to flop, tight
## enough that a horse does not fold through itself — a ragdoll with no limits reads as a bag of
## bricks rather than as a body, which is the failure worth avoiding.
const SWING := 0.9
const TWIST := 0.5

## How heavily a ragdoll damps. Higher than a loose brick: a body has muscle and hide and does not
## bounce like a crate, and this is the cheapest way to say so.
const LINEAR_DAMP := 0.25
const ANGULAR_DAMP := 1.4


## Turn a built rig into a pile of jointed bodies, standing where its last pose left it.
##
## Returns `{ bodies, joints, why }`. A refusal comes back with `bodies` empty and `why` set — the
## caller keeps its kinematic creature, which is the right failure: a creature that stays animated
## is odd, and one that half-converts is broken.
static func convert(rig: Rig, into: Node3D, materials: MaterialSet,
		palette: Palette) -> Dictionary:
	if rig == null or rig.root == null or into == null:
		return { "bodies": [], "joints": [], "why": "nothing to let go of" }

	# Count first. Every bone but the root gets a joint to its parent, so the constraint count is
	# one less than the bone count — and it is checked *before* anything is built, because a
	# half-converted creature is worse than one that stays animated.
	var needed := maxi(0, rig.order.size() - 1)
	if needed > MAX_CONSTRAINTS:
		return { "bodies": [], "joints": [], "why":
			"%s would need %d physical constraints and RIG-SPEC §2 caps an object at %d" % [
				rig.asset_id, needed, MAX_CONSTRAINTS] }

	var bodies: Dictionary = {}
	var made: Array[RigidBody3D] = []
	for name in rig.order:
		var bone := rig.bone(String(name))
		if bone == null or bone.node == null:
			continue
		var body := _body_for(bone, into, materials, palette)
		if body != null:
			bodies[String(name)] = body
			made.append(body)

	var joints: Array[Node] = []
	for name in rig.order:
		var bone := rig.bone(String(name))
		if bone == null or bone.parent == "" or not bodies.has(bone.parent):
			continue
		if not bodies.has(String(name)):
			continue
		var joint := _joint(bodies[bone.parent], bodies[String(name)], bone, into)
		if joint != null:
			joints.append(joint)

	# The rig stops being anything. Leaving it visible under the ragdoll is the bug where a dead
	# horse is drawn twice, once falling and once still standing in its last pose.
	rig.root.visible = false
	return { "bodies": made, "joints": joints, "why": "" }


## One bone, as a body, at the world transform the animation left it in.
static func _body_for(bone: Rig.Bone, into: Node3D, materials: MaterialSet,
		palette: Palette) -> RigidBody3D:
	var size := PartGeometry.size_m(bone.part.get("size"))
	if size.length_squared() <= 0.0:
		return null
	var material := StringName(String(bone.part.get("material", "hide")))
	var body := Brick.spawn(into, bone.node.global_position, bone.node.global_basis,
		size, material, Vector3.ZERO, materials, palette)
	if body == null:
		return null
	body.name = "ragdoll_%s" % bone.name
	# A ragdoll is not rubble. It must not be culled by the debris sweep or launched by a blast as
	# loose bricks — it is a body, and it leaves the group that would have made it either.
	body.remove_from_group(&"bricks")
	body.linear_damp = LINEAR_DAMP
	body.angular_damp = ANGULAR_DAMP
	return body


## Parent to child, at the joint the rig already knew about. A cone-twist because that is what a
## shoulder, a hip and a hock all are — swing in a cone, limited twist about the bone.
static func _joint(parent: RigidBody3D, child: RigidBody3D, bone: Rig.Bone,
		into: Node3D) -> Node:
	var joint := ConeTwistJoint3D.new()
	joint.name = "ragdoll_joint_%s" % bone.name
	into.add_child(joint)
	# At the bone's own pivot rather than at its centre. A ragdoll jointed through the middle of
	# each limb bends in the wrong places, which reads as a broken skeleton rather than a dead one.
	joint.global_transform = Transform3D(child.global_basis,
		child.global_transform * (-bone.pivot))
	joint.node_a = parent.get_path()
	joint.node_b = child.get_path()
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, SWING)
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, TWIST)
	return joint


## What a ragdoll of this rig would cost, without building one. For the validator, and for anybody
## asking whether a creature is affordable before authoring the rest of it.
static func constraints_for(rig: Rig) -> int:
	return maxi(0, rig.order.size() - 1) if rig != null else 0


## Whether it fits RIG-SPEC §2's per-object cap.
static func affordable(rig: Rig) -> bool:
	return constraints_for(rig) <= MAX_CONSTRAINTS
