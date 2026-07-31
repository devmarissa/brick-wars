# Where the C4 build and the specs disagree

Running list, opened at the start of C4. `DEVIATIONS-C1.md` through `DEVIATIONS-C3.md` are the
closed ones; read the relevant one before assuming a mismatch is a bug.

Same sorting as before — by what I need from you, not by subject.

**A** — forks worth a decision.
**B** — calls made where the specs said nothing, or said a range.
**C** — structural notes.
**D** — policy lines with no test that fails when you break them.

---

## A · One fork, and it is about the plan rather than the code

### A1. `BUILD-ORDER` schedules no input layer, at C4 or anywhere

Not a deviation from a spec — a gap in the plan, found by looking for the milestone that unblocks
you and not finding one.

Your locomotion feel-check has been waiting since C2. I said last session it was "blocked until
C4"; that was wrong, and worth correcting rather than quietly restating. C4 is *verbs, combat and
tools*. Reading the rest: C5 is destruction, C6 is vehicles, C7 is modes and AI, C8 is netcode.
**Nothing in the nine milestones builds a thing that reads a key.**

That is survivable and has been survived three times, because every milestone so far has been
demonstrated without one: `Walker` drove locomotion in C2 with nobody at the controls, `DemoGround`
dug a trench in C3 with no spade in anyone's hands, and C4's done-condition — *"a weapon defined in
data fires"* — is a sentence a test can ask for directly. So this does not block C4 and I am not
building one inside it. I built a player controller mid-C2 and you reverted it; the circumstances
here are close enough that I have not repeated it.

But three things you have already asked for are *only* answerable with hands on a keyboard, and all
three are currently `[~]` waiting on nothing in particular:

- the locomotion feel-check (`CHECKLIST` §2)
- horse gait realism — trot and walk timings read wrong to you and tuning them is a feel loop
- the creature-vs-creature collision fling, which needs someone deliberately walking into things

**What I need from you:** where this goes. It is a small milestone — input map, a camera, a
controller on the existing `Walker` — and it is genuinely blocking your half of the work rather
than mine. My reading is that it is worth slotting in before C5 rather than after C8, but it is
your plan and the ordering has been right so far.

---

## B · Calls made where the specs said nothing

### B1. The vocabulary is closed in code and described in data

`CORE-SPEC` §2 fixes the ten verbs and says packs cannot add one. It does not say where the list
lives. `VerbSet.VOCABULARY` is a `const` in GDScript and `verbs.json` supplies each verb's detail;
the loader refuses a file that adds a verb *or* omits one.

The split is copied from `SlotSet.KINDS`, which states the reasoning for it: a data file that
*could* add one would imply a pack may. Putting the whole vocabulary in JSON would have read as an
extension point. Putting the whole thing in code would have hidden ten paragraphs of reasoning
about what each verb is for in a file nobody reads for that.

### B2. A slot chooses its verbs; assets have no `verb` field

`FORMAT-SPEC` §7 gives weapons a `slot`, `stats` and `anim`, and never mentions verbs. So the
question "how does a weapon say what it does" had to be answered, and the answer is that it does
not: `verbs.json` lists, per verb, the archetype slots that dispatch it. A pack picks `ranged_slow`
and thereby picks `fire`.

The consequence is the one worth having. "Packs cannot define new verbs" stops needing enforcement,
because **there is nowhere in the asset format to write one down.** A rule that cannot be broken
beats a rule that is checked.

A slot may appear under more than one verb. `melee_light` is under both `melee` and `dig` — an
entrenching tool digs a hole and hits people, which is why it was issued — and a tidier one-verb
-per-slot model would have had to invent a `tool` slot to hold shovels, which is an era-shaped
category of exactly the kind `slots.json` says it is avoiding.

### B3. `build` is reserved to C5, though C4's sentence lists it

`BUILD-ORDER`'s C4 paragraph names all ten verbs, including `build`. Its **done-condition** names
only firing. I have declared `build` and reserved it to C5.

The argument: placing a sandbag wall is a couple of hours' work, and a sandbag wall that does not
yet topple sideways where a clay one slumps is a prop with a placement cost. C5 is the milestone
that *"switches material behaviour on"* and whose own done-condition names that exact sandbag-versus
-clay distinction. Building `build` in C4 would produce something that looks finished and would have
to be revisited the moment materials arrive.

Reversible if you disagree — it is a status field and an arm on the dispatcher.

### B4. Which milestone owns each reserved verb

