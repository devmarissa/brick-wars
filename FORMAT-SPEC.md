# BRICK WARS — Data Format Spec

*The part table, the asset definition, and the pack manifest. This is simultaneously
our authoring format and the mod format — there is no internal-only path.*

**Status: decided, 30 Jul 2026.** The four open questions are closed — JSON, integer
modules, namespaced ids, and `extends` with full cross-pack reach capped at three levels.
§12 records them and why. Everything below is now a contract, not a proposal.

---

## 1 · Principles

- **Data only.** No executable code in a pack (`CORE-SPEC` §5). Everything here is
  declarative.
- **One format for us and for modders.** If we need an escape hatch that packs don't
  get, the format is wrong.
- **Unviolatable by construction where possible.** The grid law and the palette law are
  enforced by the format itself, not by review discipline.
- **Readable and diffable.** A human should be able to open an asset and understand it,
  and a change should show up cleanly in version control.
- **Forward-compatible.** Unknown fields warn rather than fail; every file carries a
  format version.

## 2 · File format — **JSON** ✓

**Decided: JSON.** Modders already know it, every tool on earth reads it, it
diffs cleanly, and Godot parses it natively. The costs are no comments and some
verbosity. Alternatives considered: Godot `.tres` (native and fast, but alien to modders
and horrible to diff), TOML (comments and less noise, needs a parser), and a custom
format (never worth it).

Mitigation for load speed: JSON is the *authoring* format; the loader can bake a binary
cache on import. Modders never see the cache.

## 3 · Units — **integer modules** ✓

**Decided: integer modules.** One module = 0.1 m (ART-BIBLE §1). All sizes,
offsets and pivots are whole numbers of modules.

```json
"size": [4, 2, 2]     // 0.4 × 0.2 × 0.2 m
"offset": [0, 18, -3] // 0 m, 1.8 m up, 0.3 m forward
```

Why integers rather than metres: the grid law becomes impossible to break rather than
merely discouraged, there's no float drift or `0.30000000000004`, and diffs are clean.
The cost is a small mental conversion — mitigated by editor tooling showing metres.

The alternative was metres-as-floats with validation rejecting anything off-grid. That
reads more naturally but makes the law a check rather than a guarantee, and at this
scale the guarantee is worth more than the readability. Editor tooling shows metres, so
the cost lands on the tooling rather than on every asset ever authored.

**Rotations** are in degrees, and restricted to multiples of 15° for blocks. Primitives
and rigged parts may use any integer degree.

## 4 · Colours

Packs reference palette entries **by name only. Hex literals are rejected by the
validator.** This is how the palette law (ART-BIBLE §2) is enforced rather than hoped
for.

```json
"colour": "wood"          // core palette
"colour": "faction_a"     // resolved from the pack's palette.json
"colour": "faction_a_dark"
```

A pack may add named colours in its `palette.json`, but they're validated against the
value and saturation bounds in ART-BIBLE §2 and rejected if they're out of range.

### 4b · Materials

**Materials work exactly like colours: named references only, resolved against the core
material set** (`MATERIAL-SPEC` §5). A part's material decides its mass, how it breaks,
what load it carries, what tool works it and whether it burns — so this is the single
most consequential field on a part after `size`.

```json
"material": "sandbag"
"material": "brick_masonry"
```

Every part carries exactly one. It's **required** — there is no default, deliberately, so
that nobody ever ships a stone wall that behaves like timber because they forgot a line.
The validator names the file and the part.

Materials also supply **default colours**. A part may override `colour` within the
material's declared colour set, but not outside it; `sandbag` cannot be gunmetal. This is
what keeps a thousand workshop packs from each inventing their own idea of what sandbags
look like.

A pack may derive a material via `extends` within bounded multipliers — `MATERIAL-SPEC` §8
has the rules.

## 5 · The part object

```json
{
  "name": "barrel",
  "shape": "cylinder",
  "offset": [0, 3, -14],
  "rotation": [0, 0, 0],
  "size": [3, 3, 22],
  "material": "steel",
  "colour": "gunmetal",
  "jitter": 0.0,
  "parent": "receiver",
  "joint": { "type": "hinge", "axis": "x", "limits": [-30, 45], "rest": 0 }
}
```

