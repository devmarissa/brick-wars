# BRICKFIELD: WESTERN FRONT — Design Vision

*"The first shooter where the earth is the gameplay."*

Pordier at War proved the appetite. BattleBit proved blocky + massive works. Teardown
proved physical destruction sells. Nobody has combined them — because nobody else's
battlefield is actually simulated. Ours is.

## The Thesis

WW1 combat WAS terrain manipulation. Artillery reshaped the ground; saps crept forward
night by night; mines went under the wire and erased hilltops. Every WW1 game fakes this
with static maps. BRICKFIELD makes the land itself the simulation: every shovel of dirt,
sandbag, plank, and shell crater is real, persistent, and shared by 200 players.

Destruction in Battlefield is spectacle. In Teardown it's puzzle. **Here it is strategy.**

## The Four Verbs

Everything in the game is one of these, and they all operate on the same earth-grid:

1. **DIG** — entrench, deepen, sap forward, tunnel under. Digging is not a menu action:
   you swing a shovel at brick-earth and the bricks come out (and become spoil you can
   sandbag). A trench is a hole shaped like tactics.
2. **BUILD** — revet walls, stack sandbags, lay duckboards, string wire, timber tunnels,
   build MG nests and OP towers. Building consumes materiel that has to physically reach
   you (see Logistics).
3. **DESTROY** — rifles chip, grenades gouge, artillery excavates, mines delete hills.
   Counter-battery fire, wire-cutting barrages, collapsing tunnels on the men inside them.
4. **ADVANCE** — go over the top and take ground. The front line is wherever the living
   defenders and the surviving earthworks say it is.

## Core Loop (the peak-WW1 fantasy)

A match is a **living siege** over a strip of front, not a respawn arena:

- Quiet phase: both sides dig, wire, revet, stockpile shells, push listening saps,
  start mine tunnels. Observers map enemy works.
- Preparation: artillery cuts wire and flattens parapets. Sappers blow the mine —
  if the counter-miners didn't find them first.
- The assault: whistles, creeping barrage, over the top. Attackers cross a no-man's-land
  their own guns just reshaped, into whatever defenses actually survived.
- Consolidation: captured trench gets reversed (fire steps re-cut facing the other way),
  runners bring up materiel, the line has MOVED — by 40 real meters.
- Win by pushing the enemy line past their last trench network, or by attrition/morale
  collapse. Kills matter less than ground and works.

## Classes = Roles in the Machine

BattleBit-simple kits, but every class touches the earth-game:

- **Rifleman** — the mass. Rifle, grenades, entrenching tool (slow dig).
- **Sapper** — fast dig, builds all fortifications, lays and disarms mines, timbers tunnels.
- **Machine gunner** — sets up a real gun on a real parapet; the gun is an emplacement,
  not a loadout item. Displacing takes time. Losing the nest means losing the gun.
- **Artillery observer** — binoculars + flare pistol; spots for the guns. Artillery is
  player-crewed and fires from the map, over the horizon, at map coordinates.
- **Runner / logistics** — moves shells, timber, and sandbags forward (and orders back).
  The most unglamorous class is why your side's guns are still firing. Supply routes
  are physical and cuttable.
- **Officer** — whistle, rally, marks objectives; small buffs to nearby dig/build speed.

## Signature Systems

**Sapping & entrenching.** Earth is a chunk-managed brick grid. Dig rate depends on tool
(shovel > entrenching tool > hands) and soil. Spoil is real: dug dirt becomes carriable
brick-bags — the parapet in front of a fresh sap is literally yesterday's hole.

**Mining & counter-mining.** Tunnels need timbering (untimbered spans collapse — on you,
or on command). Chambers packed with explosive crates produce the game's apex moment:
a hill, a trench section, and everyone in it go up at once. Counter-play: listening posts
(audio of nearby digging), camouflets (small charges that collapse enemy tunnels).

**Artillery & the reshaped field.** Guns are crewed, fed by logistics, and fire at
coordinates. Craters are cover AND obstacle (vehicles bog). Sustained shelling of the
same sector churns it into a moonscape that is genuinely harder to attack across —
history's actual lesson, emerging from physics instead of being scripted.

**WW1 vehicles & logistics.** Rhomboid landships that crush wire and cross trenches
(or ditch in them), armored cars, supply trucks, light rail for shells, biplanes for
recon (photographing enemy works), artillery spotting, and bombing. Tanks are rare,
slow, terrifying, and mechanically unreliable by design.

**Tunnels, dugouts, insanity.** Deep dugouts that survive barrages (the reason attackers
find defenders alive after a week of shelling), tunnel fights with pistols and spades,
flooding low tunnels, gas hanging in low ground (craters and trenches — your own works
can drown you in it).

## Scale: the 100v100 Plan

- **The earth-grid is the netcode win.** Dig/place/blast are tiny grid events —
  event-sourced, exactly the DecimalCubed-style encoding we validated in the harness
  (2-byte grid indices, ~14k blocks/sec). Late joiners replay the event log; the
  battlefield's whole history compresses to kilobytes.
- Debris physics stays client-side cosmetic beyond a relevance radius (M2 governor);
  authoritative state is the grid + bodies near players (M4 interest management).
- Sector sharding along the front: 200 players naturally spread along a 1km line —
  each client simulates its neighborhood at full fidelity.
- Ladder: single-player earth sandbox → AI-filled front (fill both sides with bot
  soldiers so 100v100 *feel* arrives before 100v100 *netcode*) → networked squads →
  the full siege server.

## Milestones

1. **M-EARTH (the keystone).** One strip of front becomes real chunked brick-earth.
   Shovel digs it, spoil comes out, sandbags/planks place into it, artillery carves it.
   A player can dig a connected sap across no-man's-land. THE architecture milestone —
   everything else stands on it.
2. **M-TUNNEL.** Digging below grade + timbering + collapse rule + explosive chambers.
   Blow a mine under the enemy trench.
3. **M-ENEMY.** Bot defenders that man parapets, shoot back, and die into bricks;
   bot waves that come over the top at you. The game becomes a game here.
4. **M-SIEGE.** The loop: quiet phase / barrage / assault / consolidation, win by ground.
   Logistics chain v1 (shells + timber move forward by truck and hand).
5. **M-WW1-KIT.** Rhomboid tank, armored car, biplane recon/bombing, gas, flares,
   period weapons pass. Art direction hardening (mud, rain, night flares).
6. **M-NET.** The harness netcode, for real: grid events over UDP, interest management,
   100v100 with bots filling gaps.

## Why We Win

- Roblox trench games: the fantasy, none of the physics. We ARE the physics.
- BattleBit: the scale and readable blocky style, but static maps. Our map is a character.
- Teardown: the destruction fidelity, but single-player puzzle. Ours is a war.
- The moat is compounding: earth-grid → tunnels → logistics → siege loop all feed each
  other. A competitor must build the whole stack to copy any of it.
