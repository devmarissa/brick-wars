class_name Leg
extends RefCounted
## One leg of a walking thing, measured off its rest pose. RIG-SPEC §4.
##
## A `locomotion` block names two bones per leg — where it attaches and which end touches the
## ground — and everything else a driver needs about that leg is already implied by the pose
## the author wrote. This file is where the implying happens, once at setup rather than per
## frame: how long each segment is, how far the foot can chase the ground, where the sole rests
## when nothing is driving it, and which way the knee points.
##
## That last one is the reason this is a file rather than four fields on a dictionary. A human
## knee points forward and a horse's hock points backward, and the difference could have been a
## `bend` field in the format — one more thing to document, validate, and get silently wrong in
## a mod. Instead it is read off the rest pose: the part of the hip→knee line that is not on
## the hip→ankle line *is* the bend direction, and an author who bent the leg has already said
## it. A leg drawn straight has said nothing, which is exactly the case that warns.
##
## The other distinction that matters: `chain[0]` and `chain[1]` are solved by IK, and every
## bone past them is passive — a fetlock, a pastern — and hangs. `trail` is their total length,
## and the IK pair is therefore solved to where the *ankle* must be for the passive segments to
## put the sole on the target, not to the target itself.

## What a leg can still chase the ground with when its author wrote it straight at rest.
## Straight legs have no room and no bend direction; this is a floor so such a creature moves
## badly rather than freezing, and the validator complains about the same thing in words.
const MIN_REACH := 0.05

const TINY := 0.000001

var root := ""
var foot := ""

## The pack's own phase offset, used when a gait does not list per-leg phases.
var phase := 0.0

## Bones from `root` down to `foot`, inclusive. `[0]` and `[1]` are the IK pair; the rest are
## passive, and `passive` holds their lengths in the same order, with `trail` their sum.
var chain: Array[String] = []
var passive: Array[float] = []
var upper := 0.0
var lower := 0.0
var trail := 0.0

## How far up or down from its rest position this foot may chase the ground, and how far below
## the body's own origin its sole reaches at full stretch.
var reach := 0.0
var drop := 0.0

## Where the sole sits in creature space with nothing driving the leg. Every foot position the
## driver computes is this point plus a gait offset.
var home := Vector3.ZERO

## Which way the knee travels, read off the rest pose.
var bend := Vector3.FORWARD

## Which way the passive segments currently point, in creature space. The one piece of per-leg
## state that survives a frame.
var hang := Vector3.DOWN

var plant: Dictionary = {}
var stance := true
var strain := 0.0


## Measure one `legs` entry against a built rig, or return null when it does not describe a
## chain of two or more bones — which is a fact about the data rather than an error here,
## because the validator has already said it in words and a leg the driver skips holds its rest
## pose. Anything worth saying is appended to `warnings`.
static func measure(rig: Rig, entry: Dictionary, warnings: Array[String]) -> Leg:
	var leg := Leg.new()
	leg.root = String(entry.get("root", ""))
	leg.foot = String(entry.get("foot", ""))
	leg.phase = fposmod(float(entry.get("phase", 0.0)), 1.0)
	leg.chain = chain_between(rig, leg.root, leg.foot)
	if leg.chain.size() < 2:
		warnings.append("leg `%s` → `%s` is not a chain of two or more bones, so it cannot be solved" % [
			leg.root, leg.foot])
		return null

	leg.upper = length_of(rig, leg.chain[0])
	leg.lower = length_of(rig, leg.chain[1])
	for i in range(2, leg.chain.size()):
		var each := length_of(rig, leg.chain[i])
		leg.passive.append(each)
		leg.trail += each

	leg.home = tip_of(rig, leg.chain[leg.chain.size() - 1])
	var anchor := rig.joint_position(leg.chain[0])
	var span := leg.upper + leg.lower + leg.trail
	# What is left of the leg once it is standing: a leg bent at rest can straighten by this
	# much, and a leg already straight cannot, which is true and is why the validator asks for
	# a `rest` angle.
	leg.reach = maxf(span - anchor.distance_to(leg.home), MIN_REACH)
	leg.drop = span - anchor.y
	leg.bend = _bend(rig, leg, anchor, warnings)
	return leg


## The bones from `root` down to `foot`, walked upward from the foot because a part knows its
## parent and not its children. An empty answer means they are not on one chain at all.
static func chain_between(rig: Rig, root: String, foot: String) -> Array[String]:
	var out: Array[String] = []
	var at := foot
	var depth := 0
	while at != "" and rig.has(at) and depth <= PartPlacement.MAX_PARENT_DEPTH:
		out.append(at)
		if at == root:
			out.reverse()
			return out
		at = (rig.bone(at) as Rig.Bone).parent
		depth += 1
	return [] as Array[String]


static func length_of(rig: Rig, name: String) -> float:
	return (rig.bone(name) as Rig.Bone).length()


## A bone's far end in the creature's own space — its joint, plus its own length down its own
## -Z (ART-BIBLE §7).
static func tip_of(rig: Rig, name: String) -> Vector3:
	return rig.joint_position(name) - rig.space_basis(name).z * length_of(rig, name)


## Which way the knee points, taken as the part of the rest pose that is not on the line from
## the hip to the ankle. This is the whole of the difference between a man and a horse and it
## costs no field: an author who bent the leg has said it.
static func _bend(rig: Rig, leg: Leg, anchor: Vector3, warnings: Array[String]) -> Vector3:
	var ankle := tip_of(rig, leg.chain[1])
	var line := ankle - anchor
	if line.length_squared() <= TINY:
		return Vector3.FORWARD
	var axis := line.normalized()
	var knee := rig.joint_position(leg.chain[1]) - anchor
	var out := knee - axis * axis.dot(knee)
	if out.length_squared() <= TINY:
		warnings.append(("leg `%s` is straight at rest, so which way its knee bends is a guess" +
			" — give its upper joint a `rest` angle") % leg.root)
		return Vector3.FORWARD
	return out.normalized()
