class_name Gait
extends RefCounted
## Walk, trot, gallop — as numbers a pack writes and core interprets. RIG-SPEC §5.
##
## The point of this file is that a modder gets a gait without animating a frame. They say
## how many legs there are, where the legs attach, what order the legs fire in, how far a
## stride reaches and how high a foot lifts. Core owns everything after that: which gait a
## given speed calls for, how one gait becomes the next without a hitch, and where a foot
## should be at any point in its cycle.
##
## No clips, ever, for locomotion. RIG-SPEC §4 gives the reason and it is specific to this
## game: our ground is constantly being dug up, so the surface a canned animation was authored
## against does not exist by the time anybody walks on it. A phase and a stride length survive
## a crater; a keyframed footfall does not.
##
## Pure functions over dictionaries, no state and no nodes, for the same reason the IK solver
## is: this is arithmetic that is wrong in ways you cannot see until something is on screen,
## and it has to be checkable without building anything.

## Fraction of a leg's cycle spent on the ground, when a gait does not say.
##
## RIG-SPEC §5's block has no `duty` field and its example does not set one. Two thirds is a
## walk — three feet down at any moment on a quadruped, which is what makes a walk read as
## unhurried — and it is a poor gallop, where the whole animal is airborne for part of the
## cycle. So a gait that means to be fast has to say so; the default is the safe end, because
## a gallop with a walk's duty looks laboured and a walk with a gallop's duty looks like the
## creature is skating.
const DEFAULT_DUTY := 0.66

## How much of two adjacent gaits' speed ranges to blend across when the author leaves no
## overlap of their own, as a fraction of the narrower of the two ranges.
##
## Overlapping ranges are the real mechanism — an author who writes walk `[0, 4]` and trot
## `[3, 9]` has said "take a whole unit of speed to change gait", and that is more control
## than any field this file could invent. But the spec's own example ranges merely touch, so
## touching has to mean something better than a snap, and a tenth of a range is short enough
## to read as a transition rather than as a long ambiguous shuffle.
const TOUCH_BLEND := 0.1


## The gait to use at a given speed, with everything already blended. Returns:
##
##     name      String        the dominant gait, for anything that wants to say which
##     stride    float         metres from footfall to footfall
##     lift      float         metres a foot clears the ground at the top of its swing
##     duty      float         fraction of the cycle the foot is planted
##     phases    Array[float]  per-leg offsets into the cycle, in the pack's leg order
##     blending  bool          true while two gaits are being mixed
##
## An empty gait list, or a speed below every range, answers with the first gait rather than
## with nothing. A creature standing still is still standing in some pose, and the pose it
## should hold is its slowest gait's, frozen — which is what a zero phase advance gives.
static func for_speed(gaits: Array, speed: float) -> Dictionary:
	var usable := _usable(gaits)
	if usable.is_empty():
		return {}
	var at := _index_for(usable, speed)
	var here: Dictionary = usable[at]

	# Blending only ever looks upward, so a slowing creature crosses the same band as an
	# accelerating one and the transition is symmetric. Handling it in both directions would
	# be two code paths that have to agree, and the way they stop agreeing is hysteresis
	# nobody asked for.
	if at + 1 < usable.size():
		var next: Dictionary = usable[at + 1]
		var band := _band(here, next)
		if speed > band[0] and band[1] > band[0]:
			var mix := clampf((speed - band[0]) / (band[1] - band[0]), 0.0, 1.0)
			return _mix(here, next, mix)
	return _mix(here, here, 0.0)


## Where one foot sits at a point in its cycle, in the creature's own space, relative to where
## that foot rests when it is standing. -Z is forward (ART-BIBLE §7), so a foot that has just
## landed is at negative Z and travels to positive Z as the body passes over it.
##
## Stance is linear on purpose. A planted foot has to travel backward at exactly the speed the
## body travels forward or it slides, and any easing at all is a slide — this is the one curve
## in the file that must be a straight line. The swing is eased at both ends instead, which is
## where the character is anyway: a foot leaves the ground quickly and is set down gently.
static func foot_cycle(phase: float, stride: float, lift: float,
		duty := DEFAULT_DUTY) -> Dictionary:
	var p := fposmod(phase, 1.0)
	var half := stride * 0.5
	var hold := clampf(duty, 0.05, 0.95)

	if p < hold:
		var t := p / hold
		return {
			"offset": Vector3(0.0, 0.0, lerpf(-half, half, t)),
			"planted": true,
			"cycle": t,
		}

	var swing := (p - hold) / (1.0 - hold)
	return {
		"offset": Vector3(0.0, sin(PI * swing) * lift, lerpf(half, -half, smoothstep(0.0, 1.0, swing))),
		"planted": false,
		"cycle": swing,
	}


