class_name PartGeometry
extends RefCounted
## The five primitives as actual geometry: a mesh, a collision shape, and a volume.
##
## Everything else in the pipeline talks about parts in modules and in words. This is where
## `{"shape": "wedge", "size": [6, 4, 8]}` becomes triangles, a shape Jolt can collide, and
## the cubic metres the mass is derived from. One place, so the mesh a player sees, the
## shape they bump into and the mass they feel are all the same object by construction —
## a wedge that renders as a ramp and collides as a box is a step nobody can climb and an
## afternoon of wondering why.
##
## The wedge and the corner wedge are built by hand rather than taken from `PrismMesh`,
## because the orientation has to be *stated*. ART-BIBLE §7 fixes facing at -Z, so a wedge
## is high at -Z and slopes down toward +Z, and a corner wedge is that same wedge with its
## high edge collapsed to a single corner. An author writing `rotation` needs to know which
## way the thing points before they rotate it, and "whatever the engine's prism does" is
## not an answer.
##
## Volumes are exact, not approximated: half a box for a wedge, a third for a corner wedge
## (it is a pyramid over one corner), πr²l and 4/3πr³ for the round two. Mass is derived
## from volume × density and nowhere else (MATERIAL-SPEC §2), so a wrong constant here is a
## tank that floats.

## One module in metres. FORMAT-SPEC §3 — every size, offset and collider in the format is
## an integer count of these, and this is the only place that count becomes a distance.
const MODULE := 0.1

## Shell thickness for `hollow`, in modules. A crate is boards around air, and one module
## of board is the thinnest thing the grid can express — which is also about right for a
## packing crate at 1:1.
const SHELL_MODULES := 1


## Modules to metres. Anything shorter than a module is a rounding artefact and the format
## does not permit it, so this never has to be careful.
static func size_m(size: Variant) -> Vector3:
	if typeof(size) != TYPE_ARRAY or (size as Array).size() != 3:
		return Vector3.ZERO
	var v: Array = size
	return Vector3(float(v[0]), float(v[1]), float(v[2])) * MODULE


static func offset_m(offset: Variant) -> Vector3:
	return size_m(offset)


static func rotation_basis(rotation: Variant) -> Basis:
	if typeof(rotation) != TYPE_ARRAY or (rotation as Array).size() != 3:
		return Basis.IDENTITY
	var v: Array = rotation
	return Basis.from_euler(Vector3(
		deg_to_rad(float(v[0])), deg_to_rad(float(v[1])), deg_to_rad(float(v[2]))))


## Cubic metres of solid material. `hollow` swaps in a shell: the same shape with a shape
## one module smaller on every side taken out of it, which for anything already thinner
## than two modules leaves the volume alone rather than going negative.
static func volume_m3(shape: String, size: Vector3, hollow := false) -> float:
	var outer := _volume(shape, size)
	if not hollow:
		return outer
	var wall := 2.0 * SHELL_MODULES * MODULE
	var inner_size := Vector3(
		maxf(0.0, size.x - wall), maxf(0.0, size.y - wall), maxf(0.0, size.z - wall))
	return maxf(0.0, outer - _volume(shape, inner_size))


static func _volume(shape: String, size: Vector3) -> float:
	match shape:
		"wedge":
			return size.x * size.y * size.z * 0.5
		"corner_wedge":
			# A pyramid over one corner of the box, so a third of it.
			return size.x * size.y * size.z / 3.0
		"cylinder":
			var r := size.x * 0.5
			return PI * r * r * size.z
		"sphere":
			var rs := size.x * 0.5
			return 4.0 / 3.0 * PI * rs * rs * rs
		_:
			return size.x * size.y * size.z


## The visual mesh, sized in metres and centred on the part's own origin.
static func mesh_for(shape: String, size: Vector3) -> Mesh:
	match shape:
		"wedge":
			return _hull_mesh(_wedge_points(size), _wedge_faces())
		"corner_wedge":
			return _hull_mesh(_corner_points(size), _corner_faces())
		"cylinder":
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x * 0.5
			cyl.bottom_radius = size.x * 0.5
			cyl.height = size.z
			cyl.radial_segments = _segments(size.x)
			cyl.rings = 1
			return cyl
		"sphere":
			var sph := SphereMesh.new()
			sph.radius = size.x * 0.5
			sph.height = size.x
			sph.radial_segments = _segments(size.x)
			sph.rings = maxi(4, _segments(size.x) / 2)
			return sph
		_:
			var box := BoxMesh.new()
			box.size = size
			return box


