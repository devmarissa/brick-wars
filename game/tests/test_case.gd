class_name TestCase
extends RefCounted
## One test case. Override two methods.
##
## `run` may await — most of what needs testing here only becomes true a few physics ticks
## after you ask for it, and pretending otherwise is how you get a suite that passes on a
## fast machine and fails on CI.

func case_name() -> String:
	return "unnamed"


## Do the work; record results through `t`. Throwing is not a thing in GDScript, so a case
## that discovers it cannot continue should call `t.fail(...)` and return.
func run(_t: TestContext) -> void:
	pass