| Field | Required | Default | Notes |
|---|---|---|---|
| `name` | only if parented or IK-targeted | — | unique within the asset |
| `shape` | no | `"block"` | `block` · `wedge` · `corner_wedge` · `cylinder` · `sphere` (ART-BIBLE §1b) |
| `offset` | yes | — | modules, relative to parent (or asset origin) |
| `rotation` | no | `[0,0,0]` | degrees |
| `size` | yes | — | modules; cylinders use `[diameter, diameter, length]`, spheres `[d,d,d]` |
| `material` | **yes** | — | material name (§4b) — no default, on purpose |
| `colour` | no | material default | palette name, must be in the material's colour set |
| `jitter` | no | `0.0` | forced to 0 on non-block shapes (ART-BIBLE §1b) |
| `parent` | no | asset root | makes this a rigged child |
| `joint` | no | `fixed` | see `RIG-SPEC` §3; limits mandatory on non-fixed |

**Origin convention**: asset origin is at ground contact, centred in x/z. **Facing**: `-Z`
is forward, always (ART-BIBLE §7).

## 6 · Asset definition

```json
{
  "format": 1,
  "id": "core:prop_crate_small",
  "kind": "prop",
  "name": "Small Crate",
  "parts": [
    {"offset": [0, 3, 0],  "size": [6, 6, 6], "material": "plank", "jitter": 0.05},
    {"offset": [0, 3, 3],  "size": [7, 1, 1], "material": "plank", "colour": "wood2", "jitter": 0.03},
    {"offset": [0, 3, -3], "size": [7, 1, 1], "material": "plank", "colour": "wood2", "jitter": 0.03}
  ],
  "collider": [{"offset": [0, 3, 0], "size": [6, 6, 6]}],
  "hollow": true,
  "destructible": true
}
```

Note there's no `mass`. **Mass is derived from volume × the material's density**
(`MATERIAL-SPEC` §2), so a stone crate is heavy because stone is heavy rather than because
somebody typed a number. `hollow: true` applies a shell approximation for containers;
an explicit `mass` field still exists as an override for the genuinely odd case, but
reaching for it usually means the material is wrong.

`kind` is one of: `prop` · `structure` · `weapon` · `vehicle` · `buildable` · `character`
· `emplacement`. Each kind adds its own stat block (§7).

**Colliders are declared separately from parts** and are always blocks — never derived
from the visual parts. This is the compound-collider lesson from the tank, written into
the format so it can't be repeated. Validator caps colliders at 4 per asset.

### Inheritance — `extends` ✓

```json
{ "id": "great_war:rifle_sniper", "extends": "great_war:rifle_bolt",
  "name": "Scoped Rifle",
  "parts+": [ {"name": "scope", "shape": "cylinder", "offset": [0, 5, -2], "size": [3,3,10], "colour": "gunmetal"} ],
  "stats": { "zoom": 4.0 } }
```

`extends` merges over a base asset; `parts+` appends, `parts` replaces. A variant costs
five lines instead of a hundred, and — more importantly — a fix to the base propagates to
every variant instead of being copied by hand into six files that then drift apart.

**Merge semantics**, defined boringly and precisely because vagueness here is where the
debugging hours go:

| Field kind | Behaviour | Example |
|---|---|---|
| scalar (`name`, `slot`, `kind`) | child replaces parent | `"name": "Scoped Rifle"` |
| object (`stats`, `anim`, `cost`) | **deep merge**, key by key | `{"zoom": 4.0}` adds one stat, keeps the rest |
| list (`parts`, `collider`, `seats`) | child **replaces** the whole list | `"parts"` wipes and redeclares |
| list with `+` suffix (`parts+`) | child **appends** to the parent's list | `"parts+"` adds the scope |
| named list member | `parts~` patches a part by `name` | see below |

```json
"parts~": [ {"name": "barrel", "size": [3, 3, 30]} ]   // longer barrel, everything else inherited
```

`parts~` is the one that saves a redeclare when you want to nudge a single part. It
matches on `name`, so a part you intend to be patchable needs one; patching an unnamed
part is an error that names the base asset.

**Chain depth is capped at 3.** `core → pack base → variant` and no further. Deep enough
for every real case, shallow enough that a resolved asset stays legible. A fourth level
fails to load with a message naming the whole chain.

**Cross-pack `extends` is allowed**, and it's the thing that lets a mod scene compound
instead of everyone restarting from core. The rules that make it survivable:

- Extending outside your own pack requires a **declared dependency with a semver range**
  in `pack.json`. Reaching into an undeclared pack is an error, not a lucky success.
- The loader **topologically sorts** packs by their dependency graph, tie-breaking by
  pack id so load order is byte-identical on every machine. Netcode depends on this.
- **Cycles are detected and refused** with both pack names, across packs and within one.
- If a base pack is missing, out of range, or has since removed the extended asset, the
  **dependent pack is disabled with a clear message naming both packs and the asset** —
  it never half-loads into a broken state, and it never takes the game down with it.
- Resolution happens **once at load time and is baked**. Nothing resolves at runtime.

