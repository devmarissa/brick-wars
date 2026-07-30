class_name AssetResolver
extends RefCounted
## Carrying out every `extends` in the content set, once, at load time. FORMAT-SPEC §6, §10.
##
## The merge itself lives next door in `AssetMerge`. What lives here is everything that has
## to be true before a merge is allowed to happen: the chain is at most three deep, it does
## not come back round to where it started, every step outside the pack was declared in
## `pack.json`, and the asset at the top actually exists.
##
## Every one of those failures is scoped to a pack, never to the game. A workshop upload that
## extends an asset its author deleted last week gets disabled with a message naming both
## packs and the asset, and the other three hundred packs load exactly as they would have.
## That is the rule the whole content pipeline is built around and it is the reason this runs
## in passes: refusing a pack takes its assets out of circulation, which can invalidate an
## asset in a pack that extended one of them, so the whole set is resolved again until a pass
## goes by without anything being refused.

const MAX_DEPTH := 3

## A guard on chain walking, not a rule. The depth cap below is the rule; this only stops a
## pathological file from walking forever before the cap gets a chance to report it, and it
## is generous so the message can still name the whole chain.
const WALK_LIMIT := 32

var resolved: Dictionary = {}       ## String id -> ResolvedAsset
var errors: Array[String] = []
var refused: Dictionary = {}        ## StringName pack id -> Array[String] reasons


## Resolve everything the enabled packs publish, disabling packs as required. Returns false
## if anything at all was refused; for everything except core, that is not fatal.
func resolve_all(index: AssetIndex, packs: PackSet) -> bool:
	resolved.clear()
	errors.clear()
	refused.clear()

	# Problems found while merely reading the folder are pack problems too — two files
	# claiming one id is not a pack that should be allowed to half-load.
	for pack_id in ContentLoader.sorted_names(index.pack_errors.keys()):
		_refuse(packs, pack_id, index.pack_errors[pack_id])

	var passes := 0
	while true:
		passes += 1
		resolved.clear()
		var problems: Dictionary = {}
		for id in _live_ids(index, packs):
			_resolve(id, index, packs, problems)
		if problems.is_empty():
			break
		for pack_id in ContentLoader.sorted_names(problems.keys()):
			_refuse(packs, pack_id, problems[pack_id])
		if passes > packs.packs.size() + 1:
			# Unreachable: every pass but the last removes at least one pack, and there are
			# finitely many. If it ever fires, the bug is here and not in anybody's pack.
			errors.append("the asset resolver did not settle after %d passes — this is a core bug" % passes)
			break

	return errors.is_empty()


func get_asset(id: String) -> ResolvedAsset:
	return resolved.get(id)


func has(id: String) -> bool:
	return resolved.has(id)


func sorted_ids() -> Array[String]:
	var out: Array[String] = []
	for id in resolved:
		out.append(String(id))
	out.sort()
	return out


func _live_ids(index: AssetIndex, packs: PackSet) -> Array[String]:
	var out: Array[String] = []
	for id in index.ids:
		if packs.is_enabled(index.owner_of(id)):
			out.append(id)
	return out


func _resolve(id: String, index: AssetIndex, packs: PackSet, problems: Dictionary) -> void:
	if resolved.has(id):
		return
	var chain := _chain_for(id, index, packs, problems)
	if chain.is_empty():
		return

	var merge := AssetMerge.new()
	for i in chain.size():
		var step: String = chain[i]
		merge.apply(index.document(step), step, index.path_of(step),
			"" if i == 0 else chain[i - 1])
	if not merge.errors.is_empty():
		_blame(problems, index.owner_of(id), merge.errors)
		return

	var out := ResolvedAsset.new()
	out.id = id
	out.owner = index.owner_of(id)
	out.path = index.path_of(id)
	out.chain = chain
	out.data = merge.data
	out.data["id"] = id
	out.provenance = merge.provenance
	resolved[id] = out


