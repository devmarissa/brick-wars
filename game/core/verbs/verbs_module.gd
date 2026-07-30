extends Module
## The interaction vocabulary — fire, throw, dig, build, melee, carry, enter, man,
## interact, signal — plus the weapon archetype slots and the loadout system.
## CORE-SPEC §2.
##
## **Packs cannot define new verbs.** A pack that wants one is a core change request, and
## that constraint is what keeps the netcode and the animation state machine finite.
##
## Every verb owes the full chain before it counts as done: input → animation → sound →
## VFX → camera response → UI acknowledgment (`PRODUCTION.md`). Six steps, not one.
##
## Placeholder until C4. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"verbs"


func module_milestone() -> String:
	return "C4"


func module_is_stub() -> bool:
	return true
