class_name CameraRig
extends Node3D
## First and third person, on one pivot. `CHECKLIST` §13, C4b.
##
## Deliberately small. §13 also wants ADS, shake, FOV rules, a HUD framework, a kill feed and a
## server browser — none of which is this, and C4b's scope note says so: the milestone exists so
## Marissa can *feel* the locomotion she has been unable to judge since C2, and everything past a
## camera you can look around with is the UI milestone's.
##
## ### Third person is the default, and that is a decision
##
## The three things waiting on C4b are all about watching a body move: the locomotion feel, the
## horse's trot and walk timings, and the collision fling between two creatures. None of them can be
## judged from inside the soldier's head. So `Tab` swaps, and the build starts in the view that
## answers the questions it was built to answer.
##
## ### The spring, and why it is not a camera problem
##
## The boom pulls in when something is between it and the head, which is the standard fix for a
## third-person camera clipping through a wall. It uses the same sweep a bullet does — `Projectile`
## — rather than its own ray, because two pieces of code that both answer "what is between these two
## points" will eventually disagree, and the one that disagrees quietly is the camera.

## How far back the boom sits when nothing is in the way.
const BOOM := 4.2

## Where the boom is anchored on the body: head height, so first person lands behind the eyes rather
## than in the chest.
const EYE_HEIGHT := 1.55

## How close the boom may be pulled before it gives up and goes inside the head. Below this the
## soldier's own body fills the screen, and first person is the better answer than a camera wedged
## in his collar.
const MIN_BOOM := 0.8

## Radians per pixel of mouse movement. §13 wants a sensitivity slider; this is the number it will
## multiply.
const SENSITIVITY := 0.0022

## How far up and down the view may go. Just short of straight up and straight down, because exactly
## vertical makes the yaw basis degenerate and the view rolls for one frame.
const PITCH_LIMIT := 1.55

var first_person := false
var yaw := 0.0
var pitch := -0.16

var _camera: Camera3D = null
var _ignore: Array[RID] = []


static func of(exclude: Array[RID] = []) -> CameraRig:
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	rig._ignore = exclude
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	cam.fov = 74.0
	rig._camera = cam
	rig.add_child(cam)
	return rig


func camera() -> Camera3D:
	return _camera


## Which way the player is asking to go, on the ground plane. The camera owns this rather than the
## controller because the camera is what "forward" means to somebody holding the keys.
func facing() -> Basis:
	return Basis(Vector3.UP, yaw)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * SENSITIVITY
		pitch = clampf(pitch - motion.relative.y * SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed(&"view_toggle"):
		first_person = not first_person
	elif event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# Click to take the mouse back. The other half of `Esc` releasing it — a game that can give
		# the cursor up and not take it again is a game you have to restart to keep playing.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Follow a body. Called from the controller's `_physics_process` rather than this node's own, so
## the camera moves in the same step the body does — a camera on `_process` lags the thing it is
## following by up to a frame, which reads as the world juddering rather than as the camera being
## late, and is the single most common way third person is got wrong.
func follow(target: Vector3) -> void:
	var head := target + Vector3.UP * EYE_HEIGHT
	global_position = head
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

	if first_person:
		_camera.position = Vector3.ZERO
		return

	# Behind and slightly up, pulled in by whatever is in the way. `Projectile.SKIN` keeps the near
	# plane off the surface rather than exactly on it, for the same reason a bounce resumes off it.
	var back := global_transform.basis.z * BOOM
	var found := Projectile.sweep(get_world_3d().direct_space_state, head, head + back, _ignore)
	var distance := BOOM
	if found["hit"]:
		distance = maxf(head.distance_to(Vector3(found["position"])) - Projectile.SKIN, MIN_BOOM)
	_camera.position = Vector3(0.0, 0.0, distance)
