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


## Where packs are looked for, in order. `res://packs` is what ships; `user://packs` is
## where a workshop subscription or a hand-installed mod lands, and it comes second so a
## local copy of a pack id loses to the shipped one rather than silently replacing it.
const PACK_ROOTS: Array[String] = ["res://packs", "user://packs"]

var palette := Palette.new()
var materials := MaterialSet.new()
var slots := SlotSet.new()
var installed := PackSet.new()
var index := AssetIndex.new()
var resolver := AssetResolver.new()
var validator := AssetValidator.new()

## True once both core data files loaded clean. Nothing downstream should half-run on a
## broken palette: a part that cannot resolve its colour is not a part that should be
## quietly grey.
var data_ok := false
var data_errors: Array[String] = []


## Where packs are actually looked for this run: the two that ship, plus anything
## `--pack-root` added. The extra ones come last for the same reason `user://packs` does —
## a root handed over on the command line is the least authoritative thing in the list, and
## it must not be able to quietly replace a shipped pack id.
func pack_roots() -> Array[String]:
	var out: Array[String] = PACK_ROOTS.duplicate()
	for root in CLI.shared().pack_roots:
		if not out.has(root):
			out.append(root)
	return out


func module_name() -> StringName:
	return &"content"


func module_milestone() -> String:
	return "C1"


## No longer a stub as of C1. The bar for flipping this was not "has code in it" — it was
## BUILD-ORDER's C1 sentence: a new prop is a JSON file and nothing else, a variant of it
## costs five lines, and a pack that is wrong is disabled with a reason instead of taking
## the game down. All three are demonstrable against this module, so it stops apologising.
##
## What it still does not do is C2's problem and later: nothing here rigs, animates or
## spawns on demand, and the map is still code in `mode/sandbox.gd` rather than data.
func module_is_stub() -> bool:
	return false


func module_depends() -> Array[StringName]:
	return [&"physics"]


func module_init() -> void:
	data_ok = _load_core_data()

	# Packs are discovered even when core's own data is broken. Their manifests do not
	# depend on it, and a run that reports both problems at once is worth more than one
	# that stops at the first.
	installed.discover(pack_roots())
	for problem in installed.errors:
		push_error("pack folder: " + problem)

	# Assets are read and their `extends` chains carried out once, here, and baked. Nothing
	# resolves at runtime (FORMAT-SPEC §6), so a merge that was going to fail fails now,
	# during boot, in front of whoever installed the pack — rather than in the middle of a
	# round when somebody first spawns the thing.
	index.scan(installed)
	resolver.resolve_all(index, installed)

	# Validation needs the palette, the materials and the slot registry to check anything
	# against, so a broken core skips it rather than refusing every pack in the game for
	# naming a material that core forgot to load.
	if data_ok:
		validator.validate_all(resolver, index, installed, materials, palette, slots)
		push_warning(AssetValidator.dormant_report())

	# Read after resolving, because resolving can disable more of them.
	for id in installed.disabled:
		push_warning("pack `%s` is disabled — %s" % [id, installed.disabled[id]])

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
	ok = slots.load_core() and ok
	data_errors.append_array(slots.errors)
	return ok


## One line for the boot log. The counts are the useful part: if the palette suddenly has
## nineteen colours, something got dropped in a merge and this is where it shows.
func summary() -> String:
	if not data_ok:
		return "content: core data FAILED, %d problem(s)" % data_errors.size()
	return "content: %d colours (%d exempt), %d materials, %d slots, %d pack(s)%s, %d asset(s)%s" % [
		palette.colours.size(), palette.exemptions.size(), materials.materials.size(),
		slots.slots.size(), installed.order.size(),
		"" if installed.disabled.is_empty() else ", %d disabled" % installed.disabled.size(),
		resolver.resolved.size(),
		"" if validator.warnings.is_empty() else ", %d warning(s)" % validator.warnings.size()]
