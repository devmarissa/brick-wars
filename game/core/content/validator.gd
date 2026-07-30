class_name AssetValidator
extends RefCounted
## The gate every resolved asset passes before anything is allowed to build it. FORMAT-SPEC §10.
##
## The rules themselves live in `PartRules` and `AssetRules`. What lives here is the part
## that makes them useful to a person: running them over the whole content set, working out
## which file and which line each complaint belongs to, deciding which pack is at fault, and
## taking that pack out of circulation without touching anybody else's.
##
## Pointing at the right file is most of the job. An asset that inherits a bad material from
## a base three packs away has its mistake in the base, so the message goes to the base's
## file — `ResolvedAsset` already recorded which document wrote every field, and `SourceLines`
## turns that document into a line number. Sending a modder to their own variant, which is
## correct, is how somebody loses an evening.
##
## Failure is scoped and it cascades. A pack with a single refused asset is disabled whole —
## it never half-loads — and any asset built on one of its assets is refused in turn, because
## a variant of a thing that was not allowed to exist is not a thing that should load either.

## The document format this build reads. FORMAT-SPEC §11.
const FORMAT := 1

## Rules §10 asks for that nothing here can enforce yet. They are reported at boot rather
## than quietly skipped: a written rule that silently does not run is worse than one nobody
## wrote, because everyone downstream builds as though it were holding.
const DORMANT := [
	"`anim` keys are not checked against core animation states — core has no state list yet, and the animation style guide that would define one is deferred until there is a running game to write it against.",
	"the physical-constraint budget per object and per scene is not enforced — RIG-SPEC §2 and §6 assert the budget exists and state no numbers.",
	"derived-material multipliers are not checked — the ×0.5–×2.0 bound, and `class`, `failure` and `hardness` being un-overridable, need the pack-material resolver (MATERIAL-SPEC §8), which is not built.",
]

var errors: Array[String] = []
var warnings: Array[String] = []
var refused: Dictionary = {}        ## StringName pack id -> Array[String] reasons
var checked := 0
var core_failed := false

var _lines := SourceLines.new()


## Check every asset an enabled pack publishes, disabling packs as required. Returns false
## if anything was refused; for everything except core, that is not fatal.
func validate_all(resolver: AssetResolver, index: AssetIndex, packs: PackSet,
		materials: MaterialSet, palette: Palette, slots: SlotSet) -> bool:
	errors.clear()
	warnings.clear()
	refused.clear()
	checked = 0
	core_failed = false

	# Every asset is checked before any pack is refused, so one broken pack does not hide the
	# problems in the next one. Somebody fixing a content set wants the whole list.
	var problems: Dictionary = {}
	for id in resolver.sorted_ids():
		var asset: ResolvedAsset = resolver.resolved[id]
		if not packs.is_enabled(asset.owner):
			continue
		checked += 1
		_validate(asset, index, materials, palette, slots, problems)

	for pack_id in ContentLoader.sorted_names(problems.keys()):
		_refuse(packs, pack_id, problems[pack_id])
	_cascade(resolver, index, packs)
	_drop_disabled(resolver, packs)
	return refused.is_empty()


## The rules §10 asks for that this build does not run, for the boot log.
static func dormant_report() -> String:
	return "validator: %d rule(s) declared and not yet enforced —\n  %s" % [
		DORMANT.size(), "\n  ".join(DORMANT)]


func _validate(asset: ResolvedAsset, index: AssetIndex, materials: MaterialSet,
		palette: Palette, slots: SlotSet, problems: Dictionary) -> void:
	# `AssetRules` asks for a location by (part, field) and `PartRules` by (field) alone, so
	# they get differently shaped closures over the same lookup rather than one awkward
	# signature that neither of them wants.
	var asset_at := func(part_name: String, field: String) -> String:
		return _where(asset, index, part_name, part_name, field)

	var rules := AssetRules.new()
	rules.check(asset, asset_at, slots)
	rules.check_names(asset, asset_at)
	_check_format(asset, index, asset_at, rules)

	var parts := asset.parts()
	var names := asset.part_names()
	var part_rules := PartRules.new()
	for i in parts.size():
		if typeof(parts[i]) != TYPE_DICTIONARY:
			rules.errors.append("%s — part %d is not an object. %s (FORMAT-SPEC §5)" % [
				asset_at.call("", "parts"), i + 1,
				"`parts` is a list of part objects, each with an `offset`, a `size` and a `material`"])
			continue
		var part: Dictionary = parts[i]
		var part_name := String(part.get("name", ""))
		# Unnamed parts are keyed by position, exactly as the merge keys them, so a location
		# lookup on one finds the same provenance entry the merge wrote.
		var key := part_name if part_name != "" else str(i)
		var label := "part `%s`" % part_name if part_name != "" else "part %d" % (i + 1)
		part_rules.check(part, label, _part_at(asset, index, part_name, key),
			names, materials, palette)

	_collect(asset, rules.errors, rules.warnings, problems)
	_collect(asset, part_rules.errors, part_rules.warnings, problems)


