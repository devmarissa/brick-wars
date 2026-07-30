class_name ContentLoader
extends RefCounted
## Reading JSON, and failing at it in a way a modder can act on.
##
## Every file the content pipeline reads comes through here — core's palette and material
## set, every `pack.json`, every part table. There is one reason for that: the error
## messages. A pack author who gets `Parse error` and nothing else has been told their pack
## is broken and given no way to find out where, and the next thing they do is give up. So
## a failure here always says which file, which line, and what was actually wrong.
##
## `errors` is passed in rather than owned, because the validator (FORMAT-SPEC §10) needs
## every problem in a pack at once. Finding out about eleven mistakes one run at a time is
## how a format gets a reputation.
##
## Keys beginning with `_` are comments. JSON has none, and the alternative was either a
## separate document that drifts out of date or data files with no explanation in them at
## all. Both are worse. They are stripped before anything sees the data, so `_earth` in
## the middle of the material list is a section heading and not a material called `_earth`.

const COMMENT_PREFIX := "_"


## Read and parse a JSON file. Returns the parsed value, or `null` having appended a
## human-readable explanation to `errors`.
static func read_json(path: String, errors: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s does not exist" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("%s exists but could not be opened (%s)" % [
			path, error_string(FileAccess.get_open_error())])
		return null

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		# `get_error_line()` is zero-based. Editors are not, so it is corrected here once
		# rather than in the head of every modder who tries to go and look at the line.
		var line_no := json.get_error_line() + 1
		errors.append("%s:%d — %s" % [path, line_no, json.get_error_message()])
		var line := _line_at(text, line_no)
		if line != "":
			errors.append("    %s" % line)
		return null

	return strip_comments(json.data)


## Read a JSON file that must contain an object. The commonest single mistake in a hand-
## written pack is a stray `[` at the top, and "expected an object, found an array" is a
## more useful thing to be told than a type error forty lines later.
static func read_object(path: String, errors: Array[String]) -> Dictionary:
	var data: Variant = read_json(path, errors)
	if data == null:
		return {}
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("%s is %s at the top level — it has to be an object, `{ ... }`" % [
			path, _type_name(data)])
		return {}
	return data


## Strip `_`-prefixed documentation keys, recursively.
static func strip_comments(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				if typeof(key) == TYPE_STRING and key.begins_with(COMMENT_PREFIX):
					continue
				out[key] = strip_comments(value[key])
			return out
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(strip_comments(item))
			return arr
	return value


## Fetch a required field, complaining usefully rather than returning a silent default.
## `where` is whatever the reader should go and look at — a file path, or a path plus the
## part id, because "material is missing" is not actionable and "crate.json, part 3:
## material is missing" is.
static func require(obj: Dictionary, key: String, where: String,
		expected: int, errors: Array[String]) -> Variant:
	if not obj.has(key):
		errors.append("%s: `%s` is required and is not there" % [where, key])
		return null
	var value: Variant = obj[key]
	if not _type_matches(value, expected):
		errors.append("%s: `%s` should be %s, found %s" % [
			where, key, _expected_name(expected), _type_name(value)])
		return null
	return value


## Numbers arrive from JSON as float even when written `1900`, so an int field has to
## accept both and an accidental `"1900"` has to be caught rather than coerced. Silent
## string-to-number coercion is how a typo becomes a physics value.
static func _type_matches(value: Variant, expected: int) -> bool:
	if expected == TYPE_FLOAT:
		return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
	return typeof(value) == expected


static func _expected_name(expected: int) -> String:
	match expected:
		TYPE_FLOAT: return "a number"
		TYPE_STRING: return "a string"
		TYPE_BOOL: return "true or false"
		TYPE_ARRAY: return "a list"
		TYPE_DICTIONARY: return "an object"
	return "type %d" % expected


static func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "true/false"
		TYPE_INT, TYPE_FLOAT: return "a number"
		TYPE_STRING, TYPE_STRING_NAME: return "a string"
		TYPE_ARRAY: return "a list"
		TYPE_DICTIONARY: return "an object"
	return "something unexpected"


## Godot's parser reports the line but not its contents. Showing the offending line is the
## difference between "go and count to 41" and "oh, the trailing comma".
static func _line_at(text: String, line_no: int) -> String:
	if line_no < 1:
		return ""
	var lines := text.split("\n")
	if line_no > lines.size():
		return ""
	return lines[line_no - 1].strip_edges()


## Sort names for display and for anything reproducible.
##
## `Array[StringName].sort()` does not do this. StringName's `<` compares the interned
## pointer, so it sorts by allocation order wearing a sort's clothes — the kernel's module
## list printed in the wrong order on the project's first ever boot for exactly this
## reason. Anywhere a stable order matters, it goes through here.
static func sorted_names(names: Array) -> Array[StringName]:
	var strings: Array[String] = []
	for n in names:
		strings.append(String(n))
	strings.sort()
	var out: Array[StringName] = []
	for s in strings:
		out.append(StringName(s))
	return out
