class_name EarthSettle
extends RefCounted
## The earth trying to obey its own angle of repose — slumping, in bounded work per frame.
## EARTH-SPEC §3, §5, §9.
##
## Cut a face steeper than the soil will hold and it comes down over a second or two, spreading to
## its neighbours, which is what makes it look like real earth settling rather than a scripted
## animation. Shell a trench and its walls slump past 60° and it stops being a trench. §2 calls the
## transition between those two states *"the game"*, and this is the half of it that moves.
##
## ### It is a queue, not a sweep
##
## §3's design, and the reason is a performance one with a gameplay consequence. Sweeping the map
## looking for unstable faces costs the whole map every frame; an event-driven queue costs only what
## has changed. When a cell moves, it and its eight neighbours go on the queue, and each tick a
## bounded number come off — §9 budgets 512. Where a step is too steep, half the excess moves
## downhill and *both* cells push their neighbours back on, so a slump propagates outward the way a
## real one does, over frames, rather than resolving instantly and looking like a cut scene.
##
## Half the excess rather than all of it is what makes it look like earth. Moving the whole
## difference in one tick levels a face in a single frame; moving half of it each time converges
## geometrically and reads as material finding its own angle.
##
## ### Every number here is an integer, and that is the netcode
##
## §5's largest claim is that **slumping is never replicated**: the server sends the dig, and every
## client derives the identical collapse from the same event. That holds only if the arithmetic is
## exact and the order is fixed — so heights are whole centimetres, the repose threshold is a whole
## centimetre step from `EarthRepose`, "half the excess" is integer division, and the queue is FIFO
## with neighbours pushed in a fixed order. There is not a float in the loop, and `EarthField`'s
## rolling hash is what catches it if that ever stops being true.

## §9's budget: cells popped per tick. Bounded work, so a shell that dirties a thousand cells costs
## the same per frame as a spade that dirties nine — it just takes longer to finish.
const BUDGET := 512

## The most earth one column may shed in one tick, in centimetres.
##
## This is what makes a slump take *time*, and it is a separate lever from `BUDGET` — which is a
## performance cap and turns out not to pace anything. Without it the demo trench finished
## collapsing in five frames, 0.08 seconds: geometrically correct, and on screen a snap. §3 asks for
## "over a second or two, spreading to its neighbours, which is what makes it look like real earth
## settling rather than a scripted animation", and a cell count per frame cannot deliver that
## because the cascade is only a few thousand cell-visits however big the collapse is.
##
## Capping the *amount* rather than the *count* paces it by the thing a viewer actually sees. A face
## sheds a centimetre, wakes its neighbours, and comes back round next tick — so a deep collapse
## takes many passes and a shallow one takes few, which is also how earth behaves.
##
## One centimetre is the finest quantum the field has, so this is as slow as integer heights can be
## made to go. It puts the demo trench at 21 frames — a third of a second, against 5 frames before,
## and clearly a settle rather than a snap. §3 asks for "a second or two"; a small trench is quicker
## than that because there is less earth in it, and a shell crater is slower because there is more
## and because 512 cells a frame starts binding. Duration scaling with the size of the event is the
## property worth having, and it is the one this gets.
const MAX_SHED_CM := 1

## The eight neighbours, in a fixed order, because the order events are applied in is part of what
## two machines have to agree on. Orthogonal first, then diagonal.
const AROUND := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var materials: MaterialSet = null

## How much earth this queue has moved, in column-centimetres, since it was made. Slumping conserves
## volume — it is the same earth in a different place — so a test can assert that and a boot log can
## report it.
var moved_cm := 0

var _queue: Array[Vector2i] = []
var _waiting: Dictionary = {}


static func of(materials_: MaterialSet) -> EarthSettle:
	var settle := EarthSettle.new()
	settle.materials = materials_
	return settle


## Wake a cell and everything touching it. Called after a dig, a deposit, a blast, or a piece of
## revetment being destroyed — anything that could have left a face standing steeper than it can.
func disturb(cell: Vector2i) -> void:
	_wake(cell)
	for offset in AROUND:
		_wake(cell + (offset as Vector2i))


func pending() -> int:
	return _queue.size()


## One tick of settling. Returns how many cells were looked at, which is what a caller watching the
## budget cares about; `moved_cm` is what a caller watching the earth cares about.
func run(field: EarthField, budget := BUDGET) -> int:
	var looked := 0
	while looked < budget and not _queue.is_empty():
		var cell: Vector2i = _queue.pop_front()
		_waiting.erase(cell)
		looked += 1
		_settle_one(field, cell)
	return looked


## Everything, until the earth stops moving. For tests and for world generation, never for a frame:
## the whole point of the budget is that a frame does not do this.
func run_to_rest(field: EarthField, limit := 200000) -> int:
	var ticks := 0
	while not _queue.is_empty() and ticks < limit:
		ticks += run(field, BUDGET)
	return ticks


## One column against its neighbours. Where the step down to a neighbour is steeper than this soil
## will hold, half the excess goes over the edge.
##
## The threshold is read from the *higher* of the two columns, because it is the higher one whose
## face is standing: a clay bank above a sand pit stands at clay's angle, and the sand does not get
## a say in whether the clay above it holds.
func _settle_one(field: EarthField, cell: Vector2i) -> void:
	var here := field.surface_cm(cell)
	var hold := EarthRepose.for_column(field, cell, materials)

	for step in AROUND:
		var offset: Vector2i = step
		var other := cell + offset
		var there := field.surface_cm(other)
		if there >= here:
			continue                       # downhill only; the neighbour will look at its own face
		var diagonal := offset.x != 0 and offset.y != 0
		var allowed := EarthRepose.diagonal_step_cm(hold) if diagonal else EarthRepose.step_cm(hold)
		var excess := (here - there) - allowed
		if excess <= 0:
			continue

		# Half, and integer — see the class docstring. A move of zero would spin the queue forever
		# on a one-centimetre excess, so anything that rounds to nothing is left alone: the face is
		# within a centimetre of its angle and a centimetre is invisible.
		var move := mini(excess / 2, MAX_SHED_CM)
		if move <= 0:
			continue
		field.carve(cell, move)
		field.deposit(other, move)
		moved_cm += move
		here -= move

		# Both ends of the move wake their own neighbourhoods, which is how a slump spreads outward
		# over frames instead of resolving in one.
		disturb(cell)
		disturb(other)


func _wake(cell: Vector2i) -> void:
	if _waiting.has(cell):
		return
	_waiting[cell] = true
	_queue.append(cell)


func report() -> String:
	return "settle: %d cell(s) waiting, %d column-cm moved" % [_queue.size(), moved_cm]
