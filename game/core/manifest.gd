class_name CoreManifest
extends RefCounted
## The list of core modules, in no particular order — the kernel sorts them.
##
## Explicit rather than discovered by scanning the folder, for one reason: adding a module
## to the game should be a decision that shows up in a diff, not a side effect of creating
## a file. `tools/check.sh` enforces the other half of that bargain — every `*_module.gd`
## under `core/` must appear here, so a file can't sit in the tree quietly not loading.
##
## What belongs in each of these is settled by CORE-SPEC §2, not here.

const MODULES := {
	# --- live in C0 ---
	&"physics": "res://core/physics/physics_module.gd",
	&"mode":    "res://core/mode/mode_module.gd",
	&"ui":      "res://core/ui/ui_module.gd",

	# --- placeholders, each waiting on its milestone ---
	&"content": "res://core/content/content_module.gd",
	&"earth":   "res://core/earth/earth_module.gd",
	&"rig":     "res://core/rig/rig_module.gd",
	&"combat":  "res://core/combat/combat_module.gd",
	&"verbs":   "res://core/verbs/verbs_module.gd",
	&"vehicle": "res://core/vehicle/vehicle_module.gd",
	&"ai":      "res://core/ai/ai_module.gd",
	&"net":     "res://core/net/net_module.gd",
	&"audio":   "res://core/audio/audio_module.gd",
	&"vfx":     "res://core/vfx/vfx_module.gd",
}
