class_name PartPlacement
extends RefCounted
## Where every part of an asset ends up, in the asset's own space, before anything is built.
##
## Split out of the builder because it is the half that has no opinion about physics. Nothing
## here knows what a material weighs or what colour a palette entry is — it composes `parent`
## chains into transforms, works out how far a jittered block wanders, and fits a box round
## the result. The builder then turns that into bodies.
##
## The seam is worth having beyond line count: this is the part a future editor, a placement
## preview and the collider fallback all want, and none of them want a `RigidBody3D`.
##
## The random draws live here too, and they are seeded rather than random. Two clients build
## the same wall down to the last brick or they have desynced, and `hash(id#index#stream)` is
## the entire mechanism standing in the way of that.

## Parenting depth is bounded for the same reason the `extends` chain is: a cycle in `parent`
## is a hang, and a hang at load time is indistinguishable from a crash.
const MAX_PARENT_DEPTH := 8

## How far a jittered part may be turned, in degrees. Jitter is a hand-stacked look, not a
## collapse — past a few degrees a wall reads as already ruined.
const JITTER_YAW_DEGREES := 6.0

var errors: Array[String] = []


## `[{ part, index, transform }]` in part order. Order matters, because the shade and jitter
## draws are seeded by position: a table that reshuffles between two clients is a wall that
## desyncs.
func place(asset: ResolvedAsset) -> Array:
	var by_name: Dictionary = {}
	for part in asset.parts():
		if typeof(part) == TYPE_DICTIONARY and part.has("name"):
			by_name[String(part["name"])] = part

	var out: Array = []
	var parts := asset.parts()
	for i in parts.size():
		if typeof(parts[i]) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = parts[i]
		out.append({ "part": part, "index": i, "transform": _compose(asset, part, by_name) })
	return out


## A part's own offset and rotation, with each ancestor's applied over the top of it. This is
## the machinery a rig hangs off: a hoof on a lower leg on an upper leg on a body.
func _compose(asset: ResolvedAsset, part: Dictionary, by_name: Dictionary) -> Transform3D:
	var local := Transform3D(
		PartGeometry.rotation_basis(part.get("rotation")),
		PartGeometry.offset_m(part.get("offset")))

	var current := part
	var depth := 0
	while current.has("parent") and depth < MAX_PARENT_DEPTH:
		var parent_name := String(current["parent"])
		if not by_name.has(parent_name):
			errors.append("%s: part `%s` is parented to `%s`, which is not a part of it" % [
				asset.id, current.get("name", "?"), parent_name])
			break
		var parent: Dictionary = by_name[parent_name]
		if parent == current:
			errors.append("%s: part `%s` is its own parent" % [asset.id, parent_name])
			break
		local = Transform3D(
			PartGeometry.rotation_basis(parent.get("rotation")),
			PartGeometry.offset_m(parent.get("offset"))) * local
		current = parent
		depth += 1
	if depth >= MAX_PARENT_DEPTH:
		errors.append("%s: part `%s` is more than %d levels of `parent` deep, or in a loop" % [
			asset.id, part.get("name", "?"), MAX_PARENT_DEPTH])
	return local


## The box that holds every placed part, in the asset's own space. Round shapes sit inside
## their own bounding box by definition, so the corners of the box are the right envelope for
## all five primitives without a special case.
static func envelope(placed: Array) -> AABB:
	var box := AABB()
	var first := true
	for entry in placed:
		var part: Dictionary = entry["part"]
		var xform: Transform3D = entry["transform"]
		for corner in PartGeometry.corners(PartGeometry.size_m(part.get("size"))):
			var point: Vector3 = xform * corner
			if first:
				box = AABB(point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(point)
	return box


## ART-BIBLE §3: jitter scales a block in x and z and turns it slightly about Y. Primitives
## are machined and never jitter — `PartRules` has already forced their value to zero, so this
## reads what it is given rather than deciding again.
static func jitter_basis(asset: ResolvedAsset, part: Dictionary, index: int) -> Basis:
	var jitter := float(part.get("jitter", 0.0))
	if jitter <= 0.0:
		return Basis.IDENTITY
	var draw := rng(asset, index, 1)
	var yaw := deg_to_rad(draw.randf_range(-JITTER_YAW_DEGREES, JITTER_YAW_DEGREES) * jitter)
	return Basis(Vector3.UP, yaw).scaled(Vector3(
		1.0 + draw.randf_range(-jitter, jitter), 1.0,
		1.0 + draw.randf_range(-jitter, jitter)))


## The size a part is actually drawn and collided at, jitter included. One function, because
## a brick that looks hand-stacked and collides as though it were not is a wall with invisible
## edges sticking out of it.
static func size_of(part: Dictionary, jitter: Basis) -> Vector3:
	return PartGeometry.size_m(part.get("size")) * jitter.get_scale()


## Seeded from the asset id and the part's position in the table, never from the clock. Two
## streams per part so that changing how a shade is drawn does not move every brick.
static func rng(asset: ResolvedAsset, index: int, stream: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = hash("%s#%d#%d" % [asset.id, index, stream])
	return generator
