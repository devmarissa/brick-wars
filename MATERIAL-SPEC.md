# BRICK WARS — Materials

*What everything is made of, and therefore what happens when you hit it.*

Materials are the missing core system. Until now a brick was a brick and a sandbag was a
brick that happened to be beige. This spec makes "a brick is harder than cloth, and packed
earth behaves differently from a stacked sandbag wall" a property of the world rather than
a thing we hand-wave per object.

It sits alongside `EARTH-SPEC.md` — the two were written together, because the earth is
just the largest thing made of materials.

---

## 1 · The rule

> **Every part, brick and terrain span carries exactly one material, referenced by name.
> The material decides mass, how it breaks, what it holds up, what tool touches it, and
> whether it burns.**

Named references, not raw numbers — exactly like colours (`FORMAT-SPEC` §4), for exactly
the same reason. If a modder could type in their own integrity value, the workshop would
fill up with unbreakable crates inside a week. A pack asks for `"material": "sandbag"` and
gets the same sandbag behaviour as everything else in the game.

The core ships one material set spanning every era, ancient to modern. Packs choose from
it. §8 covers the narrow, bounded way a pack can add one.

## 2 · What a material carries

**Identity**

| Field | Notes |
|---|---|
| `id` | name, e.g. `clay`, `sandbag`, `armour_plate` |
| `class` | `earth` · `stone` · `wood` · `metal` · `fabric` · `other` — drives default resistances, audio and VFX |

**Mass**

| Field | Notes |
|---|---|
| `density` | kg/m³. **Mass is derived**: volume × density. A stone block is heavy because stone is heavy, not because someone typed a number. |

`FORMAT-SPEC` §6's `mass` field becomes an override for the rare case where derived mass
is wrong (a hollow crate, a fuel drum). Default is derived.

**Destructibility**

| Field | Notes |
|---|---|
| `integrity` | damage absorbed per m³ before failing |
| `resist` | multiplier per damage type (§3); below 1 = resistant |
| `failure` | `shatter` · `crumble` · `splinter` · `tear` · `deform` · `burn_through` |
| `spall` | does breaking it throw fragments that hurt people nearby? |

`spall` is small but it makes cover choice tactical: sheltering behind stone means taking
chips when it's hit, sheltering behind earth doesn't. Concrete is the worst offender,
which is historically correct and gives sandbag revetment a real reason to exist.

**Structural support** — the sandbag insight, made numeric

| Field | Notes |
|---|---|
| `support_vertical` | load it carries in compression |
| `support_lateral` | resistance to being pushed or toppled sideways |
| `cohesion` | how strongly it binds to its neighbours |
| `angle_of_repose` | granular materials only, degrees — steeper than this and it slumps |
| `shoreable` | can revetment/timbering hold it steeper, and by how much |

**This is the whole of your observation, and it falls out of three numbers.** A stacked
sandbag wall has good `support_vertical`, poor `support_lateral` and near-zero `cohesion` —
so it stops bullets and eats blast beautifully, and then a tank shoves straight through it
and a near miss topples it as loose units. Packed clay has high `cohesion` and a 55° angle
of repose — so it doesn't topple at all, it *slumps*, and only when you over-steepen it.
Same system, two completely different feels, no special-case code.

**Tool gating**

| Field | Notes |
|---|---|
| `hardness` | integer tier 0–5 (§4) |
| `work_rate` | speed multiplier once you *can* work it — clay is slower than loam |

**Fire**

| Field | Notes |
|---|---|
| `flammability` | 0 = won't burn, 1 = catches instantly |
| `burn_rate`, `fuel` | how fast and how long |
| `spread_radius` | how far it reaches neighbours |
| `on_burnt` | `ash` · `charred` · `gone` — what it leaves behind |
| `smoke` | volume; concealment as well as feel |

**Surface** — `footstep`, `impact`, `friction`, `roughness`, and the default palette
colours for this material. Free hooks now that materials exist at all.

## 3 · Damage types

Six, closed set. Every material has a resistance multiplier for each.

`kinetic` (bullets, arrows, fragments) · `blast` · `crushing` (rams, falling debris,
direct artillery) · `cutting` (blades, saws, cutters) · `fire` · `dig` (tools)

Class defaults, overridable per material. Numbers are *damage taken*, so lower is tougher:

| class | kinetic | blast | crushing | cutting | fire | dig |
|---|---|---|---|---|---|---|
| earth | 0.15 | 0.50 | 0.70 | 0.30 | 0.00 | 1.50 |
| stone | 0.30 | 0.80 | 1.20 | 0.15 | 0.05 | 0.40 |
| wood | 0.60 | 1.00 | 0.90 | 1.60 | 2.00 | 0.80 |
| metal | 0.50 | 0.70 | 0.60 | 0.80 | 0.10 | 0.20 |
| fabric | 0.40 | 0.60 | 0.50 | 2.50 | 2.20 | 1.20 |

Read across a row and the material's personality is right there. Stone shrugs off a blade
and shatters under a hammer. Earth swallows bullets and is trivially dug. Fabric stops
almost nothing but a knife goes through it like it isn't there.

