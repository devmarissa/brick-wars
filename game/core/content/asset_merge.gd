class_name AssetMerge
extends RefCounted
## The `extends` merge table from FORMAT-SPEC §6, and the paper trail it leaves behind.
##
## The table is short enough to quote: scalars replace, objects deep-merge key by key, lists
## replace wholesale, `list+` appends, `list~` patches a member by `name`. The spec calls it
## "defined boringly and precisely because vagueness here is where the debugging hours go",
## and this file is that sentence turned into code — nothing clever, nothing inferred, one
## branch per row.
##
## The provenance map is the other half and the more important one. Every field that any
## document in the chain sets is recorded against the id of the document that set it, so
## `--resolve` can answer "where did this number come from" without anybody opening three
## files. A wrong value two levels up is otherwise a genuinely bad afternoon, and `extends`
## stops being a feature and becomes a trap.
##
## Paths in that map read like the thing they point at: `kind`, `stats.zoom`,
## `parts[barrel].size`, `collider[0].offset`. Named list members are keyed by name because
## that is the handle `parts~` uses and the one a person thinks in; unnamed ones fall back to
## their index, which is the best that can be done for something with no handle.

## Fields that belong to the document rather than to the asset, and so never merge. `id` is
## the leaf's own by definition, `format` is about the file, and `extends` is the instruction
## being carried out rather than data being carried down.
const NOT_MERGED := ["format", "id", "extends"]

const APPEND := "+"
const PATCH := "~"

## What `source_of` reports for a field nobody ever wrote down.
const DEFAULT_SOURCE := "core (default)"

var data: Dictionary = {}
var provenance: Dictionary = {}
var errors: Array[String] = []


## Merge one document over whatever has accumulated so far. `source_id` is the document's
## own asset id and is what gets recorded as the origin of everything it sets; `where` is its
## file path, for messages; `base_id` is the asset being extended, which is the thing a
## `parts~` complaint has to name so its author knows which file to go and read.
func apply(doc: Dictionary, source_id: String, where: String, base_id: String) -> void:
	# Three sub-passes rather than one walk, because the order the author happened to type
	# their keys in must not change what the merge does. `parts` replaces first, then `parts~`
	# patches what is now there, then `parts+` appends to it. A document with both `parts` and
	# `parts~` is odd but well-defined; a document where it depends on key order would not be.
	for key in doc:
		var name := String(key)
		if NOT_MERGED.has(name) or name.ends_with(APPEND) or name.ends_with(PATCH):
			continue
		_assign(data, provenance, name, doc[key], source_id)

	for key in doc:
		var name := String(key)
		if name.ends_with(PATCH):
			_patch(name.trim_suffix(PATCH), doc[key], source_id, where, base_id)

	for key in doc:
		var name := String(key)
		if name.ends_with(APPEND):
			_append(name.trim_suffix(APPEND), doc[key], source_id, where)


## Set one field, deep-merging when both sides are objects and replacing otherwise. The two
## sides being objects is the only case where the child does not simply win — `{"zoom": 4.0}`
## adds one stat and keeps the other seven, which is the whole point of the object row.
static func _assign(into: Dictionary, prov: Dictionary, key: String, value: Variant,
		source_id: String, prefix := "") -> void:
	var path := key if prefix == "" else "%s.%s" % [prefix, key]
	if typeof(value) == TYPE_DICTIONARY and typeof(into.get(key)) == TYPE_DICTIONARY:
		for sub in value:
			_assign(into[key], prov, String(sub), value[sub], source_id, path)
		return
	into[key] = _copy(value)
	_record(prov, path, value, source_id)


## Record where a value came from, and where everything inside it came from. Recursing is
## what makes `parts[barrel].size` answerable at all; without it the trail stops at `parts`
## and the answer to "which document set this number" is "one of these three".
static func _record(prov: Dictionary, path: String, value: Variant, source_id: String) -> void:
	prov[path] = source_id
	match typeof(value):
		TYPE_DICTIONARY:
			for key in value:
				_record(prov, "%s.%s" % [path, key], value[key], source_id)
		TYPE_ARRAY:
			# Only lists of objects are walked into. `size: [3, 3, 30]` is one value that
			# happens to be written as three numbers, and reporting provenance for `size[1]`
			# would be noise; `parts` is a list of things that each have their own history.
			if not _is_member_list(value):
				return
			for i in value.size():
				_record(prov, "%s%s" % [path, _member_key(value[i], i)], value[i], source_id)


