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

## §9's budget: *"Remesh: ≤ 8 chunks per frame."* Kept as the ceiling, but it is no longer the thing
## that decides when to stop — see `REMESH_BUDGET_MS`.
const REMESH_PER_FRAME := 8

## How long rebuilding may take in one frame, in milliseconds.
##
## §9 budgets chunks and this budgets time, which is a deviation with a measurement behind it
## (`DEVIATIONS-C4.md` C4). A chunk count is only a frame budget if you know what a chunk costs, and
## ours costs far more than eight-per-frame implies — so the count alone let a collapse rebuild
## every dirty chunk every frame and stall for a third of a second. Marissa's report was *"the
## terrain updates are super laggy."*
##
## Time is also the thing that stays true. When the mesher gets faster, or a chunk gets smaller, or
## somebody runs this on a slower machine, a millisecond budget still means what it says and a chunk
## count does not. The queue is never dropped — work deferred is work done next frame, and a
## collapse taking an extra few frames to finish redrawing is invisible where a 300 ms hitch is not.
const REMESH_BUDGET_MS := 4.0

## Standing water, as ART-BIBLE would have it: a palette colour, not a shader. `water` is one of
## the three materials §8 defers the numbers for, so this is a look rather than a substance — which
## is all §8 asks for. Translucent enough to read the trench floor through.
const WATER_COLOUR := Color(0.36, 0.42, 0.40, 0.72)

var field: EarthField = null

## The earth settling into its own angle of repose, a bounded number of cells a frame. Live rather
## than run-to-rest: a wall that has just lost its revetment should come down over a second or two
## while somebody watches, which is what §3 means by "real earth settling rather than a scripted
## animation".
var settle: EarthSettle = null

var _palette: Palette = null
var _materials: MaterialSet = null
var _meshes: Dictionary = {}        ## Vector2i -> MeshInstance3D
var _shapes: Dictionary = {}        ## Vector2i -> CollisionShape3D
var _queue: Array[Vector2i] = []
var _water: MeshInstance3D = null

# What remeshing actually costs, accumulated. Reported rather than guessed at, because the two
# halves of a rebuild — building the mesh and building the collision shape from it — are not the
# same price and the wrong guess sends you optimising the cheap one.
var _remeshes := 0
var _mesh_usec := 0
var _shape_usec := 0
var _worst_frame_usec := 0
var _said_settled := false
var _settle_usec := 0
var _worst_settle_usec := 0


static func of(field_: EarthField, palette: Palette, materials: MaterialSet) -> EarthTerrain:
	var terrain := EarthTerrain.new()
	terrain.name = "Earth"
	terrain.field = field_
	terrain._palette = palette
	terrain._materials = materials
	terrain.settle = EarthSettle.of(materials)
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
	_build_water()
	return built


## One flat sheet at the water table, across everything the field covers. EARTH-SPEC §8 is a level
## and a fill rule and explicitly not a simulation, so this is a plane — and a plane is the honest
## shape for it. Ground above the level is above the sheet and hides it; ground below is under it
## and reads as flooded, which is the whole effect and costs two triangles.
func _build_water() -> void:
	if field.water_cm <= EarthField.NO_WATER:
		return
	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "Water"
		var surface := StandardMaterial3D.new()
		surface.albedo_color = WATER_COLOUR
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		surface.roughness = 0.15
		# Lit from both sides: standing in a flooded dugout, the sheet is above you.
		surface.cull_mode = BaseMaterial3D.CULL_DISABLED
		_water.material_override = surface
		add_child(_water)

	var span := AABB()
	var first := true
	for key in field.chunks:
		var corner := Vector3(key.x * EarthChunk.SIZE * EarthGrid.CELL_M, 0.0,
			key.y * EarthChunk.SIZE * EarthGrid.CELL_M)
		var box := AABB(corner, Vector3(EarthChunk.SIZE * EarthGrid.CELL_M, 0.0,
			EarthChunk.SIZE * EarthGrid.CELL_M))
		span = box if first else span.merge(box)
		first = false
	if first:
		return

	var plane := PlaneMesh.new()
	plane.size = Vector2(span.size.x, span.size.z)
	_water.mesh = plane
	_water.position = Vector3(span.position.x + span.size.x * 0.5, field.water_cm * 0.01,
		span.position.z + span.size.z * 0.5)


