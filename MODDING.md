# Modding Brick Wars

This is the modder-facing companion to `FORMAT-SPEC.md`. The spec is the law; this is the
part you actually need to have read before you upload something, plus the two commands that
answer most questions faster than reading either.

Eras are packs. Everything from ancient warfare to modern is content in this format, and
core has no idea which era anything belongs to — so a pack you write sits in exactly the
same place, loaded by exactly the same code, as the ones that ship with the game.

## Your pack id is a claim, and it is permanent

A pack id is global. It is how every other pack in the world refers to yours, it is how the
load order is tie-broken, and it is baked into every asset id you publish (`yourpack:rifle`).
Pick something distinctive — `siege`, `trenches` and `medieval` will collide with somebody,
and the loser of a collision is whichever copy the player installed second: it gets disabled
and reported rather than silently replacing the other, which is better than the alternative
and still not a good afternoon for either of you.

Rename it later and you have not renamed a folder. You have renamed every asset in it, every
`extends` pointing into it and every `depends` entry naming it, in packs you have never seen.

## An asset somebody else extends is public surface

`extends` is the whole point of the format — a variant of a rifle should cost five lines,
not a copied part table — and it works across packs. That is a feature with a bill attached:
the moment somebody writes `extends: "yourpack:rifle_bolt"`, that asset's part names, its
field names and its stats block are an interface.

Renaming a part is a breaking change. So is removing one, and so is changing a `parts~`
patch target. Adding is safe; anything else needs a major version, because a dependent pack
declares a semver range against yours and that range is the only thing standing between your
tidy-up and somebody else's mod disappearing from a player's game.

If you would rather not carry that: say so in your pack description. There is no mechanism
for it and there is not going to be one — a pack that cannot be extended is a pack that has
opted out of the thing that makes this a modding game.

## When something does not load

Nothing here fails silently and nothing here fails halfway. A pack that is wrong is disabled
whole, reported with the file, the line, the value and the rule it broke, and stepped over;
the rest of the game loads exactly as it would have. If your pack vanished, the reason is in
the boot log.

Two commands:

    godot --headless --path game -- --resolve yourpack:rifle_sniper

prints the asset as the game actually sees it, after `extends` has been carried out, with
every field attributed to the document that set it — including the ones you did not write,
which report `core (default)`. Add `--part <name>` to narrow it to one part. When a field
has a value you did not type, this is the fastest way to find out which of the four
documents in the chain typed it.

    godot --headless --path game -- --pack-root /path/to/your/packs

loads your pack folder alongside the shipped ones without installing anything. This is the
authoring loop. `game/tests/fixtures/broken` is a folder of packs that are wrong on purpose;
point the flag at it to see what a refusal reads like before it is yours.

## The rules that will catch you first

Most first uploads break one of these, and every one of them is checked before your pack is
allowed to load:

A module is 0.1 m and it is not divisible — every `offset`, `size` and collider dimension is
a whole number of modules. A block turns in steps of 15°; an angle is a design statement,
not a modelling accident. Every part names a `material` from the core table and there is no
default, so a stone wall never behaves like timber. Colours come from the core palette and a
material only accepts some of them, because painting steel pink is how a sandbox stops
reading as a battlefield. At least 70% of any asset is plain blocks — the other four
primitives are for the things that are genuinely round or genuinely wedge-shaped. And
`extends` chains cap at three levels, named end to end in the error when they do not.

`ART-BIBLE.md` explains why each of those exists. Arguing with them is allowed and the specs
name their own sections so you know what you are arguing with.

## Two fields worth understanding before you need them

**`class`** is your asset's part budget — `small_prop` and its siblings, from `budgets.json`.
It is optional, and an asset that leaves it out is held to the widest range its `kind` allows,
which usually means nothing complains until you are well past sensible. Declaring it is how
you tell the validator what you meant to build, and it is the only way to be told you have
come in *under* budget as well as over. A variant inherits it from its base and should not
restate it; `--resolve` will show you which file it came from.

**`body`** decides whether your asset is one rigid body or many. One is the default and is
what you want for anything that should hold together — a crate that sheds boards under its
own weight is a bug, not detail. Many is for things whose whole point is coming apart:
`core:wall_sandbag` is 114 bodies because a wall that cannot fall in courses is a painted
backdrop. This is a judgement the format cannot make for you, and getting it wrong is the
most common reason a good-looking asset feels wrong to play with.

## Why your hollow crate weighs two hundred kilos

Mass is derived from volume × the material's density, which is right almost always and
notably wrong for containers. `hollow: true` hollows your asset out, but the shell it leaves
is **one module thick** — 0.1 m — because one module is the thinnest wall the grid can
express. A real packing crate has walls a fifth of that, so a derived hollow crate at plank
density lands near 167 kg where the object should be nearer 30.

The sanctioned answer is to **declare `mass` in the file**. Every hollow asset core ships does
exactly this, and the boot log prints `(declared)` beside each one so the substitution is
never invisible. It is not a hack you are getting away with; it is the documented behaviour
for the one case where the density model and the module size disagree. Do not reach for it on
a *solid* object — there, a mass that feels wrong almost always means the material is wrong.
