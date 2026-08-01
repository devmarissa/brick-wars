extends Module
## Combat maths — projectile ballistics, melee resolution, the damage model, hit
## detection, area-effect falloff. CORE-SPEC §2.
##
## Era-neutral by construction: arrows and bullets are the same maths, and the day this
## module contains the word `rifle` the boundary has already failed. The bow in TESTPACK
## exists to make that failure loud and immediate rather than discovered in year two.
##
## The combat maths lives under `core/combat/` and is reached through its classes: `Ballistics` is
## where a projectile goes, `Projectile` is the sweep that decides whether it ever arrives, and
## `Damage` is how much of a hit lands.


func module_name() -> StringName:
	return &"combat"


func module_milestone() -> String:
	return "C4"


## No longer a stub as of C4. Its own docstring set the bar — *"the day this module contains the
## word `rifle` the boundary has already failed"* — and `case_fire.gd` asserts that against the
## source text rather than trusting it. A bolt rifle and a bow go through one formula that was never
## told which was which, and at 40 m one has dropped 0.71 m and the other 5.29.
##
## Where it stops is the line worth keeping: **C4 works out how much damage arrives; C5 decides what
## the thing on the receiving end does about it.** So nothing here reads `failure`, `fire`,
## `support_vertical` or `cohesion`, though the material file has carried all four since C1. The
## blast model, spall, fire propagation and tool gating are **C5**'s by name, and the area-falloff
## *curve* is here only because CORE-SPEC lists it under combat maths.
func module_is_stub() -> bool:
	return false
