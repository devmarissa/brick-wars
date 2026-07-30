extends Module
## Rigs, joints and constraints — the kinematic joint types, physical constraint types,
## the two-bone IK solver, foot planting, the procedural gait engine, ragdoll conversion,
## and the budgets that keep all of it affordable. CORE-SPEC §2, `RIG-SPEC.md`.
##
## Packs declare hierarchies and gait data; the core drives them. This is the module the
## horse test lives or dies on: a modded, properly articulated, two-joints-in-the-leg
## quadruped has to be possible in data alone, with no core code written for it. The
## four-legged test creature walks here, in C2, long before any horse art exists.
##
## Placeholder until C2. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"rig"


func module_milestone() -> String:
	return "C2"


func module_is_stub() -> bool:
	return true
