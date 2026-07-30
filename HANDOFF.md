# HANDOFF — Brick Wars, start of C3

Rewritten 30 July 2026. This is everything a fresh agent needs to pick the build up without
re-deriving it. Read `VISION.md` and `BUILD-ORDER.md` first if you have not; this file assumes
them and covers what is *not* written down elsewhere.

---

## 1 · Where the build actually is

`BUILD-ORDER.md` splits the core into nine milestones, C0 through C8. **C0, C1 and C2 are closed
and signed off.** C3 is one increment in.

**C2 — rigs, IK and the soldier — closed 30 July**, signed off by Marissa after she watched it,
ran the gate and cleared the deviations. Its done-condition holds: a soldier defined entirely in
data walks, sprints and jumps over uneven ground with its feet planting, and a four-legged
creature does the same through the same system out of a *non-core pack* with zero core changes.
The pieces: `Rig`, `TwoBoneIK`, `Footing`, `Gait`, `Leg`, `Locomotion`, `Walker`,
`LocomotionRules`/`GaitRules`, `--rig` as an inspector CLI, `core:soldier`, `testpack:horse`, and
`ANIMATION-SPEC.md`.

**C3 — the earth — increment 1 done.** `EarthSpan`, `EarthChunk`, `EarthField`, `EarthLog`: the
column-span field, digging with conservation of volume, and the event log. Nothing is meshed or
drawn yet, on purpose.

Gate is green: **22 cases, 947 checks**, no source file over 300 lines, 8 of 13 modules still
honestly stubs.

---

## 2 · The working agreement with Marissa

The part most easily lost in a handoff, and it matters more than any technical detail below.

**She approves checklist items, not technical tasks.** Do not ask her which library, which file
layout, or whether to refactor. Decide, do it, and record why in the code.

**Check in at milestone boundaries, not inside them.** The one exception is a genuine design fork
— a decision that changes what the game *is* rather than how it is built. Those get a question.

**The repo is the channel.** Push every milestone; her Mac only pulls. She does not want to run
build commands beyond `./tools/check.sh`.

**Nothing gets `[x]` in `CHECKLIST.md` until she says it feels right.** `[~]` means in the game
but rough. C2's line is `[x]` because she said so, in those words.

**Stay in plan order.** This was learned the hard way: mid-C2 I built a player-input layer so she
could feel the locomotion, and she stopped it — input is C4's. *"i dont want you to make stuff out
of order... we already have a dev plan."* It was reverted. If something seems missing, check
`BUILD-ORDER.md` for which milestone owns it before building it.

---

## 3 · The lesson C2 paid for, which applies to everything after it

**Test the result, not the intention.**

Every foot-planting assertion in C2 read `leg.plant` — where `Footing` *decided* a foot should go.
Not one read the rig back to see where the foot actually ended up. Two test fixtures had a 0.2 m
gap at the knee, so their feet missed the ground by 0.2 m for a fortnight, and the entire suite was
green throughout. Worse, I reported it to Marissa as an engine defect before measuring the shipped
content, which was correct all along.

Two habits came out of it and both are now load-bearing:

**`tools/mutate.py`** — break one policy line, confirm a test goes red, put it back. It reports
**15 caught, 1 missed** today, and the miss (the hang lag's frame-rate independence,
`DEVIATIONS-C2.md` §D2) is an entry in the harness rather than a note in a document, so it
announces itself every run. Run it after adding a policy line. It found the sliding-foot bug that
every existing test agreed with.

**Measure before believing.** Marissa said the hooves "slip a bit backwards". Straight-line tests
all passed; measuring a *turn* showed 0.022 m per frame against a body covering 0.033. Predicted
numbers matching to five decimals is a different kind of evidence than "looks about right", and it
is what turned three separate suspicions into one-line fixes this milestone.

---

## 4 · Environment facts that will otherwise cost you an hour each

- **Godot is 4.7.1.stable.official.a13da4feb.** Keep parity; a version drift silently changes
  physics.
- **`godot --headless --path game` never exits.** Pass `--quit-after 400`. The fastest way to see a
  parse error is `godot --headless --path game res://tests/test_main.tscn`, which exits by itself.
- **A new `class_name` needs `godot --headless --path game --import`** before anything referencing
  it will parse. This also bites right after a `git pull` that brings new files.
- **User arguments go after `--`.** Godot's own flags go before it.
- **GDScript warnings are errors here.** `var x := some_callable.call(...)` is a hard parse
  failure — every `Callable.call` result needs an explicit type. Dictionary lookups used as typed
  values need a cast.
