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
## The rig system lives under `core/rig/` and is reached through its classes rather than through
## this node: `Rig` builds a hierarchy and poses it, `TwoBoneIK` bends a limb, `Footing` plants a
## foot and levels a body, `Gait` turns a speed into a step cycle, `Leg` measures one off its rest
## pose, `Locomotion` runs them in order, `Walker` puts the result on a body physics owns, and
## `LocomotionRules` and `RigRules` refuse the data that would break any of it. None of that needs
## a module instance to hold it, which is why this file is short and is not a sign that nothing
## happened.


func module_name() -> StringName:
	return &"rig"


func module_milestone() -> String:
	return "C2"


## No longer a stub as of C2. The bar was BUILD-ORDER's C2 sentence rather than a line count: *a
## soldier defined entirely in data walks, sprints and jumps over uneven ground with feet that
## plant correctly, and a four-legged test creature walks using the same system*. Both halves are
## demonstrable — `core:soldier` and `testpack:horse` do it in `case_walker.gd` against real
## physics, and the second of them comes out of a non-core pack with no core change, which is the
## horse test this module's own docstring said it would live or die on.
##
## What it still does not do is later milestones' problem. Nothing here converts a rig to a
## ragdoll (C5), tracks a turret or puts hands on controls (C6), or enforces the physical
## constraint budgets — `AssetValidator.DORMANT` says so at boot rather than pretending, because
## RIG-SPEC §2 and §6 assert those budgets exist and state no numbers to check against.
func module_is_stub() -> bool:
	return false
