class_name PackSet
extends RefCounted
## Every installed pack, in the order they can safely load. FORMAT-SPEC §9, §10.
##
## The kernel next door solves the same problem for core modules and is allowed to give up:
## a core module that cannot start means the game cannot start. This one is not allowed to
## give up. A broken workshop upload is a normal Tuesday, and the rule is that it gets
## disabled, reported, and stepped over — it never half-loads and it never takes the other
## packs with it (FORMAT-SPEC §10).
##
## What "disabled" cascades to is the interesting part. If `great_war` is refused, then
## `mcheves_cavalry`, which extends its tanks, cannot load either — but the reason it gets
## told is `great_war`'s reason, not "missing dependency", because the author of the
## cavalry pack did nothing wrong and pointing them at their own manifest wastes their
## evening.
##
## Order is deterministic: dependencies first, ties broken alphabetically, identical on
## every machine and every run. Anything else and a pack that happens to load earlier on
## one server wins an id collision that it loses on another.

const MANIFEST := Pack.MANIFEST

var packs: Dictionary = {}            ## StringName -> Pack, every pack that parsed
var order: Array[StringName] = []     ## enabled packs, in load order
var disabled: Dictionary = {}         ## StringName -> reason
var errors: Array[String] = []        ## problems with the set, not with one pack
var warnings: Array[String] = []


## Scan `roots` for pack folders, read every manifest, and resolve the load order. Returns
## false if anything at all was refused — the caller decides whether that is fatal, and for
## everything except core it is not.
func discover(roots: Array[String]) -> bool:
	packs.clear()
	order.clear()
	disabled.clear()
	errors.clear()
	warnings.clear()

	for root in roots:
		for folder in _pack_folders(root):
			_read_pack(folder)

	_check_core_version()
	_check_dependencies()
	_cascade()
	_resolve_order()

	return disabled.is_empty() and errors.is_empty()


func get_pack(id: StringName) -> Pack:
	return packs.get(id)


func is_enabled(id: StringName) -> bool:
	return packs.has(id) and not disabled.has(id)


func enabled_packs() -> Array[Pack]:
	var out: Array[Pack] = []
	for id in order:
		out.append(packs[id])
	return out


## One line per pack for the boot log, disabled ones included and marked. A pack that
## quietly is not there is the single most confusing thing that can happen to someone
## running a modded server.
func report() -> String:
	var lines: Array[String] = []
	for id in order:
		lines.append("  on   %s" % packs[id].described())
	for id in ContentLoader.sorted_names(disabled.keys()):
		lines.append("  OFF  %s — %s" % [id, disabled[id].get_slice("\n", 0)])
	if lines.is_empty():
		return "no packs installed"
	return "\n".join(lines)


