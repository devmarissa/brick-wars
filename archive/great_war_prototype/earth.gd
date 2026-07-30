class_name EarthField
extends Node3D
## M-EARTH — the diggable battlefield keystone.
## No-man's-land is a heightfield grid of static earth columns: zero physics cost until
## disturbed, exact grid addressing, and every change (dig / place / carve) is a tiny
## grid event — the same representation the 100v100 netcode will ship over the wire.
##
## dig(i)   -> lower a column one scoop (the dirt becomes spoil the player carries)
## place(i) -> raise a column one scoop (build a parapet out of yesterday's hole)
## carve()  -> artillery: crater a radius of columns at once

const CELL := 2.5        # column footprint (m)
const CELL_H := 0.8      # one shovel scoop (m)
const LIP := 0.06        # field sits a hair above the surrounding plain (churned soil)
const MAX_UP := 3        # scoops you can stack above grade
const EARTH_COLORS := [0x5e5240, 0x6a5c47, 0x74604a, 0x66594a]

var main                 # Main node (dynamic ref: unit_box / mat live there)
var origin := Vector3.ZERO
var nx := 0
var nz := 0
var depth_cells := 6     # diggable depth below grade (6 x 0.8 = 4.8 m)
var heights := PackedInt32Array()
var cols := {}           # column index -> StaticBody3D (only existing columns have nodes)

func setup(m, aorigin: Vector3, anx: int, anz: int) -> void:
	main = m
	origin = aorigin
	nx = anx
	nz = anz
	heights.resize(nx * nz)
	for i in nx * nz:
		heights[i] = depth_cells
		_rebuild(i)

func col_at(pos: Vector3) -> int:
	var ix := int(floor((pos.x - origin.x) / CELL))
	var iz := int(floor((pos.z - origin.z) / CELL))
	if ix < 0 or ix >= nx or iz < 0 or iz >= nz:
		return -1
	return ix * nz + iz

func top_y(i: int) -> float:
	return -depth_cells * CELL_H + heights[i] * CELL_H + LIP

func dig(i: int) -> bool:
	if i < 0 or heights[i] <= 0:
		return false
	heights[i] = heights[i] - 1
	_rebuild(i)
	return true

func place(i: int) -> bool:
	if i < 0 or heights[i] >= depth_cells + MAX_UP:
		return false
	heights[i] = heights[i] + 1
	_rebuild(i)
	return true

## artillery / heavy blasts: crater every column in radius, deeper toward the center
func carve(point: Vector3, radius: float, power: float) -> int:
	var carved := 0
	var ix0 := maxi(int(floor((point.x - radius - origin.x) / CELL)), 0)
	var ix1 := mini(int(floor((point.x + radius - origin.x) / CELL)), nx - 1)
	var iz0 := maxi(int(floor((point.z - radius - origin.z) / CELL)), 0)
	var iz1 := mini(int(floor((point.z + radius - origin.z) / CELL)), nz - 1)
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var cx := origin.x + (ix + 0.5) * CELL
			var cz := origin.z + (iz + 0.5) * CELL
			var d := Vector2(cx - point.x, cz - point.z).length()
			if d > radius * 0.85:
				continue
			var i := ix * nz + iz
			var scoops := int(round((1.0 - d / radius) * clampf(power / 22.0, 1.0, 3.0) + 0.3))
			var changed := false
			for s in scoops:
				if heights[i] > 0:
					heights[i] = heights[i] - 1
					carved += 1
					changed = true
			if changed:
				_rebuild(i)
	return carved

func _rebuild(i: int) -> void:
	var h := heights[i]
	if h <= 0:
		# dug to bedrock — the column ceases to exist
		if cols.has(i):
			cols[i].queue_free()
			cols.erase(i)
		return
	var ix := int(i / float(nz))
	var iz := i % nz
	var height_m := h * CELL_H
	var bottom := -depth_cells * CELL_H
	var cx := origin.x + (ix + 0.5) * CELL
	var cz := origin.z + (iz + 0.5) * CELL
	var cy := bottom + height_m * 0.5 + LIP
	if cols.has(i):
		var b: StaticBody3D = cols[i]
		var cs: CollisionShape3D = b.get_child(0)
		(cs.shape as BoxShape3D).size = Vector3(CELL, height_m, CELL)
		var mi: MeshInstance3D = b.get_child(1)
		mi.scale = Vector3(CELL - 0.02, height_m, CELL - 0.02)
		b.position = Vector3(cx, cy, cz)
	else:
		var b := StaticBody3D.new()
		b.set_meta("earth", i)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(CELL, height_m, CELL)
		cs.shape = sh
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = main.unit_box
		mi.scale = Vector3(CELL - 0.02, height_m, CELL - 0.02)
		mi.material_override = main.mat(EARTH_COLORS[(ix * 7 + iz * 13) % 4], (ix + iz) % 4)
		b.add_child(mi)
		b.position = Vector3(cx, cy, cz)
		add_child(b)
		cols[i] = b