This is the real cost of the decision, and it's worth naming: publishing an asset that
other packs extend makes it part of your public surface, and changing it is a breaking
change. The semver range in `depends` is what turns that from a silent break into a
refusal to load.

**The validator prints provenance.** `--resolve <asset_id>` dumps the fully merged asset
with every field annotated by where it came from:

```
size      [3, 3, 30]   ← great_war:rifle_sniper
material  steel        ← great_war:rifle_bolt
jitter    0.0          ← core (default)
```

This is not a nice-to-have. Without it, a wrong number three levels up is a bad afternoon,
and `extends` stops being a feature and becomes a trap.

## 7 · Slot stat blocks

Every gameplay asset fills a **core archetype slot** and supplies the numbers that slot
defines. The core owns the field list; a pack that invents a field gets a warning and
the field is ignored.

```json
// weapon
"slot": "ranged_slow",
"stats": { "damage": 95, "velocity": 150, "cycle": 1.15, "capacity": 5,
           "reload": 3.4, "spread": 0.16, "recoil": 0.8, "ads_fov": 60 },
"anim": { "fire": 0.12, "cycle": 1.15, "reload": 3.4, "raise": 0.35 }

// vehicle
"slot": "fast_transport",
"locomotion": { "type": "legged", "...": "see RIG-SPEC §5" },
"seats": [ {"role": "driver", "eye": [0, 22, 4], "controls": ["reins_l", "reins_r"]} ],
"stats": { "max_speed": 20, "accel": 14, "turn_rate": 2.6, "grip": 9, "health": 400 }

// buildable
"slot": "barrier",
"cost": { "spoil": 4 },
"stats": { "build_time": 2.5 }
```

A vehicle's `health` is the exception that proves the rule: it's the **crew-and-systems
pool** that decides mobility and firepower kills, not the toughness of its plating. How
much a shell does to the hull is decided by the hull's material like everything else.

Note the buildable has no `health` at all — **durability comes from its materials**. A
sandbag barrier and a stone barrier fill the same slot, cost the same to place, and behave
completely differently under fire, without either one declaring a hit-point total.

`anim` supplies **timings for existing core states only**. A key that isn't a core state
is rejected — this is the rule from `CORE-SPEC` §5 enforced by the format.

## 8 · IDs & namespacing — **`pack:asset`** ✓

**Decided: `pack_id:asset_name`**, lowercase snake_case, e.g.
`core:prop_crate_small`, `great_war:vehicle_tank_rhomboid`, `mcheves_cavalry:horse_bay`.

The pack id is the namespace, so two mods can both ship a `horse` without colliding, and
`extends` can reach across packs (with a declared dependency). Bare names are resolved
within the current pack first, then core.

Namespacing is what makes cross-pack `extends` expressible at all — `mcheves_cavalry`
extending `great_war:vehicle_tank_rhomboid` is unambiguous in a way that a bare
`tank_rhomboid` in a world of four hundred workshop packs never could be. The two
decisions hold each other up.

**Pack ids are claimed, not just chosen.** Two packs with the same id can't coexist, so
the id wants to be distinctive from day one — `mcheves_cavalry`, not `cavalry`. Worth a
line in the modding docs before the workshop opens rather than after.

## 9 · Pack manifest & folder contract

```json
// pack.json
{
  "format": 1,
  "id": "great_war",
  "name": "The Great War",
  "version": "0.1.0",
  "author": "Smokestack",
  "core_version": ">=0.4",
  "depends": [],
  "era": { "period": "1914-1918", "tone": "see style.json" },
  "factions": ["allied", "central"],
  "content": ["weapons/", "vehicles/", "buildables/", "kits/", "maps/", "modes/"]
}
```

A pack that extends another declares it with a semver range. This is what the loader
sorts on, and what turns a base-pack update from a silent break into a refusal:

```json
{
  "id": "mcheves_cavalry",
  "core_version": ">=0.4",
  "depends": [ { "id": "great_war", "version": ">=0.3 <0.5" } ]
}
```

```
packs/great_war/
  pack.json
  palette.json      faction colours (2 + 2 shadows)
  materials.json    optional: derived materials via extends (MATERIAL-SPEC §8)
  style.json        sky, sun, fog, tonemap, ambience bed, tone statement
  weapons/*.json    assets filling weapon slots
  vehicles/*.json
  buildables/*.json
  kits/*.json       classes: which slots each role gets
  audio/            weapon & vehicle voices only
  maps/*.json       earth grid + placements + objectives
  modes/*.json      mode parameter sets
  strings/*.json    display names, localisation
```

## 10 · Validation

A pack fails to load, with a message naming the file, the line, and the rule, when it:

