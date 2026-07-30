extends Module
## Combat maths — projectile ballistics, melee resolution, the damage model, hit
## detection, area-effect falloff. CORE-SPEC §2.
##
## Era-neutral by construction: arrows and bullets are the same maths, and the day this
## module contains the word `rifle` the boundary has already failed. The bow in TESTPACK
## exists to make that failure loud and immediate rather than discovered in year two.
##
## Placeholder until C4. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"combat"


func module_milestone() -> String:
	return "C4"


func module_is_stub() -> bool:
	return true
