class_name TestGround
extends StaticBody3D
## Uneven ground to plant feet on, one milestone before there is any earth to plant them in.
##
## **This file is scaffolding and is deleted at C3.** It is named `TestGround`, it lives in
## `core/mode` rather than in `core/earth`, and it says so here in the first paragraph, all
## three on purpose: `earth_module` is still an honest stub and must stay one until the thing
## `EARTH-SPEC.md` describes actually exists. A greybox that quietly moved into `core/earth`
## would make the module graph a lie for the sake of a screenshot.
##
## What C2 needs from the ground is only that it is *not flat*. Foot planting and body tilt
## are indistinguishable from a fixed offset on a plate — a leg solved against y = 0 looks
## exactly like a leg that was never solved at all — so there has to be something with a
## gradient under the creature before any of it can be said to work.
##
## ### Three features, chosen because a leg fails differently on each
##
## A **ramp**, because a slope is where body tilt shows: the pelvis has to stay level to the
## hill rather than to the world, and a soldier walking up a gradient with a horizontal pelvis
## reads as a man being dragged.
##
## A **lip**, because a step is where planting shows. A gradient can be faked by lowering the
## whole body; a knee-high curb cannot, because one foot is on it and the other is not, and
## the two answers differ by more than the body can split.
##
## A **bowl**, because a depression is where reach shows — a foot swinging out over a hollow
## finds nothing at stride length and the solver has to return `reached: false` rather than
## stretch. It is also the one curved feature, and it is a cosine rather than a cone because
## Marissa's note on terrain is that it has to feel organic rather than like a grid of chunky
## rectangles, and scaffolding that teaches the opposite habit is worse than none.
##
## Every number below is analytic and static: `height_at` is a pure function of two floats
## that needs no scene, no physics and no instance. That is what lets the locomotion tests
## check a gait against ground truth without standing a world up, and it is why the mesh is
## generated *from* the function rather than the function being sampled off a mesh.

## Half-width. The ground runs from -EXTENT to +EXTENT on both axes.
const EXTENT := 12.0

## Mesh resolution. Every feature boundary below is a whole multiple of it, so each vertex
## sits exactly on the analytic surface and the linear span between two of them *is* the
## analytic surface wherever the feature is a straight line. The bowl is the exception and
## the only place the mesh and the function disagree, by the sag of a chord.
const STEP := 0.5

## The ramp: flat, then a quarter gradient for four metres, then a plateau one metre up.
## 0.25 is about 14°, which is a road cutting rather than a mountainside — steep enough that
## a level pelvis looks wrong, shallow enough that failing to lift the feet does not.
const RAMP_START := 2.0
const RAMP_RUN := 4.0
const RAMP_RISE := 1.0

## The lip: 0.4 m over one cell, running the width of the map. Knee-high on a 1.8 m soldier
## and a 39° face, so it is a step to be climbed rather than a slope to be walked.
const LIP_AT := 3.0
const LIP_RUN := STEP
const LIP_RISE := 0.4

## The bowl: a cosine hollow, deepest at the middle, meeting the surrounding ground at zero
## gradient so there is no crease where it ends.
const BOWL_AT := Vector2(-5.0, -4.0)
const BOWL_RADIUS := 3.0
const BOWL_DEPTH := 0.8

## How far apart the two samples of a central difference are taken. Small enough to be local,
## large enough that two nearby heights do not cancel into float noise.
const PROBE := 0.01

const COLOUR_LOW := Color("4a4235")
const COLOUR_HIGH := Color("6f6349")

## The band the vertex tint is spread across — the bowl floor to the top of the lip on the
## plateau, which is the full range `height_at` can return.
const LOWEST := -BOWL_DEPTH
const HIGHEST := RAMP_RISE + LIP_RISE


## The surface, as a pure function. Three features summed rather than a piecewise switch, so
## the plateau carries the lip and the answer at any point is the sum of terms you can read
## off separately — which is what makes a failing assertion say *which* feature moved.
static func height_at(x: float, z: float) -> float:
	return _ramp(x) + _lip(z) + _bowl(x, z)


## Rises RAMP_RISE over RAMP_RUN and then stays up. A hill that came back down would put the
## interesting half of the map behind a second slope for no extra thing to test.
static func _ramp(x: float) -> float:
	return clampf((x - RAMP_START) / RAMP_RUN, 0.0, 1.0) * RAMP_RISE


static func _lip(z: float) -> float:
	return clampf((z - LIP_AT) / LIP_RUN, 0.0, 1.0) * LIP_RISE