## Subfolders of `root` that contain a `pack.json`, alphabetically. A folder without one is
## not a broken pack, it is not a pack — screenshots, notes and `.DS_Store` live in pack
## directories too, and complaining about them trains people to ignore the log.
func _pack_folders(root: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	var names := DirAccess.get_directories_at(root)
	names.sort()
	for name in names:
		var folder := "%s/%s" % [root.trim_suffix("/"), name]
		if FileAccess.file_exists("%s/%s" % [folder, MANIFEST]):
			out.append(folder)
	return out


func _read_pack(folder: String) -> void:
	var pack := Pack.new()
	pack.load_from(folder)
	warnings.append_array(pack.warnings)

	if pack.id == &"":
		# No usable id means it cannot even be listed by name, so it is reported against
		# its folder and dropped. Everything else gets to exist and be disabled.
		errors.append("%s: no usable pack id, so it cannot be loaded:\n    %s" % [
			folder, "\n    ".join(pack.errors)])
		return

	if packs.has(pack.id):
		var first: Pack = packs[pack.id]
		_disable(pack.id, "two packs claim the id `%s` (%s and %s) — %s" % [
			pack.id, first.root, pack.root,
			"ids are claimed, not chosen, so neither loads until one is renamed"])
		return

	packs[pack.id] = pack
	if not pack.is_ok():
		_disable(pack.id, "manifest problems:\n      %s" % "\n      ".join(pack.errors))


func _check_core_version() -> void:
	for id in packs:
		if disabled.has(id):
			continue
		var pack: Pack = packs[id]
		var probe: Array[String] = []
		if not SemVer.satisfies(CoreVersion.VERSION, pack.core_version,
				"%s: `core_version`" % pack.manifest_path(), probe):
			if probe.is_empty():
				_disable(id, "needs core %s and this is %s" % [
					pack.core_version, CoreVersion.described()])
			else:
				_disable(id, "unreadable `core_version`: %s" % "; ".join(probe))


func _check_dependencies() -> void:
	for id in packs:
		if disabled.has(id):
			continue
		var pack: Pack = packs[id]
		for dep in pack.depends:
			var dep_id: StringName = dep["id"]
			if not packs.has(dep_id):
				_disable(id, "requires `%s` %s, which is not installed" % [dep_id, dep["range"]])
				break
			var other: Pack = packs[dep_id]
			var probe: Array[String] = []
			if not SemVer.satisfies(other.version, dep["range"],
					"%s: dependency on `%s`" % [pack.manifest_path(), dep_id], probe):
				if probe.is_empty():
					# The refusal that earns the whole semver subset: a base pack moved and
					# this one has not been tested against where it moved to.
					_disable(id, "requires `%s` %s, and the installed one is %s" % [
						dep_id, dep["range"], other.version])
				else:
					_disable(id, "unreadable dependency range: %s" % "; ".join(probe))
				break


## A pack whose dependency is off is off too, and it inherits the reason. Repeated to a
## fixpoint because the chain can be three deep and disabling the middle of it does not
## help the end of it until the next pass.
func _cascade() -> void:
	var changed := true
	while changed:
		changed = false
		for id in ContentLoader.sorted_names(packs.keys()):
			if disabled.has(id):
				continue
			for dep in (packs[id] as Pack).depends:
				var dep_id: StringName = dep["id"]
				if disabled.has(dep_id):
					_disable(id, "`%s` is disabled, so this cannot load either (%s)" % [
						dep_id, disabled[dep_id].get_slice("\n", 0)])
					changed = true
					break


## Kahn's algorithm over the enabled packs, alphabetical tie-break — the same shape as the
## kernel's module resolver, for the same reason: the order has to be identical on every
## machine, every run.
func _resolve_order() -> void:
	var live: Array[StringName] = []
	for id in packs:
		if not disabled.has(id):
			live.append(id)
	live = ContentLoader.sorted_names(live)

	var incoming: Dictionary = {}
	var dependents: Dictionary = {}
	for id in live:
		incoming[id] = 0
		dependents[id] = []
	for id in live:
		for dep in (packs[id] as Pack).depends:
			var dep_id: StringName = dep["id"]
			if not incoming.has(dep_id):
				continue    # already disabled and reported; nothing to wait on
			incoming[id] += 1
			dependents[dep_id].append(id)

	var ready: Array[StringName] = []
	for id in live:
		if incoming[id] == 0:
			ready.append(id)
	ready = ContentLoader.sorted_names(ready)

	order.clear()
	while not ready.is_empty():
		var id: StringName = ready.pop_front()
		order.append(id)
		var freed: Array[StringName] = []
		for d in dependents[id]:
			incoming[d] -= 1
			if incoming[d] == 0:
				freed.append(d)
		if not freed.is_empty():
			ready.append_array(freed)
			ready = ContentLoader.sorted_names(ready)

	if order.size() == live.size():
		return

	# Whatever is left is waiting on something else that is also left. FORMAT-SPEC §10 asks
	# for a message that names both ends, so it names all of them: with three packs in a
	# ring, naming two would send someone looking for a two-pack cycle that is not there.
	var stuck: Array[StringName] = []
	for id in live:
		if not order.has(id):
			stuck.append(id)
	stuck = ContentLoader.sorted_names(stuck)
	for id in stuck:
		_disable(id, "dependency cycle between %s — each one waits on another in that set" % [
			", ".join(PackedStringArray(stuck))])


func _disable(id: StringName, reason: String) -> void:
	if disabled.has(id):
		return
	disabled[id] = reason
