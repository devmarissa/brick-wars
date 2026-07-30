class_name SourceLines
extends RefCounted
## Finding the line a field was written on, so a refusal can point at it. FORMAT-SPEC §10.
##
## "A pack fails to load, with a message naming the file, the line, and the rule." The file
## and the rule fall out of the data; the line does not, because Godot's JSON parser hands
## back a Dictionary and throws the document's shape away. So this reads the text back and
## looks for the key.
##
## It is a search, not a parser, and it is allowed to fail: a part written on one line
## finds its part and not its field, and a field written twice finds the first. Both cases
## drop the line number and print the file alone, which is what the message would have said
## anyway. What it must never do is point at the wrong line — being sent to line 61 when the
## mistake is on line 14 is worse than not being sent anywhere.
##
## The file it points at is the file that *wrote* the value, which after an `extends` chain
## is frequently not the file being validated. A part inherited from a base three packs away
## with a bad material has its mistake in the base, and telling somebody to fix their own
## variant would send them to a file with nothing wrong in it.

## How far past a part's `name` to keep looking for one of its fields. Generous — the part
## objects in FORMAT-SPEC §5 run to eleven fields and a hand-authored one may be spaced out
## — but bounded, so a part whose field is genuinely absent does not match the next part's.
const FIELD_REACH := 24

var _lines: Dictionary = {}      ## path -> PackedStringArray


## `path:14` when the line can be found, `path` when it cannot.
func at(path: String, part_name := "", field := "") -> String:
	var line := line_of(path, part_name, field)
	return path if line <= 0 else "%s:%d" % [path, line]


## The line `field` was written on inside the part called `part_name`, 1-based. Either may
## be empty: with no part, the first occurrence of the field anywhere; with no field, the
## line the part is named on.
func line_of(path: String, part_name := "", field := "") -> int:
	var lines := _text(path)
	if lines.is_empty():
		return 0

	var from := 0
	var until := lines.size()
	if part_name != "":
		var at_part := _find(lines, _key_value("name", part_name), 0, lines.size())
		if at_part < 0:
			return 0
		if field == "":
			return at_part + 1
		from = at_part
		until = mini(lines.size(), at_part + FIELD_REACH)

	if field == "":
		return 0
	var found := _find(lines, _key(field), from, until)
	return 0 if found < 0 else found + 1


func _text(path: String) -> PackedStringArray:
	if _lines.has(path):
		return _lines[path]
	var out := PackedStringArray()
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			# Stored with the whitespace taken out, one entry per line so the numbers still
			# line up. Comparing whitespace-free copies is the cheapest way to be indifferent
			# to the formatting an author chose without writing a tokeniser for a job that
			# does not need one.
			for line in file.get_as_text().split("\n"):
				out.append(String(line).replace(" ", "").replace("\t", ""))
			file.close()
	_lines[path] = out
	return out


static func _find(lines: PackedStringArray, needle: String, from: int, until: int) -> int:
	for i in range(from, until):
		if lines[i].contains(needle):
			return i
	return -1


## `"material"` — with the quotes and the colon, so a part named `material_test` does not
## match and neither does the word appearing inside a comment.
static func _key(field: String) -> String:
	return "\"%s\":" % field


## `"name": "barrel"`, tolerating the space after the colon being absent. Matching on the
## pair rather than the value alone keeps a part called `barrel` from being found by the
## `parent: "barrel"` of the part above it.
static func _key_value(field: String, value: String) -> String:
	return "\"%s\":\"%s\"" % [field, value]
