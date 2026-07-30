class_name EarthSpan
extends RefCounted
## One run of solid ground in a column: bedrock to surface, or a tunnel roof, or the floor under
## a dugout. EARTH-SPEC §1.
##
## This is the currency of the whole earth system, and it exists from the first line of C3 for one
## reason `EARTH-SPEC` §1 states outright: *"retrofitting spans onto a flat heightfield is a
## rewrite."* Almost every column in the game has exactly one span and will for the whole of C3 —
## nothing splits them until tunnels arrive at C3b — so it would be entirely possible to ship a
## `height_at()` now and grow spans underneath it later. That is the trade this file refuses.
## Meshing, collision, digging and slumping all read spans, so a tunnel is a new *case* in code
## that already has the right shape rather than a new shape for all of it.
##
## Heights are **integer centimetres**, and that is not a storage detail either. §5's largest
## claim is that slumping is never sent over the wire, because every client derives the same
## collapse from the same dig — which is only true if the arithmetic is exact. One float in the
## settle path and two machines disagree by a centimetre, then by a metre, and nothing says so.
## So there are no floats in this file, and `EarthChunk` asserts the same of itself.

## The bit that separates dug ground from ground that has never been touched. `disturbed` is one
## flag rather than a parallel set of "loose" materials (EARTH-SPEC §4): repose -15°, cohesion
## ×0.4, support ×0.6, applied on top of whatever the material already says. A parapet thrown up
## from its own spoil behaves noticeably worse than the same shape cut out of virgin clay, and it
## costs a bit.
const DISTURBED_REPOSE_PENALTY := 15

var bottom_cm := 0
var top_cm := 0
var material := &""
var disturbed := false


static func make(bottom_cm_: int, top_cm_: int, material_: StringName,
		disturbed_ := false) -> EarthSpan:
	var span := EarthSpan.new()
	span.bottom_cm = bottom_cm_
	span.top_cm = top_cm_
	span.material = material_
	span.disturbed = disturbed_
	return span


## Thickness in centimetres. Never negative: a span whose top is below its bottom is not a thin
## span, it is a bug, and reporting 0 hides it. Callers that care use `is_sane`.
func thickness_cm() -> int:
	return maxi(0, top_cm - bottom_cm)


## Whether this span could exist. Checked at the edges of the system rather than on every access,
## because it is a statement about data somebody wrote rather than about arithmetic core did.
func is_sane() -> bool:
	return top_cm > bottom_cm and material != &""


## The angle this span's face will stand at, in whole degrees, given what the material says and
## whether the ground has been dug. Integer, like everything else here — `MATERIAL-SPEC` §5 states
## repose in whole degrees and there is no reason for the earth to hold it more finely than the
## material does.
func repose_degrees(from_material: int) -> int:
	return maxi(0, from_material - (DISTURBED_REPOSE_PENALTY if disturbed else 0))


func duplicated() -> EarthSpan:
	return EarthSpan.make(bottom_cm, top_cm, material, disturbed)


func _to_string() -> String:
	return "%s %d..%d cm%s" % [material, bottom_cm, top_cm, " (disturbed)" if disturbed else ""]