- **No source file over 300 lines.** When something does not fit, split it on a real conceptual
  seam — do **not** trim the prose comments; they are the design record and the reason this
  codebase can be handed over at all. Several files sit at exactly 300.
- **`--pack-root` *adds* to the default roots.** Pointing it at a fixture tree whose `pack.json`
  claims `id: core` collides with the real core pack and disables both. Use a test that calls
  `FixtureWorld.load_root` instead.
- **Run `./tools/check.sh` before every push.** A pre-push hook runs it too.

---

## 5 · What C3 needs next, in order

1. **Meshing** — slope-dependent, `EARTH-SPEC` §2: triangulate smoothly between column centres
   below the 60° cliff threshold with smoothed normals; above it, emit the upper column's edge and
   a **vertical skirt** with flat normals. The same field then gives rolling organic ground *and*
   knife-edge trench walls, decided by the terrain rather than by an authoring mode. This is the
   increment where C3 becomes something to look at.
2. **The texture side-by-side** — build it during meshing, on the same trench section: flat colour,
   greyscale pixel detail modulating palette colour, and full-colour pixel. `DEVIATIONS-C3.md` A2
   has the argument; Marissa picks by looking. Do not decide it in prose.
3. **Chunked Jolt heightfield collision**, rebuilt with the mesh.
4. **The angle-of-repose settle queue** (§3) — the actual slumping. Event-driven, ≤512 cells a
   frame, and **integer arithmetic only**: §5's entire netcode saving is that slumping is never
   replicated because every client derives it identically.
5. **Water level** (§8), then the sandbox onto the real field.

---

## 6 · Design decisions already made, and why

**Spans are the primitive, from line one.** `spans_at` is the API and `surface_cm` sits on it, not
the other way round. `EARTH-SPEC` §1 says retrofitting spans onto a flat heightfield is a rewrite.
Nothing splits a column until C3b; the point is that tunnels are then a longer array in code that
already reads spans.

**No floats anywhere in the earth.** Heights are integer centimetres. This is not a storage detail
— §5 stakes the netcode on it. There is no way to test "no floats", so what is tested is the
property that would break: identical events give byte-identical ground, via `rolling_hash`.

**`carve` returns the volume it moved** rather than taking a destination, so ignoring it is
visibly deleting earth. That signature is the enforcement of §4's "digging is not deletion".

**`TestGround` is not going anywhere.** Every rig case asserts exact numbers against it as an
analytic function. The real field replaces it *in the sandbox*, not in the suite.

**A planted foot latches.** `Leg.anchor` holds a foot's world position from footfall to lift, with
only the height re-probed. Without it a turning creature drags its feet; with it, zero slide.

**A leg's bend direction is derived, not declared** — read off the rest pose, which is what makes a
knee and a hock one function with no field between them. Shipped rigs are bent by `rest` angles
with joints coincident; `Leg.MAX_CHAIN_GAP` refuses a chain whose bones do not meet.

---

## 7 · Open, and owed to Marissa

- **`DEVIATIONS-C3.md` A1 — the playable deformable area.** Specced as a *range*, 400–800 m.
  Deferred deliberately, and her reason is new information: aerial vehicles were not in the spec's
  framing, and at 40 m/s an 800 m map is twenty seconds corner to corner. May want a deformable
  core inside a larger non-deformable arena rather than a bigger number. Must be settled before
  "512 cells a frame" means anything.
- **`DEVIATIONS-C3.md` A2 — pixel textures.** Her proposal. Greyscale detail maps and PBR
  roughness/normal/metallic are compatible with everything written; **full-colour albedo is the
  fork**, because it retires the palette law. Show her, do not argue it.
- **Creature-vs-creature collision** (`CHECKLIST.md` §2) — "they fling out then continue back on
  their paths". Head-on is measured clean in both body and meshes; not yet tried are glancing
  meetings and one creature catching the top edge of the other's lower collider box.
- **Horse gait realism** — trot/walk patterns want tuning to read as a real horse. Feel work; needs
  input, which is C4's.
- **The locomotion feel-check** — `CHECKLIST.md` §2's first two items are `[~]` until C4, not until
  she finds ten minutes. Nothing in the build reads a keyboard.

---

## 8 · Security

The fine-grained GitHub token from the original Cowork session is still in that transcript in
plain text. It is scoped to `brick-wars` alone, but it should be revoked and reissued.
