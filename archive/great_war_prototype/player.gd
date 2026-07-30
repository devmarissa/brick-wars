class_name Player
extends CharacterBody3D
## Unturned-style soldier on Godot's battle-tested CharacterBody3D controller.
## The visual body hangs under $Body; its FRONT is modelled on -Z (Godot look_at convention).

const WALK := 12.0
const SPRINT := 22.0
const JUMP := 14.0
const GRAV := 40.0       # snappy, weighty fall (world gravity is for rigid bodies; we run our own here)

var knock := Vector3.ZERO # explosion knockback, decays
var cam_yaw := 0.0        # set by main each frame — movement is camera-relative

# -- third-person procedural animation (mirrors the first-person viewmodel states) --
# Body child order (built by main): 0-1 boots, 2-3 legs, 4 torso, 5 rig, 6 pack,
# 7 right arm, 8 left arm, 9 head, 10 helmet, 11 brim, 12 collar, 13-14 knees, then $Body/Rifle
var bases := []
var rifle_node: Node3D = null
var anim_state := ""
var anim_t := 0.0
var swing_phase := 0.0

## one-shot pose events driven by main: "fire", "dig", "throw"
func flash(state: String) -> void:
	anim_state = state
	anim_t = 0.45 if state == "dig" else 0.32

## rotate a limb around a pivot height instead of its center (hips / shoulders)
func _limb(idx: int, pivot_y: float, ang: float) -> void:
	var body := $Body
	var mi: Node3D = body.get_child(idx)
	var base: Vector3 = bases[idx]
	var d := base.y - pivot_y
	mi.rotation.x = ang
	mi.position = Vector3(base.x, pivot_y + d * cos(ang), base.z + d * sin(ang))

func _process(dt: float) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	if bases.is_empty():
		for c in body.get_children():
			bases.append(c.position)
		rifle_node = body.get_node_or_null("Rifle")
	var speed := Vector2(velocity.x, velocity.z).length()
	var amp := clampf(speed / 12.0, 0.0, 1.3) * 0.55
	if speed > 1.0 and is_on_floor():
		swing_phase += dt * clampf(speed, 0.0, 24.0) * 0.7
	var sw := sin(swing_phase) * amp
	_limb(2, -0.1, sw)      # legs stride
	_limb(3, -0.1, -sw)
	anim_t = maxf(anim_t - dt, 0.0)
	if anim_t > 0.0 and anim_state == "fire":        # rifle shouldered
		_limb(7, 0.8, 1.25)
		_limb(8, 0.8, 0.45)
		if rifle_node != null:
			rifle_node.rotation.x = 0.7
	elif anim_t > 0.0 and anim_state == "dig":       # shovel chop
		var c := sin(anim_t * 14.0) * 0.5 + 0.6
		_limb(7, 0.8, c)
		_limb(8, 0.8, c)
	elif anim_t > 0.0 and anim_state == "throw":     # overarm lob
		_limb(7, 0.8, 1.7 * (1.0 - anim_t / 0.32))
		_limb(8, 0.8, -sw)
	else:                                            # arms counter-swing the stride
		_limb(7, 0.8, -sw)
		_limb(8, 0.8, sw)
		if rifle_node != null:
			rifle_node.rotation.x = 0.0

func _physics_process(dt: float) -> void:
	var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir += fwd
	if Input.is_physical_key_pressed(KEY_S): dir -= fwd
	if Input.is_physical_key_pressed(KEY_D): dir += right
	if Input.is_physical_key_pressed(KEY_A): dir -= right
	var speed := SPRINT if Input.is_physical_key_pressed(KEY_SHIFT) else WALK
	var horiz := dir.normalized() * speed if dir.length_squared() > 0.0 else Vector3.ZERO

	if is_on_floor():
		velocity.y = -2.0
		if Input.is_physical_key_pressed(KEY_SPACE) and knock.y <= 0.1:
			velocity.y = JUMP
	else:
		velocity.y -= GRAV * dt

	velocity.x = horiz.x + knock.x
	velocity.z = horiz.z + knock.z
	if knock.y > 0.0:
		velocity.y += knock.y
		knock.y = 0.0
	knock *= maxf(1.0 - 5.0 * dt, 0.0)

	move_and_slide()

	# face where we're going (body front is on -Z, which is what look_at aims)
	if horiz.length_squared() > 0.1:
		var t := global_position + Vector3(horiz.x, 0.0, horiz.z)
		$Body.look_at(Vector3(t.x, $Body.global_position.y, t.z), Vector3.UP)
