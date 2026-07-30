class_name Projectile
extends RigidBody3D
## A shell / bullet / grenade. fuse == 0 -> explodes on first contact.
## fuse > 0 -> timed grenade: bounces around, then explodes.

var radius := 8.0
var power := 42.0
var fuse := 0.0
var ttl := 4.0
var source: Node = null    # the vehicle that fired it (immune to its own shell)
var main: Node3D = null
var exploded := false

func _ready() -> void:
	continuous_cd = true
	if fuse <= 0.0:
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(_on_hit)

func _on_hit(body: Node) -> void:
	if body == source:
		return
	_explode()

func _explode() -> void:
	if exploded:
		return
	exploded = true
	if main != null:
		main.queue_blast(global_position, radius, power, source)
	queue_free()

func _physics_process(dt: float) -> void:
	if fuse > 0.0:
		fuse -= dt
		if fuse <= 0.0:
			_explode()
			return
	ttl -= dt
	if ttl <= 0.0:
		if power >= 25.0:
			_explode()   # heavy shells air-burst at end of life
		else:
			queue_free() # rifle rounds just vanish
