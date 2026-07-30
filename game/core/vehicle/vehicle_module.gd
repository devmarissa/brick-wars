extends Module
## Vehicle simulation — ground, air and water locomotion across all five types (wheeled,
## tracked, legged, flying, floating), seats and crew, hands on controls via the C2 IK,
## turret tracking, spring suspension, damage states, ragdoll conversion. CORE-SPEC §2.
##
## Handling is **built here, not ported** (`BUILD-ORDER` §1b). The old build's numbers were
## never signed off — the verdict was that the turn radius was bad on most vehicles — so
## honest mass distribution and real suspension come first and handling is tuned on top of
## them, rather than tuning a feel on top of a placeholder. C6 does not close without a
## named sign-off on one wheeled, one tracked and one flying vehicle.
##
## Placeholder until C6. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"vehicle"


func module_milestone() -> String:
	return "C6"


func module_is_stub() -> bool:
	return true