## Walk `extends` upwards, checking each step, and hand back the whole chain root-first.
## Returns an empty array having recorded the problem against whichever pack owns the
## document that made the mistake — which is not always the pack that owns `id`, and blaming
## the wrong author is how a modder spends an evening reading a file that is correct.
func _chain_for(id: String, index: AssetIndex, packs: PackSet, problems: Dictionary) -> Array[String]:
	var chain: Array[String] = [id]
	var cur := id

	while chain.size() < WALK_LIMIT:
		var doc := index.document(cur)
		if not doc.has("extends"):
			break
		var owner := index.owner_of(cur)
		var where := index.path_of(cur)

		if typeof(doc["extends"]) != TYPE_STRING:
			_blame1(problems, owner, "%s: `extends` should be the id of the asset to extend, like `core:prop_crate`" % where)
			return []

		var base := index.resolve_reference(String(doc["extends"]), owner)

		if chain.has(base):
			_blame1(problems, owner, "%s: `%s` extends `%s`, which is already in its own chain — a cycle: %s. %s" % [
				where, cur, base, _ring(chain, base),
				"A cycle has no base to start the merge from, so no asset in it can load."])
			return []

		var base_owner := index.owner_of(base)
		if not index.has(base) or not packs.is_enabled(base_owner):
			# Both halves of this are the same event to the person reading it: the asset is
			# not there. Whether that is because it was renamed, deleted, or lives in a pack
			# that was itself refused, the next thing to do is go and look at the pack.
			_blame1(problems, owner, "%s: `%s` extends `%s`, and no enabled pack publishes it. %s" % [
				where, cur, base,
				"Either it was renamed or removed, or the pack that has it is not loaded."])
			return []

		if base_owner != owner and base_owner != &"core":
			# Core is the exception, and only core: `core_version` on the manifest already is
			# a declared dependency with a semver range, so asking for a second one in
			# `depends` would be asking every pack in existence to write the same line.
			var pack := packs.get_pack(owner)
			if pack == null or not pack.depends_on(base_owner):
				_blame1(problems, owner, "%s: `%s` extends `%s`, and `%s` does not declare a dependency on `%s`. %s %s" % [
					where, cur, base, owner, base_owner,
					"Reaching into an undeclared pack is refused, not a lucky success.",
					"Add { \"id\": \"%s\", \"version\": \">=%s\" } to `depends` in pack.json." % [
						base_owner, _installed_version(packs, base_owner)]])
				return []

		chain.push_front(base)
		cur = base

	if chain.size() > MAX_DEPTH:
		# The whole chain, not the last two links. Being told the cap was exceeded without
		# being shown what by is a message that costs more time than it saves.
		_blame1(problems, index.owner_of(id), "%s: the `extends` chain is %d deep and the cap is %d — %s. Chain: %s" % [
			index.path_of(id), chain.size(), MAX_DEPTH,
			"core → pack base → variant, and no further",
			" → ".join(chain)])
		return []

	return chain


## The ring as somebody walking it would meet it — in `extends` order, ending where it
## started. The chain is held root-first for merging, and printing that order for a cycle
## reads backwards to the person who wrote the `extends` lines.
static func _ring(chain: Array[String], base: String) -> String:
	var walk: Array[String] = []
	for i in range(chain.size() - 1, -1, -1):
		walk.append(chain[i])
	walk.append(base)
	return " → ".join(walk)


static func _installed_version(packs: PackSet, pack_id: StringName) -> String:
	var pack := packs.get_pack(pack_id)
	return pack.version if pack != null else "0.1"


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
	# The first line is the first actual problem, not a count of them. The boot report shows
	# one line per disabled pack, and "3 asset problem(s)" is a line that tells somebody their
	# pack is off and gives them nothing whatsoever to do about it.
	packs.refuse(pack_id, "\n      ".join(lines))


func _blame(problems: Dictionary, pack_id: StringName, lines: Array[String]) -> void:
	if not problems.has(pack_id):
		problems[pack_id] = [] as Array[String]
	problems[pack_id].append_array(lines)


func _blame1(problems: Dictionary, pack_id: StringName, line: String) -> void:
	_blame(problems, pack_id, [line] as Array[String])
