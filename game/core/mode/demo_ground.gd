class_name DemoGround
extends RefCounted
## The sandbox's starting terrain: `TestGround`'s shape, as a real diggable field, with a trench
## cut into it. EARTH-SPEC §2.
##
## The shape is sampled from `TestGround.height_at` rather than invented, and that is the whole
## point of it. C1's greybox swap held the camera, the sun and the sky still so the before-and-after
## screenshots were comparable; this does the same thing one layer down. The ramp, the step and the
## bowl are the same ramp, step and bowl the rig has been walking over since C2 — so a picture of
## the earth field is a picture of *the field*, not of a different map that also has a hill in it.
##
## `TestGround` itself is not going anywhere. Every rig case asserts exact numbers against it as a
## pure analytic function, and it stays the suite's surface (DEVIATIONS-C3 C1). What changes is what
## the *sandbox* stands on.
##
## Map generation is C7's problem. This is a table of shapes, in the same spirit as `Sandbox.LAYOUT`
## being a table rather than a sequence of calls: turning it into a file later is a reader rather
## than a rewrite.

## How far out the field is generated, in metres. `TestGround` is 24 m across and the walkers circle
## inside it; a couple of metres of margin keeps them off the edge of the world.
const EXTENT_M := 14.0

## The trench, in world metres: where it runs, how wide, how deep. Deep enough to be past the
## mesher's 87 cm cliff threshold, so it comes out with vertical walls rather than as a soft
## depression — which is the entire thing C3's meshing increment is here to show.
const TRENCH_X := -9.0
const TRENCH_HALF_WIDTH := 0.6
const TRENCH_FROM_Z := -6.0
const TRENCH_TO_Z := 2.0
const TRENCH_DEPTH_CM := 140

## Where the trench runs, and it is out west of the props on purpose. The first attempt cut it
## through the middle of the world and heaped its spoil on top of `core:wall_sandbag`, which
## promptly collapsed — correct behaviour by the physics and a useless screenshot.
##
## Where the spoil goes. Digging is not deletion (§4), so the trench's own earth becomes the
## parapet beside it — which is also why the parapet is `disturbed` and will stand less steeply
## than the wall opposite once the settle queue arrives.
const PARAPET_OFFSET_CELLS := -2

## How many cells the spoil is spread over. Not cosmetic: three cells of 140 cm cut dumped onto two
## cells is a 2.1 m parapet, which is a wall rather than something to fire over — and it read as a
## slab of dark grey in the first screenshot because a 2 m vertical face away from the sun is
## unlit. Spread over six it comes out around 70 cm, which is under the 87 cm cliff threshold, so
## the parapet is a smooth mound and the cut is the sharp thing in frame. Both behaviours, one
## picture.
const PARAPET_CELLS := 6


## How steep the revetment holds a wall. Timber and sandbag facing stand near-vertical, which is
## the whole reason trenches are revetted at all — loam holds 38° and a 38° trench is a ditch.
const SHORING_DEGREES := 80

## Where the water table sits, in centimetres. Below the surrounding ground and above the trench
## floor, so the cut fills and everything around it stays dry — which is the case §8 is about and
## the reason a Great War trench had duckboards in it.
const WATER_CM := -90


## Sculpt the starting ground, cut the trench, and hand back how much earth moved.
static func make(field: EarthField, settle: EarthSettle) -> int:
	field.water_cm = WATER_CM
	var reach := int(EXTENT_M / EarthGrid.CELL_M)
	for cz in range(-reach, reach + 1):
		for cx in range(-reach, reach + 1):
			var centre := EarthGrid.centre_of(Vector2i(cx, cz))
			field.sculpt(Vector2i(cx, cz), roundi(TestGround.height_at(centre.x, centre.y) * 100.0))
	var moved := _cut_trench(field, settle)
	_shell_it(field, settle)
	return moved


## Shell the ground around the trench, through the same `EarthCrater` C5's blast will call. Not a
## blast model — radius and depth are picked here rather than derived from anything — but the
## earth's response to one is C3's business and §4 specifies it: about 70% of what comes out lands
## on the rim, and the rest goes to the air.
##
## Kept west of the props: the first pass shelled the ground under the watchtower and undermined
## it, which is exactly right — §7 says removing the ground under a foundation costs it its support
## — and made a picture of a collapsed tower rather than of a cratered field. Undermining gets its
## own demonstration when structures are the subject.
##
## Seeded, so the world is the same world every time it boots. A battlefield that reshuffled itself
## between screenshots would make every before-and-after comparison worthless.
static func _shell_it(field: EarthField, settle: EarthSettle) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	for shell in 14:
		var at := Vector2i(rng.randi_range(-27, -13), rng.randi_range(-17, 6))
		EarthCrater.form(field, settle, at, rng.randi_range(3, 6), rng.randi_range(70, 190))


## A trench, dug rather than sculpted: it carves real volume out and piles every centimetre of it
## on the parapet, so the ground either side is `disturbed` and the field has as much earth in it
## afterwards as before.
static func _cut_trench(field: EarthField, settle: EarthSettle) -> int:
	var moved := 0
	var from_z := int(TRENCH_FROM_Z / EarthGrid.CELL_M)
	var to_z := int(TRENCH_TO_Z / EarthGrid.CELL_M)
	var centre_x := int(TRENCH_X / EarthGrid.CELL_M)
	var half := int(TRENCH_HALF_WIDTH / EarthGrid.CELL_M)

	for cz in range(from_z, to_z + 1):
		var spoil := 0
		for cx in range(centre_x - half, centre_x + half + 1):
			spoil += field.carve(Vector2i(cx, cz), TRENCH_DEPTH_CM)
			# Digging wakes the earth. That is the contract — nothing sweeps the map looking for
			# faces that have stopped standing — so a cut that forgot to say so is a cut whose
			# walls never fall, which is a much harder thing to notice than a crash.
			settle.disturb(Vector2i(cx, cz))
		# The northern half is revetted and the southern half is bare, which is the whole of §3 in
		# one trench: the shored walls stand where they were cut, and the moment the settle queue
		# reaches the unshored end it slumps to what loam actually holds — 38°, which is a ditch.
		if cz < (from_z + to_z) / 2:
			for cx in range(centre_x - half - 1, centre_x + half + 2):
				field.shore(Vector2i(cx, cz), SHORING_DEGREES)
		moved += spoil
		# All of it onto one side, which is what gives a trench a parapet and a firing step rather
		# than a symmetrical ditch. Spread rather than piled — see `PARAPET_CELLS`.
		var lip := centre_x - half + PARAPET_OFFSET_CELLS
		var each := spoil / PARAPET_CELLS
		for i in PARAPET_CELLS:
			# The last cell takes the remainder, so no centimetre of earth is lost to integer
			# division. §4 means it, and a rounding leak is still a leak.
			var share := each if i < PARAPET_CELLS - 1 else spoil - each * (PARAPET_CELLS - 1)
			field.deposit(Vector2i(lip - i, cz), share)
			settle.disturb(Vector2i(lip - i, cz))
	return moved
