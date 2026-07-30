extends Module
## Deliberately broken: the manifest lists this under one name and it answers to another.
## Silently trusting the manifest key here would make `use()` fail somewhere far away.

func module_name() -> StringName:
	return &"actually_something_else"
