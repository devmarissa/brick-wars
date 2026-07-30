class_name SemVer
extends RefCounted
## Versions and version ranges, for `pack.json`'s `core_version` and `depends`.
##
## This exists so that a base pack updating is a refusal rather than a silent break. A
## cavalry pack that extends `great_war` at 0.3 and gets loaded against 0.6 is not a pack
## that works slightly worse; it is a pack whose parent asset ids may not exist any more.
## The range is the author's statement of what they tested against, and honouring it is
## the difference between a workshop that degrades gracefully and one where every base-pack
## update produces a wave of broken uploads nobody can diagnose.
##
## Deliberately a small subset of semver: comparators (`>=`, `>`, `<`, `<=`, `=`) joined by
## spaces, and `*` for anything. `>=0.3 <0.5` is the shape FORMAT-SPEC §9 uses and the shape
## this understands. Everything outside the subset — caret, tilde, `||`, prerelease tags —
## is refused by name with the supported forms listed, because a range that gets silently
## misparsed is worse than one that gets rejected: it fails later, somewhere else, as a
## missing asset.

const OPERATORS := [">=", "<=", ">", "<", "="]
const ANY := "*"


## Parse `1.2.3`, `1.2` or `1` into a comparable triple. Missing components are zero, so
## `0.4` is `0.4.0` — which is what a pack author writing `>=0.4` means.
##
## Returns `Vector3i(-1, -1, -1)` having appended to `errors`. A caller that wants to test
## without reporting passes an array it then throws away.
static func parse(text: String, where: String, errors: Array[String]) -> Vector3i:
	var bad := Vector3i(-1, -1, -1)
	var s := text.strip_edges()

	if s.is_empty():
		errors.append("%s: empty version" % where)
		return bad

	if s.contains("-") or s.contains("+"):
		errors.append("%s: `%s` has a prerelease or build tag. %s" % [where, s,
			"Versions here are plain numbers — 1.2.3, 1.2, or 1."])
		return bad

	var parts := s.split(".", false)
	if parts.size() > 3:
		errors.append("%s: `%s` has %d parts — a version is major.minor.patch" % [
			where, s, parts.size()])
		return bad

	var out := Vector3i.ZERO
	for i in parts.size():
		if not parts[i].is_valid_int():
			errors.append("%s: `%s` — `%s` is not a number" % [where, s, parts[i]])
			return bad
		var n := int(parts[i])
		if n < 0:
			errors.append("%s: `%s` has a negative component" % [where, s])
			return bad
		out[i] = n
	return out


## -1, 0 or 1. Compares major, then minor, then patch, which is the whole of the ordering.
static func compare(a: Vector3i, b: Vector3i) -> int:
	for i in 3:
		if a[i] != b[i]:
			return -1 if a[i] < b[i] else 1
	return 0


## Does `version` fall inside `range_text`? Both are validated; a problem with either is
## reported and the answer is false, because "we could not tell" and "no" have to be the
## same answer when the alternative is loading a pack against a core it never saw.
static func satisfies(version: String, range_text: String, where: String,
		errors: Array[String]) -> bool:
	var v := parse(version, where, errors)
	if v == Vector3i(-1, -1, -1):
		return false
	return satisfies_parsed(v, range_text, where, errors)


static func satisfies_parsed(v: Vector3i, range_text: String, where: String,
		errors: Array[String]) -> bool:
	var clauses := _clauses(range_text, where, errors)
	if clauses.is_empty():
		return false

	for clause in clauses:
		if clause["op"] == ANY:
			continue
		var cmp := compare(v, clause["version"])
		match clause["op"]:
			">=": if cmp < 0: return false
			">":  if cmp <= 0: return false
			"<=": if cmp > 0: return false
			"<":  if cmp >= 0: return false
			"=":  if cmp != 0: return false
	return true


## Check a range parses, without testing anything against it. Manifest validation wants to
## report a malformed range as a malformed range, at the point of reading the manifest,
## rather than later as a dependency that mysteriously does not resolve.
static func is_valid_range(range_text: String, where: String, errors: Array[String]) -> bool:
	return not _clauses(range_text, where, errors).is_empty()


## Split `">=0.3 <0.5"` into comparators. Empty on any failure, having said why.
static func _clauses(range_text: String, where: String, errors: Array[String]) -> Array:
	var s := range_text.strip_edges()
	if s.is_empty():
		errors.append("%s: empty version range. %s" % [where, _supported()])
		return []
	if s == ANY:
		return [{ "op": ANY, "version": Vector3i.ZERO }]

	if s.contains("||") or s.contains("^") or s.contains("~"):
		errors.append("%s: `%s` uses a range operator this loader does not have. %s" % [
			where, s, _supported()])
		return []

	var out: Array = []
	for token in s.split(" ", false):
		var op := ""
		for candidate in OPERATORS:
			if token.begins_with(candidate):
				op = candidate
				break
		var number := token
		if op == "":
			# A bare `0.4` in a range field almost always means `=0.4`, but "almost always"
			# is not good enough for the field that decides whether a pack loads.
			errors.append("%s: `%s` has no comparator. %s" % [where, token, _supported()])
			return []
		number = token.substr(op.length())

		var v := parse(number, where, errors)
		if v == Vector3i(-1, -1, -1):
			return []
		out.append({ "op": op, "version": v })

	if out.is_empty():
		errors.append("%s: `%s` is not a version range. %s" % [where, s, _supported()])
	return out


static func _supported() -> String:
	return "Supported: `*`, or comparators (>=, >, <=, <, =) joined by spaces, e.g. `>=0.3 <0.5`."
