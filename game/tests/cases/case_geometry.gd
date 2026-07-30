extends TestCase
## The five primitives as geometry: volumes, winding, and the shapes they collide as.
##
## Separate from the builder case because these fail differently from everything else. A
## wrong volume constant is a tank that floats, a wrong winding is a ramp you can see
## straight through, and neither shows up in a game that boots fine and passes every other
## test. They are arithmetic, so they are checked as arithmetic — no loader, no fixtures, no
## scene.
##
## Godot's own convention is asserted rather than assumed, off `BoxMesh`. The wedges are hand
## built and depend on it; if a future engine version flips it, this case is what says so.

## A tenth of a millimetre cubed. The volumes here are order 1 m³, so anything this far apart
## is a different formula rather than a different rounding.
const EPSILON := 0.0001


func case_name() -> String:
	return "geometry"


func run(t: TestContext) -> void:
	_volumes(t)
	_hollow(t)
	_meshes_face_outward(t)
	_axes(t)
	_collision_shapes(t)
	_modules(t)


## Exact, not approximate. Half a box for a wedge, a third for a corner wedge — it is a
## pyramid over one corner, and a pyramid is a third of its box — and the round two from
## their own formulae. A constant wrong by a factor of two is an asset that weighs twice what
## it looks like it should, which reads as bad physics rather than as bad arithmetic.
func _volumes(t: TestContext) -> void:
	var m := Vector3.ONE
	t.near(PartGeometry.volume_m3("block", m), 1.0, EPSILON, "a one-metre block is one cubic metre")
	t.near(PartGeometry.volume_m3("wedge", m), 0.5, EPSILON, "a wedge is half its box")
	t.near(PartGeometry.volume_m3("corner_wedge", m), 1.0 / 3.0, EPSILON,
		"a corner wedge is a third of it")
	t.near(PartGeometry.volume_m3("cylinder", m), PI * 0.25, EPSILON, "a cylinder is πr²l")
	t.near(PartGeometry.volume_m3("sphere", m), 4.0 / 3.0 * PI * 0.125, EPSILON,
		"a sphere is 4/3πr³")

	# An unknown shape cannot reach here — `PartRules` refuses anything outside the five — but
	# if one ever did, a box is the answer that makes it heavy rather than weightless.
	t.near(PartGeometry.volume_m3("torus", m), 1.0, EPSILON,
		"and anything unrecognised is measured as its box rather than as nothing")


## `hollow` is a one-module shell, which is what a crate actually is: boards around air.
func _hollow(t: TestContext) -> void:
	t.near(PartGeometry.volume_m3("block", Vector3.ONE, true), 1.0 - 0.8 * 0.8 * 0.8, EPSILON,
		"a hollow metre block is the metre less the 0.8 m of air inside it")

	# The case that would go negative if nobody clamped it. A one-module plank has no room for
	# a shell inside it, and the honest answer is that it is already solid.
	var thin := Vector3(0.8, 0.1, 0.8)
	t.near(PartGeometry.volume_m3("block", thin, true), PartGeometry.volume_m3("block", thin),
		EPSILON, "and a part thinner than two modules is left solid rather than made negative")


## The wedge and the corner wedge are built by hand, so their winding is a decision rather
## than an engine default — and a wedge wound inwards is invisible until it is on screen, at
## which point it is a ramp with no far side.
func _meshes_face_outward(t: TestContext) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	t.ok(_winding_is_negative_cross(box),
		"Godot still stores the negative of (b-a)×(c-a) as a face's normal")

	for shape in ["wedge", "corner_wedge"]:
		var mesh := PartGeometry.mesh_for(shape, Vector3(0.6, 0.4, 0.8))
		t.ok(mesh is ArrayMesh, "a %s is built by hand rather than borrowed from a prism" % shape)
		t.ok(_all_faces_outward(mesh), "and every one of its faces points out of the solid")

	t.ok(PartGeometry.mesh_for("cylinder", Vector3.ONE) is CylinderMesh, "a cylinder is a cylinder")
	t.ok(PartGeometry.mesh_for("sphere", Vector3.ONE) is SphereMesh, "a sphere is a sphere")
	t.ok(PartGeometry.mesh_for("block", Vector3.ONE) is BoxMesh, "and a block is a box")


