class_name Fire
extends Node
## Burning, spreading, and what is left afterwards. MATERIAL-SPEC §5–6, CORE-SPEC §2, C5.
##
## Fire is not in C5's done-condition, and it is in C5's paragraph — so it goes in last, and it goes
## in for one reason: it is the fourth step of the **medieval mining loop**, which `MATERIAL-SPEC` §6
## calls the acceptance test for materials the way the horse test was for rigs.
##
##     1. Dig a tunnel under the wall — chalk, hardness 2, holds a 65° face
##     2. Prop the roof with timber — support_vertical 70 holds the span
##     3. Pack it with brush and light it
##     4. Fire consumes the props: flammability 0.70, on_burnt: charred
##     5. charred_timber has support_vertical 20 — the span exceeds what the props hold
##     6. The tunnel collapses, the ground subsides, the wall above it comes down
##
## Every step is a number in the material file. Nothing here knows what a prop is, what a tunnel is,
## or that step 5 follows step 4 — a burnt prop is simply a brick whose material changed, and the
## support calculation that was already there reads the new number.
##
## **That is the whole argument for materials being in the core rather than in the Great War pack.**
## The same code path is a mine gallery under a trench line, and the counter-play is counter-mining,
## and nobody writes either.
##
## ### It changes what a thing is made of, and stops
##
## When fuel runs out the brick's `material_id` becomes the material's `becomes` — timber to
## `charred_timber` — and that is the entire consequence. Fire does not weaken anything, collapse
## anything or tell anybody. The support calculation reads `material_id` and gets a different answer
## than it did a minute ago, which is the mechanism §6 is describing.
##
## Where `becomes` is `null` the thing is consumed outright: thatch and canvas leave nothing, which
## is why `on_burnt` says `ash` and `gone` rather than naming a material.
##
## ### Determinism
##
## Spread rolls against a seeded generator, not `randf()`. Two clients watching the same fire have
## to see the same props fail in the same order or the tunnel collapses in one and not the other —
## the same discipline as the earth's integer arithmetic and the blast's spread.

## How often burning is stepped, in seconds. Fire is slow, and a fire that recomputed spread every
## frame would spend a frame budget arguing with itself about a thing that takes a minute.
const TICK := 0.25

## How much of the roll a material's flammability accounts for. A material at 1.0 catches every
## chance it gets; 0.0 never catches, which is what makes chalk and steel fireproof without a flag.
const CATCH_SCALE := 1.0

var burning := 0
var burnt := 0
var consumed := 0

var _lit: Dictionary = {}          ## RigidBody3D -> fuel remaining
var _materials: MaterialSet = null
var _palette: Palette = null
var _rng := RandomNumberGenerator.new()
var _since := 0.0


static func of(materials: MaterialSet, palette: Palette, seed := 1) -> Fire:
	var fire := Fire.new()
	fire.name = "Fire"
	fire._materials = materials
	fire._palette = palette
	fire._rng.seed = seed
	return fire


## Set something alight. Refuses what will not burn, which is a material question and not a flag.
func light(brick: Brick) -> bool:
	if brick == null or _materials == null or _lit.has(brick):
		return false
	var def := _materials.get_def(brick.material_id)
	if float(def.get("flammability", 0.0)) <= 0.0:
		return false
	var fire: Variant = def.get("fire")
	if typeof(fire) != TYPE_DICTIONARY:
		return false
	_lit[brick] = float((fire as Dictionary).get("fuel", 0.0))
	burning = _lit.size()
	return true


func is_burning(brick: Brick) -> bool:
	return _lit.has(brick)


func fuel_left(brick: Brick) -> float:
	return float(_lit.get(brick, 0.0))


func _physics_process(delta: float) -> void:
	_since += delta
	if _since < TICK:
		return
	var step := _since
	_since = 0.0
	burn(step)


## One step of burning, spreading and burning out. Separate from `_physics_process` so a test can
## run a minute of fire in a loop rather than in a minute.
func burn(delta: float) -> void:
	if _lit.is_empty():
		return
	var still: Dictionary = {}
	var caught: Array[Brick] = []

	for key in _lit:
		var brick := key as Brick
		if not is_instance_valid(brick):
			continue
		var def := _materials.get_def(brick.material_id)
		var fire: Dictionary = def.get("fire", {})
		var left := float(_lit[brick]) - float(fire.get("burn_rate", 1.0)) * delta

		_spread_from(brick, fire, delta, caught)

		if left > 0.0:
			still[brick] = left
		else:
			_burn_out(brick, fire)

	for brick in caught:
		if not still.has(brick):
			var def := _materials.get_def(brick.material_id)
			var fire: Dictionary = def.get("fire", {})
			still[brick] = float(fire.get("fuel", 0.0))

	_lit = still
	burning = _lit.size()


## Try to set light to what is near enough. Rolled per tick against flammability, so a low-flammable
## thing next to a fire eventually catches rather than never catching or catching instantly.
func _spread_from(brick: Brick, fire: Dictionary, delta: float, caught: Array[Brick]) -> void:
	var radius := float(fire.get("spread_radius", 0.0))
	if radius <= 0.0:
		return
	for node in Brick.all(get_tree()):
		var other := node as Brick
		if other == null or other == brick or _lit.has(other) or caught.has(other):
			continue
		if brick.global_position.distance_to(other.global_position) > radius:
			continue
		var flammability := float(_materials.get_def(other.material_id).get("flammability", 0.0))
		if flammability <= 0.0:
			continue
		if _rng.randf() < flammability * CATCH_SCALE * delta:
			caught.append(other)


## What is left. The material changes and nothing else happens — the support calculation reads the
## new number on its own, which is §6's entire mechanism.
func _burn_out(brick: Brick, fire: Dictionary) -> void:
	var becomes: Variant = fire.get("becomes")
	if becomes == null or String(becomes) == "":
		brick.queue_free()
		consumed += 1
		return
	brick.material_id = StringName(String(becomes))
	brick.mass = maxf(Brick.MIN_MASS, _materials.mass_for(brick.material_id, _volume_of(brick)))
	_recolour(brick)
	burnt += 1


func _volume_of(brick: Brick) -> float:
	for child in brick.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var size: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size
			return size.x * size.y * size.z
	return 1.0


func _recolour(brick: Brick) -> void:
	for child in brick.get_children():
		if child is MeshInstance3D:
			var surface := StandardMaterial3D.new()
			surface.albedo_color = _palette.colour(StringName(
				String(_materials.get_def(brick.material_id).get("colour", ""))))
			surface.roughness = 0.95
			(child as MeshInstance3D).material_override = surface


func report() -> String:
	return "fire: %d burning, %d charred, %d consumed" % [burning, burnt, consumed]
