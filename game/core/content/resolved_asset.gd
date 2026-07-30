class_name ResolvedAsset
extends RefCounted
## One asset after `extends` has been carried out — baked, with a record of where every
## field came from. FORMAT-SPEC §6.
##
## "Resolution happens once at load time and is baked. Nothing resolves at runtime." So this
## is the only form of an asset anything downstream ever sees: the builder reads `data` and
## never learns that four documents were involved in producing it.
##
## `provenance` is what makes that survivable for the person authoring the four documents.
## `--resolve <asset_id>` prints it, and the format is the one the spec asked for:
##
##     size      [3, 3, 30]   ← great_war:rifle_sniper
##     material  steel        ← great_war:rifle_bolt
##     jitter    0.0          ← core (default)
##
## A field nobody wrote down reports `core (default)` rather than going missing, because
## "where did this 0 come from" is exactly as urgent a question as "where did this 30 come
## from" and rather harder to answer by reading files.

const DEFAULT_SOURCE := AssetMerge.DEFAULT_SOURCE

## The spec's column widths, used as-is for a part dump and as minimums for a whole-asset
## one. The maximums exist because a single 300-character part table would otherwise push
## the source column off the right of the terminal for every other row in the dump; a row
## that overruns its column takes one space and keeps going, which is ragged but readable.
const PATH_COLUMN := 10
const VALUE_COLUMN := 13
const PATH_COLUMN_MAX := 34
const VALUE_COLUMN_MAX := 30

var id := ""                        ## `pack:asset`
var owner: StringName = &""         ## the pack the leaf document lives in
var path := ""                      ## the file the leaf document came from
var data: Dictionary = {}           ## fully merged
var provenance: Dictionary = {}     ## field path -> the asset id that set it
var chain: Array[String] = []       ## base first, leaf last — one entry if nothing was extended


func kind() -> String:
	return String(data.get("kind", ""))


func name() -> String:
	return String(data.get("name", ""))


func parts() -> Array:
	var list: Variant = data.get("parts", [])
	return list if typeof(list) == TYPE_ARRAY else []


func part_names() -> Array[String]:
	var out: Array[String] = []
	for part in parts():
		if typeof(part) == TYPE_DICTIONARY and part.has("name"):
			out.append(String(part["name"]))
	return out


func inherited() -> bool:
	return chain.size() > 1


## Where a field came from, by path (`kind`, `stats.zoom`, `parts[barrel].size`).
func source_of(field_path: String) -> String:
	return String(provenance.get(field_path, DEFAULT_SOURCE))


## The whole asset, one line per field that somebody actually wrote a value into, in path
## order. Columns are sized to the contents rather than to the spec's fixed widths, because
## the spec's sample is a part dump — its labels are `size` and `material`, and a full path
## like `parts[barrel].material` is more than twice as wide as the column it was given.
func dump() -> String:
	var lines: Array[String] = []
	lines.append("%s   (%s)" % [id, path])
	if inherited():
		lines.append("extends chain: %s" % " → ".join(chain))
	else:
		lines.append("extends nothing")
	lines.append("")

	var paths := _leaf_paths()
	var path_width := PATH_COLUMN
	var value_width := VALUE_COLUMN
	for field_path in paths:
		path_width = maxi(path_width, field_path.length() + 2)
		value_width = maxi(value_width, value_text(_at(field_path)).length() + 2)
	path_width = mini(path_width, PATH_COLUMN_MAX)
	value_width = mini(value_width, VALUE_COLUMN_MAX)

	for field_path in paths:
		lines.append(line(field_path, _at(field_path), "", path_width, value_width))
	return "\n".join(lines)


## The recorded paths that hold a value, dropping the containers on the way to them.
##
## Provenance records `parts` and `parts[barrel]` as well as `parts[barrel].size`, which the
## merge needs and a reader does not: the container rows print an entire serialized list on
## one line, and — worse — a list that was inherited, patched and appended to is attributed
## to whichever document first declared it. That attribution is the honest one for the list
## as an object, and it reads as a flat lie next to the printed contents. The per-member rows
## underneath it already say where each piece came from, so the containers come out.
func _leaf_paths() -> Array[String]:
	var all: Array[String] = []
	for key in provenance:
		all.append(String(key))
	all.sort()

	var container: Dictionary = {}
	for field_path in all:
		for step in [".", "["]:
			var cut := field_path.rfind(step)
			if cut > 0:
				container[field_path.substr(0, cut)] = true

	var out: Array[String] = []
	for field_path in all:
		if not container.has(field_path):
			out.append(field_path)
	return out


