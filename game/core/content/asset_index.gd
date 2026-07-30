class_name AssetIndex
extends RefCounted
## Every asset document every enabled pack publishes, keyed by `pack:asset`. FORMAT-SPEC §8.
##
## This is only the reading step. Nothing here carries out an `extends`, checks a material
## name or counts colliders — it answers "what documents exist and which pack published
## them", which is the question the resolver has to have answered before it can start, since
## an asset that extends another cannot be looked at until the other one has been found.
##
## What counts as an asset document is deliberately loose: any `.json` in a pack that is an
## object with an `id` or an `extends`. Packs also carry style, strings, audio manifests and
## maps, and a scanner that demanded a sanctioned folder name would reject a crate somebody
## put in `props/` for no reason a modder could act on. The reserved filenames at the pack
## root are the exception — `pack.json` and friends have their own readers.

const RESERVED := ["pack.json", "palette.json", "materials.json", "style.json"]

## Folders that are never scanned. Both hold files that are content but not assets, and
## walking them would only produce complaints about documents that are fine.
const SKIP_DIRS := ["audio", "strings"]

const NAME_PATTERN := "^[a-z][a-z0-9_]*$"

var documents: Dictionary = {}      ## String id -> Dictionary, the raw document
var owners: Dictionary = {}         ## String id -> StringName pack id
var paths: Dictionary = {}          ## String id -> String file path
var ids: Array[String] = []         ## every id, sorted

## Problems, keyed by the pack that has to answer for them. A pack whose documents cannot be
## read is a pack that must not half-load, and the resolver turns these into refusals.
var pack_errors: Dictionary = {}    ## StringName -> Array[String]


func scan(packs: PackSet) -> void:
	documents.clear()
	owners.clear()
	paths.clear()
	ids.clear()
	pack_errors.clear()

	for pack in packs.enabled_packs():
		_scan_pack(pack)

	ids.sort()


func has(id: String) -> bool:
	return documents.has(id)


func document(id: String) -> Dictionary:
	return documents.get(id, {})


func owner_of(id: String) -> StringName:
	return owners.get(id, &"")


func path_of(id: String) -> String:
	return paths.get(id, "")


func ids_in(pack_id: StringName) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		if owners[id] == pack_id:
			out.append(id)
	return out


## FORMAT-SPEC §8: "Bare names are resolved within the current pack first, then core."
## A name that is already qualified is left exactly as written — reaching for another pack
## is meant to look like reaching for another pack.
func resolve_reference(reference: String, from_pack: StringName) -> String:
	if reference.contains(":"):
		return reference
	var own := "%s:%s" % [from_pack, reference]
	if documents.has(own):
		return own
	var from_core := "core:%s" % reference
	if documents.has(from_core):
		return from_core
	return own


func _scan_pack(pack: Pack) -> void:
	var files: Array[String] = []
	_files_under(pack.root, true, files)
	for file in files:
		_read_document(pack, file)


func _files_under(folder: String, at_root: bool, out: Array[String]) -> void:
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for file in names:
		if not file.ends_with(".json"):
			continue
		if at_root and RESERVED.has(file):
			continue
		out.append("%s/%s" % [folder, file])

	var dirs := DirAccess.get_directories_at(folder)
	dirs.sort()
	for dir in dirs:
		if SKIP_DIRS.has(dir):
			continue
		_files_under("%s/%s" % [folder, dir], false, out)


func _read_document(pack: Pack, file: String) -> void:
	var problems: Array[String] = []
	var data := ContentLoader.read_object(file, problems)
	if not problems.is_empty():
		_fail(pack.id, problems)
		return
	if not data.has("id") and not data.has("extends"):
		return    # style, strings, a map — somebody else's file, and not a mistake

	var raw: Variant = ContentLoader.require(data, "id", file, TYPE_STRING, problems)
	if raw == null:
		_fail(pack.id, problems)
		return

	var id := _qualified(pack, String(raw), file, problems)
	if id == "":
		_fail(pack.id, problems)
		return

	if documents.has(id):
		# Within one pack, since the pack id is half of every asset id. Two files claiming
		# one asset is a question only a human can settle, so neither wins.
		_fail(pack.id, ["%s: `%s` is already claimed by %s. Two files, one id — %s" % [
			file, id, paths[id], "rename one of them, because nothing here can pick."]])
		return

	documents[id] = data
	owners[id] = pack.id
	paths[id] = file
	ids.append(id)


## An id is either bare and belongs to this pack, or qualified and must agree about which
## pack that is. A pack cannot publish into another pack's namespace: that is the guarantee
## that makes `pack:asset` mean anything at all across four hundred workshop uploads.
func _qualified(pack: Pack, raw: String, file: String, problems: Array[String]) -> String:
	var asset_name := raw
	if raw.contains(":"):
		var claimed := StringName(raw.get_slice(":", 0))
		asset_name = raw.substr(raw.find(":") + 1)
		if claimed != pack.id:
			problems.append("%s: id `%s` puts this asset in pack `%s`, and it is in `%s`. %s" % [
				file, raw, claimed, pack.id,
				"A pack publishes into its own namespace and no other."])
			return ""

	var re := RegEx.new()
	re.compile(NAME_PATTERN)
	if re.search(asset_name) == null:
		problems.append("%s: `%s` is not an asset name. %s" % [file, asset_name,
			"Lowercase letters, digits and underscores, starting with a letter."])
		return ""
	return "%s:%s" % [pack.id, asset_name]


func _fail(pack_id: StringName, problems: Array[String]) -> void:
	if not pack_errors.has(pack_id):
		pack_errors[pack_id] = [] as Array[String]
	pack_errors[pack_id].append_array(problems)
