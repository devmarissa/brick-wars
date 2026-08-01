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
## The verb system lives under `core/verbs/` and is reached through its classes rather than through
## this node: `VerbSet` is the closed vocabulary and its refusals, `Verbs` is the one door every
## interaction goes through, `VerbDig` / `VerbFire` / `VerbMelee` / `VerbThrow` are the verbs that
## do something, and `Loadout` is what a soldier is carrying and therefore what they can do.


func module_name() -> StringName:
	return &"verbs"


func module_milestone() -> String:
	return "C4"


## No longer a stub as of C4. The bar was BUILD-ORDER's C4 sentence rather than a line count —
## *a weapon defined in data fires, a bow and a rifle are the same code path, and TESTPACK's bow
## works with zero core changes* — and `case_fire.gd` walks all three clauses against real content.
##
## The vocabulary is closed and there is nowhere in the asset format to write a new verb down, which
## is what makes CORE-SPEC's *"packs cannot define new verbs"* true without anybody enforcing it: a
## slot decides its verbs, and a pack picks a slot.
##
## What it still does not do is later milestones' problem, and each piece says which. `throw` is
## `partial` — it flies, and the blast is **C5**'s. `build` is declared and reserved to **C5**,
## because a sandbag wall that does not topple sideways where a clay one slumps is a prop with a
## placement cost. `enter` and `man` are **C6**'s; `carry`, `interact` and `signal` are **C7**'s.
## Nothing here reads an input — **C4b** is the milestone that puts hands on any of it.
func module_is_stub() -> bool:
	return false
