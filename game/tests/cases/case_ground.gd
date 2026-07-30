extends TestCase
## The C2 test ground: three features, and a mesh that is actually the function it claims.
##
## This is a test for scaffolding, which is worth a sentence of justification. `TestGround`
## is deleted at C3 and everything it does will be done properly by `EARTH-SPEC.md` — but
## between now and then it is the ground truth that foot planting and body tilt are checked
## against, and an incorrect ruler makes every measurement taken with it wrong in a way that
## looks like the thing being measured. The scaffold gets a test because the tests that
## matter stand on it.
##
## Every expected number here was worked out by hand from the three constants blocks in
## `test_ground.gd`, not read off a run. The features were given whole-number bounds for
## exactly this reason.

const EPSILON := 0.0001


func case_name() -> String:
	return "test ground"


func run(t: TestContext) -> void:
	_features(t)
	_summed(t)
	_normals(t)
	_edges(t)
	_the_mesh_is_the_function(t)


## Each feature alone, sampled where the other two are zero. The ramp is read along z = 0,
## the lip along x = -8 (before the ramp starts), and the bowl at its own centre — which is
## at x = -5, also before the ramp, and at z = -4, well below the lip.
func _features(t: TestContext) -> void:
	t.near(TestGround.height_at(0.0, 0.0), 0.0, EPSILON, "the middle of the map is the datum")
	t.near(TestGround.height_at(2.0, 0.0), 0.0, EPSILON, "the ramp has not started at x = 2")
	t.near(TestGround.height_at(4.0, 0.0), 0.5, EPSILON, "and is half up two metres along")
	t.near(TestGround.height_at(6.0, 0.0), 1.0, EPSILON, "and fully up at the end of its run")
	t.near(TestGround.height_at(10.0, 0.0), 1.0, EPSILON,
		"and stays up — the plateau is flat, not a hill that comes back down")

	t.near(TestGround.height_at(-8.0, 3.0), 0.0, EPSILON, "the lip has not started at z = 3")
	t.near(TestGround.height_at(-8.0, 3.25), 0.2, EPSILON, "and is half up across one cell")
	t.near(TestGround.height_at(-8.0, 3.5), 0.4, EPSILON, "and is a knee-high step by z = 3.5")
	t.near(TestGround.height_at(-8.0, 9.0), 0.4, EPSILON, "and holds that height to the edge")

	t.near(TestGround.height_at(-5.0, -4.0), -0.8, EPSILON, "the bowl is 0.8 m deep at its centre")
	t.near(TestGround.height_at(-3.5, -4.0), -0.4, EPSILON, "and half that at half its radius")
	t.near(TestGround.height_at(-2.0, -4.0), 0.0, EPSILON, "and meets the ground at its rim")
	t.near(TestGround.height_at(-5.0, 0.0), 0.0, EPSILON, "and is nothing at all outside it")


## The three are summed rather than switched between, and the corner where two of them
## overlap is the one place that distinction is visible.
func _summed(t: TestContext) -> void:
	t.near(TestGround.height_at(8.0, 4.0), 1.4, EPSILON,
		"the plateau carries the lip — the two features add rather than one winning")
	t.near(TestGround.height_at(8.0, 4.0), TestGround.HIGHEST, EPSILON,
		"which is the highest point the map can return, and what the tint is scaled to")
	t.near(TestGround.height_at(-5.0, -4.0), TestGround.LOWEST, EPSILON, "as the bowl is the lowest")