## `CylinderMesh` and `SphereMesh` stand up the Y axis; the format measures a cylinder as
## `[diameter, diameter, length]` with the length along Z, because -Z is forward and a gun
## barrel points forward. This is that difference, and it is a property of the engine's
## primitives rather than of the part, so it lives here and not in the part table.
static func axis_fix(shape: String) -> Basis:
	return Basis(Vector3.RIGHT, PI * 0.5) if shape == "cylinder" else Basis.IDENTITY


## Collision for a part standing as its own body. ART-BIBLE §1b allows the round two their
## analytic shapes — they are cheap in Jolt — and gives the wedges a box or a convex hull.
## They get the hull, because the box is the ramp you cannot walk up.
##
## Declared colliders (FORMAT-SPEC §6) do not come through here. Those are always boxes,
## hand-fitted, capped at four, and that rule is not negotiable per shape.
static func collision_for(shape: String, size: Vector3) -> Shape3D:
	match shape:
		"wedge":
			return _hull_shape(_wedge_points(size))
		"corner_wedge":
			return _hull_shape(_corner_points(size))
		"cylinder":
			var cyl := CylinderShape3D.new()
			cyl.radius = size.x * 0.5
			cyl.height = size.z
			return cyl
		"sphere":
			var sph := SphereShape3D.new()
			sph.radius = size.x * 0.5
			return sph
		_:
			var box := BoxShape3D.new()
			box.size = size
			return box


static func box_shape(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box


## The eight-ish corners a part occupies, for fitting a box around a whole asset. Round
## shapes are inside their own bounding box by definition, so the box is the right envelope
## for all five without a special case.
static func corners(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var out := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(Vector3(h.x * sx, h.y * sy, h.z * sz))
	return out


## Radial segments scaled to size: a 3-module pipe does not need the 32 sides a 20-module
## boiler does, and in a game that puts thousands of these on a battlefield the difference
## is the frame budget.
static func _segments(diameter_m: float) -> int:
	return clampi(int(roundf(diameter_m / MODULE)) * 2 + 6, 8, 32)


## High at -Z, sloping down to +Z. Base is the full rectangle, top is a single edge.
static func _wedge_points(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	return PackedVector3Array([
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),      # 0 1  back base
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),        # 2 3  front base
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),        # 4 5  top edge
	])


static func _wedge_faces() -> Array:
	return [
		[0, 3, 2], [0, 2, 1],       # base, facing down
		[0, 1, 5], [0, 5, 4],       # the back wall at -Z
		[4, 5, 2], [4, 2, 3],       # the slope
		[0, 4, 3], [1, 2, 5],       # the two triangular sides
	]


## The same wedge with its top edge collapsed onto one corner — the transition piece where
## two wedged faces meet, which is the only thing this shape is for.
static func _corner_points(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	return PackedVector3Array([
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z),                                 # 4  the apex
	])


static func _corner_faces() -> Array:
	return [
		[0, 3, 2], [0, 2, 1],       # base
		[0, 1, 4],                  # the vertical face at -Z
		[0, 4, 3],                  # the vertical face at -X
		[1, 2, 4], [2, 3, 4],       # the two slopes that meet at the apex
	]


## Flat-shaded by construction: a vertex per corner per face, with the face's own normal.
## Smooth normals on a wedge round its edges off, and the whole look depends on edges
## staying hard (ART-BIBLE §1).
##
## Winding is fixed here rather than in the face tables, because getting it wrong is
## invisible until something is on screen and then it is a shape you can see straight
## through. Every face is turned to point away from the solid's centre — these are convex,
## so "away from the middle" is the same thing as "outward" — and Godot's convention was
## measured off `BoxMesh` rather than remembered: its stored normal is the *negative* of
## `(b-a) × (c-a)`, so a front face is wound clockwise seen from outside.
static func _hull_mesh(points: PackedVector3Array, faces: Array) -> ArrayMesh:
	var middle := Vector3.ZERO
	for p in points:
		middle += p
	middle /= float(points.size())

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for face in faces:
		var order: Array = face
		var a: Vector3 = points[order[0]]
		var b: Vector3 = points[order[1]]
		var c: Vector3 = points[order[2]]
		var n := (c - a).cross(b - a).normalized()
		if n.dot((a + b + c) / 3.0 - middle) < 0.0:
			order = [order[0], order[2], order[1]]
			n = -n
		for i in 3:
			verts.append(points[order[i]])
			normals.append(n)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _hull_shape(points: PackedVector3Array) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape
