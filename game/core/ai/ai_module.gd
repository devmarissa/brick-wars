extends Module
## AI behaviour — cover, garrison, assault, sap, squad logic, bot fill. CORE-SPEC §2.
##
## Packs tune parameters; they do not author behaviour trees. An era changes what a soldier
## carries and what they look like, not how a squad decides to take a position.
##
## Placeholder until C7. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"ai"


func module_milestone() -> String:
	return "C7"


func module_is_stub() -> bool:
	return true