## FORMAT-SPEC §5 measures a cylinder along Z because -Z is forward and a barrel points
## forward; `CylinderMesh` stands up Y. The fix belongs to the engine's primitive rather than
## to the part, which is why it is a function of shape alone.
func _axes(t: TestContext) -> void:
	var forward: Vector3 = PartGeometry.axis_fix("cylinder") * Vector3.BACK
	t.near(absf(forward.y), 1.0, EPSILON, "a cylinder's length is turned from Y onto Z")
	t.ok(PartGeometry.axis_fix("block") == Basis.IDENTITY, "and nothing else is turned at all")


## ART-BIBLE §1b: the round two keep their analytic shapes because those are cheap in Jolt,
## and the wedges get a hull rather than a box — a wedge that collides as a box is a ramp
## nobody can walk up, which is the entire point of having put a wedge there.
func _collision_shapes(t: TestContext) -> void:
	var m := Vector3.ONE
	t.ok(PartGeometry.collision_for("block", m) is BoxShape3D, "a block collides as a box")
	t.ok(PartGeometry.collision_for("cylinder", m) is CylinderShape3D, "a cylinder analytically")
	t.ok(PartGeometry.collision_for("sphere", m) is SphereShape3D, "and so does a sphere")
	t.ok(PartGeometry.collision_for("wedge", m) is ConvexPolygonShape3D,
		"a wedge collides as a hull, so the slope is a slope")
	t.ok(PartGeometry.collision_for("corner_wedge", m) is ConvexPolygonShape3D,
		"and so does a corner wedge")


## FORMAT-SPEC §3: one module is 0.1 m, and this is the only place in the game that turns a
## count of them into a distance.
func _modules(t: TestContext) -> void:
	t.near(PartGeometry.MODULE, 0.1, EPSILON, "a module is ten centimetres")
	t.ok(PartGeometry.size_m([8, 1, 4]).is_equal_approx(Vector3(0.8, 0.1, 0.4)),
		"eight modules is eighty centimetres")
	t.ok(PartGeometry.size_m("nonsense") == Vector3.ZERO,
		"and anything that is not three numbers measures nothing rather than crashing")

	var turned := PartGeometry.rotation_basis([0, 90, 0])
	t.near(absf((turned * Vector3.BACK).x), 1.0, EPSILON, "rotations are written in degrees")

	# Round shapes sit inside their own bounding box, so eight corners is the right envelope
	# for all five primitives and the collider fallback needs no special case.
	t.eq(PartGeometry.corners(Vector3.ONE).size(), 8, "a part occupies eight corners")


## Measured off `BoxMesh` rather than remembered, because remembering it wrong costs an
## afternoon of wondering why a ramp has no far side.
func _winding_is_negative_cross(mesh: Mesh) -> bool:
	for tri in _triangles(mesh):
		if _face_normal(tri).dot(tri[3]) < 0.9:
			return false
	return true


## Convex, so "away from the middle" and "outward" are the same claim — which is exactly why
## the builder can fix its own winding instead of keeping a face table correct by hand.
func _all_faces_outward(mesh: Mesh) -> bool:
	var tris := _triangles(mesh)
	if tris.is_empty():
		return false

	var middle := Vector3.ZERO
	for tri in tris:
		middle += (tri[0] + tri[1] + tri[2]) / 3.0
	middle /= float(tris.size())

	for tri in tris:
		var face: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		var out := _face_normal(tri)
		if out.dot(face - middle) <= 0.0 or out.dot(tri[3]) < 0.9:
			return false
	return true


## The winding claim itself, in one place: a face's normal is the negative of (b-a) × (c-a).
func _face_normal(tri: Array) -> Vector3:
	return (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()


## `[a, b, c, normal]` per triangle, de-indexed.
##
## Two traps, both found the hard way. `get_mesh_arrays()` belongs to `PrimitiveMesh` and an
## `ArrayMesh` does not have it, so the hand-built wedges need `surface_get_arrays`. And the
## engine's primitives are *indexed* — a `BoxMesh` is 24 vertices and 36 indices — so reading
## the vertex array in threes gives twelve triangles that do not exist, made of corners that
## never met. A winding test on those is noise that happens to be about 50% right.
func _triangles(mesh: Mesh) -> Array:
	var arrays: Array = []
	if mesh is PrimitiveMesh:
		arrays = (mesh as PrimitiveMesh).get_mesh_arrays()
	elif mesh.get_surface_count() > 0:
		arrays = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return []

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var order := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		order = arrays[Mesh.ARRAY_INDEX]
	else:
		for i in verts.size():
			order.append(i)

	var out: Array = []
	for i in range(0, order.size() - 2, 3):
		out.append([verts[order[i]], verts[order[i + 1]], verts[order[i + 2]], normals[order[i]]])
	return out