`enter` and `man` → C6, `interact`, `carry` and `signal` → C7. Those follow from the milestone text
directly (C6 names multi-crew seats and enter/exit by name; C7 names the supply chain, capture and
the AI behaviour set). `carry` gets C7 rather than C4 on the argument that carrying is cargo and
loadout is kit — C4 decides what a soldier is *holding*, and walking an ammunition crate forward has
no purpose until there is a supply chain that makes the walk worth making.

`man` and `fire` both list the gun slots, deliberately. Manning a gun and firing it are different
verbs on the same object, and modelling them as one would collapse the two-soldier crew case that
C6 exists to build.

### B5. `dig`'s two numbers are invented

`MAX_BITE_CM = 25` and `MAX_THROW_CELLS = 1`. No spec states either.

The bite limit is not a limit for its own sake: it is what puts digging on a clock. A caller asking
for a metre asks four times, and the settle queue slumps *between* the bites rather than all at once
after them — which is the difference between earth moving and earth teleporting. The throw limit is
one cell because a soldier with a shovel throws to the side of the hole and not across the road, and
it is what makes a parapet appear on the side you dug from without anything deciding that it should.

Diagonals are allowed. Restricting spoil to the four orthogonal neighbours would have been a grid
artefact rather than a constraint.

---

## C · Structural notes

### C1. `earth` was still declaring itself a stub after C3 shipped

Found while reading the manifest at the start of C4, not while closing C3 — a loose end from the
previous milestone rather than a deviation in this one. `earth_module.gd` still returned
`module_is_stub() == true` with the whole field, mesher, settle queue and event log behind it.

Fixed, with the same shape of note `rig` got at C2: what the bar was, that it was walked, and what
the module still does not do (single-span columns until C3b, no blast, no render LOD). The stub
literal in `case_module_graph.gd` is one name shorter, and it now also asserts that `verbs` and
`combat` *are* still stubs — so C4's own un-stubbing has to be a deliberate edit rather than a
side effect.

### C2. Two files, not one, for the verb system

`verb_set.gd` is the vocabulary and its refusals; `verbs.gd` is dispatch. They were one file for
about ten minutes. The seam is real rather than a line-count dodge: the vocabulary is core data with
rules about it, and dispatch is control flow — and a dispatcher that also owned the loader would be
the thing every verb has to reach through, which is how the old build's 1,500-line `main.gd`
started.

Per the same reasoning `dig` is its own file. Each verb owns its arguments and its refusals, and
`verbs.gd` knows only how to route. A dispatcher that knew every verb's arguments would be the file
this project exists to not rebuild.

### C3. The suite could report a case as passing when it had crashed

Not a deviation from a spec — a hole in the gate, found by accident and worth writing down because
it silently weakened every milestone before this one.

When GDScript hits a runtime error it prints, abandons the current function, and returns to the
caller. A test case whose body dies halfway through therefore reports as **passed**, with fewer
checks than it should have had and nothing anywhere saying so. `case_fire.gd` called a method that
does not exist on `ResolvedAsset`; four of its five sections died on their first line; the suite
said `ok fire 9 checks` and the gate went green.

`tools/check.sh` now fails when the test log contains an error that is never deliberate —
`Nonexistent function`, `Invalid call`, `Invalid access`, and the two `Trying to` forms. Cases that
provoke `push_error` on purpose (the module boundary refusals, the validator's) do not match,
because those are error *messages* rather than the engine reporting the script itself is wrong.

It earned itself on the run it was added: the very next failure was `VerbFire.reload(...)` silently
resolving to `GDScript.reload()`, the engine's own script-reload method, which takes one argument
and has nothing to do with weapons. Renamed to `refill`. That would have shipped.

**Worth knowing:** this guard is a net, not a proof. A case that returns early for a reason other
than a crash still passes quietly. The stronger fix is a sentinel every case has to reach, which is
28 files of ceremony and has not been done.

---

## D · Policy lines with no test that fails when you break them

### D1. `partial` is a declared status that nothing uses

`VerbSet.STATUSES` allows `live`, `partial` and `reserved`. Nothing is `partial` at HEAD, so the
value is unexercised — a `partial` that was silently treated as `reserved` would pass the suite.

It is there rather than removed because `throw` becomes exactly that inside C4: the flight is C4's
and the detonation is C5's, which is the same split already drawn at C3 where `EarthCrater` is the
earth's half of an explosion and not the explosion. Calling that either "live" or "reserved" is a
lie in one direction. The value gets its test in the diff that makes `throw` fly, and if that diff
does not happen, this line should be deleted rather than left as an option nobody took.
