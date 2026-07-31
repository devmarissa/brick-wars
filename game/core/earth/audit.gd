class_name EarthAudit
extends RefCounted
## Questions you ask *about* a field rather than of it: how much earth is in it, what still needs
## remeshing, and the hash two machines compare. EARTH-SPEC §5, §9.
##
## Its own file because it is its own kind of thing, and because `EarthField` grew past the
## 300-line cap once digging, water, shoring and the event log all landed on it. The seam is real:
## everything here reads the whole field and changes none of it, and everything there is the ground
## itself.
##
## `rolling_hash` is the one that matters. §5 does not replicate slumping — the server sends the
## dig and every client derives the collapse — which is a claim that is either true or has been
## quietly false for a week. So chunks carry a hash, it is reconciled periodically, and a mismatched
## chunk is re-snapshotted. Drift is *caught* rather than assumed away, and the same number is what
## makes determinism cheap to assert in a test.

## The sum of every column's surface height, in centimetres. Not a physical volume — the columns
## all reach the same bedrock, so it differs from one by a constant — which makes it exactly the
## right thing to assert conservation against: carve a hundred and deposit a hundred and this
## number comes back to where it started.
static func surface_sum_cm(field: EarthField) -> int:
	var total := 0
	for key in field.chunks:
		var chunk: EarthChunk = field.chunks[key]
		for z in EarthChunk.SIZE:
			for x in EarthChunk.SIZE:
				total += chunk.base_cm + chunk.surface_cm(x, z)
	return total


static func dirty_chunks(field: EarthField) -> int:
	var count := 0
	for key in field.chunks:
		if (field.chunks[key] as EarthChunk).dirty:
			count += 1
	return count


## One number for the whole field's state, for §5's drift reconciliation and for asserting that
## two runs of the same events agree. Chunks are folded in sorted order, because a dictionary's
## iteration order is not a promise and a hash that depended on it would report drift that was
## only ever a different insertion sequence.
static func rolling_hash(field: EarthField) -> int:
	var hash := 2166136261
	var keys: Array = field.chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for key in keys:
		var chunk: EarthChunk = field.chunks[key]
		for value in [key.x & 0xFFFF, key.y & 0xFFFF, chunk.rolling_hash()]:
			hash = ((hash ^ int(value)) * 16777619) & 0xFFFFFFFF
	# Shoring is state like any other: two clients that disagree about which walls are held would
	# disagree about which ones fall, and that is exactly the drift §5 wants caught rather than
	# assumed away. Sorted, because a dictionary's iteration order is not a promise.
	var held: Array = field.shoring.keys()
	held.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for key in held:
		for value in [key.x & 0xFFFF, key.y & 0xFFFF, int(field.shoring[key])]:
			hash = ((hash ^ int(value)) * 16777619) & 0xFFFFFFFF
	return hash
