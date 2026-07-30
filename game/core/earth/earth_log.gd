class_name EarthLog
extends RefCounted
## Every modification to the ground, as a serialised event. EARTH-SPEC §5.
##
## This exists from day one of C3 and not because C3 needs it. §5 is explicit that the log is
## simultaneously the netcode foundation, the replay system and the late-join path, and that the
## single largest saving it buys is one nobody would think to look for:
##
## > **Slumping is never replicated.** Because heights are integers and the settle queue runs in a
## > fixed order, every client derives identical slumping from the same event stream. The server
## > sends the dig; the collapse happens everywhere by itself.
##
## Given how much of this game is earth moving, that is most of the terrain traffic gone. It is
## also a claim that is either true or has been quietly false for a month, so `EarthField`'s
## `rolling_hash` is what catches the drift rather than assuming it away — and the test that
## matters is that the same events replayed onto a fresh field produce the same hash.
##
## A record is 14 bytes rather than §5's "about 10", and that is a deliberate trade recorded in
## DEVIATIONS-C3: the seven fields §5 names do not fit in ten without bit-packing the tick and the
## op together, and a wire format that is hard to read in a debugger is a bad trade at this stage.
## It is a fixed-width record so a log can be sliced without parsing it.

## §5's own list. The order is the wire encoding, so entries are appended and never reordered.
const OPS := ["carve", "deposit", "split", "collapse", "shore", "unshore"]

const CARVE := 0
const DEPOSIT := 1
const SPLIT := 2
const COLLAPSE := 3
const SHORE := 4
const UNSHORE := 5

## tick u32 · actor u8 · op u8 · cell.x i16 · cell.y i16 · delta i16 · span u8 · material u8
const RECORD_BYTES := 14

var events: Array[Dictionary] = []


## Append one modification. Nothing validates the op against the delta — a `collapse` with a
## positive delta is a legal thing to record and an interesting thing to have recorded.
func record(tick: int, actor: int, op: int, cell: Vector2i, delta_cm: int, span := 0,
		material := 0) -> void:
	events.append({
		"tick": tick, "actor": actor, "op": op, "cell": cell,
		"delta_cm": delta_cm, "span": span, "material": material,
	})


func size() -> int:
	return events.size()


func at(i: int) -> Dictionary:
	return events[i] if i >= 0 and i < events.size() else {}


static func op_name(op: int) -> String:
	return OPS[op] if op >= 0 and op < OPS.size() else "?"


## Apply the log to a field, in order. This is late join and replay both: a client that has a
## chunk snapshot and the events since is a client that agrees with the server.
##
## Only `carve` and `deposit` do anything yet. `split` and `collapse` arrive with tunnels at C3b,
## and shoring with revetment — they are in `OPS` now so the wire format does not have to change
## when they land, which is the same reasoning that put spans in on day one.
func replay(field: EarthField) -> int:
	var applied := 0
	for event in events:
		match int(event["op"]):
			CARVE:
				field.carve(event["cell"], absi(int(event["delta_cm"])))
				applied += 1
			DEPOSIT:
				field.deposit(event["cell"], absi(int(event["delta_cm"])))
				applied += 1
	return applied


## The log as bytes, fixed-width and little-endian. Fixed-width so a range of ticks can be sliced
## out of a stream without parsing every record before it, which is what a late-joining client
## wants to do to a log it is only interested in the tail of.
func encode() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(events.size() * RECORD_BYTES)
	for i in events.size():
		var event := events[i]
		var base := i * RECORD_BYTES
		out.encode_u32(base, int(event["tick"]))
		out[base + 4] = int(event["actor"]) & 0xFF
		out[base + 5] = int(event["op"]) & 0xFF
		out.encode_s16(base + 6, (event["cell"] as Vector2i).x)
		out.encode_s16(base + 8, (event["cell"] as Vector2i).y)
		out.encode_s16(base + 10, clampi(int(event["delta_cm"]), -32768, 32767))
		out[base + 12] = int(event["span"]) & 0xFF
		out[base + 13] = int(event["material"]) & 0xFF
	return out


## Bytes back into a log. Returns null rather than a half-read log when the length is not a whole
## number of records — a truncated stream is a connection problem, and guessing at the last record
## turns it into a terrain problem three seconds later.
static func decode(bytes: PackedByteArray) -> EarthLog:
	if bytes.size() % RECORD_BYTES != 0:
		return null
	var log := EarthLog.new()
	for i in bytes.size() / RECORD_BYTES:
		var base := i * RECORD_BYTES
		log.record(bytes.decode_u32(base), bytes[base + 4], bytes[base + 5],
			Vector2i(bytes.decode_s16(base + 6), bytes.decode_s16(base + 8)),
			bytes.decode_s16(base + 10), bytes[base + 12], bytes[base + 13])
	return log


## One line per event, for a boot log or a replay dump.
func report(limit := 8) -> String:
	var lines: Array[String] = ["earth log: %d event(s), %d bytes" % [
		events.size(), events.size() * RECORD_BYTES]]
	for i in mini(limit, events.size()):
		var event := events[i]
		lines.append("  t%-6d %-8s (%d, %d) %+d cm" % [
			event["tick"], op_name(int(event["op"])), (event["cell"] as Vector2i).x,
			(event["cell"] as Vector2i).y, event["delta_cm"]])
	if events.size() > limit:
		lines.append("  … %d more" % (events.size() - limit))
	return "\n".join(lines)
