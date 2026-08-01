class_name CLI
extends RefCounted
## The command line, parsed once and shared. FORMAT-SPEC §6's `--resolve` lives here.
##
## Everything here is a *diagnostic* flag, and that is a deliberate limit. The moment the
## command line can change how the game plays, two people running the same build are running
## different games and neither of them knows it. These three only ask the game questions:
## which packs did you look at, what did this asset resolve to, where did each field of it come
## from, and what did the rig system make of it.
##
##     godot --headless --path game -- --resolve core:crate_ammo
##     godot --headless --path game -- --resolve core:barrel --part hoop
##     godot --headless --path game -- --rig core:soldier
##     godot --headless --path game -- --pack-root res://tests/fixtures/broken
##
## `--pack-root` is the one that earns its keep beyond authoring. A pack that fails has to
## disable itself, say exactly why, and take nothing else down with it — and the only way to
## be sure of that is to point the real game at a deliberately broken pack and watch the rest
## of the world load anyway. That is a C1 done-condition, and without this flag it can only
## be demonstrated by editing shipped content, which is a test nobody runs twice.
##
## Parsed from the arguments after `--`, because everything before it belongs to Godot.

## Flags that take exactly one value. Anything else is a usage error rather than a silent
## no-op, since a mistyped diagnostic that prints nothing looks identical to a clean result.
const TAKES_VALUE := ["--resolve", "--part", "--rig", "--pack-root", "--shot", "--settle"]

## Flags that are on or off rather than followed by a value. Kept as its own list so the parser can
## tell "this flag needs a value and did not get one" from "this flag never wanted one", which are
## different mistakes and deserve different messages.
const BARE_FLAGS := ["--play"]

static var _shared: CLI = null

var resolve_id := ""                    ## `--resolve <pack:asset>`
var part_name := ""                     ## `--part <name>`, narrows the dump to one part
var rig_id := ""                        ## `--rig <pack:asset>`
var pack_roots: Array[String] = []      ## `--pack-root <path>`, repeatable
var errors: Array[String] = []          ## problems with the arguments themselves

## `tools/screenshot.sh`, which boots the real `main.gd` inside a scene of its own. Its two
## arguments live here rather than in that scene because a process has one command line, and
## two parsers reading it disagree the moment either grows a flag. They were positional until
## the parser above existed, which meant a fumbled invocation quietly wrote a picture to a
## file named `--rendering-driver`.
var shot_path := ""                     ## `--shot <path>`, relative to `game/`
var settle_seconds := 0.0               ## `--settle <seconds>`, 0 meaning the tool's default

## `--play`. C4b: spawn a controllable soldier even while capturing a screenshot. Normally a `--shot`
## run is deliberately *not* playable, so milestone captures keep the fixed framing they have been
## compared in since C1 — this is how you photograph the game as somebody actually sees it.
var play := false

## Whether the last `resolve_report()` found what it was asked for. A dump that reports "no
## such asset" is still a useful answer, but it is not a successful one, and a script driving
## this needs the exit code to say so.
var resolve_ok := false

## Same for `--rig`. Separate flags rather than one, because a script that asks both questions
## needs to know which of the two it got a useful answer to.
var rig_ok := false


## The real command line, parsed on first use and remembered. Both `main.gd` and the content
## module ask for this, and parsing twice would let them disagree about their own process.
static func shared() -> CLI:
	if _shared == null:
		_shared = CLI.new()
		_shared.parse(OS.get_cmdline_user_args())
	return _shared


## Replace what `shared()` hands out. For tests, which have their own command line and no
## interest in it.
static func use(cli: CLI) -> void:
	_shared = cli