- uses a hex colour, or a named colour outside ART-BIBLE §2 bounds
- omits `material` on any part, or names a material that doesn't exist
- gives a part a colour outside its material's declared colour set
- derives a material with a multiplier outside ×0.5–×2.0, or tries to override `class`,
  `failure` or `hardness` (`MATERIAL-SPEC` §8)
- uses a non-integer or off-grid size or offset
- uses a shape outside the five sanctioned primitives
- has under 70% block parts on an asset (ART-BIBLE §1b)
- declares more than 4 colliders, or a non-block collider
- declares a joint without limits, or a joint/constraint type not in `RIG-SPEC`
- exceeds the physical-constraint budget per object or per scene
- supplies an `anim` key that isn't a core animation state
- fills a slot that doesn't exist, or omits a required stat for that slot
- exceeds the part budget for its asset class (ART-BIBLE §5)
- declares an unmet dependency or an incompatible `core_version`
- `extends` a chain deeper than 3 levels (message names the whole chain)
- `extends` an asset in a pack it hasn't declared a dependency on
- `extends` an asset that doesn't exist, or forms a cycle (message names both ends)
- `parts~` patches a part with no `name`, or a `name` not present in the base

Warnings (load anyway): unknown fields, missing optional stats, missing audio.

**Failure is scoped to the pack.** A pack that fails validation is disabled and reported;
it never half-loads, and it never takes the game or the other packs down with it. With
cross-pack `extends` in play this matters more than it used to — one broken workshop
upload cannot be allowed to break a server's whole content set.

**The validator is a first-class feature, not a chore.** It's the difference between a
workshop that stays coherent and one that turns into a colour-clashing mess in a month.

## 11 · Versioning

Every file carries `"format": N`. The loader migrates older formats forward where it can
and refuses with a clear message where it can't. `core_version` on the manifest uses
semver ranges. Breaking the format after 1.0 requires a migration path, not a shrug.

## 12 · Decision record — closed 30 Jul 2026

All four are settled. They're written down with their reasoning because in eighteen months
somebody (probably us) will want to reopen one, and the useful thing to have then is not
the verdict but the argument.

**1 · Format: JSON.** Modders already know it, every tool reads it, Godot parses it
natively, it diffs cleanly. The cost is no comments and some verbosity; documentation
carries what comments would have. TOML would have been more pleasant to author and less
familiar to everyone else — the audience won. Load speed is handled by baking a binary
cache on import, which modders never see.

**2 · Units: integer modules.** Guarantee over readability, explicitly. A float-metres
format makes the grid law a validator check; integer modules make it *unrepresentable* to
break. At this scale — thousands of assets, most of them eventually authored by people
we'll never talk to — a law that can't be broken is worth more than one that reads
naturally. Materials strengthened this after the fact: the earth stores height as integer
centimetres so slumping is deterministic and never has to be replicated (`EARTH-SPEC` §5),
which is a large netcode saving floats would have cost us. One integer decision, two
places it pays.

**3 · IDs: `pack:asset` namespacing.** Two mods can ship a `horse` without colliding, and
cross-pack references become unambiguous. This one turned out to be a precondition for
decision 4 rather than an independent choice.

**4 · `extends`: yes, full cross-pack reach, chain depth capped at 3.** The most
consequential of the four, and the only one with a real ongoing cost. It does three jobs:
variants stop being copy-paste and stop drifting; packs get bounded material derivation,
which is the *only* sanctioned way a pack defines a material at all (`MATERIAL-SPEC` §8,
`CORE-SPEC` §5); and mods can build on other mods, so the workshop compounds instead of
everyone restarting from core.

The cost is accepted with eyes open: a dependency resolver, deterministic topological load
order, cycle detection, and the permanent reality that a widely-extended asset is public
surface that can't be changed freely. Four things keep it survivable — declared semver
dependencies, pack-scoped failure so one bad upload disables one pack, the depth-3 cap,
and validator provenance output (`--resolve`). That last one is load-bearing: without it
`extends` is a trap rather than a feature, so it ships *with* the resolver, not after it.

The narrower option — extends limited to core bases and within-pack — was on the table and
was rejected deliberately. It's the safer build, but it caps what the mod scene can become,
and a compounding workshop is a large part of why this game exists at all.

### Still open elsewhere

Not format decisions, but the things that were riding alongside these:

- **The texture question** (flat colour vs subtle per-material grain) — deferred to C3,
  when there's real ground to judge it against (`ART-BIBLE` §8).
- **The hosting model** (community-hosted vs official) — gates the entire mod security
  story, and cross-pack `extends` raises the stakes slightly since content now arrives in
  graphs rather than singly (`CHECKLIST` §17).
