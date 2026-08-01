class_name Brick
extends RigidBody3D
## One brick. Everything in a built structure is made of these.
##
## Almost empty from C0 until now, holding one line: *what a thing is made of decides what happens
## to it, not a counter on the object.* C5 is the milestone that makes that true, and this is where
## it starts — a brick that knows its own material, and a way to make one from nothing but numbers.
##
## ### Why a factory, and why now
##
## `AssetBuilder` already makes bricks from an asset's part table; that is how a wall becomes 120
## separate bodies. What did not exist is a way to make one with **no asset behind it**, and two
## things need exactly that:
##
## - **Debris.** A blast that shatters a vehicle or carves the earth spawns bricks nobody authored.
##   The old build's `spawn_brick` did this, and it is part of what C5 ports.
## - **The blast fixture.** `blast-fixture/` stands a 120-brick wall at a fixed place, size and
##   material, and it has to build the *same* wall the old build did — otherwise every number it
##   measures afterwards is measuring the scenario rather than the blast.
##
## So this is core rather than test scaffolding. It is the smaller half of
## `AssetBuilder._brick_body` — same mesh, same collider, same group, same mass from the same
## material density — with the asset lookup taken out.
##
## ### It joins `bricks`
##
## The group is how a blast finds what to push and how the sleep discipline counts what is still
## moving. A brick outside it is invisible to both, which surfaces as "part of the wall did not
## react" and costs an afternoon.

## The least a brick may weigh, in kilograms. Matches `AssetBuilder`, for the same reason: a body
## light enough to be launched into orbit by a nudge is not a brick, it is a bug.
const MIN_MASS := 0.5

## How far a jittered brick may be turned, in radians per unit of `jitter`. A hand-stacked wall is
## not a lattice, and the fixture's wall was stacked with 0.04 of this.
const JITTER_RADIANS := 1.0

## How a brick behaves once it is moving, ported from the old build's `spawn_brick`, and every bit
## as load-bearing as the blast constants themselves.
##
## These were missing from the first version of this file, and the fixture found it: with no damping
## and no friction the same blast threw bricks 20–30% further and settled them at a different rate.
## The impulse was right and the aftermath was wrong, which is exactly the sort of thing "port
## verbatim" is meant to prevent and exactly the sort of thing you cannot spot by reading.
##
## `angular_damp` is the big one. At 0.8 a tumbling brick stops spinning quickly and comes to rest;
## near zero it rolls, and a wall of rolling bricks scatters much wider than a wall of tumbling ones.
const LINEAR_DAMP := 0.08
const ANGULAR_DAMP := 0.8
const FRICTION := 0.8

## Made once and shared. A `PhysicsMaterial` per brick would be thousands of identical resources.
static var _shared_physics: PhysicsMaterial = null

## Set from the part table at C1, or from the caller here. What this brick is made of is the only
## thing that decides what happens to it — there is no hit-point number and there never will be.
var material_id: StringName = &""


## Make one and put it in the world. Returns the body, already parented and placed.
##
## `jitter` turns the brick slightly off true, seeded from its own position so that the same wall
## built twice is the same wall. That determinism is not decoration: the fixture's whole claim is
## that it measures the blast rather than the arrangement, and a wall that stacked differently each
## run would make every metric noise.
static func spawn(into: Node, at: Vector3, rotation: Basis, size: Vector3, material: StringName,
		velocity: Vector3, materials: MaterialSet, palette: Palette,
		jitter := 0.0) -> Brick:
	if into == null or materials == null:
		return null

	var body := Brick.new()
	body.material_id = material
	body.add_to_group(&"bricks")

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _surface(materials, palette, material)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	body.mass = maxf(MIN_MASS, materials.mass_for(material, size.x * size.y * size.z))
	body.linear_damp = LINEAR_DAMP
	body.angular_damp = ANGULAR_DAMP
	body.physics_material_override = _physics()
	into.add_child(body)
	body.global_transform = Transform3D(
		_jittered(rotation, at, jitter) if jitter > 0.0 else rotation, at)
	if velocity != Vector3.ZERO:
		body.linear_velocity = velocity
	return body


## Every brick in the world. The one place the group name is written down, so a caller cannot get it
## subtly wrong and quietly push nothing.
static func all(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(&"bricks")


## A turn seeded off the brick's own position, so the same wall builds identically every run.
static func _jittered(rotation: Basis, at: Vector3, amount: float) -> Basis:
	var seeded := RandomNumberGenerator.new()
	# Quantised before hashing. Floating-point positions differing in their last bit would seed
	# differently, and the wall would be *almost* the same each run — worse than either extreme,
	# because it looks deterministic right up until a metric moves and nobody knows why.
	seeded.seed = hash(Vector3i(roundi(at.x * 100.0), roundi(at.y * 100.0), roundi(at.z * 100.0)))
	var swing := amount * JITTER_RADIANS
	return rotation \
		* Basis(Vector3.RIGHT, seeded.randf_range(-swing, swing)) \
		* Basis(Vector3.UP, seeded.randf_range(-swing, swing)) \
		* Basis(Vector3.FORWARD, seeded.randf_range(-swing, swing))


static func _surface(materials: MaterialSet, palette: Palette, material: StringName) -> Material:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = palette.colour(
		StringName(String(materials.get_def(material).get("colour", ""))))
	surface.roughness = 0.9
	return surface


static func _physics() -> PhysicsMaterial:
	if _shared_physics == null:
		_shared_physics = PhysicsMaterial.new()
		_shared_physics.friction = FRICTION
	return _shared_physics