## `parts~` — patch a named member in place, leaving everything else about it inherited.
## This is the row that saves a redeclare when you want to nudge one part, and the one with
## the most ways to go wrong, so it accounts for all of them by name.
func _patch(key: String, patches: Variant, source_id: String, where: String, base_id: String) -> void:
	var about := "`%s`" % key
	if base_id != "":
		about = "`%s` in `%s`" % [key, base_id]
	if typeof(patches) != TYPE_ARRAY:
		errors.append("%s: `%s%s` should be a list of patches, each naming the member it patches" % [
			where, key, PATCH])
		return
	if typeof(data.get(key)) != TYPE_ARRAY:
		errors.append("%s: `%s%s` patches %s, and there is no `%s` list there to patch" % [
			where, key, PATCH, about, key])
		return

	var members: Array = data[key]
	for patch in patches:
		if typeof(patch) != TYPE_DICTIONARY:
			errors.append("%s: every `%s%s` entry is an object with a `name`" % [where, key, PATCH])
			continue
		if not patch.has("name") or String(patch["name"]).is_empty():
			# FORMAT-SPEC §10, last bullet. The message names the base asset because that is
			# the file that needs the `name` added, and it is not the file being edited.
			errors.append("%s: a `%s%s` patch has no `name`. It matches on `name`, so both the patch and the member of %s it means to patch need one." % [
				where, key, PATCH, about])
			continue

		var target := String(patch["name"])
		var at := _index_of(members, target)
		if at < 0:
			errors.append("%s: `%s%s` patches `%s`, and %s has no member by that name. Present: %s" % [
				where, key, PATCH, target, about, _names_in(members)])
			continue

		var member_path := "%s[%s]" % [key, target]
		for field in patch:
			if String(field) == "name":
				continue
			_assign(members[at], provenance, String(field), patch[field], source_id, member_path)


## `parts+` — add to the inherited list rather than replacing it. The list's own provenance
## is deliberately left pointing at whoever declared it: after an append the list genuinely
## came from two places, and the per-member entries are where the honest answer lives.
func _append(key: String, additions: Variant, source_id: String, where: String) -> void:
	if typeof(additions) != TYPE_ARRAY:
		errors.append("%s: `%s%s` should be a list of things to add to `%s`" % [
			where, key, APPEND, key])
		return
	if not data.has(key):
		data[key] = []
	elif typeof(data[key]) != TYPE_ARRAY:
		errors.append("%s: `%s%s` appends to `%s`, which is not a list" % [where, key, APPEND, key])
		return

	var members: Array = data[key]
	for item in additions:
		var i := members.size()
		members.append(_copy(item))
		_record(provenance, "%s%s" % [key, _member_key(item, i)], item, source_id)


static func _index_of(members: Array, target: String) -> int:
	for i in members.size():
		var m: Variant = members[i]
		if typeof(m) == TYPE_DICTIONARY and String(m.get("name", "")) == target:
			return i
	return -1


## The names that were available, for the "no member by that name" message. Being shown the
## four things you could have written beats being told the one you did write is wrong.
static func _names_in(members: Array) -> String:
	var names: Array[String] = []
	for m in members:
		if typeof(m) == TYPE_DICTIONARY and m.has("name"):
			names.append(String(m["name"]))
	if names.is_empty():
		return "none of them are named"
	names.sort()
	return ", ".join(names)


static func _member_key(member: Variant, index: int) -> String:
	if typeof(member) == TYPE_DICTIONARY and member.has("name"):
		return "[%s]" % member["name"]
	return "[%d]" % index


static func _is_member_list(value: Array) -> bool:
	if value.is_empty():
		return false
	for item in value:
		if typeof(item) != TYPE_DICTIONARY:
			return false
	return true


## Merged data is baked and handed on, so it must not share structure with the document it
## came from — a base asset extended by four variants would otherwise find its parts quietly
## rewritten by the last one to load.
static func _copy(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY, TYPE_ARRAY:
			return value.duplicate(true)
	return value