## 4 · Hardness tiers & tool gating

| Tier | Materials | Worked by |
|---|---|---|
| 0 | loose sand, snow, ash | bare hands |
| 1 | topsoil, loam, gravel, sandbag, rubble | shovel |
| 2 | clay, hardpack, chalk, timber, ice | shovel (slow), pick, axe |
| 3 | soft stone, brick, sheet metal, wire | pick, sledge, cutter |
| 4 | hard stone, concrete, iron | drill, charge |
| 5 | reinforced concrete, steel, armour plate | charge, cutting torch |

A tool declares `tool_power`; it works material where `tool_power >= hardness`.

> **Rule: a tool that can't do the job says so.** *"Your shovel won't cut chalk — you need
> a pick."* Never a silent no-op, never an animation that plays and achieves nothing. This
> is the entire cost of tool gating, and it's cheap to pay.

The upside is that hardness gives each era its own texture in how it breaks the world —
ancient does everything by hand and by fire, gunpowder brings the charge, modern brings
the drill and the torch — with no era-specific code anywhere.

## 5 · The sanctioned material set

Closed list, same discipline as the primitives (`ART-BIBLE` §1b) and the constraint types
(`RIG-SPEC` §6). Abbreviated: `dens` kg/m³ · `hd` hardness · `int` integrity · `vert` /
`lat` support · `coh` cohesion · `rep` angle of repose · `flm` flammability.

**Earth** — the diggable substrate (`EARTH-SPEC`)

| id | dens | hd | int | vert | lat | coh | rep | flm | failure |
|---|---|---|---|---|---|---|---|---|---|
| `sand` | 1600 | 0 | 5 | 30 | 5 | 5 | 30° | 0 | crumble |
| `topsoil` | 1300 | 1 | 8 | 35 | 12 | 20 | 35° | .05 | crumble |
| `loam` | 1400 | 1 | 10 | 40 | 15 | 25 | 38° | 0 | crumble |
| `gravel` | 1700 | 1 | 8 | 45 | 8 | 5 | 36° | 0 | crumble |
| `mud` | 1750 | 0 | 4 | 15 | 5 | 20 | 15° | 0 | crumble |
| `clay` | 1900 | 2 | 22 | 60 | 35 | 55 | 55° | 0 | crumble |
| `hardpack` | 2000 | 2 | 30 | 70 | 45 | 60 | 60° | 0 | crumble |
| `chalk` | 2100 | 2 | 28 | 65 | 40 | 60 | 65° | 0 | crumble |
| `snow` | 400 | 0 | 3 | 10 | 3 | 15 | 35° | 0 | crumble |

**Stone & masonry**

| id | dens | hd | int | vert | lat | coh | rep | flm | failure |
|---|---|---|---|---|---|---|---|---|---|
| `rubble` | 1500 | 1 | 6 | 35 | 6 | 3 | 40° | 0 | crumble |
| `brick_masonry` | 1900 | 3 | 50 | 80 | 45 | 65 | — | 0 | shatter |
| `soft_stone` | 2300 | 3 | 55 | 85 | 60 | 70 | — | 0 | shatter |
| `hard_stone` | 2700 | 4 | 80 | 95 | 75 | 80 | — | 0 | shatter |
| `concrete` | 2400 | 4 | 85 | 95 | 70 | 85 | — | 0 | shatter |
| `reinforced_concrete` | 2500 | 5 | 130 | 99 | 90 | 95 | — | 0 | deform→shatter |

**Wood**

| id | dens | hd | int | vert | lat | coh | rep | flm | failure |
|---|---|---|---|---|---|---|---|---|---|
| `plank` | 600 | 2 | 20 | 45 | 25 | 50 | — | .80 | splinter |
| `timber` | 700 | 2 | 35 | 70 | 40 | 60 | — | .70 | splinter |
| `log` | 750 | 2 | 45 | 75 | 45 | 60 | — | .60 | splinter |
| `charred_timber` | 400 | 1 | 8 | 20 | 10 | 30 | — | .30 | crumble |

**Fabric & filled**

| id | dens | hd | int | vert | lat | coh | rep | flm | failure |
|---|---|---|---|---|---|---|---|---|---|
| `canvas` | 300 | 0 | 2 | 2 | 2 | 40 | — | .85 | tear |
| `thatch` | 200 | 0 | 3 | 5 | 3 | 20 | — | 1.0 | burn_through |
| `hide` | 900 | 1 | 8 | 5 | 4 | 45 | — | .50 | tear |
| `rope` | 900 | 1 | 12 | — | — | — | — | .60 | tear |
| `wicker` | 1400 | 1 | 15 | 50 | 20 | 30 | — | .70 | tear |
| `sandbag` | 1500 | 1 | 18 | 55 | **8** | **5** | — | .15 | tear→crumble |