func parse(args: PackedStringArray) -> void:
	resolve_id = ""
	part_name = ""
	rig_id = ""
	pack_roots.clear()
	errors.clear()
	shot_path = ""
	settle_seconds = 0.0
	play = false

	var i := 0
	while i < args.size():
		var flag := String(args[i])
		if not flag.begins_with("--"):
			errors.append("`%s` is not a flag and nothing was expecting a bare value there" % flag)
			i += 1
			continue
		if BARE_FLAGS.has(flag):
			if flag == "--play":
				play = true
			i += 1
			continue
		if not TAKES_VALUE.has(flag):
			errors.append("`%s` is not a flag this game knows. %s" % [flag, usage()])
			# Swallow whatever followed it, if that was a value rather than the next flag.
			# Otherwise one typo produces two complaints, and the second one — "`core:crate`
			# is not a flag" — sends the reader looking at the part they got right.
			i += 1 if i + 1 >= args.size() or String(args[i + 1]).begins_with("--") else 2
			continue
		if i + 1 >= args.size():
			errors.append("`%s` needs a value after it" % flag)
			i += 1
			continue

		var value := String(args[i + 1])
		match flag:
			"--resolve":
				resolve_id = value
			"--part":
				part_name = value
			"--rig":
				rig_id = value
			"--pack-root":
				pack_roots.append(value)
			"--shot":
				shot_path = value
			"--settle":
				if not value.is_valid_float():
					errors.append("`--settle` wants a number of seconds, not `%s`" % value)
				settle_seconds = maxf(0.0, value.to_float())
		i += 2

	if part_name != "" and resolve_id == "":
		errors.append("`--part` narrows a `--resolve` dump, so it needs one to narrow")


func wants_resolve() -> bool:
	return resolve_id != ""


func wants_rig() -> bool:
	return rig_id != ""


static func usage() -> String:
	return ("Known: --resolve <pack:asset>, --part <name>, --rig <pack:asset>, "
		+ "--pack-root <path>, --shot <path>, --settle <seconds>, --play.")


## The dump the flag asks for, or a refusal that says which of the two things went wrong —
## the pack is not loaded, or the pack is loaded and has no such asset. Those have different
## fixes, and an author who is told only "not found" will go looking in the wrong file.
func resolve_report(content: Module) -> String:
	resolve_ok = false
	var asset: ResolvedAsset = content.resolver.get_asset(resolve_id)
	if asset == null:
		return _no_such_asset(content)
	resolve_ok = true
	if part_name != "":
		# No defaults dict: the validator writes FORMAT-SPEC §5's defaults into the part in
		# place, so they are already in `data` and provenance reports them as `core (default)`
		# on its own. A second table here would be a second answer to the same question.
		return "%s   (%s)\n\n%s" % [asset.id, asset.path, asset.dump_part(part_name)]
	return asset.dump()


func _no_such_asset(content: Module) -> String:
	var pack := resolve_id.get_slice(":", 0)
	if resolve_id.contains(":") and content.installed.disabled.has(pack):
		return "no `%s` — pack `%s` is disabled, so none of its assets exist: %s" % [
			resolve_id, pack, content.installed.disabled[pack]]
	if resolve_id.contains(":") and not content.installed.packs.has(StringName(pack)):
		return "no `%s` — there is no pack called `%s` in %s" % [
			resolve_id, pack, ", ".join(content.pack_roots())]
	return "no `%s` — that pack is loaded and has no asset by that name. It has: %s" % [
		resolve_id, ", ".join(content.index.ids_in(StringName(pack)))]


## What the rig system made of an asset — `RigReport`, which owns the formatting. Built here
## rather than in the report because building needs the material set and the palette, and the
## content module is what has them.
func rig_report(content: Module) -> String:
	rig_ok = false
	var asset: ResolvedAsset = content.resolver.get_asset(rig_id)
	if asset == null:
		var was := resolve_id
		resolve_id = rig_id
		var said := _no_such_asset(content)
		resolve_id = was
		return said
	rig_ok = true
	return RigReport.of(asset, AssetBuilder.new().build(asset, content.materials, content.palette))
