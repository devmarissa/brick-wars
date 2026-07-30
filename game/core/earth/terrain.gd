class_name EarthTerrain
extends StaticBody3D
## The field, in the world: a mesh and a collider per chunk, rebuilt when the ground changes.
## EARTH-SPEC §2, §9.
##
## `EarthField` is the ground as data and knows nothing about Godot. This is the other half — the
## part that puts it on screen and gives it something to stand on — and it is deliberately thin,
## because everything interesting about the earth is arithmetic that wanted testing without a
## viewport.
##
## ### Collision is a trimesh for now, not a heightfield
##
## §2 asks for "a Jolt heightfield collider per chunk", which is cheaper, and this builds a
## `ConcavePolygonShape3D` from the mesh instead. Recorded in `DEVIATIONS-C3.md` with the argument:
## a heightfield cannot represent a vertical skirt as anything but a very steep ramp, and it cannot
## represent a tunnel at all — §6 already says voids need box colliders on the side. Starting with
## the shape that is *correct* and moving to the one that is *cheap* when there is a frame budget
## saying so is the right order; the other way round means discovering at C3b that the collision
## model cannot hold the feature the whole span system exists for.
##
## ### Remeshing is bounded
##
## §9 budgets eight chunks a frame. Digging dirties a chunk and its neighbours, and a shell dirties
## a lot at once, so the queue is drained a few at a time rather than all at once — a mine going
## off out of view still has to be real, but it does not have to be instant.

## §9's budget. Deliberately a constant rather than a guess at call sites.
const REMESH_PER_FRAME := 8

var field: EarthField = null

var _palette: Palette = null
var _materials: MaterialSet = null
var _meshes: Dictionary = {}        ## Vector2i -> MeshInstance3D
var _shapes: Dictionary = {}        ## Vector2i -> CollisionShape3D
var _queue: Array[Vector2i] = []


static func of(field_: EarthField, palette: Palette, materials: MaterialSet) -> EarthTerrain:
	var terrain := EarthTerrain.new()
	terrain.name = "Earth"
	terrain.field = field_
	terrain._palette = palette
	terrain._materials = materials
	return terrain


## Build every chunk the field currently has, at once. For a world coming up rather than for a
## dig — `_physics_process` is what keeps an edit inside the frame budget.
func build_all() -> int:
	for key in field.chunks:
		if not _queue.has(key):
			_queue.append(key)
	var built := 0
	while not _queue.is_empty():
		_remesh(_queue.pop_front())
		built += 1
	return built


## Mark a chunk for rebuild, and its neighbours with it: a column on a border helps decide the
## corner heights of the chunk next door, so a dig at the edge changes two meshes.
func touch(cell: Vector2i) -> void:
	var home := EarthField.chunk_of(cell)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var key := home + Vector2i(dx, dz)
			if field.chunks.has(key) and not _queue.has(key):
				_queue.append(key)


func pending() -> int:
	return _queue.size()


func _physics_process(_delta: float) -> void:
	for i in mini(REMESH_PER_FRAME, _queue.size()):
		_remesh(_queue.pop_front())


func _remesh(key: Vector2i) -> void:
	var mesh := EarthMesher.build(field, key, _palette, _materials)
	if mesh == null:
		return

	var view: MeshInstance3D = _meshes.get(key)
	if view == null:
		view = MeshInstance3D.new()
		view.name = "chunk_%d_%d" % [key.x, key.y]
		# Vertex colour, unshaded by any texture: ART-BIBLE's palette is the whole colour model and
		# the mesher has already folded the per-vertex variation in. `§8`'s texture decision, when
		# it lands, changes this material and nothing else.
		var surface := StandardMaterial3D.new()
		surface.vertex_color_use_as_albedo = true
		surface.roughness = 0.95
		view.material_override = surface
		add_child(view)
		_meshes[key] = view
	view.mesh = mesh

	var shape: CollisionShape3D = _shapes.get(key)
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "collide_%d_%d" % [key.x, key.y]
		add_child(shape)
		_shapes[key] = shape
	shape.shape = mesh.create_trimesh_shape()

	if field.chunks.has(key):
		(field.chunks[key] as EarthChunk).dirty = false


## One line for the boot log: how much ground there is, and what it cost.
func report() -> String:
	var triangles := 0
	for key in _meshes:
		var mesh: ArrayMesh = (_meshes[key] as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			triangles += mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	return "earth: %d chunk(s), %d columns, %d triangles, %d kB of field" % [
		field.chunks.size(), field.chunks.size() * EarthChunk.CELLS, triangles,
		field.chunks.size() * EarthChunk.CELLS * EarthChunk.BYTES_PER_COLUMN / 1024]
