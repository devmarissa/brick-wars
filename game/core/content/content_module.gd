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
## Built so far: the two core data files and their registries. Still to come before this
## stops being a stub — pack manifests and load order, the extends resolver, the validator,
## and the builder that turns a part table into bricks.


var palette := Palette.new()
var materials := MaterialSet.new()

## True once both core data files loaded clean. Nothing downstream should half-run on a
## broken palette: a part that cannot resolve its colour is not a part that should be
## quietly grey.
var data_ok := false
var data_errors: Array[String] = []


func module_name() -> StringName:
	return &"content"


func module_milestone() -> String:
	return "C1"


func module_is_stub() -> bool:
	return true


func module_depends() -> Array[StringName]:
	return [&"physics"]


func module_init() -> void:
	data_ok = _load_core_data()
	if not data_ok:
		# Core's own data failing is a different kind of event from a pack failing. A bad
		# pack gets disabled and the game carries on without it; bad core data means every
		# material name in the game is now unknown, so it says so loudly and once.
		push_error("core content data did not load — %d problem(s):\n  %s" % [
			data_errors.size(), "\n  ".join(data_errors)])


func _load_core_data() -> bool:
	data_errors.clear()
	var ok := palette.load_core()
	data_errors.append_array(palette.errors)
	# The material set is read even when the palette failed, because its other eighty
	# checks are still worth running and reporting in the same pass. Every problem at
	# once beats one problem per run.
	ok = materials.load_core(palette) and ok
	data_errors.append_array(materials.errors)
	return ok


## One line for the boot log. The counts are the useful part: if the palette suddenly has
## nineteen colours, something got dropped in a merge and this is where it shows.
func summary() -> String:
	if not data_ok:
		return "content: core data FAILED, %d problem(s)" % data_errors.size()
	return "content: %d colours (%d exempt), %d materials" % [
		palette.colours.size(), palette.exemptions.size(), materials.materials.size()]
