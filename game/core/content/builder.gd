class_name AssetBuilder
extends RefCounted
## The part table becomes a thing in the world. FORMAT-SPEC §5–§6, ART-BIBLE §1b and §3.
##
## Everything before this point reads files and argues about them. This is where a validated
## asset turns into meshes, collision shapes and rigid bodies — and it is deliberately the
## *only* place that happens, because the moment a second code path builds something the
## format stops being the description of the game and becomes one of two descriptions.
##
## Three decisions are made here and they are worth stating plainly:
##
## **Mass is derived and nothing types it.** Volume × the material's density
## (MATERIAL-SPEC §2). `hollow` swaps solid volume for a one-module shell, which is what a
## crate actually is. A `mass` field still overrides it, per part or per asset, and the
## built asset records that it was overridden so the number can be traced back to a person.
##
## **Colliders are declared, never derived from the visual parts.** That is the
## compound-collider lesson from the tank (FORMAT-SPEC §6), and it is why a forty-part hull
## costs the broad phase one box and not forty.
##
## **A thing is one body or a stack of bricks, and the format says which.** A crate is one
## body; a wall is not, or it falls over as a single slab. `body` decides it, defaulting by
## kind — structures and buildables come apart, everything else does not.
##
## Where the parts go is not here: `PartPlacement` composes the `parent` chains, makes the
## seeded jitter and fits the envelope, and knows nothing about mass, colour or bodies. The
## split is what lets a future editor and a placement preview ask where a part lands without
## instantiating a `RigidBody3D` to find out.

## How an asset occupies the physics world.
const BODY_MODES := ["single", "bricks"]

## The default per kind, for the assets that do not say. A structure is a stack of bricks
## that happens to be standing up, and that is the entire reason a wall collapsing looks
## like anything.
const BODY_BY_KIND := {
	"structure": "bricks",
	"buildable": "bricks",
}
const DEFAULT_BODY := "single"

## ART-BIBLE §3. Multiplied into the base colour per part, so a wall of one colour reads as
## masonry instead of as a texture.
const SHADES := [1.0, 0.92, 0.85, 1.06]

var errors: Array[String] = []
var warnings: Array[String] = []

var _surfaces: Dictionary = {}      ## colour key -> StandardMaterial3D


## Build one asset. The result is a node holding every body the asset produced; the caller
## adds it to whatever scene it belongs in, which is what makes this testable without one.
func build(asset: ResolvedAsset, materials: MaterialSet, palette: Palette) -> BuiltAsset:
	var out := BuiltAsset.new()
	out.name = asset.id.replace(":", "_")
	out.asset_id = asset.id
	out.kind = asset.kind()
	out.destructible = bool(asset.data.get("destructible", true))

	var mode := body_mode_of(asset)
	var hollow := bool(asset.data.get("hollow", false))
	var placement := PartPlacement.new()
	var placed := placement.place(asset)
	errors.append_array(placement.errors)

	if mode == "bricks":
		for entry in placed:
			var body := _brick_body(asset, entry, hollow, materials, palette)
			out.bodies.append(body)
			out.add_child(body)
			out.mass += body.mass
	else:
		var body := _single_body(asset, placed, hollow, materials, palette)
		out.bodies.append(body)
		out.add_child(body)
		out.mass = body.mass

	if asset.data.has("mass"):
		out.mass = maxf(0.0, float(asset.data["mass"]))
		out.mass_declared = true
		if mode == "single":
			out.bodies[0].mass = maxf(_min_mass(), out.mass)
		else:
			_spread_mass(out)
	return out


## Every part of the asset in one body, colliding as the boxes the author declared.
func _single_body(asset: ResolvedAsset, placed: Array, hollow: bool,
		materials: MaterialSet, palette: Palette) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "body"
	body.add_to_group(&"bricks")

	var total := 0.0
	for entry in placed:
		var part: Dictionary = entry["part"]
		var mesh := _mesh_of(asset, part, entry["index"], palette)
		mesh.transform = entry["transform"] * mesh.transform
		body.add_child(mesh)
		total += _mass_of(part, hollow, materials)

	for shape in _declared_colliders(asset, placed):
		body.add_child(shape)
	body.mass = maxf(_min_mass(), total)
	return body


