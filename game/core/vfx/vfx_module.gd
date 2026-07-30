extends Module
## Core VFX — explosion, dust, smoke, fire, dirt fountain, water splash, muzzle flash,
## tracer, impact chips, brick burst. CORE-SPEC §3. Packs tune scale and colour; they do
## not author new effects, and they never ship shaders (CORE-SPEC §5 — a shader that
## disables depth testing is a wallhack, and this game is built on being unseen).
##
## Lands with destruction in C5 because half of what an explosion *feels* like is what it
## looks like, and the blast fixture measures the other half.
##
## Placeholder until C5. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"vfx"


func module_milestone() -> String:
	return "C5"


func module_is_stub() -> bool:
	return true