## Mark a chunk for rebuild, and its neighbours with it: a column on a border helps decide the
## corner heights of the chunk next door, so a dig at the edge changes two meshes.
func touch(cell: Vector2i) -> void:
	if settle != null:
		settle.disturb(cell)
	var home := EarthGrid.chunk_of(cell)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var key := home + Vector2i(dx, dz)
			if field.chunks.has(key) and not _queue.has(key):
				_queue.append(key)


func pending() -> int:
	return _queue.size()


func _physics_process(_delta: float) -> void:
	# Settle first, then remesh, so a chunk the settle queue just moved earth in is rebuilt this
	# frame rather than next. The other way round shows the collapse a frame late, which on a
	# slump that takes a second is invisible — and on one that takes three frames is most of it.
	var was := settle.moved_cm
	var settle_began := Time.get_ticks_usec()
	settle.run(field)
	var settle_took := Time.get_ticks_usec() - settle_began
	_settle_usec += settle_took
	_worst_settle_usec = maxi(_worst_settle_usec, settle_took)
	if settle.moved_cm != was:
		for key in field.chunks:
			if (field.chunks[key] as EarthChunk).dirty and not _queue.has(key):
				_queue.append(key)
	var frame_began := Time.get_ticks_usec()
	var budget := int(REMESH_BUDGET_MS * 1000.0)
	var done := 0
	# At least one a frame however slow it is, or a chunk more expensive than the whole budget would
	# never be rebuilt at all and that part of the ground would simply stop updating.
	while not _queue.is_empty() and done < REMESH_PER_FRAME:
		_remesh(_queue.pop_front())
		done += 1
		if Time.get_ticks_usec() - frame_began >= budget:
			break
	_worst_frame_usec = maxi(_worst_frame_usec, Time.get_ticks_usec() - frame_began)

	# Say what the collapse cost, once, when the ground finally stops moving. The boot log is printed
	# before any of this has happened, so without this the only numbers anybody ever saw were the six
	# rebuilds of the initial build — which is not the case that was ever slow.
	if not _said_settled and _queue.is_empty() and settle.pending() == 0 and _remeshes > 6:
		_said_settled = true
		print("earth settled — " + _cost_report().strip_edges())


func _remesh(key: Vector2i) -> void:
	var began := Time.get_ticks_usec()
	var mesh := EarthMesher.build(field, key, _palette, _materials)
	_mesh_usec += Time.get_ticks_usec() - began
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
	var shaping := Time.get_ticks_usec()
	shape.shape = mesh.create_trimesh_shape()
	_shape_usec += Time.get_ticks_usec() - shaping
	_remeshes += 1

	if field.chunks.has(key):
		(field.chunks[key] as EarthChunk).dirty = false


## One line for the boot log: how much ground there is, and what it cost.
func report() -> String:
	var triangles := 0
	for key in _meshes:
		var mesh: ArrayMesh = (_meshes[key] as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			triangles += mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	return "earth: %d chunk(s), %d columns, %d triangles, %d kB of field, %d cell(s) shored\n  %s" % [
		field.chunks.size(), field.chunks.size() * EarthChunk.CELLS, triangles,
		field.chunks.size() * EarthChunk.CELLS * EarthChunk.BYTES_PER_COLUMN / 1024,
		field.shoring.size(), settle.report()] + _water_report() + _cost_report()


## What the rebuilding has cost so far. The number that matters is the worst *frame*, not the total:
## a rebuild that averages well and occasionally takes 40 ms is a rebuild that stutters.
func _cost_report() -> String:
	if _remeshes == 0:
		return ""
	return ("\n  remesh: %d rebuild(s), %.1f ms meshing + %.1f ms collision, " +
		"worst single frame %.1f ms; settle %.1f ms total, worst %.1f ms") % [
		_remeshes, _mesh_usec / 1000.0, _shape_usec / 1000.0, _worst_frame_usec / 1000.0,
		_settle_usec / 1000.0, _worst_settle_usec / 1000.0]


func _water_report() -> String:
	if field.water_cm <= EarthField.NO_WATER:
		return ""
	var flooded := 0
	for key in field.chunks:
		for z in EarthChunk.SIZE:
			for x in EarthChunk.SIZE:
				if field.is_flooded(key * EarthChunk.SIZE + Vector2i(x, z)):
					flooded += 1
	return "\n  water table at %d cm, %d column(s) under it" % [field.water_cm, flooded]
