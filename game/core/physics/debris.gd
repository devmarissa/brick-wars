class_name Debris
extends Node
## What happens to the pieces afterwards. CORE-SPEC §2, C5.
##
## C5's done-condition ends with a clause that is easy to read past: *"and the world is back to zero
## awake bodies within seconds."* Not "the blast looks right" — **the world goes quiet again**. That
## is a performance claim and a correctness one at the same time, and without something owning it a
## siege accumulates rubble until the frame budget is gone.
##
## Three rules, and each exists because of a specific way the world fails to go quiet.
##
## **A cap, oldest first.** Debris is unbounded by construction — every shell makes more, and a
## twenty-minute siege makes thousands. The cap is what turns "how long can this run" from a question
## into a constant. Oldest first because the newest rubble is the rubble somebody is looking at.
##
## **A lifetime, counted from when it stopped.** Not from when it spawned: debris still in the air
## when its timer ran out would vanish mid-flight, which is the single most noticeable way a cleanup
## policy announces itself. Resting rubble that disappears while nobody is near it is invisible;
## rubble that pops out of existence at head height is not.
##
## **A forced sleep.** The one that actually delivers the done-condition. A brick wedged against two
## others can jitter below the speed anybody would call moving and above the threshold Jolt calls
## asleep, forever. It is not visibly moving and it is not free. So a body still awake long after
## everything around it went quiet is put to sleep, and the world reaches zero.
##
## ### It only ever touches debris
##
## Nothing here culls a brick that came out of an asset. A wall somebody built is theirs until
## something destroys it, and a cleanup policy that quietly deleted structures would be a far worse
## bug than a slow frame. Only bodies handed to `track` are ever considered.

## The most debris bodies alive at once. A number rather than a measurement, and the reason it is
## this number: `blast-fixture`'s heaviest scenario leaves 120 bricks lying about, so a cap below a
## few hundred would start eating the aftermath of a single shell while the player watched it.
const CAP := 400

## How long a piece of debris lies where it stopped before it is cleared, in seconds. Long enough to
## walk over to and look at; short enough that a firefight does not silt up.
const LIFETIME := 45.0

## How long a body may stay awake before it is put to sleep regardless, in seconds. Generous — a
## genuine collapse cascading through a structure takes a few seconds and must not be cut short —
## and still far below the point where jitter costs anything anybody would notice.
const FORCE_SLEEP_AFTER := 12.0

## How often the sweep runs, in seconds. Culling is not urgent and running it every frame over
## hundreds of bodies would be its own performance problem.
const SWEEP_EVERY := 0.5

var culled := 0
var forced := 0

var _tracked: Array[Dictionary] = []
var _since_sweep := 0.0
var _clock := 0.0


static func of() -> Debris:
	var debris := Debris.new()
	debris.name = "Debris"
	return debris


## Take responsibility for a piece. Anything not handed here is left alone forever.
func track(brick: RigidBody3D) -> void:
	if brick == null:
		return
	_tracked.append({ "brick": brick, "born": _clock, "stopped": -1.0 })


func tracking() -> int:
	return _tracked.size()


func awake_count() -> int:
	var awake := 0
	for entry in _tracked:
		var brick: RigidBody3D = entry["brick"]
		if is_instance_valid(brick) and not brick.sleeping:
			awake += 1
	return awake


func _physics_process(delta: float) -> void:
	_clock += delta
	_since_sweep += delta
	if _since_sweep < SWEEP_EVERY:
		return
	_since_sweep = 0.0
	sweep()


## One pass. Split out from `_physics_process` so a test can run it directly rather than waiting
## half a second of wall clock for each one.
func sweep() -> void:
	var living: Array[Dictionary] = []
	for entry in _tracked:
		var brick: RigidBody3D = entry["brick"]
		if not is_instance_valid(brick):
			continue

		if brick.sleeping:
			# Note *when* it stopped, once. The lifetime runs from here rather than from birth, so
			# nothing vanishes while it is still in the air.
			if float(entry["stopped"]) < 0.0:
				entry["stopped"] = _clock
			if _clock - float(entry["stopped"]) > LIFETIME:
				brick.queue_free()
				culled += 1
				continue
		else:
			entry["stopped"] = -1.0
			if _clock - float(entry["born"]) > FORCE_SLEEP_AFTER:
				# The line that delivers "zero awake bodies within seconds". A brick wedged between
				# two others can jitter below visible movement and above Jolt's sleep threshold for
				# as long as the level exists.
				brick.sleeping = true
				forced += 1
		living.append(entry)

	_tracked = living
	_enforce_cap()


## Over the cap, oldest first — and only ones that have already stopped. Culling something still
## moving is how a cleanup policy makes itself visible.
func _enforce_cap() -> void:
	if _tracked.size() <= CAP:
		return
	var over := _tracked.size() - CAP
	var kept: Array[Dictionary] = []
	for entry in _tracked:
		var brick: RigidBody3D = entry["brick"]
		if over > 0 and is_instance_valid(brick) and brick.sleeping:
			brick.queue_free()
			culled += 1
			over -= 1
			continue
		kept.append(entry)
	_tracked = kept


func report() -> String:
	return "debris: %d tracked, %d awake, %d culled, %d forced to sleep" % [
		_tracked.size(), awake_count(), culled, forced]
