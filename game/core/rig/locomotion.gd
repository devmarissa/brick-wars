class_name Locomotion
extends RefCounted
## The thing that makes a creature walk: gaits from data, feet on ground nobody authored.
## RIG-SPEC §4–§5.
##
## Everything this needs exists in pieces already. `Gait` says where a foot should be in its
## cycle, `Footing` says where the ground will let it go and what the body should do about it,
## `TwoBoneIK` bends a limb to reach a point, `Rig` applies a pose. Missing was the thing that
## runs them in the right order, per leg, per frame — which is what turns a `locomotion` block
## into a creature that moves.
##
## ### Why `legged` is a locomotion type and not a creature system
##
## RIG-SPEC §5 lists six: `wheeled`, `tracked`, `legged`, `flying`, `floating`, `static`. Legs
## sit in that list rather than in a character controller because of the horse test. A horse is
## a fast transport vehicle whose ground contact happens to be four legs instead of four
## wheels, and if legs are a locomotion type a modder gets a rideable horse by writing a
## `locomotion` block — no core change, no new archetype, no permission. If legs are a creature
## system, the horse is a special case forever and the mod is a fork.
##
## ### What core owns and what the pack owns
##
## The pack says how many legs there are, which bones they run through, what order they fire
## in, how far a stride reaches and how high a foot lifts. Core owns everything after: which
## gait a speed calls for, how one becomes the next, where the ground is, how far the body
## comes down to keep the low leg reachable, and which way a knee points. That last is worth
## naming because it is the field this file deliberately does *not* add — a human knee points
## forward and a horse's hock backward, and rather than make an author declare it the direction
## is read off the rest pose. A leg bent at rest has already said which way it bends.
##
## Nothing here is simulated: same body transform, same ground, same `delta` gives the same
## pose on every machine, which is what RIG-SPEC §9's plan to replicate a creature as a root
## transform and a handful of floats depends on. The one piece of state carried between frames
## is each leg's hang direction, an exponential follow rather than a spring precisely so that
## it converges rather than rings.

## RIG-SPEC §5's closed set. A pack cannot invent one, for the same reason it cannot invent a
## joint type: each of these is a driver somebody in core has to have written.
const TYPES := ["wheeled", "tracked", "legged", "flying", "floating", "static"]

## How fast a passive segment — a fetlock, a pastern — catches up with the direction it should
## hang, per second. RIG-SPEC §4 asks for a third bone that "lags behind with a spring-follow",
## and this is the lag: high enough that a hoof is not left pointing at yesterday, low enough
## that the lag is visible, which is the entire reason for the bone.
const FOLLOW_RATE := 12.0

## The furthest a body banks into a turn, whatever `lean_into_turn` says. Past about this a
## creature reads as falling over rather than as leaning.
const MAX_LEAN := 30.0

## Dips of the body per cycle. One footfall of an alternating pair is half a cycle, so a body
## that dipped once per cycle would bob on one side only — which reads as a limp.
const BOB_PER_CYCLE := 2.0

const TINY := 0.000001

var rig: Rig = null
var legs: Array[Leg] = []
var gaits: Array = []
var type := "static"

var body_bob := 0.0
var body_pitch := 0.0
var lean_into_turn := 0.0

## How high the body rides above its feet on level ground, and how far below itself it can
## put the lowest of them. Both measured off the rest pose, so an author retunes a creature's
## stance by moving its bones rather than by writing a number twice.
var stand := 0.0
var drop := 0.0

var phase := 0.0
var gait: Dictionary = {}
var warnings: Array[String] = []


## The `locomotion` block an asset declares, or an empty one. FORMAT-SPEC lists the field;
## this is the only place that reads it.
static func declared(asset: ResolvedAsset) -> Dictionary:
	var block: Variant = asset.data.get("locomotion")
	return block if typeof(block) == TYPE_DICTIONARY else {}


## Measure a rig against its `locomotion` block. Returns false when there is nothing to drive
## — a wheeled or static thing, or a legged one whose legs do not name bones that exist —
## which is a fact rather than a failure: the validator has already said so in words, and a
## creature with no driver holds its rest pose, which is a pose.
func setup(on: Rig, block: Dictionary) -> bool:
	rig = on
	legs.clear()
	warnings.clear()
	phase = 0.0
	type = String(block.get("type", "static"))
	var listed: Variant = block.get("gaits", [])
	gaits = listed if typeof(listed) == TYPE_ARRAY else []
	body_bob = float(block.get("body_bob", 0.0))
	body_pitch = float(block.get("body_pitch", 0.0))
	lean_into_turn = float(block.get("lean_into_turn", 0.0))

	if type != "legged" or rig == null:
		return false
	var declared_legs: Variant = block.get("legs", [])
	if typeof(declared_legs) != TYPE_ARRAY:
		return false
	for entry in declared_legs as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var leg := Leg.measure(rig, entry as Dictionary, warnings)
		if leg != null:
			legs.append(leg)
	if legs.is_empty():
		return false
	_measure()
	return true


