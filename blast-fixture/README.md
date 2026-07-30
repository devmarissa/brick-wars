# BRICK WARS — Blast Feel Fixture

*"I always had fun blowing stuff up, it felt good."*

That sentence is a specification. This is it written down before it evaporates.

Everything else in the old prototype is going to be rebuilt — vehicles, terrain, materials,
the lot. The blast is the one thing that is already right, and the one thing that would be
quietly, unrecoverably lost if the rebuild produced something merely *similar*. Feel doesn't
survive in a design doc. It survives in numbers and frames.

So: this harness fires identical charges at identical structures from identical seeds,
records what happened, and gives you a file you can hold the rebuild against.

---

## Run it

```
./run_fixture.sh                          # headless, against the archived prototype
./run_fixture.sh --windowed               # ...and capture screenshots (this is the one you want)
./run_fixture.sh <project-dir> <out-dir>  # against anything else, e.g. the rebuild
```

It needs Godot 4.6+. It finds `godot` on your PATH, or `/Applications/Godot.app`, or
whatever you set `GODOT=` to.

**The archive is never written to.** The script copies the project to a scratch directory,
drops the fixture in there, runs it, and copies the results back. `archive/great_war_prototype/`
stays playable and pristine, as `BUILD-ORDER` §4 requires.

You get `out/blast_baseline.json`, `out/run.log`, and — with `--windowed` — `out/shots/`.

**Don't click in the window.** The fixture won't let a click do damage — see "Keeping the
run clean" below — but it will mark the run contaminated and refuse to let you use it, and
you'll have to run it again. Let it play out and it takes about a minute.

## The baseline — captured

**`reference/macos-20260729/`.** Godot 4.7.1, M4, clean run, zero strays, 110 frames,
30 July 2026. That directory is the definition of what the game is supposed to feel like,
and it was taken on the machine the rebuild happens on, which is the only thing that makes
it authoritative. Everything from here compares against it:

```
./compare_baselines.py reference/macos-20260729/blast_baseline.json out/blast_baseline.json
```

If you ever need to retake it — a deliberate, better blast, or a Godot upgrade — the
command is:

```
./run_fixture.sh --windowed
cp -R out reference/macos-$(date +%Y%m%d)
```

...and say so in the commit, because a silently recaptured baseline defeats the whole gate.

A note on cross-platform comparison, which turned out better than expected.
`reference/linux-baseline.json` (Godot 4.6, x86) and the Mac capture agree on **132 of 134
metrics** — every first-tick impulse number, every peak height, every shake and knock
value, and both earth carve counts matched to the last digit. The only two that missed were
`pile_standard_shell`'s settle time (+13.8%) and max displacement (+10.1%): the loose heap,
the most chaotic scenario of the eight, across two engine versions and two CPU
architectures. So Jolt is far more portable here than the usual warning implies.

That's a pleasant confirmation, not licence to skip your own capture next time the machine
changes. The number that gates the rebuild is Mac-to-Mac.

## Compare a rebuild against it

```
./compare_baselines.py reference/macos-20260729/blast_baseline.json out/blast_baseline.json
```

Exit 0 = still feels right. Exit 1 = something drifted, with a per-metric table of what and
by how much. Exit 2 = the two files aren't comparable at all.

That exit code is the whole point: this goes in CI as a standing gate (`CHECKLIST` §8), so
the blast can't be degraded by an unrelated physics tweak six months from now without
someone being told.

Verified: a 12% change to the blast impulse multiplier — small enough that you might not
notice it playing, large enough that the game is worse — fails 34 metrics across 7 of the 8
scenarios. It is not a rubber stamp.

## The eight scenarios

Six run on a bare 240 m plate parked at (600, 0, 600), far from the map, so they measure the
**blast** and not the level. Two run in the live no-man's-land, on the real diggable earth,
because craters are half the feeling and you can't get those on a plate.

| | what it asks |
|---|---|
| `wall_standard_shell` | the baseline question: what does one shell do to a stacked wall? |
| `wall_light_charge` | same wall, power 18 — *below* `SHATTER_POWER`, so it shoves instead of shattering. **The difference between this and the one above is the thing being protected.** |
| `wall_heavy_point_blank` | the showpiece. 80 power, 12 m radius, right up against it |
| `wall_airburst` | detonated 6 m up: tests the downward/outward split |
| `pile_standard_shell` | same charge, same brick count, dumped in a heap instead of stacked. Structure vs mass |
| `empty_standard_shell` | nothing but air. Isolates camera shake and player knockback from any debris |
| `earth_standard_shell` | on the real earth field: crater size, spoil thrown, lip |
| `earth_heavy_charge` | the big one, same place |

Every scenario puts the player 8 m away on the ground, because shake and knockback fall off
with distance from the player and mean nothing unless the observer stands somewhere fixed.
The screenshot camera sits over that observer's shoulder looking at the charge, so two runs
can be flicked between frame by frame.

## What it records, and why each number is there

**`impulse`** — how hard the first tick hits. `mean_launch_speed` and `max_launch_speed` are
measured on the very first physics tick after detonation, before gravity and collisions
muddy it. This is the punch.

**`wake`** — `peak_height` is how high the highest brick got, `peak_awake` is how many were
in motion at once and when. This is the plume, and the sense of the whole thing *lifting*.

**`felt`** — `shake_peak`, `shake_seconds`, `player_knock_peak`. The part that hits the
player rather than the world. Easy to break, impossible to notice you've broken until it's
been broken for a month.

