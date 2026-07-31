class_name EarthCrater
extends RefCounted
## What a shell does to the ground: a bowl, and a rim made of the bowl. EARTH-SPEC §4.
##
## This is the *earth's* half of an explosion and not the explosion. Radius, falloff, impulse,
## what it does to the people standing near it — all of that is the blast model and belongs to C5.
## What belongs here is the one sentence §4 spends on where the material goes:
##
## > Blast conserves about 70% of displaced volume onto the rim; the rest goes airborne as dust and
## > debris and disperses. Full conservation makes craters look wrong — a real crater loses material
## > to the air.
##
## So a crater is a carve and a deposit, and the raised lip is not decoration: it is the earth that
## came out of the hole, which is why a cratered field gets rougher rather than lower. C5's blast
## calls this once it knows where and how hard; until then the earth can already be cratered, which
## is what lets C3's done-condition be walked without a blast system.

## §4's figure. The other 30% is dust — modelled by not being anywhere, which is the correct amount
## of modelling for something that has blown away.
const RIM_FRACTION_NUM := 70
const RIM_FRACTION_DEN := 100

## How far past the lip the spoil is spread, in cells. One ring: piling it all on the very edge
## makes a volcano rather than a crater.
const RIM_CELLS := 2


## Blow a hole. Returns the volume actually displaced, in column-centimetres.
##
## The profile is a cone rather than a hemisphere — deepest at the centre, tapering to nothing at
## the edge — because it is the shape that stays a crater after the settle queue has been at it. A
## flat-bottomed hole slumps into a cone anyway; starting there means the ground moves once instead
## of twice.
static func form(field: EarthField, settle: EarthSettle, at: Vector2i, radius: int,
		depth_cm: int) -> int:
	if radius <= 0 or depth_cm <= 0:
		return 0

	var displaced := 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var away := sqrt(float(dx * dx + dz * dz))
			if away > radius:
				continue
			var cut := int(depth_cm * (1.0 - away / float(radius + 1)))
			if cut <= 0:
				continue
			var cell := at + Vector2i(dx, dz)
			displaced += field.carve(cell, cut)
			if settle != null:
				settle.disturb(cell)

	_raise_rim(field, settle, at, radius, displaced * RIM_FRACTION_NUM / RIM_FRACTION_DEN)
	return displaced


## The lip, spread over a ring rather than heaped on one cell. Every centimetre is accounted for:
## the last cell takes the remainder, because integer division that quietly loses earth is the same
## bug as digging that quietly loses earth, and §4 is about exactly that.
static func _raise_rim(field: EarthField, settle: EarthSettle, at: Vector2i, radius: int,
		spoil: int) -> void:
	if spoil <= 0:
		return
	var ring: Array[Vector2i] = []
	for dz in range(-radius - RIM_CELLS, radius + RIM_CELLS + 1):
		for dx in range(-radius - RIM_CELLS, radius + RIM_CELLS + 1):
			var away := sqrt(float(dx * dx + dz * dz))
			if away > radius and away <= radius + RIM_CELLS:
				ring.append(at + Vector2i(dx, dz))
	if ring.is_empty():
		return

	var each := spoil / ring.size()
	for i in ring.size():
		var share := each if i < ring.size() - 1 else spoil - each * (ring.size() - 1)
		field.deposit(ring[i], share)
		if settle != null:
			settle.disturb(ring[i])
