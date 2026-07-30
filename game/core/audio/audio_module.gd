extends Module
## The engine side of audio — mixing, the distance model, occlusion, reverb zones — plus
## the core audio set: footsteps by surface, the three-stage dig, impacts and ricochets,
## debris, brick collapse, water, wind bed. CORE-SPEC §2, §3. Packs supply weapon and
## vehicle voices only.
##
## Fills out alongside the verbs, because a verb without a sound is a third of a verb. The
## audio direction document is deliberately deferred until there is a running game to judge
## it against — writing it now would be describing a sound nobody has heard.
##
## Placeholder until C4. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"audio"


func module_milestone() -> String:
	return "C4"


func module_is_stub() -> bool:
	return true