**`earth`** — `height_cells_removed` and `debris_spawned`. Did it actually dig a hole.

**`settle`** — how long from detonation until nothing is moving. Rubble that stops dead
feels cheap; rubble that keeps trickling for four seconds feels heavy. This number is that
distinction.

**`scatter`** — where everything ended up. `mean_displacement`, `max_displacement`, how many
moved more than half a metre, and how many left the world entirely.

**`timeline`** — every other tick: awake count, mean speed, max height, shake. This is the
curve, and it's what you plot when a summary number changes and you want to know *when*.

Two deliberate exclusions. `ejection_artefacts` counts bricks that came out above 200 m/s —
that's an interpenetration bug, not feel, and it's kept out of the peak-speed number so it
can't poison it. The rebuild should not reproduce it. `left_the_world` counts bricks that
fell past y = −20; they get frozen so a scenario can't hang waiting for something falling
forever, and "sent it into orbit" is itself a fact worth recording.

## Keeping the run clean

The first real capture on the Mac came back wrong, and it's worth writing down why because
it's the sort of thing that would have poisoned the project quietly.

The prototype grabs the mouse on startup and fires from the player on left-click. The
fixture teleports the observer to 8 m from the charge and hands them a loaded rifle without
meaning to. One click in the window — the ordinary reflex of clicking a game window to
focus it — put a round into the test wall. `wall_standard_shell` came back with a peak of
112 m/s instead of 11, a brick thrown 94 m instead of 10, and a settle time a second long.
Nothing about the output announced itself as broken. It just looked like the blast was much
punchier on macOS than on Linux, which is exactly the kind of wrong conclusion that gets
built on.

A fixture you can perturb by touching the window isn't a fixture, so there are now three
layers, and the run reports on itself:

1. The mouse is held released every physics tick, which is the first thing the prototype's
   fire routine checks.
2. The capture grace is pinned, which is the second thing it checks.
3. Anything that gets fired regardless is destroyed in the tick it was created — before it
   can travel — and **counted**. A run with a non-zero count writes `"clean": false`,
   prints a warning, and exits 3. `compare_baselines.py` refuses such a file outright
   rather than reporting drift that isn't drift.

Verified by injecting a shot mid-scenario: with the guard off it moves peak speed 11 → 88,
knock 3.8 → 6.5 and shake 0.75 → 0.91; with the guard on the numbers are identical to a
clean run to the last digit, and the run is flagged.

`felt.observer_drift` is in the output for the same reason — how far the blast moved the
observer is deterministic, so it doubles as a tripwire for anyone leaning on a movement key
mid-run.

## Determinism, honestly

The six pad scenarios are **bit-identical run to run** on a given machine — verified across
three consecutive runs, every metric, every timeline sample. Those are the tight gate.

The two earth scenarios are **not**. They run in the live map where the solver is working
across many bodies at once, and ordering there isn't reproducible. Across three runs their
launch speeds moved about 1–2% and `peak_awake` swung between 22 and 49. They're kept
because craters matter, and `compare_baselines.py` holds them to loose tolerances on
purpose. They exist to catch *"the crater stopped happening"*, not to police decimals. Pass
`--strict` to hold them to pad tolerances and watch it fail; that's expected.

If you want a stricter earth gate later, the honest fix is to give the earth scenarios their
own isolated field rather than to tighten the numbers.

## Turning the frames into something watchable

```
cd out/shots
ffmpeg -framerate 6 -pattern_type glob -i 'wall_heavy_point_blank_t*.png' \
       -vf scale=960:-1 wall_heavy.gif
```

Fourteen frames per scenario, front-loaded (ticks 0, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96,
128, 192) because everything that matters happens in the first half second, plus one at rest.

`wall_heavy.gif` is that sequence from the Mac capture, already assembled.

One wrinkle found in that capture. Screenshots are read off the viewport on physics ticks,
but the viewport only updates on a *drawn* frame, and with vsync on, 60 Hz physics against a
60 Hz display sits exactly on the aliasing boundary — one hitch and the engine takes two
physics steps inside a single drawn frame, and both captures read back the same picture.
Three pairs came back byte-identical (t002≡t004, t006≡t008, t012≡t016): the flipbook running
at half rate in precisely the window it was front-loaded to cover. The fixture now turns
vsync off and uncaps the frame rate so draws comfortably outnumber physics steps, and counts
any duplicate that slips through anyway as `duplicate_frames`, per scenario and in the
header. A degraded flipbook should announce itself rather than be found by `md5sum` a year
later.

This is a **pixels-only** problem — every measured number comes from physics state, so the
numeric baseline was never affected. That's why `fixture_version` deliberately stays at 2:
bumping it would make `compare_baselines.py` refuse the baseline you already captured, over
a change that provably moves nothing. Verified by re-running the archive after the change
and getting all 134 metrics identical.

## Pointing it at the rebuild

The fixture talks to the target project through exactly four things:

- `res://main.tscn` loads and builds a world
- `main.queue_blast(point, radius, power)`
- `main.spawn_brick(pos, basis, size, colour, linvel, asleep, jitter)`
- `main.player`, `main.cam_shake`, `main.earth`, `main.SHATTER_POWER`

Keep those reachable in C0/C1 — or write a thin adapter node exposing them — and the same
fixture runs against the rebuild unmodified, which is the only way the comparison means
anything.
