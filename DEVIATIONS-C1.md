# Every place the build and the specs disagree, as of C1

Thirty items. None of them block C2 — this is the full account, not a problem list.

The specs were written before a line of the rebuild existed, which was the right order, and
the price of that order is that building the thing finds the places the writing was wrong,
vague, or silent. This is that list, checked against the actual files today rather than
reported from memory. It is sorted by what I need from you, not by subject:

**A** — four real forks, put to Marissa on 30 Jul and **all four decided**. Each keeps its
full argument, so the decision can be re-argued later against what it was weighing rather
than against a summary of it.
**B** — seven places the spec text was simply wrong or behind the code. **All seven amended**
in the same pass; none was a design question.
**C** — fifteen calls I made where the specs said nothing at all. All reversible, all cheap
to reverse now. Read them as FYI; say the word on any one and it changes. One of them (C1)
turned out to be a real bug and was fixed rather than documented.
**D** — four things deliberately left undone, with what they're waiting on.

---

## A · Decided, 30 Jul 2026

All four went the way the write-up leaned. Recorded here and folded into the specs in the
same commit; each item below keeps its full argument so the decision can be re-argued later
against what it was actually weighing rather than against a summary of it.

### A1. The 0.1 m module, and the declared-mass workaround it forced

This is the big one, and the reason it's first is that changing it invalidates every asset
authored so far.

MODULE = 0.1 m. Every part's `size` and `offset` are whole numbers of modules, so a sandbag
is 4 × 2 × 2 and a crate is 6 × 6 × 6. That's a fine number for props. Where it goes wrong is
hollow objects: a crate shell one module thick is 0.1 m of solid timber on every face, which
at plank density comes out around 167 kg for a box a soldier is meant to shove. There is no
thinner wall available — one module *is* the floor.

So every hollow thing that ships declares its `mass` in the file and overrides the derived
number. `core:crate` says 32 kg, the watchtower says 1400, the table says 34. The boot log
prints `(declared)` next to each so it's never invisible. It works, but it means the density
tables in MATERIAL-SPEC are decorative for exactly the class of object most likely to be
thrown around, and every modder authoring a container will hit the same wall and won't have
the boot log to tell them why.

Three ways out, and they cost very different amounts:

- **Keep it.** Declared mass stays the documented answer for hollow shells and MODDING.md
  grows a paragraph explaining it. Costs nothing today; the density model stays half-real.
- **Drop MODULE to 0.05 m.** Shells get a true half-module wall and derive sensible masses.
  Every shipped asset's numbers double, which is a mechanical rewrite of nine JSON files
  today and a breaking change for every pack in existence later.
- **Add a `hollow` wall thickness in sub-module units.** Keeps authoring on the 0.1 m grid,
  lets the *physics* wall be thinner than the *visual* one. Most flexible, most code, and
  it's a lie the renderer and the solver have to keep telling consistently.

