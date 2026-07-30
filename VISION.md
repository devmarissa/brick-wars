# BRICK WARS

*Every age of warfare, one physical world.*

## The pitch

**Battlefield × Roblox × Squad × Teardown.** A brick world where everything is a real
physical object, every battle is a siege, and the dirt under your feet is the primary
weapon. Ancient, medieval, gunpowder, Great War, WWII, modern — each a first-class game
mode with its own kit, but all running the same four verbs on the same physics.

Simple enough that a Roblox player picks it up in ten seconds. Deep enough that a
hundred people can coordinate a siege for forty minutes. Moddable enough that the
community builds eras we never shipped.

## Why eras work (the engineering case, not just the fantasy)

The reason this isn't six games is that warfare has been the same four verbs for three
thousand years. Only the kit changes.

| Verb | Ancient | Medieval | Gunpowder | Great War | WWII | Modern |
|---|---|---|---|---|---|---|
| **DIG** | siege ramp, counter-tunnel | mine under the tower, fire the props | Vauban parallels (literal trench-digging) | the sap | fighting positions | fighting positions, IED holes |
| **BUILD** | palisade, shield wall | hoarding, siege tower | star-fort earthworks, gabions | sandbags, wire, dugouts | pillboxes, hedgehogs | HESCO, sandbags |
| **DESTROY** | ram, onager, fire | trebuchet, undermining | cannon breach | artillery barrage | bombers, arty | ATGM, drone, JDAM |
| **ADVANCE** | on foot, behind shields | over the breach | in line, under smoke | over the top | combined arms | fire and movement |

Same earth grid. Same brick destruction. Same siege loop. An era is a **data pack**:
weapon table, vehicle table, buildable table, palette, ambience, map set. That is the
entire architectural bet, and it's the same bet as moddability — if eras are data, mods
are eras. We get the modding pillar for free by building the era system correctly.

The corollary is a hard rule: **nothing era-specific gets hardcoded from here on.**
No `if weapon == "rifle"` in the core. WW1 goes into a data pack alongside everything
else, and if it can't be expressed in the pack format, the pack format is wrong.

## What we ship first

**One era, premium, then eras as content.** The Great War pack is the flagship — it's
what's built, it's the most distinctive (nobody has done destructible trench warfare),
and it's the hardest test of the core (digging, mining, artillery, 100v100). If the
core survives WW1 it survives everything else.

The other eras exist in the architecture from day one and in the build later:

1. **GREAT WAR** — flagship, ships first, defines the quality bar
2. **MEDIEVAL** — second era, and the proof that the data pack works (furthest kit from
   WW1: no guns at all, so it stress-tests every hardcoded assumption)
3. **MODERN** — the Squad-adjacent mode, biggest audience pull
4. **WWII** — combined arms, most familiar
5. **ANCIENT** — shield walls, ramps, the most novel physics (formations)
6. **GUNPOWDER / NAPOLEONIC** — line infantry and star forts, the connoisseur era

Order after #2 is market-driven, not fixed.

## The four pillars

**Everything is physical.** No baked destruction, no scripted collapse. If you can see
it, it's bricks, and bricks move. The earth included.

**The earth is the gameplay.** Dig, and the hole stays. Build, and the parapet stays.
Shell it, and the crater stays. This is the mechanic nothing else in the space has, and
it's the same system in every era.

**Accessible controls, deep systems.** Roblox-simple input: WASD, click, one build key,
one dig key. No stance-modifier-lean-combos. The depth is in what a hundred people do
with those inputs, not in the input list. Cross-platform because the controls are
simple enough to be.

**Mods are first-class.** The community shipping eras, maps, and events is the endgame.
Big group events — 100 people, custom pack, a rebuilt historical siege — are the thing
that makes this spread.

## Positioning, honestly

- **From Battlefield**: spectacle and scale, the sense of a big loud war around you.
- **From Roblox**: accessibility, simple controls, social events, user-generated everything.
- **From Squad**: coordination that actually matters, logistics, a front line with geography.
- **From Teardown**: destruction that feels physical and consequential, not cosmetic.
- **From nobody**: the diggable earth as the connective tissue between all of them.

We are not competing on fidelity. We are competing on *consequence* — a brick world
where the battlefield at minute 40 does not look like the battlefield at minute 0.

## Risks we're naming now

- **Scope.** Six eras is a trap if we build them in parallel. Mitigation: the era pack
  format is built now, the eras are built one at a time, and era 1 ships alone.
- **The name.** "Brick Wars" is memorable but crowded — *Brick Rigs* is a live product
  in adjacent space, and "brick" + LEGO-adjacent branding invites trademark scrutiny.
  Needs a search and probably a distinguishing subtitle before any store page. On the
  release checklist, not a blocker for building.
- **Tone.** Historical warfare, from bronze age to modern, rendered in bricks. The brick
  abstraction is our friend here, but each era needs a deliberate tone call rather than
  a default. See ART-BIBLE §9.
- **Mods vs. netcode.** Modding a 100v100 authoritative server is genuinely hard.
  Decide early whether mods are server-side-only (safe) or client-authoritative (fast
  but exploitable). Currently unresolved — checklist item.

## The one-line version

*A physics sandbox where you dig, build, and blow apart the battlefields of every era
of warfare — with friends, on any platform, with whatever mods you want.*