`sandbag` overrides its class resistances: `blast 0.25`, `kinetic 0.20`. Sandbags are the
best blast absorber on the list and among the best against bullets — and they still fall
over if you push them. That combination is why every era from Vauban to Helmand used them.

**Metal**

| id | dens | hd | int | vert | lat | coh | rep | flm | failure |
|---|---|---|---|---|---|---|---|---|---|
| `wire` | 7800 | 3 | 10 | — | — | — | — | 0 | tear |
| `sheet_metal` | 7800 | 3 | 25 | 20 | 15 | 80 | — | 0 | deform |
| `iron` | 7200 | 4 | 70 | 90 | 70 | 90 | — | 0 | deform |
| `steel` | 7800 | 5 | 95 | 95 | 85 | 95 | — | 0 | deform |
| `armour_plate` | 7800 | 5 | 140 | 99 | 95 | 99 | — | 0 | deform |

**Other** — `ice`, `glass`, `water` (`EARTH-SPEC` §8).

**Thirty-three materials, as shipped at C1.** This section was written saying "thirty", as a
discipline device rather than a count, and building the thing overran it by three before any
era pack existed. Amended 30 Jul 2026 to say the real number, because a limit that quietly
slides is not a limit.

The discipline it was reaching for still stands, and now has a mechanism instead of a
sentence: **adding a material is a core change request and needs a written justification in
`materials.json`, the same way a palette entry over the saturation law needs a `why`.** The
bar is that an era needs a behaviour the existing thirty-three cannot express — not that it
needs a different-looking version of one of them. Colour is not a material.

## 6 · Two loops this system produces for free

Worth writing down, because they're the argument that materials earn their complexity.

**The sandbag parapet.** Built from low-cohesion units: excellent against `kinetic` and
`blast`, so it's real cover. Poor `support_lateral`, so a tank drives through it and a
close shell topples a section as loose bags rather than a crater. Hardness 1, so a shovel
takes it apart — sapping a parapet is a thing you can actually do. Nobody wrote parapet
code; it's four numbers.

**Medieval siege mining, in full, with no special-case code:**

1. Dig a tunnel under the wall — `chalk`, hardness 2, holds a 65° face (`EARTH-SPEC` §6)
2. Prop the roof with `timber` — `support_vertical` 70 holds the span
3. Pack it with brush and light it
4. Fire consumes the props: `flammability` 0.70, `on_burnt: charred`
5. `charred_timber` has `support_vertical` 20 — the span exceeds what the props hold
6. The tunnel collapses, the ground subsides, the wall above it comes down

That is how mining actually worked, and here it's an emergent consequence of six material
properties. It also works in reverse for Great War: the same code path is a mine gallery
under a trench line, and the same counter-play is counter-mining. **This is the payoff for
building materials into the core instead of the Great War pack.**

## 7 · Materials and the blast model

You said blowing things up felt good. That's the one piece of subjective feedback in the
project that we can't re-derive, so it gets protected explicitly:

> **The existing blast feel is the specification. Materials modulate what a blast does to
> each thing it touches; they do not touch the impulse curve, the falloff, the screen
> shake, or the timing.**

Before the earth or destruction rebuild starts, we capture it (`BUILD-ORDER` §1c): a fixed
test scene — standard wall, standard charge, locked camera — run in the archived build,
with the numbers and a screenshot sequence recorded as a **feel regression fixture**. The
rebuild has to reproduce it. That's how "it felt good" survives a rewrite instead of being
something we remember fondly and never get back.

What materials add on top: the same charge now scatters a sandbag wall, punches a hole in
brick, dents armour plate, and blows a proper crater in loam while barely marking chalk.
Same bang, different consequences — which is the version of "it felt good" that also has
tactics in it.

## 8 · Core vs pack

**Core owns**: the material list, the property schema, the six damage types, failure
modes, the hardness tiers, the support/cohesion/repose solver, fire propagation, and the
validator.

**Packs reference materials by name.** A pack may define a new material *only* by
`extends` on a core material, and only within bounded multipliers:

```json
{ "id": "great_war:duckboard", "extends": "plank",
  "colour": "wood2", "integrity": 0.8, "work_rate": 1.2 }
```

Multipliers clamp to ×0.5–×2.0 on any property, `class`, `failure` and `hardness` are
inherited and not overridable, and the derived material must still obey the resistance
table for its class. Identity is a pack's to define; physics is not. Same rule as colour,
same rule as animation states, same reason.

## 9 · What this changes elsewhere

- **`FORMAT-SPEC`** — `material` becomes a required field on every part, validated by name
  like `colour`. `mass` becomes optional and derived by default.
- **`ART-BIBLE`** — material carries default colours, so the palette and the material set
  have to agree; a material's colours must sit inside the palette law.
- **`EARTH-SPEC`** — every terrain span carries a material; soil type *is* material.
- **`CORE-SPEC` §2** — materials join the non-negotiable core system list.
- **Structural integrity** stops being a single global rule and becomes a load calculation
  against `support_vertical` / `support_lateral` / `cohesion`.
- **Audio and VFX** get their surface hooks from material rather than from guesswork.