**Decided: keep 0.1 m, declared mass stays.** FORMAT-SPEC §6 now states the shell thickness
(one module, a consequence of §3's unit rather than a tunable), says plainly that reaching for
`mass` on a hollow object usually means the shell is thicker than the real thing's walls
rather than that the material is wrong, and records the decision. Revisit if C4's destruction
work shows declared masses make collapse feel wrong.

### A2. The `wood` palette exemption — 0.472 against a 0.35 law

ART-BIBLE §2 says saturation stays under ~35%. That tilde was doing a lot of quiet work, so
`palette.json` turned it into an exact number plus a named-exception list: any colour over
the line carries `exempt` and a written `why`, and one without a `why` is refused outright.

Six of the twenty are exempt. Four are rounding — `clay` and `tan` at 0.362, `webbing` at
0.352 — and I'd defend those without asking. `skin` at 0.439 saturation and 0.769 value is
the only entry breaking two laws, on the grounds that faces have to read at range against
every terrain colour we ship. Also defensible.

`wood` at **0.472** is not rounding. It is 35% over the law, and the file itself says so:
*"The largest exemption in the file and the one most worth arguing about."* The argument for
it is that timber desaturated to 0.35 stops reading as wood and starts reading as dirt, and
duckboards over mud have to be a different material at a glance. The argument against is
that this is the first crack in a law whose entire value is that it's a law — and `wood2` at
0.443 exists only because `wood` does.

**Decided: keep the exemption as written.** The mechanism is the point — an exception you
have to name and defend in the file is a different thing from a limit nobody checks — and the
argument for wood is the one the file already makes. ART-BIBLE §2's palette laws now carry the
exact numbers instead of a tilde, the named-exemption rule, and all six exemptions with which
of them are rounding and which are decisions.

### A3. The 26-slot archetype registry

`slots.json` defines 26 archetype slots across seven kinds — prop, structure, weapon,
vehicle, buildable, character, emplacement. Every gameplay asset fills a core slot and
supplies the numbers that slot defines; core owns the field list, and a pack that invents a
field gets a warning and has the field ignored.

I authored all 26 from FORMAT-SPEC §7's description of what a slot *is*. The spec never named
them. This is the single largest piece of design I've written that you haven't looked at, and
it's the file that decides what shapes of thing the game can contain — if there's no slot for
it, a modder can't build it without asking us to add one.

Right now it costs nothing to change because only props exist. From C4 (verbs, combat and
tools) onward the weapon and emplacement slots start carrying real numbers and changing them
means rebalancing. *(I called this "C3" when I put the question to you — C3 is the earth;
combat is C4. The reasoning is unchanged, the milestone number was wrong.)*

**Decided: review at C4.** Only the prop slots have been tested by anything, and reviewing
weapon and emplacement slots in the abstract produces agreement about words rather than about
numbers. Written into BUILD-ORDER §C4 as a named carried item so it is deferred deliberately
rather than inherited by accident.

### A4. The `class` and `body` fields, which are in the code and not in the spec

FORMAT-SPEC.md contains zero occurrences of `"class"` and zero of `"body"`. Both are fields I
added to the asset format while building C1, and both are load-bearing.

`class` is the budget class — `small_prop`, and so on. It's what ties an asset to
`budgets.json`, which is what stops somebody shipping a chair made of four hundred bricks.
`core:table` declares `small_prop` and its seven parts sit inside that class's 3–8 range.

`body` is the physics-body hint: whether an asset builds as one rigid body or many. The
sandbag wall is 114 bodies; the crate is one.

**Decided: both stay, and FORMAT-SPEC §6 is amended to spec them.** Both are load-bearing and
neither has caused trouble; the amendment states that `class` is optional and falls back to
`kind`, that a variant inherits rather than restates it, and why `body` is a decision the
author has to make rather than one the format can infer. They go into MODDING.md as public
surface with the same wording.

---

## B · The spec text was wrong or behind the code — amended 30 Jul 2026

Nothing here was a design question. All seven landed in one spec-amendment pass alongside
the A decisions.

**B1. MATERIAL-SPEC §5 says "Thirty materials covers ancient through modern. If an era
genuinely needs a thirty-first…"** — and 33 ship. The sentence was written as a discipline
device and it's already been overrun by three. Amendment: state the real number, keep the
discipline, and make adding a material require a written justification the way palette
entries do.

**B2. ART-BIBLE's palette table names colours in uppercase abbreviations** — `SBAG`, `GUN`,
`PACK` — while ART-BIBLE line 256 states that naming is `era_class_name` in snake_case. The
doc contradicts its own rule. `palette.json` uses the snake_case forms, which match
FORMAT-SPEC's own examples. One of them changed meaningfully rather than cosmetically:
ART-BIBLE's `PACK` (`#584c39`, "webbing, packs, straps") ships as **`webbing`**, because a
colour called `pack` sitting next to `pack.json` and pack ids is a trap somebody falls into.
Amendment: the spec table gets rewritten to match the file.

**B3. FORMAT-SPEC §10's refusal list doesn't mention checking `format`.** §11 line 3 does say
every file carries `"format": N`, and the validator does check it — so the rule is real and
enforced but appears in the wrong section. Amendment: add it to §10 where the other refusals
live.

**B4. EARTH-SPEC §8 was supposed to supply ice, glass and water material numbers and doesn't.**
EARTH-SPEC mentions water in four places — wet ground and angle of repose, a per-map water
level, and an explicit "full water simulation is not in scope" — but never gives the material
figures. Nothing needs them yet. Amendment: either write them or say plainly they arrive with
the era pack that first needs them.

**B5. `palette.json`'s own header says "seven of the twenty entries below are over the line."**
Six are. I counted them by hand when writing the comment and by machine when checking this
list. Amendment: one word.

**B6. RIG-SPEC §2 and §6 assert a physical-constraint budget per object and per scene, and
state no numbers.** This is why one of the validator's dormant rules is dormant. It can't be
amended from a desk — the numbers come out of C2, when there are actual rigs to measure.
Flagged here so it's not mistaken for an oversight.

**B7. FORMAT-SPEC says `hollow: true` "applies a shell approximation" and never says how
thick the shell is.** The code fixes it at one module — `SHELL_MODULES := 1` — which is the
thinnest thing the grid can express and is the direct cause of A1. An author reading the spec
cannot work out what their crate will weigh. Amendment: state the thickness, and state that
it is a consequence of the module size rather than a tunable.

FORMAT-SPEC also says, in the same paragraph, that reaching for an explicit `mass` "usually
means the material is wrong." For hollow shells at this module size it usually doesn't — it
means the shell is thicker than the real object's walls. That sentence needs softening
whichever way A1 goes.

---

## C · Calls I made where the specs were silent

All reversible. Read these as notification rather than a list of questions.

**C1. `core` is itself a pack, and the dependency cascade couldn't see the edge that made it
one — now fixed.** `res://packs/core` has its own `pack.json` like anything else. In load order it gets
an implicit incoming edge from every other pack, so it always sorts first — `pack_set.gd:218`
does that explicitly, with the reasoning that a pack handed a content set core hasn't filled
in yet is worse than a pack that waits. But the *disable cascade* only walks declared
`depends`. So if core were ever refused, a pack that extends `core:` without a `depends`
entry wouldn't be cascaded off — it would load, then fail at resolution with "no enabled pack
publishes it". That's a worse message than the true one, and it sends an author to look at
their own file for a problem nowhere near it. Unreachable in the shipped game — a core that
will not load is its own fatal path — but the cascade should be true on its own terms rather
than because nothing happens to exercise it. **Fixed in `_cascade()` and asserted in
`case_pack_order.gd`**, which refuses core against the real pack root and checks that
`testpack` goes down carrying core's reason rather than being blamed itself.

**C2. Extending `core:` needs no `depends` entry.** `core_version` on the manifest already
*is* a declared dependency with a semver range, so asking for a second one would make every
pack in existence write the same line. Every other cross-pack `extends` is refused unless
declared. Core is the only exception, and it's the only one.

**C3. Core is versioned `0.<milestone>.<fix>` and currently sits at `0.1.0`.** So C2 ships
`0.2.0`. Nothing specced this; it means packs can write `"core_version": ">=0.1.0"` and have
that mean something concrete, and it means 1.0.0 is a statement about the format being frozen
rather than about the game being finished.

**C4. Godot's JSON parser accepts trailing commas, and `get_error_line()` is zero-based.**
Neither is documented anywhere. The first means a pack file that would be rejected by every
other JSON tool loads fine here, which is a compatibility trap for modders round-tripping
through other software. The second cost me a debugging session and is now compensated for at
the one place line numbers are produced.

**C5. An asset with no `collider` gets a fitted envelope rather than a refusal.**
`PartPlacement.envelope()` computes the bounding box of the placed parts and uses it. The
alternative was making `collider` mandatory, which would mean every three-brick prop carries
a hand-written box that is exactly its own bounding box. Assets that need something other
than their envelope — the watchtower, the table — declare one.

**C6. `PartRules` enforces FORMAT-SPEC §5's `[d, d, length]` size convention for cylinders**
and `[d, d, d]` for spheres, with a refusal rather than a silent reinterpretation. §5
describes the convention and never says what happens when an author writes `[4, 6, 4]` for a
cylinder. It's now an error naming the rule.

**C7. `--pack-root` folders sort after the shipped ones.** FORMAT-SPEC §9 covers load order
between packs and says nothing about load order between *roots*. The rule I picked is that a
root added on the command line can never displace a shipped pack, because a diagnostic flag
that changes which content wins is a diagnostic flag that lies.

**C8. The command line is diagnostic-only, on purpose, and that policy lives in `cli.gd`
rather than in a spec.** No flag can change how the game plays. A command line that can means
two people on the same build are playing different games, which is a support burden with no
upside for a moddable sandbox. Worth promoting into a spec if you agree with it.

**C9. Exit code 4, `CLI_FAILED`, joins 3, `BOOT_FAILED`.** A question the game can't answer
exits distinctly from a game that couldn't start. CI can tell them apart; a human running the
resolver can too.

**C10. `game/tests/fixtures/broken` ships in the repo.** Two packs that are wrong on purpose
— four bad fields in one part, and an `extends` onto an asset nobody publishes. They're
separate packs because a missing base is caught a pass earlier than a bad field, and a pack
with both is disabled before the field validator ever runs. They're the worked example in
MODDING.md, so they're documentation as much as test data.

**C11. `MODDING.md` is a new root doc that wasn't in the spec set.** FORMAT-SPEC is the
normative document and it is not a thing a first-time modder should have to read. MODDING.md
is the companion: id claims and what renaming one costs, extended assets as public interface,
the two diagnostic commands, and the six rules that catch a first upload.

**C12. Scene layout is code, not data.** `sandbox.gd`'s `LAYOUT` is a table of ids and
positions rather than a sequence of spawn calls, which makes turning it into a file later a
reader instead of a rewrite. The map format is C7's problem and I didn't want to invent half
of it here.

**C13. `AssetBuilder` was split, and `part_rules.gd` is at 294 lines against a 300 cap.**
Part placement now lives in its own `part_placement.gd`. `game/core/content/` is 3,914 lines
across thirteen files. `part_rules.gd` needs a deliberate split in the next milestone or two
— flagging it before the cap forces a rushed one.

**C14. The two tables stayed in the world.** `core:table` and `core:table_map` were authored
to *close* C1 — a new prop as one JSON file and nothing else, then a variant of it in five
lines — and I kept them in the sandbox rather than deleting them after the demonstration.
Deleting a proof after proving it turns a done-condition into a story about something that
used to work. They're also era-neutral furniture the world didn't have.

**C15. `--shot` and `--settle` moved into the game's own CLI parser.** The screenshot tool
used to read positional arguments, which meant a fumbled invocation quietly wrote a picture
to a file named `--rendering-driver`. A process has one command line and two parsers reading
it disagree the moment either grows a flag.

**C16. The C0 "brick" was a 540 kg sandbag,** because the greybox's brick was hay-bale sized
and nobody had derived a mass yet. Fixed when real densities landed; the drop height in the
sandbox is now tied to the smallest object in the world rather than the largest.

**C17. `ContentModule.summary()` existed and was never called** for three commits. It's wired
into the boot log now. Mentioned because it's the exact shape of thing that rots.

**C18. `case_geometry.gd` asserted a winding convention it wasn't actually measuring.** The
wedge and the corner wedge are built by hand, so their winding is a decision rather than a
consequence, and the test now measures it.

---

## D · Deliberately deferred

**D1. Three validator rules are DORMANT and say so at every boot.** A written rule that
silently doesn't run is worse than one nobody wrote, because everyone downstream builds as
though it were holding — so they're reported rather than skipped. They are: `anim` keys
aren't checked against core animation states (core has no state list yet); the
physical-constraint budget isn't enforced (see B6); and derived-material multipliers aren't
checked — the ×0.5–×2.0 bound, and `class`/`failure`/`hardness` being un-overridable, need
the pack-material resolver from MATERIAL-SPEC §8, which isn't built.

**D2. The animation style guide.** Deferred until there's a running game to write it against.
It gates C2's shape and it's why D1's first rule is dormant. Writing it from a desk would
produce a document about animation in general rather than about this game's.

**D3. The audio direction doc.** Same reasoning, less urgency — nothing depends on it before
C5.

**D4. Shaders and texture packs.** No pack shaders, permanently, per the earlier decision:
the three-tier art law is the entire reason the game will look coherent with a thousand
uploads in it, and a pack that can ship a shader can opt out of it. Noted here because it's
the deferral most likely to be asked about again.
