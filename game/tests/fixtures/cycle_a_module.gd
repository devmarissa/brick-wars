extends Module
## Deliberately broken: depends on cycle_b, which depends back on this. Exists so the
## kernel's cycle report is a tested behaviour rather than a hopeful branch.

func module_name() -> StringName:
	return &"cycle_a"


func module_depends() -> Array[StringName]:
	return [&"cycle_b"]
