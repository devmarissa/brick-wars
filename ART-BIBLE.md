# BRICK WARS — Art Bible

*The standard every asset is built to, from the first brick. If an asset doesn't
follow this, it gets rejected in review, not fixed later.*

Read this before building any model, prop, vehicle, weapon, or piece of world.
It exists so that a Roman ballista and a WW1 howitzer, built months apart, look like
they belong in the same game.

---

## 1 · The module system

Everything is axis-aligned boxes. Discipline is what separates "brick game" from
"pile of boxes."

- **MODULE (M) = 0.1 m.** Every part dimension is a whole number of modules.
  No 0.37 m boxes. `0.4`, `0.7`, `1.2` — yes. `0.375` — no.
- **Preferred stock sizes** (use these unless there's a reason): 1M, 2M, 3M, 4M, 6M,
  8M, 12M, 16M, 24M. Reaching for a stock size first keeps the world visually rhymed.
- **Position snapping**: part origins snap to 1M. Vehicles and soldiers may use 0.5M
  for fine facial/mechanical detail only.
- **Rotation**: parts are axis-aligned by default. Angled parts (roofs, plane wings,
  gun barrels at elevation) are allowed but must be *deliberate* — an angle is a
  design statement, not a modelling accident.

**Reference measurements (do not drift from these):**

| Thing | Size | Modules |
|---|---|---|
| Earth grid cell | 0.5 × 0.5 m footprint | 5M |
| Earth height quantisation | 0.01 m (continuous to the eye) | 0.1M |
| Soldier height | 1.8 m | 18M |
| Soldier shoulder width | 0.6 m | 6M |
| Trench depth (standard) | 2.4 m | 24M |
| Trench width | 2.0–2.5 m | 20–25M |
| Doorway / passable gap | ≥ 1.0 m wide, ≥ 2.0 m high | 10M / 20M |
| Step a soldier can walk up | 0.4 m | 4M |
| Vehicle track/wheel height | 0.8–1.2 m | 8–12M |

Anything a player walks through, climbs, or takes cover behind is sized off this table
first and styled second.

### 1b · Primitive vocabulary

Boxes alone can't make a gun barrel, a wheel, or sloped armour read correctly. Roblox
proved a small primitive set is enough for enormous expressive range, so we sanction
one — and *only* one. The list is closed; adding to it is a design review, not a
modelling decision.

| Primitive | Use |
|---|---|
| **BLOCK** | the default. Everything, unless there's a reason. |
| **WEDGE** | sloped armour, roofs, prows, plough blades, ramps, gun shields |
| **CORNER WEDGE** | corner transitions between wedged faces |
| **CYLINDER** | gun tubes, wheels, axles, pipes, logs, masts, barrels, drums |
| **SPHERE** | rare — cannonballs, ball joints, domes, boiler ends |

**The law that keeps this from becoming generic low-poly:**

- **The earth is earth. Built things are bricks. Machines have curves.** Three tiers, and
  the contrast between them is the whole look:
  - **The earth** is a continuous deformable surface, not blocks at all (`EARTH-SPEC`).
    Ground, craters, spoil, slumped trench walls — organic, curved, no grid.
  - **Built things** — buildings, structures, props, and everything a player builds — are
    **100% blocks, no exceptions**. Jittered, hand-stacked, imperfect.
  - **Machines** — vehicles, weapons, machinery, siege engines — are blocks plus
    primitives, clean and unjittered.

  This isn't a restriction, it's the aesthetic thesis. Brick against organic ground reads
  far better than brick against brick, and it makes construction *legible at any range*:
  **if it's rectangular, a person put it there.** A player scanning a ridge can tell
  earthwork from emplacement from vehicle by silhouette alone, before any detail resolves.

  *(Amended: terrain was previously specified as 100% blocks on a 2.5 m grid. That grid
  made a single cell taller and wider than a soldier, which read as chunky rectangles
  rather than ground. See `EARTH-SPEC` §1.)*
- **70/30 rule.** At least 70% of any asset's parts are blocks. A vehicle that's mostly
  cylinders has stopped being a brick vehicle.
- **Primitives obey the module grid.** A cylinder is 4M in diameter, not 0.37 m. Radii
  and lengths snap to 1M like everything else.
- **Primitives obey the palette and the material standard.** No exceptions, no gloss.
- **Jitter does not apply to primitives.** They're machined by definition — jitter 0.0
  always. This is a feature: a jittered box next to a clean cylinder tells the player
  "sandbag" vs "gun."
- **Colliders stay simple.** A visual primitive does not imply a matching collider.
  Cylinders and spheres may use their analytic shapes (cheap in Jolt); wedges use a box
  or convex hull. Vehicles still get 1–4 hand-fitted compound boxes overall — the
  primitive set changes what things *look* like, never the collision policy.
- **Destruction stays box-based.** When a primitive breaks, it shatters into blocks.
  One destruction system, unchanged. The earth grid remains boxes forever.

## 2 · Palette

**Rule: no asset introduces a new colour.** The palette is the whole game's colour
identity; ad-hoc colours are how a world starts looking like a toy bin. If an asset
genuinely needs a colour that doesn't exist, it gets added to the palette *file*
in a review, with a name, and then it's available to everyone.

### Core (era-neutral) — shipped in `core/data/palette.json`

Names are lowercase snake_case, matching §7's own naming rule and FORMAT-SPEC's examples.
This table was originally written in GDScript-constant abbreviations (`SBAG`, `GUN`, `PACK`)
against that rule; amended 30 Jul 2026 to match the file, which is the normative one.

One name changed meaningfully rather than cosmetically: **ART-BIBLE's `PACK` is `webbing`**,
because a colour called `pack` sitting next to `pack.json` and pack ids is a trap somebody
falls into.

| Name | Hex | Use |
|---|---|---|
| `mud` | `#5e5240` | primary earth, trench walls |
| `mud2` | `#6a5c47` | earth variation, spoil |
| `clay` | `#74604a` | subsoil, deep digs, crater interiors |
| `wood` | `#6a5138` | timber, duckboards, revetment |
| `wood2` | `#584431` | timber shadow/variation |
| `sandbag` | `#9a8a68` | sandbags |
| `sandbag2` | `#8b7c5e` | sandbag variation |
| `stone` | `#7d7a70` | masonry, ruins, roads |
| `stone2` | `#6e6b62` | masonry variation |
| `grey` | `#767468` | neutral grey, mechanical |
| `grey_light` | `#8f8c7c` | light grey, highlights |
| `black` | `#232019` | deepest value — tyres, openings, iron |
| `gunmetal` | `#2b2a24` | gunmetal |
| `tan` | `#8a7a58` | canvas, leather, rope |
| `canvas` | `#7d7460` | tarpaulin, tenting |
| `wire` | `#4a4440` | barbed wire, chain, cable |
| `skin` | `#c4a26e` | exposed skin |
| `webbing` | `#584c39` | webbing, packs, straps |
| `green` | `#5a5c42` | vegetation |
| `blue` | `#5c6660` | desaturated cool accent |

### Faction colours (per era)

Each era pack defines exactly **two faction colours plus one shadow variant each**.
Great War: `OLV #50543a` / `DOLV #3f4230` (allied drab) vs `FGREY #686d66` /
`FGREY2 #565b55` (field grey). Future eras follow the same two-and-two structure so
that faction readability code never changes.

### Palette laws

- **Value range is narrow and mid.** Nothing brighter than `#a5a5a5`, nothing darker
  than `#1a1a16`, except for emissive VFX. Saturation stays under 35%. This is what
  makes it read as *weathered materiel* instead of plastic.

  That "35%" used to read "~35%", and the tilde was doing a lot of quiet work: six of the
  twenty entries above are over it. So the law is now an exact number in `palette.json`
  (`saturation_max: 0.35`, `value_max: 0.647`, `value_min: 0.102`) and the tilde has been
  turned into a list of names. **Every entry that breaks a law carries `exempt` and a
  written `why`, and an entry that breaks one without a `why` is refused.** An exception you
  have to name and defend in the file is a different thing from a limit nobody checks.

  The exemptions as they stand: `clay`, `tan` and `webbing` are rounding, all within
  0.012 of the line. `skin` is the only entry breaking two laws — 0.439 saturation and
  0.769 value — because faces have to read at range against every terrain colour we ship.
  `wood` at **0.472** is the large one and the one most worth arguing about; it was argued
  on 30 Jul 2026 and kept, on the grounds that timber desaturated to 0.35 stops reading as
  wood and starts reading as dirt, and duckboards over mud have to be a different material
  at a glance. `wood2` at 0.443 follows it, because a shadow tone less saturated than its
  parent inverts the relationship and looks like a stain rather than shade.
- **Saturated colour is a signal, not decoration.** Bright red, orange, and cyan are
  reserved for fire, tracers, flares, blood decision, and UI. If a prop is bright,
  the player will read it as gameplay-relevant — so only make it bright if it is.
- **Faction colour is only ever on soldiers and vehicles.** Never on terrain, props,
  or buildables. Otherwise silhouette reading breaks at range.

## 3 · Shade variation & jitter (the anti-LEGO rules)

Uniform colour + perfect alignment = toy. These three tools are mandatory:

- **Per-brick shade**: `SHADES := [1.0, 0.92, 0.85, 1.06]` multiplied into the base
  colour, picked randomly per brick via `matv()`. Every repeated element (walls, bag
  stacks, roads, rubble) uses `matv()`, never `mat()` with a fixed shade.
- **Size jitter**: `spawn_brick(..., jitter)` scales x/z by ±jitter and adds slight
  random yaw. Standards: **0.0** for machined objects (weapons, vehicle hulls,
  precision structures), **0.04–0.08** for built-by-soldiers objects (sandbags,
  revetment, palisades), **0.10–0.15** for natural/ruined (rubble, spoil, rocks).
- **Deliberate imperfection in layout**: hand-built structures get a brick out of
  line, a gap, a bag knocked askew. Machines do not. The contrast between the two
  is a large part of what reads as "real."

## 4 · Silhouette & readability

The single most important quality gate. A player must identify **what** and **whose**
at a glance.

- **At 100 m**, faction is readable from silhouette + faction colour alone. Test by
  taking a screenshot at 100 m and squinting — if you can't call it, the asset fails.
- **Headgear carries faction.** Helmet shape is the fastest silhouette read in every
  era (brodie vs stahlhelm, galea vs great helm, kevlar vs cover). Every era pack
  gives each faction a distinct head profile.
- **Class carries silhouette too.** A sapper reads different from a rifleman from an
  MG gunner — pack shape, tool on the back, stance. Roles are recognisable before
  they're announced.
- **Vehicles are silhouette-first.** A WW1 rhomboid tank is unmistakable from its
  outline; that outline is the asset's job, and detail is secondary.
- **Negative space matters.** Gaps, wheel arches, and openings define an outline more
  than surface detail. Add a hole before you add a greeble.
- **Three-value rule.** Every asset uses at least three distinct value steps (dark
  base, mid body, light accent), so it doesn't flatten into a blob at distance.

## 5 · Detail budgets

Part counts are a performance contract *and* a style contract — consistent density
across assets is what makes a world feel authored.

| Asset class | Part budget | Notes |
|---|---|---|
| Small prop (crate, bucket, sign) | 3–8 | one silhouette idea, no more |
| Large prop (cart, gun limber, stretcher) | 10–25 | |
| Soldier | 14–18 | current player body is 15 — that is the standard |
| Weapon (world model) | 6–12 | |
| Weapon (viewmodel) | 12–20 | more detail allowed; it's on screen constantly |
| Light vehicle (jeep, cart, boat) | 30–50 | |
| Heavy vehicle (tank, plane) | 50–90 | |
| Emplacement (turret, arty, MG nest) | 20–40 | |
| Small building | 60–120 | |
| Large structure (church, castle keep) | 150–350 | may need chunking |

**Detail goes into form, not decoration.** If you're at budget and want more detail,
remove a greeble and improve the outline instead. Rivets do nothing at 30 m; a
correctly-shaped sponson does everything.

## 6 · Materials & lighting

**Material is now a system, not a look** — see `MATERIAL-SPEC.md`. Every part and every
terrain span carries a named material that decides its mass, how it breaks, what holds it
up, what tool touches it and whether it burns. The art consequence: **a material's default
colours live with the material, not with the asset**, so everything made of `sandbag` is
the same beige everywhere in the game, in every pack, forever. Palette law (§2) still binds
— a material's colours have to sit inside it.

Choosing a material is therefore an art decision *and* a physics decision at the same time,
and that's deliberate: if it looks like stone it should behave like stone.

- **All world materials**: `StandardMaterial3D`, `roughness = 0.85`, metallic 0.
  Matte and weathered. Do not ship glossy anything without a reason.
- **Exceptions on file**: water `roughness = 0.2`; emissive materials for fire,
  tracer, muzzle flash, flare, and UI only.
- **No unshaded materials in the world.** `SHADING_MODE_UNSHADED` is for VFX and
  debug only — unshaded geometry breaks the lighting read instantly.
- **Lighting assumptions** every asset is authored against: single directional sun
  `#f2ead8`, overcast sky top `#8a9490` / horizon `#b0b3a5`, fog `#a8ab9c`, filmic
  tonemap with glow. Assets are reviewed under these conditions, not under a
  neutral studio light.
- **Era light packs** may shift sun colour, fog density, and sky, but stay within
  the same value discipline — no era gets a saturated blue-hour or a bloom-heavy look
  without an explicit call.

### 6b · The earth's look

The ground is the largest surface in every frame, so it gets its own rules.

- **Per-vertex `SHADES` variation** (§3) applied across the terrain mesh, at a scale of a
  few metres rather than per cell. This is what stops a continuous surface reading as a
  flat plastic sheet, and it's the same trick as brick tinting.
- **Colour comes from the span's material.** A dug face exposes the material beneath it —
  cut through topsoil into clay and the trench wall is visibly clay. Free stratigraphy,
  and it makes depth readable at a glance.
- **`disturbed` ground reads differently**: spoil, crater fill and churned mud get a
  slightly lighter, noisier tint than virgin ground. A player should be able to see where
  the earth has been worked without being told.
- **Smooth normals below the 60° cliff threshold, flat normals above it** (`EARTH-SPEC`
  §2). This is the single strongest cue separating organic ground from a cut face, and it
  costs one branch in the mesher.
- **No terrain decals or blend maps.** Everything comes from material, vertex colour and
  geometry. If ground detail needs more than that, the answer is scatter props (rubble,
  tufts, debris), not a texture pipeline.

## 7 · Construction conventions (code-side)

- Assets are defined as **part tables** — arrays of
  `{shape, offset, rotation, size, material, colour, jitter}`, where `shape` is one of the
  five sanctioned primitives (§1b) and defaults to `block` — not as imperative build code. This is the format that becomes the mod format
  (VISION §2), so every new asset built from here on is authored as data.
- **Origin convention**: an asset's origin is at ground contact, centred in x/z.
  Soldiers, vehicles, props all follow this so placement code is universal.
- **Facing convention**: front is `-Z` (Godot `look_at` convention), matching the
  existing player body. Everything faces `-Z`. No exceptions.
- **Naming**: `era_class_name` in snake_case — `ww1_vehicle_tank_mk4`,
  `med_buildable_palisade`, `core_prop_crate_small`. `core_` prefix means era-neutral
  and shared.
- **Colliders are not the model.** Vehicles get 1–4 hand-fitted compound boxes, never
  one AABB (that bug cost us a day) and never per-part. Props get one box. Buildings
  get their real bricks.

## 8 · The texture question (open decision)

Flat colour is the current look. Teardown uses subtle textures and gets a lot of its
material read from them. **Decision pending**: prototype both on the same trench
section and compare — flat vs. very subtle per-material noise/grain. Whichever wins
becomes law here and every asset conforms. Until it's decided, build flat; the noise
would be a material-level change, not a per-asset one, so nothing is wasted.

Two things have raised the stakes on this since it was written. First, **terrain is now a
large continuous surface** rather than a grid of separately-tinted blocks, and continuous
surfaces are exactly where flat colour looks worst — the per-vertex variation in §6b is
doing work that block tinting used to do for free. Second, **materials now exist as a
system**, so per-material grain has an obvious home: it becomes one more field on the
material rather than an asset-authoring burden. Both point the same way, but the decision
still wants your eyes on a side-by-side rather than an argument on paper. Prototype it
during C3, when there's real ground to look at.

### 8b · Texture packs and shaders

These are two completely different asks that get said in one breath, and separating them
is most of the answer.

**Texture packs: yes, and the material system makes them unusually clean.** Because
everything in the world already resolves through a named core material, a texture pack is
a **material skin** — it overrides the detail map for `hard_stone`, `timber`, `sandbag`,
and every stone wall in every pack, era and workshop mod changes at once. This is strictly
better than the Minecraft model, where packs key on block ids and silently break the moment
a mod adds a block. Here there is nothing to break: a pack that skins the thirty core
materials has skinned the entire game, forever, including content that doesn't exist yet.

The bounds that keep it from destroying the look:

- A skin supplies a **greyscale detail map that modulates the palette colour**, never a
  full-colour texture that replaces it. The palette law (§2) survives contact with the
  workshop; a skin changes surface *character*, not hue.
- **Fixed resolution cap and fixed tiling scale**, declared per material class. A 4K
  photoscan of real brick is rejected — not because it wouldn't look good in a screenshot,
  but because it would look like a different game standing next to everything else.
- Skins are **cosmetic and client-side only**. They cannot touch a material's density,
  hardness, support or flammability. Retexturing steel does not make it steel-coloured
  cardboard, and it does not make it any easier to dig.

This is gated behind the §8 decision above: if flat colour wins, there is nothing to skin
and texture packs are moot. So §8 is upstream, and it stays a C3 prototype.

**Shaders: no, and this one is a hard architectural line rather than a scheduling
decision.** A shader is executable code that runs on the GPU, which puts it squarely
against `CORE-SPEC` §5's no-executable-code rule — but the real reason is narrower and
worse. *A shader that disables depth testing is a wallhack.* In a game whose entire
fantasy is digging in, hiding behind earthworks, and sapping unseen, being able to see
through terrain isn't an exploit at the edges, it's the whole game deleted. That is an
architecture problem, not a moderation problem, and it cannot be solved by review because
the review would have to happen on every upload forever.

What packs get instead is **parameterised style, not arbitrary code**. `style.json`
already carries sky, sun, fog, tonemap and ambience; the answer is to widen that exposed
surface — colour grading, fog curves, sun angle and warmth, bloom, vignette, a small set
of named post effects with bounded ranges — until packs can change the *mood* of the game
enormously without a line of GPU code. A gas-drenched 1917 dawn and a bright Bronze Age
afternoon should be reachable through parameters. If a pack genuinely needs an effect the
parameters don't reach, that's a core change request, exactly like a new interaction verb.

**Reserve the seam now, build it later.** The material schema should carry an optional
detail-map slot from C1 even though nothing fills it until C3 at the earliest, because the
cost of leaving the field there is nearly zero and the cost of retrofitting it through
thirty materials and every asset authored on top of them is not. The thing to actively
avoid is a custom shader getting hacked in for water or smoke during C3 and quietly
becoming load-bearing — at which point the door is open and closing it is a fight.

## 9 · Era styling & tone

Each era pack ships an **era style sheet** conforming to this bible, specifying:
faction colours (2 + 2 shadow), era-specific material colours, helmet/head profiles
per faction, sky/fog/sun values, ambience bed, weapon and vehicle silhouette
references, and a one-paragraph tone statement.

**Tone rules across all eras:**

- The brick abstraction is the tone regulator. No gore, no dismemberment; casualties
  read as bricks. This is a deliberate call, not squeamishness — it's what makes the
  game playable by the Roblox-adjacent audience we're targeting *and* keeps the
  subject matter from being tasteless.
- **No real insignia, flags, slogans, or leaders** — factions are colours and
  silhouettes, never named regimes. This avoids both trademark issues and the worst
  tone traps, especially for WWII and modern eras.
- Eras are named by period ("Great War"), never by nation.
- Modern-era content gets extra scrutiny — no identifiable current conflicts, no
  real-world flashpoints as map subjects.
- Mod content is where this gets tested hardest; the mod policy needs to state these
  rules explicitly (checklist §19).

## 10 · Review gate

Every asset gets three screenshots before it's considered done: **10 m** (detail read),
**100 m** (silhouette/faction read), and **in-context** (in its real environment, under
game lighting, next to a soldier for scale). If it fails at 100 m, it fails.

Sign-off is Marissa's, as with everything else. The bar: *does it look like it belongs
in the same world as everything already shipped?*
