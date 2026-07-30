extends Module
## The content pipeline — the part-table format, the five primitives (block, wedge, corner
## wedge, cylinder, sphere), the material set as data, the palette as data, the `pack.json`
## manifest, the loader, and the validator with human-readable failures. CORE-SPEC §3.
##
## Also the `extends` resolver: cross-pack inheritance capped at three levels, semver
## dependency declaration, deterministic topological load order, cycle detection,
## pack-scoped failure, and the `--resolve` provenance dump (`FORMAT-SPEC` §6).
##
## This is the milestone that decides the project's ceiling. If the format is wrong,
## everything ever authored on it is wrong — so it gets built before the first asset, not
## after. The kernel's module resolver next door is the rehearsal for it: same problem,
## thirteen items we control instead of a workshop full of them.
##
## Placeholder until C1. It boots, it declares its boundary, and it does nothing
## else — which is honest, and which means the module graph is real from day one instead of
## being retrofitted onto whatever ended up talking to whatever.


func module_name() -> StringName:
	return &"content"


func module_milestone() -> String:
	return "C1"


func module_is_stub() -> bool:
	return true

func module_depends() -> Array[StringName]:
	return [&"physics"]