## How far the cycle advances in one step, given how fast the creature is moving. A stride is
## the distance one foot covers between footfalls, so a creature travelling one stride's worth
## of ground has advanced exactly one cycle — which is the entire reason feet do not skate.
static func advance(speed: float, stride: float, delta: float) -> float:
	if stride <= 0.0:
		return 0.0
	return absf(speed) * delta / stride


## Only the entries that are actually gaits, in ascending speed order. A pack whose gaits
## arrive out of order is not an error — the validator says so as a warning — but the blend
## has to walk them in order or `walk → gallop → trot` produces a transition that goes the
## wrong way, so the sort happens here rather than being assumed upstream.
static func _usable(gaits: Array) -> Array:
	var out: Array = []
	for entry in gaits:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _low(a) < _low(b))
	return out


## Which gait owns a speed *before* any blending — the last one whose transition into it has
## finished.
##
## The obvious version of this asks "which is the last gait whose range has started", and it
## is wrong in both directions, which is what building the test found. With ranges that
## overlap, the upper gait's range starts *inside* the blend band, so the index changed before
## the band was ever entered and the blend below never ran at all. With ranges that merely
## touch, the band straddles the boundary and the index changed halfway through it, so every
## transition ran its first half and then snapped. Handing over at the *end* of the band makes
## the two agree: a gait becomes the current one exactly when the blend into it completes.
static func _index_for(gaits: Array, speed: float) -> int:
	for i in range(gaits.size() - 1, 0, -1):
		if speed >= _band(gaits[i - 1], gaits[i])[1]:
			return i
	return 0


## The speed window two adjacent gaits change over: the overlap the author declared, or a
## short band straddling the boundary when they only touch.
static func _band(here: Dictionary, next: Dictionary) -> Array:
	var here_high := _high(here)
	var next_low := _low(next)
	if next_low < here_high:
		return [next_low, here_high]
	var narrower := minf(here_high - _low(here), _high(next) - next_low)
	var half := maxf(0.0, narrower * TOUCH_BLEND * 0.5)
	return [next_low - half, next_low + half]


static func _mix(here: Dictionary, next: Dictionary, amount: float) -> Dictionary:
	return {
		"name": String(here.get("name", "")) if amount < 0.5 else String(next.get("name", "")),
		"stride": lerpf(_number(here, "stride", 1.0), _number(next, "stride", 1.0), amount),
		"lift": lerpf(_number(here, "lift", 0.1), _number(next, "lift", 0.1), amount),
		"duty": lerpf(_number(here, "duty", DEFAULT_DUTY),
			_number(next, "duty", DEFAULT_DUTY), amount),
		"phases": _mix_phases(here.get("phases", []), next.get("phases", []), amount),
		"blending": amount > 0.0 and amount < 1.0,
	}


## Phase offsets are positions on a circle, so they take the short way round: a leg going from
## 0.9 to 0.1 travels a fifth of a cycle forward, not four fifths backward. Doing this with a
## straight lerp is a leg that visibly reverses direction for the length of a gait change,
## which is the one thing a gait change is not allowed to look like.
static func _mix_phases(here: Variant, next: Variant, amount: float) -> Array:
	var from: Array = here if typeof(here) == TYPE_ARRAY else []
	var to: Array = next if typeof(next) == TYPE_ARRAY else []
	if amount <= 0.0 or to.size() != from.size():
		return from.duplicate()

	var out: Array = []
	for i in from.size():
		var a := fposmod(float(from[i]), 1.0)
		var b := fposmod(float(to[i]), 1.0)
		var step := b - a
		if step > 0.5:
			step -= 1.0
		elif step < -0.5:
			step += 1.0
		out.append(fposmod(a + step * amount, 1.0))
	return out


static func _low(gait: Dictionary) -> float:
	var span: Variant = gait.get("speed", [])
	return float(span[0]) if typeof(span) == TYPE_ARRAY and (span as Array).size() == 2 else 0.0


static func _high(gait: Dictionary) -> float:
	var span: Variant = gait.get("speed", [])
	return float(span[1]) if typeof(span) == TYPE_ARRAY and (span as Array).size() == 2 else 0.0


static func _number(gait: Dictionary, key: String, fallback: float) -> float:
	return float(gait[key]) if gait.has(key) else fallback
