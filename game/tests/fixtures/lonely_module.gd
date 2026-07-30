extends Module
## Deliberately broken: depends on a module that is not in any manifest. This is the
## mistake a pack author makes most often, so its error message is worth a test.

func module_name() -> StringName:
	return &"lonely"


func module_depends() -> Array[StringName]:
	return [&"nobody"]
