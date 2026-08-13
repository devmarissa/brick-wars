class_name Seats
extends RefCounted
## Who is on board, and where. FORMAT-SPEC §7, CORE-SPEC §2, C6.
##
## A vehicle declares its seats in data:
##
##     "seats": [ {"role": "driver", "eye": [0, 22, 4], "controls": ["reins_l", "reins_r"]} ]
##
## and the core owns everything about occupying one. Three fields, each earning its place.
##
## **`role`** is what this seat is *for*, and it is why `enter` and `man` are different verbs. Two
## soldiers on one field gun are a layer and a loader doing different jobs on the same object; two
## soldiers in a lorry are a driver and a passenger. The distinction was drawn back at C4 when the
## vocabulary was closed — *a crew station is a role rather than a ride* — and this is where it
## stops being a sentence.
##
## **`eye`** is where the occupant's head goes, in modules, so the camera has somewhere to be that
## the pack chose rather than the engine guessing. A rider sits above a horse's barrel and a driver
## sits inside a cab, and no formula gets both right.
##
## **`controls`** names the bones the occupant's hands reach for — reins, a wheel, a traverse
## handle. Nothing uses them yet: hands-on-controls is C6's IK work and this is the data it will
## read. Declared now because the seat is where they belong and adding them later would mean every
## pack re-authoring every vehicle.
##
## ### Occupancy is here rather than on the vehicle
##
## A vehicle asset is content — shared, immutable, and possibly loaded once for fifty lorries. Who
## is sitting in *this* lorry is per-instance state, so it lives in a `Seats` built from the asset
## rather than in the asset itself. Getting that backwards means every lorry of a type sharing one
## driver, which is the sort of bug that looks like a netcode problem for a week.

## The one role that drives. Any number of seats may exist; at most one of them may be this, because
## two things steering is not a seating arrangement, it is a bug.
const DRIVER := "driver"

## Where a seat's eye sits if the pack did not say. Head height above the origin, which is wrong for
## every vehicle and wrong in an obvious direction — a camera at the floor is a missing number
## somebody notices, and a camera at a plausible guess is a missing number nobody does.
const DEFAULT_EYE := Vector3(0.0, 1.0, 0.0)

var owner_id := ""
var seats: Array[Dictionary] = []     ## { role, eye, controls }
var errors: Array[String] = []

var _in: Dictionary = {}              ## int seat index -> occupant


## Read the seats off an asset. Returns a `Seats` whose `errors` are empty when the asset's seat
## table is usable — a vehicle with a broken one is refused rather than silently seating nobody.
static func of(asset: ResolvedAsset) -> Seats:
	var out := Seats.new()
	if asset == null:
		out.errors.append("a seat table needs an asset to come from")
		return out
	out.owner_id = asset.id

	var drivers := 0
	for entry in asset.data.get("seats", []):
		if typeof(entry) != TYPE_DICTIONARY:
			out.errors.append("%s: a seat should be an object" % out.owner_id)
			continue
		var seat: Dictionary = entry
		var role := String(seat.get("role", ""))
		if role == "":
			out.errors.append("%s: a seat with no `role` — %s" % [out.owner_id,
				"a seat nobody can ask for is a seat nobody sits in"])
			continue
		if role == DRIVER:
			drivers += 1
		out.seats.append({
			"role": role,
			"eye": PartGeometry.offset_m(seat.get("eye")) if seat.has("eye") else DEFAULT_EYE,
			"controls": _strings(seat.get("controls", [])),
		})

	if drivers > 1:
		out.errors.append("%s: %d seats claim to be the driver — %s" % [out.owner_id, drivers,
			"two things steering is not a seating arrangement"])
	return out


func is_valid() -> bool:
	return errors.is_empty()


func count() -> int:
	return seats.size()


func role_of(index: int) -> String:
	return String(seats[index]["role"]) if index >= 0 and index < seats.size() else ""


func eye_of(index: int) -> Vector3:
	return seats[index]["eye"] if index >= 0 and index < seats.size() else DEFAULT_EYE


func controls_of(index: int) -> Array[String]:
	return seats[index]["controls"] if index >= 0 and index < seats.size() else [] as Array[String]


## The first free seat of a role, or -1. Roles rather than indices at the call site, because a caller
## wanting "somewhere to sit" should not have to know the vehicle's seat order.
func free_seat(role := "") -> int:
	for i in seats.size():
		if _in.has(i):
			continue
		if role == "" or String(seats[i]["role"]) == role:
			return i
	return -1


func occupant(index: int) -> Variant:
	return _in.get(index)


func seat_of(who: Variant) -> int:
	for i in _in:
		if _in[i] == who:
			return int(i)
	return -1


func occupied() -> int:
	return _in.size()


## Put somebody in. Refuses a taken seat and refuses seating the same body twice, which is how a
## rider ends up driving two vehicles at once.
func take(index: int, who: Variant) -> bool:
	if index < 0 or index >= seats.size() or _in.has(index) or seat_of(who) >= 0:
		return false
	_in[index] = who
	return true


func leave(who: Variant) -> int:
	var index := seat_of(who)
	if index >= 0:
		_in.erase(index)
	return index


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(String(item))
	return out
