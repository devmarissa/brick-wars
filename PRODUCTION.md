# BRICKFIELD: WESTERN FRONT — Production Discipline

*How we stop throwing features together and start making a premium game.*

## The Shift

Phase 1 (done): PROOF MODE. Every pass proved a system: physics at scale, destruction,
vehicles, flight, diggable earth. Necessary — and it's why the game exists.
Phase 2 (now): CRAFT MODE. Feature freeze. No new systems until the vertical slice
feels shippable. Every pass takes one interaction to the premium bar and ends with
a hardware playtest by Marissa. Feel notes from that playtest steer the next pass.

## The Vertical Slice ("one perfect minute")

You spawn in the allied trench at dawn. You shoulder a rifle you can SEE. You climb
the firing step and trade shots with the enemy line. You switch to the shovel and sap
forward — dirt sounds, dirt flies, spoil stacks. A whistle: artillery walks across
no-man's-land and the ground genuinely opens up around you. You drop into a fresh
crater, prone behind its lip, and you can hear your own breathing under the barrage.
That minute, feeling like a real game, IS the product. Everything serves it.

## The Interaction Quality Bar

Every player verb must complete this chain — no verb is "done" at fewer than six:

  INPUT -> ANIMATION -> SOUND -> VFX -> CAMERA RESPONSE -> UI ACKNOWLEDGMENT

Example, rifle shot: click -> viewmodel kicks + bolt cycles -> crack with echo tail ->
muzzle flash lights your own barrel, tracer, impact dust -> camera recoil pip ->
crosshair blooms. Prototype = step 1. Premium = all six, every verb.

## Pass Order (each = one delivery + one playtest)

1. **FP PRESENTATION** — viewmodels for all four weapons (blocky arms + weapon on
   camera), sway, movement bob, recoil kick, raise/lower on switch, FP as the default
   camera. The single highest-leverage premium lever: it's on screen 100% of the time.
2. **WEAPON FEEL** — per-weapon sound identity (crack vs whoosh vs clink), bolt/reload
   rhythm and cooldown UI, tracer/impact pass, crosshair states, hitmarkers on dummies.
3. **MOVEMENT FEEL** — footsteps by surface, land thump, sprint FOV + weapon lower,
   vault/mantle out of trenches (kills the hop-spam), fall handling.
4. **DIG FEEL** — shovel swing animation, three-stage dirt sound, spoil arc to the
   parapet, satisfying "scoop" rhythm; dig speed tuning from playtest.
5. **VEHICLE PRESENTATION** — the pro-pass: seated soldier, hands on wheel, spinning
   wheels, smooth enter/exit, engine audio loop, cockpit polish per vehicle.
6. **WORLD DRESSING** — skybox mood (dawn), distant artillery rumble ambience, flare
   light events, HUD visual identity (period typography, minimal chrome).

Then — and only then — we un-freeze and return to systems: M-ENEMY, M-TUNNEL, M-SIEGE.

## Rules

- **Definition of done**: Marissa plays it on hardware and says the word "feels."
  Not "works" — "feels."
- **One pass, one focus.** A pass may fix bugs anywhere, but adds polish in one lane.
- **Nothing ships unverified.** Headless test green + screenshot review before delivery
  (as always), plus the playtest loop closes every pass.
- **Refactor as we touch.** Code that gets a polish pass gets structured properly in
  the same pass (main.gd is due to split into scenes/modules as each system matures).
- **Feel references** (the bar, stated out loud): BattleBit for FP snappiness,
  Teardown for destruction weight, Deep Rock Galactic for dig satisfaction.