## One part, one body — the wall case. Collision follows the part's own shape here, which
## the declared-collider rule does not cover and does not want to: a brick is a box, and a
## pipe lying in the mud is a cylinder.
func _brick_body(asset: ResolvedAsset, entry: Dictionary, hollow: bool,
		materials: MaterialSet, palette: Palette) -> RigidBody3D:
	var part: Dictionary = entry["part"]
	var body := RigidBody3D.new()
	body.name = String(part.get("name", "part_%d" % entry["index"]))
	body.add_to_group(&"bricks")
	body.transform = entry["transform"]

	var mesh := _mesh_of(asset, part, entry["index"], palette)
	var jitter := PartPlacement.jitter_basis(asset, part, entry["index"])
	mesh.transform = Transform3D(jitter * mesh.basis, mesh.origin)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.shape = PartGeometry.collision_for(
		String(part.get("shape", "block")), PartPlacement.size_of(part, jitter))
	body.add_child(shape)

	body.mass = maxf(_min_mass(), _mass_of(part, hollow, materials))
	return body


func _mesh_of(asset: ResolvedAsset, part: Dictionary, index: int,
		palette: Palette) -> MeshInstance3D:
	var shape := String(part.get("shape", "block"))
	var mesh := MeshInstance3D.new()
	mesh.name = String(part.get("name", "part_%d" % index))
	mesh.mesh = PartGeometry.mesh_for(shape, PartGeometry.size_m(part.get("size")))
	mesh.transform = Transform3D(PartGeometry.axis_fix(shape), Vector3.ZERO)
	mesh.material_override = _surface(_shade(asset, part, index, palette))
	return mesh


## Declared colliders, always boxes, in the asset's own space. An asset with none gets one
## box fitted around everything it is made of — not a shape per part, which is the thing the
## rule exists to prevent, and not nothing, which is a crate a player walks through.
func _declared_colliders(asset: ResolvedAsset, placed: Array) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	var declared: Variant = asset.data.get("collider")
	if typeof(declared) == TYPE_ARRAY and not (declared as Array).is_empty():
		for entry in declared as Array:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var collider: Dictionary = entry
			var shape := CollisionShape3D.new()
			shape.shape = PartGeometry.box_shape(PartGeometry.size_m(collider.get("size")))
			shape.position = PartGeometry.offset_m(collider.get("offset"))
			out.append(shape)
		return out

	var box := PartPlacement.envelope(placed)
	if box.size == Vector3.ZERO:
		return out
	var fitted := CollisionShape3D.new()
	fitted.shape = PartGeometry.box_shape(box.size)
	fitted.position = box.get_center()
	out.append(fitted)
	return out


## Volume × density, unless somebody wrote a number down. MATERIAL-SPEC §2.
func _mass_of(part: Dictionary, hollow: bool, materials: MaterialSet) -> float:
	if part.has("mass"):
		return maxf(0.0, float(part["mass"]))
	var volume := PartGeometry.volume_m3(
		String(part.get("shape", "block")), PartGeometry.size_m(part.get("size")), hollow)
	return materials.mass_for(StringName(String(part.get("material", ""))), volume)


## An asset-level `mass` on a stack of bricks is a statement about the whole stack, so it
## is spread across the bricks in proportion to what each of them already weighed.
func _spread_mass(out: BuiltAsset) -> void:
	var before := 0.0
	for body in out.bodies:
		before += body.mass
	if before <= 0.0 or out.bodies.is_empty():
		for body in out.bodies:
			body.mass = maxf(_min_mass(), out.mass / float(maxi(1, out.bodies.size())))
		return
	var scale := out.mass / before
	for body in out.bodies:
		body.mass = maxf(_min_mass(), body.mass * scale)


## Jolt refuses a zero-mass dynamic body, and a part whose material has no density yet —
## or whose size rounds to nothing — would be exactly that. A gram is close enough to
## nothing to behave like it and is a number the solver can work with.
func _min_mass() -> float:
	return 0.001


func _shade(asset: ResolvedAsset, part: Dictionary, index: int, palette: Palette) -> Color:
	var base := palette.colour(StringName(String(part.get("colour", ""))))
	var shade: float = SHADES[PartPlacement.rng(asset, index, 2).randi() % SHADES.size()]
	return Color(base.r * shade, base.g * shade, base.b * shade, base.a)


## One material per colour rather than one per part. Thousands of unique
## `StandardMaterial3D`s cost more than the physics they are sitting on.
func _surface(colour: Color) -> StandardMaterial3D:
	var key := colour.to_rgba32()
	if _surfaces.has(key):
		return _surfaces[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	_surfaces[key] = mat
	return mat


## Static, because the validator needs the same answer. If it worked this out for itself the
## two would drift, and the shape that drift takes is a warning about a fallback that never
## happens — which teaches an author to ignore warnings.
static func body_mode_of(asset: ResolvedAsset) -> String:
	var declared := String(asset.data.get("body", ""))
	if declared != "":
		return declared
	return String(BODY_BY_KIND.get(asset.kind(), DEFAULT_BODY))