## Gradients, as angles off vertical, because that is the number body tilt is written in and
## a normal quoted as three components is a number nobody can check by eye.
func _normals(t: TestContext) -> void:
	t.near(rad_to_deg(TestGround.normal_at(0.0, 0.0).angle_to(Vector3.UP)), 0.0, 0.01,
		"flat ground points straight up")
	t.near(rad_to_deg(TestGround.normal_at(4.0, 0.0).angle_to(Vector3.UP)), 14.036, 0.01,
		"the ramp's quarter gradient is about 14°")
	t.ok(TestGround.normal_at(4.0, 0.0).x < 0.0,
		"and leans back down the hill it climbs, which is the sign a tilt gets wrong")
	t.near(rad_to_deg(TestGround.normal_at(-8.0, 3.25).angle_to(Vector3.UP)), 38.66, 0.01,
		"the lip's face is a step to climb rather than a slope to walk")
	t.near(rad_to_deg(TestGround.normal_at(-5.0, -4.0).angle_to(Vector3.UP)), 0.0, 0.01,
		"the bottom of the bowl is level, by symmetry")
	# The rim is where a cone would have left a crease. A cosine arrives flat, and a foot
	# planted one probe either side of the rim gets nearly the same answer both times.
	t.ok(rad_to_deg(TestGround.normal_at(-2.0, -4.0).angle_to(Vector3.UP)) < 0.5,
		"and the rim is flat where it meets the ground, so there is no crease around it")


func _edges(t: TestContext) -> void:
	t.ok(TestGround.contains(0.0, 0.0), "the middle is on the map")
	t.ok(TestGround.contains(-12.0, 12.0), "so is a corner of it")
	t.ok(not TestGround.contains(12.5, 0.0), "and a step past the edge is not")
	# `height_at` answers past the edge because the ramp and lip clamp, and the answer is
	# meaningless. Asserted so that nobody later mistakes the clamp for a wall.
	t.near(TestGround.height_at(40.0, 0.0), 1.0, EPSILON,
		"height_at still answers off the map, which is why `contains` exists")

	# The features were placed on whole cells so the mesh can be exact. If somebody moves one
	# to a half-cell the mesh silently stops being the surface, and this is the line that says so.
	for edge in [TestGround.RAMP_START, TestGround.RAMP_START + TestGround.RAMP_RUN,
			TestGround.LIP_AT, TestGround.LIP_AT + TestGround.LIP_RUN, TestGround.EXTENT]:
		t.near(fmod(absf(float(edge)), TestGround.STEP), 0.0, EPSILON,
			"feature boundary %s lands on a cell edge" % edge)


## The claim the mesh makes: every vertex is on the analytic surface, and every triangle
## faces up. The second one is not fussiness — a winding mistake in a generated mesh is
## invisible in code review and shows up as a world you can see straight through.
func _the_mesh_is_the_function(t: TestContext) -> void:
	var ground := TestGround.make()
	var view: MeshInstance3D = null
	var shape: CollisionShape3D = null
	for child in ground.get_children():
		if child is MeshInstance3D:
			view = child
		elif child is CollisionShape3D:
			shape = child

	if view == null or view.mesh == null or shape == null:
		t.fail("the ground built without a mesh or without a collider")
		ground.free()
		return

	t.ok(shape.shape is ConcavePolygonShape3D, "the collider is a trimesh of the same surface")

	var verts: PackedVector3Array = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var cells := int(TestGround.EXTENT * 2.0 / TestGround.STEP)
	t.eq(verts.size(), cells * cells * 6, "one quad of two triangles per cell, across the map")

	var off_surface := 0
	var facing_down := 0
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		for v in [a, b, c]:
			if absf(v.y - TestGround.height_at(v.x, v.z)) > EPSILON:
				off_surface += 1
		# Godot's front faces wind clockwise, so the outward normal is (c-a) × (b-a).
		if ((c - a).cross(b - a)).y <= 0.0:
			facing_down += 1

	t.eq(off_surface, 0, "every vertex of the mesh sits exactly on `height_at`")
	t.eq(facing_down, 0, "and every triangle of it faces up rather than away")

	var box := view.mesh.get_aabb()
	t.near(box.size.x, TestGround.EXTENT * 2.0, EPSILON, "the surface spans the full map in x")
	t.near(box.size.z, TestGround.EXTENT * 2.0, EPSILON, "and in z")
	t.near(box.position.y, TestGround.LOWEST, 0.01, "with the bowl at the bottom of its bounds")
	ground.free()