## `0.5 * (1 + cos(pi * t))` runs from 1 at the centre to 0 at the rim with a flat tangent at
## both ends, which is the whole reason for the cosine: a hollow that met the ground at an
## angle would put a crease all the way round it, and a crease is a line of ground a foot
## planting solver has to be lucky about rather than correct about.
static func _bowl(x: float, z: float) -> float:
	var away := Vector2(x, z).distance_to(BOWL_AT)
	if away >= BOWL_RADIUS:
		return 0.0
	return -BOWL_DEPTH * 0.5 * (1.0 + cos(PI * away / BOWL_RADIUS))


## The surface normal, by central difference. Analytic rather than read off a collision hit
## for the same reason `height_at` is: a gait test that had to raycast would need a physics
## world, a frame to have ticked, and a body in it, and would then be testing three things.
static func normal_at(x: float, z: float) -> Vector3:
	var dx := height_at(x + PROBE, z) - height_at(x - PROBE, z)
	var dz := height_at(x, z + PROBE) - height_at(x, z - PROBE)
	return Vector3(-dx, 2.0 * PROBE, -dz).normalized()


## True when a point is on the ground at all. Past the edge `height_at` still answers — the
## ramp and lip both clamp — and the answer is meaningless, so anything that walks needs a
## way to ask rather than to find out by falling off.
static func contains(x: float, z: float) -> bool:
	return absf(x) <= EXTENT and absf(z) <= EXTENT


## Build the node: one mesh, one trimesh collider, both generated from `height_at`.
##
## A trimesh rather than a `HeightMapShape3D` even though the data is exactly a height map.
## The shape samples on a unit grid, so using it would mean scaling the collider by `STEP`,
## and a scaled collision shape is the kind of thing that works until the day somebody
## changes the resolution. This is scaffolding with a deletion date; the cheap boring shape
## is the right one.
static func make() -> TestGround:
	var ground := TestGround.new()
	ground.name = "TestGround"

	var mesh := ground._surface()
	var view := MeshInstance3D.new()
	view.name = "Surface"
	view.mesh = mesh
	# Tinted per vertex rather than per feature, so the picture reads as a landscape with
	# height in it instead of three flat patches somebody has coloured in.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	view.material_override = mat
	ground.add_child(view)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = mesh.create_trimesh_shape()
	ground.add_child(shape)
	return ground


## One line for the boot log, in the shape `sandbox.report()` uses.
static func report() -> String:
	return "ground: %.0f × %.0f m greybox — ramp %.2f over %.1f m, lip %.2f m, bowl %.2f m deep%s" % [
		EXTENT * 2.0, EXTENT * 2.0, RAMP_RISE / RAMP_RUN, RAMP_RUN, LIP_RISE, BOWL_DEPTH,
		"  (temporary; C3 replaces it)"]


func _surface() -> ArrayMesh:
	var cells := int(EXTENT * 2.0 / STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz in cells:
		for ix in cells:
			var x := -EXTENT + ix * STEP
			var z := -EXTENT + iz * STEP
			# Clockwise seen from above, which is Godot's front face. Both triangles start at
			# the low corner so a winding mistake would hide the whole surface rather than
			# every other triangle of it — a failure that is obvious instead of speckled.
			_face(st, [Vector2(x, z), Vector2(x + STEP, z), Vector2(x, z + STEP)])
			_face(st, [Vector2(x + STEP, z), Vector2(x + STEP, z + STEP), Vector2(x, z + STEP)])

	return st.commit()


func _face(st: SurfaceTool, corners: Array) -> void:
	var middle: Vector2 = (corners[0] + corners[1] + corners[2]) / 3.0
	for corner in corners:
		_corner(st, corner, middle)


## Normals come from `normal_at` rather than from `generate_normals()`, and are sampled a
## quarter of the way in from the corner toward the middle of the triangle rather than at the
## corner itself.
##
## That nudge is the whole of the difference between a lip and a fold. The vertices along the
## top of the step are shared by a 39° face and a flat one, and a normal taken *at* the shared
## corner straddles the crease and comes back with the average — so the one hard edge in the
## map renders as a soft roll, which is the feature that is there to be hard. Sampled just
## inside each face, the two triangles disagree exactly where the surface really does have a
## corner and agree everywhere it does not, so the bowl stays smooth without the lip going
## soft. Positions are untouched; this changes only what the light does.
func _corner(st: SurfaceTool, at: Vector2, middle: Vector2) -> void:
	var y := height_at(at.x, at.y)
	var shade := at.lerp(middle, 0.25)
	st.set_normal(normal_at(shade.x, shade.y))
	st.set_color(COLOUR_LOW.lerp(COLOUR_HIGH,
		clampf((y - LOWEST) / (HIGHEST - LOWEST), 0.0, 1.0)))
	st.add_vertex(Vector3(at.x, y, at.y))
