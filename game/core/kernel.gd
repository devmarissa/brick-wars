class_name Kernel
extends Node
## Loads the core modules, works out what order they can safely start in, and starts them.
##
## This is deliberately the same problem C1 has to solve for packs — a set of named things
## that declare what they depend on, needing a deterministic load order, with cycles and
## missing dependencies caught and reported rather than crashed on. Solving it here first,
## against thirteen modules we control, means the `extends` resolver in C1 is a second
## implementation of a shape we already understand rather than a first attempt under
## pressure (`FORMAT-SPEC` §6, `BUILD-ORDER` C1).
##
## Determinism matters more than it looks. If load order can vary between runs, so can
## anything that depends on it, and the blast fixture's whole premise is that a run is
## reproducible. Ties are broken alphabetically for that reason — never by dictionary order,
## and never by `Array[StringName].sort()` either (see `_sort_names`).

signal booted

var modules: Dictionary = {}          ## StringName -> Module
var order: Array[StringName] = []     ## the resolved boot order
var boot_error := ""                  ## non-empty if boot() failed, with the reason

var _stubs: Array[StringName] = []


func boot(manifest: Dictionary = CoreManifest.MODULES) -> bool:
	boot_error = ""
	if not _instantiate(manifest):
		return false
	if not _resolve_order():
		return false

	for name in order:
		modules[name].module_init()
	for name in order:
		modules[name].module_ready()

	booted.emit()
	return true


func get_module(name: StringName) -> Module:
	return modules.get(name)


func has_module(name: StringName) -> bool:
	return modules.has(name)


## Names of modules that are still placeholders. The test runner prints this so a
## skeleton is never mistaken for a finished core.
func stub_names() -> Array[StringName]:
	return _stubs.duplicate()


func _instantiate(manifest: Dictionary) -> bool:
	for name in manifest:
		var path: String = manifest[name]
		if not ResourceLoader.exists(path):
			return _fail("module '%s' is in the manifest but %s does not exist" % [name, path])
		var script: GDScript = load(path)
		var instance: Object = script.new()

		# Everything below that rejects `instance` frees it first. A Node that is created
		# and then abandoned before `add_child` is never collected — Godot reports it at
		# exit as a leaked ObjectDB instance and nothing else. The misnamed-module test
		# found this on its first green run: a *failed* boot was leaking the module it
		# refused. Harmless in a test; not harmless in C1, where a workshop pack that fails
		# to load is a normal Tuesday and can happen hundreds of times in one session.
		if not (instance is Module):
			if instance is Node:
				instance.free()
			return _fail("module '%s' at %s is not a Module" % [name, path])
		var m: Module = instance
		if m.module_name() != name:
			var claimed := m.module_name()
			m.free()
			return _fail("module at %s calls itself '%s' but the manifest lists it as '%s'"
				% [path, claimed, name])
		m.kernel = self
		m.name = String(name)
		modules[name] = m
		if m.module_is_stub():
			_stubs.append(name)
		add_child(m)
	_sort_names(_stubs)
	return true


## Kahn's algorithm, with alphabetical tie-breaking so the order is identical every run.
func _resolve_order() -> bool:
	var incoming: Dictionary = {}     # name -> unmet dependency count
	var dependents: Dictionary = {}   # name -> [names that depend on it]

	for name in modules:
		incoming[name] = 0
		dependents[name] = []
	for name in modules:
		for dep in modules[name].module_depends():
			if not modules.has(dep):
				return _fail("module '%s' depends on '%s', which is not in the manifest"
					% [name, dep])
			incoming[name] += 1
			dependents[dep].append(name)

	var ready: Array[StringName] = []
	for name in modules:
		if incoming[name] == 0:
			ready.append(name)
	_sort_names(ready)

	order.clear()
	while not ready.is_empty():
		var name: StringName = ready.pop_front()
		order.append(name)
		var freed: Array[StringName] = []
		for d in dependents[name]:
			incoming[d] -= 1
			if incoming[d] == 0:
				freed.append(d)
		if not freed.is_empty():
			ready.append_array(freed)
			_sort_names(ready)

	if order.size() != modules.size():
		var stuck: Array[StringName] = []
		for name in modules:
			if not order.has(name):
				stuck.append(name)
		_sort_names(stuck)
		return _fail("dependency cycle between: %s — every module in that set is waiting "
			% ", ".join(stuck) + "on another one in it, so none of them can start first")
	return true


## Sort module names by their text.
##
## `Array[StringName].sort()` does NOT do this. StringName's `<` compares the internal
## pointer rather than the characters, because that is fast and StringNames are usually
## only compared for equality. The very first boot of this kernel printed its ten
## independent modules as "vfx, audio, net, ai, vehicle, verbs, combat, rig, earth,
## physics" — allocation order, wearing a sort's clothes. That is precisely the
## non-determinism this resolver exists to eliminate, and it would have survived into C1's
## `extends` resolver unnoticed, because the order is stable within a run and only shifts
## when something unrelated changes what gets loaded first.
static func _sort_names(names: Array[StringName]) -> void:
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


func _fail(reason: String) -> bool:
	boot_error = reason
	push_error("kernel: " + reason)
	return false
