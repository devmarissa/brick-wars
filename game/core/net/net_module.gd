extends Module
## Netcode — the authority model, interest management, earth-event encoding, late-join
## replay, and the dedicated server. CORE-SPEC §2.
##
## Late in the order, but it constrains things from the beginning: the earth event log in
## C3 is built as a replicable stream rather than retrofitted into one, and once this lands
## the server owns every gameplay number regardless of what a client's pack claims.
##
## The gate is 32 real players in a siege, with the 100v100 bot figure measured and written
## down rather than hoped for.
##
## Placeholder until C8. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"net"


func module_milestone() -> String:
	return "C8"


func module_is_stub() -> bool:
	return true
