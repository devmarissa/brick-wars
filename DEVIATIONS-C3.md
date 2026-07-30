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

**Marissa, 30 Jul:** *"we will have to see... we want large scale combat with aerial vehicles so
who knows what testing will reveal works for player count scale and map scale."* Deferred
deliberately, and the reasoning is worth keeping because it is new information rather than a
shrug — the spec's range was written against a Great War sector a few hundred metres deep, and
**aerial vehicles were not part of that framing.** `BUILD-ORDER` names a flying vehicle as a gate
and `CORE-SPEC` §2 lists `flying` as a locomotion type, so aircraft are planned rather than
speculative.

That may push past the top of the range rather than somewhere inside it. At a biplane's 40 m/s an
800 m map is twenty seconds corner to corner, and a fighting area that an aircraft crosses in
twenty seconds is an aircraft with nowhere to go. If aerial combat is a real pillar, the honest
options are a bigger deformable area, or a deformable core inside a larger non-deformable arena —
which is a different shape of answer than a bigger number, and cheaper.

**When it has to be decided:** before the settle queue's per-frame budget means anything, because
"512 cells a frame" is a different promise over 400 m than over 800. Not before then, and it wants
a real frame budget and a real aircraft rather than a guess.

### A2. Pixel textures — Marissa's proposal, 30 Jul, and what it actually decides

> *"i think we can use pixel textures like 16x16 or 32x32 to give it nice texture across all our
> parts, maybe even pbr pixel textures? could be cool and look nice with shaders."*

This is `ART-BIBLE` §8 being answered, which is the right milestone for it — §8 says prototype it
during C3 when there is real ground to look at. Most of the proposal is compatible with everything
already written, and one part of it is a genuine fork. Separating them is the whole of the answer.

**Compatible, and arguably what §8 was reaching for.** A 16–32 px per-material detail map, tiled,
is a *tighter* version of §8b's existing rule — "fixed resolution cap and fixed tiling scale,
declared per material class". A pixel cap that low makes the texture-pack bound easy to enforce
rather than a judgement call: a 4K photoscan is not rejected by review, it is unrepresentable.

**PBR is mostly free.** Roughness, metallic and normal are not colour, so none of them touch the
palette law. Wet clay reading differently from dry chalk, or sheet metal from timber, is exactly
the "material read" §8 says Teardown gets from its textures. These can go in without deciding
anything.

**The fork is albedo.** `ART-BIBLE` §2's palette law says colour comes from a twenty-entry palette
with bounded value and saturation, and §8b is explicit that a skin supplies *"a greyscale detail
map that modulates the palette colour, never a full-colour texture that replaces it"* — because
that is what makes the palette law survive contact with the workshop. So:

- **Greyscale pixel textures modulating palette colour** — everything already written stands. The
  palette law holds, texture packs work as designed, and the game still reads as one game with a
  hundred packs in it.
- **Full-colour pixel textures** — the palette law becomes advisory, and the property it exists to
  protect goes with it. That is a change to what the game *is*, not how it is built.

**Not the blocker it looks like:** "with shaders" is fine. §8b's hard line is about *pack-uploaded*
shaders, and the reason is specific — a shader that disables depth testing is a wallhack in a game
about hiding behind earthworks. Core shaders are how anything renders at all.

**What happens next:** the side-by-side gets built during the meshing increment — flat, greyscale
pixel detail, and full-colour pixel — on the same trench section, and Marissa picks by looking.
§8 has always said the decision wants eyes rather than an argument, and this note exists so the
argument is not had twice.

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

### B4. Collision is a trimesh, not a heightfield

§2 asks for "a Jolt heightfield collider per chunk", which is cheaper. `EarthTerrain` builds a
`ConcavePolygonShape3D` from the mesh it just made instead.

The reason is that a heightfield cannot hold the feature the whole design exists for. It has one
height per cell, so a vertical skirt becomes a very steep ramp and a **tunnel cannot be
represented at all** — §6 already concedes this by saying voids and tunnel roofs get box colliders
on the side. Starting with the shape that is *correct* and moving to the one that is *cheap* when
a frame budget says so is the right order; the other way round means discovering at C3b that the
collision model cannot express spans.

Revisit when there is a real map and a profiler. The mesh already exists either way, so a trimesh
costs the shape build rather than a second traversal.

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
