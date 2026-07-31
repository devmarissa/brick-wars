extends Module
## The earth — the 0.5 m column-span field with centimetre-quantised continuous height,
## dig/build/carve, spoil with conservation of volume, angle-of-repose slumping, shoring,
## tunnels, mining, collapse, the water table, and the event log. CORE-SPEC §2,
## `EARTH-SPEC.md`.
##
## Spans go in from the start even if tunnels trail into C3b — retrofitting spans onto a
## flat heightfield is a rewrite, not an addition. The event log is likewise day-one work
## rather than a netcode chore, because it *is* the netcode foundation.
##
## The thing this replaces: terrain that read as a grid of chunky rectangles. Ground is
## meant to feel organic, which is a meshing problem, not a resolution problem — and the voxel
## experiment at C3 settled that empirically rather than by argument: 0.1 m cells came out
## *smoother* at 25× the triangles, because a heightfield over nearly-flat ground reads flat at
## any resolution. What was missing was churned ground, not smaller cells.
##
## Like `rig`, the earth is reached through its classes rather than through this node: `EarthField`
## is the ground as data and knows nothing about Godot, `EarthGrid` is the arithmetic between world
## and cell, `EarthChunk` packs 32×32 columns into three bytes each, `EarthMesher` decides smooth
## slope versus vertical skirt, `EarthTerrain` puts the result in the world and gives it collision,
## `EarthRepose` and `EarthSettle` are the slumping, `EarthCrater` is a shell's effect on the
## ground, `EarthLog` is the replayable event stream, and `EarthAudit` answers questions about a
## whole field. None of that needs a module instance to hold it.


func module_name() -> StringName:
	return &"earth"


func module_milestone() -> String:
	return "C3"


## No longer a stub as of C3. The bar was BUILD-ORDER's C3 sentence rather than a line count, and
## `case_c3_done.gd` walks all five clauses of it: dig anywhere · a trench with vertical walls that
## slump when shelled and nowhere else · craters with rims made of their own spoil · chalk holding a
## steeper face than sand with no special-case code · every modification a replayable event.
##
## What it still does not do is later milestones' problem, and is named rather than left quiet.
## Columns hold one span each — the table has been multi-span since the first line precisely so
## that tunnels, sapping and mining are an addition at **C3b** rather than a rewrite. There is no
## blast here: `EarthCrater` is the earth's half of an explosion and **C5** owns the other half.
## Render LOD at distance is unbuilt (EARTH-SPEC §9), and deformation stays full resolution
## everywhere regardless. The deformable *area* is a range in the spec and a decision nobody has
## made — `DEVIATIONS-C3.md` A1 — which is why the field is unbounded and allocates on demand.
func module_is_stub() -> bool:
	return false