## FORMAT-SPEC §11. Not a §10 rule, but it decides whether the rest of the checks mean
## anything: running format-1 rules over a format-2 document is a validator confidently
## reporting on a file it has misread.
##
## Read from the leaf document rather than from `asset.data`, because `format` is in
## `AssetMerge.NOT_MERGED` — it describes the file, not the asset, so it is deliberately not
## carried down a chain and never appears in the merged result. Checking the merged data
## instead reported every asset in the game as having no `format`, including the ones that
## declare it on line two.
func _check_format(asset: ResolvedAsset, index: AssetIndex, at: Callable,
		rules: AssetRules) -> void:
	var doc := index.document(asset.id)
	if not doc.has("format"):
		rules.warnings.append("%s — no `format`, so it is read as format %d (FORMAT-SPEC §11)" % [
			at.call("", AssetRules.ANCHOR), FORMAT])
		return
	var declared := int(doc["format"])
	if declared > FORMAT:
		rules.errors.append("%s — `format` is %d and this build reads format %d. %s (FORMAT-SPEC §11)" % [
			at.call("", "format"), declared, FORMAT,
			"The pack was written for a newer Brick Wars, so updating the game is the fix rather than editing the pack"])
	elif declared < 1:
		rules.errors.append("%s — `format` is %d, and formats start at 1 (FORMAT-SPEC §11)" % [
			at.call("", "format"), declared])


func _part_at(asset: ResolvedAsset, index: AssetIndex, part_name: String,
		key: String) -> Callable:
	return func(field: String) -> String:
		return _where(asset, index, part_name, key, field)


## `res://packs/great_war/rifle.json:41` for whichever document actually wrote the field.
##
## Three fallbacks, each one a step further out: the field itself, then the part it belongs
## to, then the asset being validated. A field nobody wrote — one this build is complaining
## about the absence of — has no provenance at all, and the file to send somebody to for a
## missing `material` is the one holding the part that is missing it.
func _where(asset: ResolvedAsset, index: AssetIndex, part_name: String, key: String,
		field: String) -> String:
	var part_path := "" if key == "" else "parts[%s]" % key
	var full := part_path
	if field != "":
		full = "%s.%s" % [part_path, field] if part_path != "" else field

	var source := ""
	if asset.provenance.has(full):
		source = asset.source_of(full)
	elif part_path != "" and asset.provenance.has(part_path):
		source = asset.source_of(part_path)

	var file := index.path_of(source) if index.has(source) else asset.path
	# An unnamed part cannot be searched for, and a line number found by looking for the bare
	# field would be the first part in the file rather than this one. Wrong is worse than
	# absent, so it goes without one.
	return _lines.at(file, part_name, field)


func _collect(asset: ResolvedAsset, errs: Array[String], warns: Array[String],
		problems: Dictionary) -> void:
	for warning in warns:
		warnings.append("%s — %s" % [asset.id, warning])
	if errs.is_empty():
		return
	# Blamed on the pack that publishes the asset, even when the offending value was written
	# in a base somewhere else. The base is validated on its own account in the same pass and
	# gets refused for its own copy of the mistake; what this pack did wrong is publish an
	# asset that does not load, and that is a true thing to say about it.
	if not problems.has(asset.owner):
		problems[asset.owner] = [] as Array[String]
	for problem in errs:
		problems[asset.owner].append("%s — %s" % [asset.id, problem])


## An asset whose chain runs through a pack that just failed has no base to have been merged
## from — the resolver's own "no enabled pack publishes it" rule, arriving one stage late.
## Refusing it here is what stops a variant of a disallowed asset from loading as though its
## base were fine. A fixpoint, because a chain is up to three deep and disabling the middle
## of one does not reach the end of it until the next pass.
func _cascade(resolver: AssetResolver, index: AssetIndex, packs: PackSet) -> void:
	var changed := true
	while changed:
		changed = false
		for id in resolver.sorted_ids():
			var asset: ResolvedAsset = resolver.resolved[id]
			if not packs.is_enabled(asset.owner):
				continue
			for step in asset.chain:
				var base_owner := index.owner_of(step)
				if base_owner == asset.owner or packs.is_enabled(base_owner):
					continue
				_refuse(packs, asset.owner, ["%s extends `%s`, and `%s` is disabled. %s" % [
					id, step, base_owner,
					"An asset built on a refused one cannot be trusted to be what it says it is."],
				] as Array[String])
				changed = true
				break


func _drop_disabled(resolver: AssetResolver, packs: PackSet) -> void:
	for id in resolver.sorted_ids():
		var asset: ResolvedAsset = resolver.resolved[id]
		if not packs.is_enabled(asset.owner):
			resolver.resolved.erase(id)


func _refuse(packs: PackSet, pack_id: StringName, reasons: Array) -> void:
	var lines: Array[String] = []
	for reason in reasons:
		lines.append(String(reason))
	if lines.is_empty():
		return
	if refused.has(pack_id):
		refused[pack_id].append_array(lines)
	else:
		refused[pack_id] = lines
	errors.append_array(lines)
	if pack_id == PackSet.CORE_ID:
		# Core failing validation is not a pack problem, it is a broken build: every asset in
		# the game inherits from it. It is still refused rather than excused, because a core
		# that is allowed to break its own rules is a core nobody else's pack can be held to.
		core_failed = true
	packs.refuse(pack_id, "\n      ".join(lines))
