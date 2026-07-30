class_name FixtureWorld
extends RefCounted
## A fixture pack root, run through the whole content pipeline exactly as `content_module` runs
## the real one.
##
## This is plumbing three cases had a copy of. `case_leg.gd`, `case_driver.gd` and
## `case_locomotion_rules.gd` all need the same fifteen lines — palette, materials and slots off
## core data, then discover, scan, resolve, validate — and the copies were identical, which means
## they were one thing written three times and one of them would eventually drift.
##
## Loading through the real pipeline rather than hand-making a part table is not incidental. Half
## of what `Rig` and `Locomotion` read is defaults `PartRules` filled in, and half of what makes
## a fixture a fair test is that the validator was given its chance to refuse it first. A case
## that built a dictionary by hand would be testing a format nobody writes.
##
## The older rig cases — `case_rig.gd`, `case_validator.gd` — still carry their own copies. They
## are not touched here because they are at 300 and 299 lines and cannot absorb an edit; folding
## them in is a job for whoever next needs a line in either of them.


## Everything a rig case needs about a fixture root. Empty when core data would not load at all,
## which is a broken build rather than a failed test, and every caller checks for it.
static func load_root(root: String) -> Dictionary:
	var palette := Palette.new()
	var materials := MaterialSet.new()
	var slots := SlotSet.new()
	if not (palette.load_core() and materials.load_core(palette) and slots.load_core()):
		return {}

	var packs := PackSet.new()
	packs.discover([root] as Array[String])
	var index := AssetIndex.new()
	index.scan(packs)
	var resolver := AssetResolver.new()
	resolver.resolve_all(index, packs)

	var validator := AssetValidator.new()
	validator.validate_all(resolver, index, packs, materials, palette, slots)
	return { "packs": packs, "index": index, "resolver": resolver, "validator": validator,
		"materials": materials, "palette": palette }


static func asset(world: Dictionary, id: String) -> ResolvedAsset:
	return (world["resolver"] as AssetResolver).get_asset(id)


static func rig(world: Dictionary, id: String) -> Rig:
	var found := asset(world, id)
	if found == null:
		return null
	return AssetBuilder.new().build(found, world["materials"], world["palette"]).rig


## A driver set up against a built rig, or null when there is nothing to drive. Built fresh on
## every call on purpose: the phase and each leg's hang direction survive frames, so two sections
## sharing one driver would be two tests sharing a state neither of them wrote down.
static func driver(world: Dictionary, id: String) -> Locomotion:
	var found := asset(world, id)
	var built := rig(world, id)
	if found == null or built == null:
		return null
	var loco := Locomotion.new()
	if not loco.setup(built, Locomotion.declared(found)):
		return null
	return loco


## `TestGround` as a pure function, answering the same three fields a downward raycast would.
## `case_footing.gd` proves the two agree against a real trimesh collider, which is what lets
## every other rig case run with no physics world, no frame having ticked and no body in it.
static func test_ground() -> Callable:
	return func(at: Vector3) -> Dictionary:
		if not TestGround.contains(at.x, at.z):
			return {"hit": false, "y": at.y, "normal": Vector3.UP}
		return {
			"hit": true,
			"y": TestGround.height_at(at.x, at.z),
			"normal": TestGround.normal_at(at.x, at.z),
		}


## Ground that is flat and everywhere, for the cases where the terrain is not what is under test.
static func flat_ground() -> Callable:
	return func(_at: Vector3) -> Dictionary:
		return {"hit": true, "y": 0.0, "normal": Vector3.UP}


## Everything the validator said about one asset, as one string. Both of its lists are prefixed
## with the asset id by `AssetValidator._collect`, which is what makes this filter possible.
static func errors_about(world: Dictionary, id: String) -> String:
	return _matching((world["validator"] as AssetValidator).errors, id)


static func warnings_about(world: Dictionary, id: String) -> String:
	return _matching((world["validator"] as AssetValidator).warnings, id)


static func _matching(lines: Array[String], id: String) -> String:
	var said := ""
	for line in lines:
		if line.begins_with(id + " —"):
			said += line + "\n"
	return said if said != "" else "(nothing was said about %s)" % id