## One part, in the spec's own column layout. `defaults` lets the caller fold in fields the
## part never declared — the validator knows what `jitter` defaults to and this does not, and
## the whole value of the dump is that the defaulted fields appear next to the authored ones
## rather than being the ones you have to remember to go and check.
func dump_part(part_name: String, defaults: Dictionary = {}) -> String:
	var found: Dictionary = {}
	for part in parts():
		if typeof(part) == TYPE_DICTIONARY and String(part.get("name", "")) == part_name:
			found = part
			break
	if found.is_empty():
		return "%s has no part called `%s`. Present: %s" % [id, part_name,
			", ".join(part_names()) if not part_names().is_empty() else "none of them are named"]

	var fields: Array[String] = []
	for key in found:
		fields.append(String(key))
	for key in defaults:
		if not fields.has(String(key)):
			fields.append(String(key))
	fields.sort()

	var prefix := "parts[%s]" % part_name
	var lines: Array[String] = []
	for field in fields:
		var value: Variant = found[field] if found.has(field) else defaults[field]
		lines.append(line("%s.%s" % [prefix, field], value, field))
	return "\n".join(lines)


## `size      [3, 3, 30]   ← great_war:rifle_sniper`. Widths default to the spec's.
func line(field_path: String, value: Variant, label := "",
		path_width := PATH_COLUMN, value_width := VALUE_COLUMN) -> String:
	var shown := label if label != "" else field_path
	return "%s%s← %s" % [_pad(shown, path_width), _pad(value_text(value), value_width),
		source_of(field_path)]


## Pad to a column, and when the content is wider than the column give it a single space
## instead of letting the next column start inside the last word. `%-10s` does not do this,
## which is how `parts[barrel].material` and `steel` came to be printed as one word.
static func _pad(text: String, width: int) -> String:
	if text.length() >= width:
		return text + " "
	return text.rpad(width)


## Values as a person would write them, not as JSON stores them. Every number arrives from
## JSON as a float, so a size of three would otherwise print `3.0` and a whole table of
## integer modules would read as though somebody had gone off-grid.
static func value_text(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var f: float = value
			if is_equal_approx(f, roundf(f)):
				return str(int(roundf(f)))
			return String.num(f, 4).rstrip("0")
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value)
		TYPE_ARRAY:
			var items: Array[String] = []
			for item in value:
				items.append(value_text(item))
			return "[%s]" % ", ".join(items)
		TYPE_DICTIONARY:
			var pairs: Array[String] = []
			for key in value:
				pairs.append("%s: %s" % [key, value_text(value[key])])
			return "{%s}" % ", ".join(pairs)
	return str(value)


## Walk `data` by a provenance path so `dump()` can print the value next to its origin.
## Returns null for anything the path does not reach, which prints as `null` and is the
## truthful answer for a field that is recorded but no longer present.
func _at(field_path: String) -> Variant:
	var cursor: Variant = data
	for step in _steps(field_path):
		if typeof(cursor) == TYPE_DICTIONARY:
			if not cursor.has(step):
				return null
			cursor = cursor[step]
		elif typeof(cursor) == TYPE_ARRAY:
			var at := _member_index(cursor, step)
			if at < 0:
				return null
			cursor = cursor[at]
		else:
			return null
	return cursor


## `parts[barrel].size` -> ["parts", "barrel", "size"].
static func _steps(field_path: String) -> Array[String]:
	var out: Array[String] = []
	for chunk in field_path.split("."):
		var text := String(chunk)
		while text.contains("["):
			var open := text.find("[")
			if open > 0:
				out.append(text.substr(0, open))
			var close := text.find("]", open)
			if close < 0:
				break
			out.append(text.substr(open + 1, close - open - 1))
			text = text.substr(close + 1)
		if text != "":
			out.append(text)
	return out


static func _member_index(members: Array, step: String) -> int:
	if step.is_valid_int():
		var i := step.to_int()
		return i if i >= 0 and i < members.size() else -1
	for i in members.size():
		var m: Variant = members[i]
		if typeof(m) == TYPE_DICTIONARY and String(m.get("name", "")) == step:
			return i
	return -1
