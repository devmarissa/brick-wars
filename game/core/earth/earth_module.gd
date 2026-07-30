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
## meant to feel organic, which is a meshing problem, not a resolution problem.
##
## Placeholder until C3. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"earth"


func module_milestone() -> String:
	return "C3"


func module_is_stub() -> bool:
	return true