## One frame. `at` is where the caller has already moved the body horizontally; `motion` is its
## world velocity, `turn` its yaw rate in radians per second, and `probe` answers what is under
## a point — `TestGround` at C2, the earth field at C3, a raycast in a match.
##
## The body's height and orientation come back rather than being written, because the caller
## owns the body: it is a physics object with a collider, and a driver that moved it directly
## would be a kinematic system arguing with a simulated one. The *rig* is posed here, as a side
## effect, because that is the part nothing else can do.
##
## The order is load-bearing. Feet are planted against the transform that came in, the new body
## height and tilt are computed from where they landed, and only then are the world foot targets
## brought into the *new* body's space to be solved. The other way round — solving against the
## old body — costs exactly one frame of lag, invisible standing still and read as skating feet
## the moment the creature turns.
func step(at: Transform3D, motion: Vector3, turn: float, delta: float,
		probe: Callable) -> Dictionary:
	if legs.is_empty():
		return {}
	var speed := Vector2(motion.x, motion.z).length()
	gait = Gait.for_speed(gaits, speed)
	if gait.is_empty():
		return {}

	var stride := float(gait["stride"])
	var lift := float(gait["lift"])
	var duty := float(gait["duty"])
	var phases: Array = gait["phases"]
	phase = fposmod(phase + Gait.advance(speed, stride, delta), 1.0)

	var plants: Array = []
	var standing: Array = []
	var normals: Array = []
	var targets: Array = []
	for i in legs.size():
		var leg := legs[i]
		# The gait's phases *replace* the leg's own rather than adding to them. A pack that
		# writes both has said the same thing twice, and adding them turns a trot into a
		# shuffle at the exact moment somebody tunes one of the two.
		var offset := float(phases[i]) if i < phases.size() else leg.phase
		var cycle := Gait.foot_cycle(phase + offset, stride, lift, duty)
		var swing: Vector3 = cycle["offset"]

		# The ground is asked about the point the foot is *travelling over*, with the swing's
		# lift left out, and the lift is added to the answer. A foot arcing over a crater
		# should clear its lip rather than be measured against thin air.
		var ideal: Vector3 = at * (leg.home + Vector3(swing.x, 0.0, swing.z))
		var found := Footing.plant(probe, ideal, leg.reach)
		leg.plant = found
		leg.stance = bool(cycle["planted"])
		plants.append(found)
		normals.append(found["normal"])
		targets.append((found["position"] as Vector3) + at.basis.y * swing.y)
		if leg.stance:
			standing.append(found)

	var forward := motion if speed > TINY else -at.basis.z
	var basis := Footing.level(normals, forward, body_pitch) * Basis(Vector3.FORWARD, _roll(turn))
	# Height off the feet that are down. A swinging foot's plant is the ground under it, which
	# is the right thing to tilt to and the wrong thing to stand on — a creature stepping over
	# a ditch does not drop into it halfway through the stride.
	var height := Footing.support(standing if not standing.is_empty() else plants,
		stand, drop) + _bob()
	var into := Transform3D(basis, Vector3(at.origin.x, height, at.origin.z)).affine_inverse()

	var strain := 0.0
	for i in legs.size():
		strain = maxf(strain, _solve(legs[i], into * (targets[i] as Vector3), basis, delta))

	return {
		"basis": basis,
		"height": height,
		"gait": String(gait["name"]),
		"blending": bool(gait["blending"]),
		"phase": phase,
		"planted": standing.size(),
		"unsupported": Footing.unsupported(plants),
		"strain": strain,
	}


## Solve one leg to a target given in creature space, and pose it.
func _solve(leg: Leg, target: Vector3, body: Basis, delta: float) -> float:
	# Frame-rate independent: `1 - e^(-rate·dt)` is the same amount of catching-up per second
	# whatever the step size, where a plain lerp by `rate · dt` is not — and a fetlock that
	# lagged further on a slow machine would be one more thing two clients disagreed about.
	var down := body.inverse() * Vector3.DOWN
	var mixed := leg.hang.lerp(down, 1.0 - exp(-FOLLOW_RATE * delta))
	leg.hang = mixed.normalized() if mixed.length_squared() > TINY else down

	# The IK pair is solved to where the *ankle* has to be for the passive segments below it,
	# hanging as they currently hang, to put the sole on the target.
	var anchor := rig.joint_position(leg.chain[0])
	var found := TwoBoneIK.solve(anchor, target - leg.hang * leg.trail,
		leg.upper, leg.lower, leg.bend)
	var knee: Vector3 = found["joint"]
	var ankle: Vector3 = found["end"]
	rig.aim(leg.chain[0], anchor, knee, leg.bend)
	rig.aim(leg.chain[1], knee, ankle, leg.bend)

	for i in range(2, leg.chain.size()):
		var from := rig.joint_position(leg.chain[i])
		rig.aim(leg.chain[i], from, from + leg.hang * leg.passive[i - 2], leg.bend)

	leg.strain = float(found["strain"])
	return leg.strain


func _roll(turn: float) -> float:
	var limit := deg_to_rad(MAX_LEAN)
	return clampf(-lean_into_turn * turn, -limit, limit)


func _bob() -> float:
	return body_bob * 0.5 * sin(TAU * BOB_PER_CYCLE * phase)


func _measure() -> void:
	var total := 0.0
	drop = INF
	for leg in legs:
		total += leg.home.y
		drop = minf(drop, leg.drop)
	stand = -total / legs.size()
