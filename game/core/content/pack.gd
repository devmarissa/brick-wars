class_name Pack
extends RefCounted
## One `pack.json`, read and checked. FORMAT-SPEC §9.
##
## The manifest is the only file in a pack that the loader reads before deciding whether to
## trust the pack at all, so everything it needs to make that decision lives here: who this
## is, what core it was built against, and what else has to be loaded first.
##
## Nothing in this class looks at content. A manifest can be perfect and every asset in the
## folder still be wrong; that is the validator's job (FORMAT-SPEC §10) and it happens after
## load order is known, because an asset that `extends` another cannot be checked until the
## pack it extends from has been read.

const MANIFEST := "pack.json"
const FORMAT := 1

## `mcheves_cavalry`, not `Cavalry` and not `mcheves-cavalry`. One spelling of an id is the
## only way `pack:asset` references stay predictable across four hundred workshop uploads.
const ID_PATTERN := "^[a-z][a-z0-9_]*$"

## Fields a manifest may carry. Anything else is a warning, not a refusal — FORMAT-SPEC §10
## puts unknown fields under "load anyway", because a pack written for a later core should
## degrade rather than die.
const KNOWN_FIELDS := [
	"format", "id", "name", "version", "author", "core_version", "depends",
	"era", "factions", "content", "description", "license", "homepage",
]

var root := ""                       ## the folder, e.g. `res://packs/great_war`
var id: StringName = &""
var name := ""
var version := "0.0.0"
var author := ""
var core_version := "*"
var depends: Array = []              ## [{ id: StringName, range: String }]
var era: Dictionary = {}
var factions: Array = []
var content: Array = []

var errors: Array[String] = []
var warnings: Array[String] = []

## Set by PackSet when this pack is refused. Held here rather than thrown away so the boot
## report can say which packs are off and why, instead of them silently not being there.
var disabled_because := ""


func is_ok() -> bool:
	return errors.is_empty()


func is_enabled() -> bool:
	return errors.is_empty() and disabled_because.is_empty()


## Read `<root>/pack.json`. Returns false having filled `errors` — all of them, not the
## first, because a modder fixing a manifest one message per run gives up on message three.
func load_from(folder: String) -> bool:
	root = folder.trim_suffix("/")
	errors.clear()
	warnings.clear()

	var path := manifest_path()
	var data := ContentLoader.read_object(path, errors)
	if data.is_empty():
		if errors.is_empty():
			errors.append("%s: the manifest is empty" % path)
		return false

	_read_identity(path, data)
	_read_versions(path, data)
	_read_depends(path, data)
	_read_optional(path, data)
	_warn_unknown(path, data)

	return errors.is_empty()


func manifest_path() -> String:
	return "%s/%s" % [root, MANIFEST]


## `great_war:vehicle_tank_rhomboid` from `vehicle_tank_rhomboid`. FORMAT-SPEC §8.
func qualify(asset: String) -> String:
	if asset.contains(":"):
		return asset
	return "%s:%s" % [id, asset]


## Does this pack declare a dependency on `other`? Cross-pack `extends` requires one, and
## this is the question the resolver asks (FORMAT-SPEC §10).
func depends_on(other: StringName) -> bool:
	for d in depends:
		if d["id"] == other:
			return true
	return false


func range_for(other: StringName) -> String:
	for d in depends:
		if d["id"] == other:
			return d["range"]
	return ""


func described() -> String:
	return "%s %s" % [id, version]


func _read_identity(path: String, data: Dictionary) -> void:
	var fmt: Variant = ContentLoader.require(data, "format", path, TYPE_FLOAT, errors)
	if fmt != null and int(fmt) != FORMAT:
		errors.append("%s: format %d, and this core reads format %d. %s" % [
			path, int(fmt), FORMAT,
			"A newer pack needs a newer core; an older one needs migrating."])

	var raw_id: Variant = ContentLoader.require(data, "id", path, TYPE_STRING, errors)
	if raw_id != null:
		var text := String(raw_id)
		var re := RegEx.new()
		re.compile(ID_PATTERN)
		if re.search(text) == null:
			errors.append("%s: `%s` is not a pack id. %s" % [path, text,
				"Lowercase letters, digits and underscores, starting with a letter."])
		else:
			id = StringName(text)

	var raw_name: Variant = ContentLoader.require(data, "name", path, TYPE_STRING, errors)
	if raw_name != null:
		name = String(raw_name)


func _read_versions(path: String, data: Dictionary) -> void:
	var raw: Variant = ContentLoader.require(data, "version", path, TYPE_STRING, errors)
	if raw != null:
		var text := String(raw)
		if SemVer.parse(text, "%s: `version`" % path, errors) != Vector3i(-1, -1, -1):
			version = text

	# `core_version` is required rather than defaulted to `*`. A pack that never said which
	# core it was built for is a pack that will one day load against a core it cannot cope
	# with, and the author will hear about it from a player rather than from the loader.
	var raw_core: Variant = ContentLoader.require(data, "core_version", path, TYPE_STRING, errors)
	if raw_core != null:
		var text := String(raw_core)
		if SemVer.is_valid_range(text, "%s: `core_version`" % path, errors):
			core_version = text


func _read_depends(path: String, data: Dictionary) -> void:
	if not data.has("depends"):
		return
	if typeof(data["depends"]) != TYPE_ARRAY:
		errors.append("%s: `depends` should be a list of { id, version }" % path)
		return

	var seen: Dictionary = {}
	for entry in data["depends"]:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: every `depends` entry is an object with `id` and `version`" % path)
			continue
		var where := "%s: `depends`" % path
		var dep_id: Variant = ContentLoader.require(entry, "id", where, TYPE_STRING, errors)
		var dep_range: Variant = ContentLoader.require(entry, "version", where, TYPE_STRING, errors)
		if dep_id == null or dep_range == null:
			continue
		var name_of := StringName(dep_id)
		if name_of == id:
			errors.append("%s: depends on itself" % path)
			continue
		if seen.has(name_of):
			errors.append("%s: depends on `%s` twice, with `%s` and `%s`. %s" % [
				path, name_of, seen[name_of], dep_range,
				"Two ranges for one pack is a question with no answer."])
			continue
		if not SemVer.is_valid_range(String(dep_range), "%s on `%s`" % [where, name_of], errors):
			continue
		seen[name_of] = dep_range
		depends.append({ "id": name_of, "range": String(dep_range) })


func _read_optional(path: String, data: Dictionary) -> void:
	author = String(data.get("author", ""))
	era = data.get("era", {})
	factions = data.get("factions", [])
	content = data.get("content", [])

	if typeof(era) != TYPE_DICTIONARY:
		errors.append("%s: `era` should be an object" % path)
		era = {}
	for key in ["factions", "content"]:
		if typeof(data.get(key, [])) != TYPE_ARRAY:
			errors.append("%s: `%s` should be a list" % [path, key])

	# Two factions, because core fixes the shape and the packs fill it in (ART-BIBLE §2).
	# A pack with three is not a pack with a bonus faction; it is a pack whose third
	# faction has no colour slot and no readability guarantee.
	if factions.size() != 0 and factions.size() != 2:
		errors.append("%s: %d factions. %s" % [path, factions.size(),
			"Core fixes two per pack, one colour and one shadow each, or none at all."])


func _warn_unknown(path: String, data: Dictionary) -> void:
	for key in data:
		if not KNOWN_FIELDS.has(String(key)):
			warnings.append("%s: unknown field `%s` — ignored" % [path, key])
