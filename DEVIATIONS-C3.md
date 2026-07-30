# Where the C3 build and the specs disagree

Running list, opened at the start of C3. `DEVIATIONS-C1.md` and `DEVIATIONS-C2.md` are the closed
ones; read the relevant one before assuming a mismatch is a bug.

Same sorting as before — by what I need from you, not by subject.

**A** — forks worth a decision.
**B** — calls made where the specs said nothing, or said a range.
**C** — structural notes.

---

## A · One fork, and the spec deliberately left it open

### A1. How big is the playable deformable area?

`EARTH-SPEC` §1 and §9 both say **400–800 m per side**, which is a 4× range in memory, remesh cost
and settle work rather than a number. That looks like an omission and is not: the spec is saying
the trade is real and wants it made against a running game rather than on paper.

Where it lands matters more than it sounds. At 800 m the base field is 2.56 M columns and about
8 MB; at 400 m it is a quarter of that. Everything downstream — how many chunks can be dirty at
once, how far a mine going off out of view has to still be real, how much a late-joining client
has to be sent — scales off it.

**Nothing has been decided, because nothing yet needs it.** `EarthField` is unbounded and
allocates chunks on demand, so the number is a policy about where the deformable area stops
rather than a constant the storage depends on. The sandbox will instantiate something far smaller
than either figure — its current world is 24 m across — and the real number wants a map, a frame
budget and somebody watching it.

**When it has to be decided:** before the settle queue's per-frame budget means anything, because
"512 cells a frame" is a different promise over 400 m than over 800.

---

## B · Calls where the spec said nothing

### B1. An event is 14 bytes, not §5's "about 10"

§5 lists seven fields — `tick`, `actor`, `cell`, `span`, `op`, `delta_cm`, `material` — and then
says the packed record is about ten bytes. Those two do not both fit unless the tick is truncated
and the op is bit-packed against the span.

It is 14: `tick u32 · actor u8 · op u8 · cell.x i16 · cell.y i16 · delta i16 · span u8 ·
material u8`. Fixed-width, so a late-joining client can slice the tail of a stream without parsing
everything before it — which is most of what the format is for.

Four bytes an event is worth revisiting when there is a real 100v100 load to measure it against;
§5's own estimate of "a few kilobytes a second" has enough headroom that guessing now would be
optimising a number nobody has watched. A wire format that is hard to read in a debugger is a bad
trade this early.

### B2. Only `earth`-class materials can be ground

The spec says soil type *is* material and points at `MATERIAL-SPEC`, but never says which
materials may be a column. The field's palette is the nine `earth`-class materials, because those
are the ones carrying `angle_of_repose`, and §3 — the whole of slumping — has nothing to work with
without it. A column of steel is not a thing the earth can represent.

This also fixes the byte encoding: seven bits of material index against nine materials leaves a
lot of room, and the palette is sorted, so the same content produces the same bytes on every
machine. That is what makes §5's chunk hashes comparable at all.

### B3. `carve` returns the volume it actually moved

§4 says material removed has to go somewhere and does not say how the code enforces it. `carve`
returns the volume rather than taking a destination: a cut that reaches bedrock moves less than it
was asked for, and a caller that ignores the return has quietly deleted earth. Making that
awkward is the point — the signature is the enforcement.

---

## C · Structural notes

### C1. `TestGround` is not going anywhere

Every rig case in the suite — footing, driver, body, walker — asserts exact numbers against
`TestGround.height_at` as a pure analytic function, which is why they can be tight. The real field
replaces `TestGround` **in the sandbox**, not in the tests. Re-baselining a dozen exact assertions
onto a surface nobody can compute with a pencil would trade a real property for a moving one.

### C2. `earth_module` stays a stub until C3's done-condition is walked

Same bar `rig` was held to at C2: the flag flips when *"you can dig anywhere on the map, a trench
you cut has vertical walls that slump organically when shelled, craters have raised rims made of
their own spoil"* is demonstrable — not when the field boots.
