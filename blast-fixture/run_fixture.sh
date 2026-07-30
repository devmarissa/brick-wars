#!/usr/bin/env bash
# BRICK WARS — blast feel fixture runner.
#
#   ./run_fixture.sh [target-project-dir] [output-dir]
#
# Copies the target Godot project to a scratch dir, drops the fixture in, runs it,
# and copies the results back out. The target project is NEVER written to — the
# archived prototype stays pristine (BUILD-ORDER §4).
#
# Defaults to running against ../archive/great_war_prototype and writing to ./out.
#
#   --windowed   run with a real window so screenshots are captured (needed for
#                the visual half of the baseline; headless skips them)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WINDOWED=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--windowed) WINDOWED=1 ;;
		*) ARGS+=("$a") ;;
	esac
done

TARGET="${ARGS[0]:-$HERE/../archive/great_war_prototype}"
OUT="${ARGS[1]:-$HERE/out}"

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	for c in godot godot4 /Applications/Godot.app/Contents/MacOS/Godot; do
		if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then GODOT="$c"; break; fi
	done
fi
if [ -z "$GODOT" ]; then
	echo "error: no Godot binary found. Install Godot 4.6+ or set GODOT=/path/to/godot" >&2
	exit 1
fi

if [ ! -f "$TARGET/project.godot" ]; then
	echo "error: $TARGET is not a Godot project (no project.godot)" >&2
	exit 1
fi

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "fixture : $HERE"
echo "target  : $TARGET"
echo "scratch : $SCRATCH"
echo "godot   : $GODOT ($("$GODOT" --version 2>/dev/null | tail -1))"
echo

# copy the project, minus its import cache, then add the fixture
cp -R "$TARGET"/. "$SCRATCH"/
rm -rf "$SCRATCH/.godot"
cp "$HERE/blast_fixture.gd" "$HERE/blast_fixture.tscn" "$SCRATCH"/

mkdir -p "$OUT"

# first pass imports assets and exits; without it the fixture can run before the
# resource cache exists and fail to load main.tscn
"$GODOT" --headless --path "$SCRATCH" --import >/dev/null 2>&1 || true

FLAGS=(--path "$SCRATCH" res://blast_fixture.tscn)
[ "$WINDOWED" -eq 1 ] || FLAGS=(--headless "${FLAGS[@]}")

set +e
"$GODOT" "${FLAGS[@]}" -- --fixture-out res://fixture_out 2>&1 | tee "$OUT/run.log"
STATUS=${PIPESTATUS[0]}
set -e

if [ -d "$SCRATCH/fixture_out" ]; then
	cp -R "$SCRATCH/fixture_out"/. "$OUT"/
fi

if [ ! -f "$OUT/blast_baseline.json" ]; then
	echo >&2
	echo "error: fixture produced no baseline. See $OUT/run.log" >&2
	exit "${STATUS:-1}"
fi

echo
echo "baseline  → $OUT/blast_baseline.json"
if [ -d "$OUT/shots" ]; then
	echo "shots     → $OUT/shots ($(ls "$OUT/shots" | wc -l | tr -d ' ') frames)"
else
	echo "shots     → none (headless run; use --windowed for frames)"
fi

# exit 3 means the fixture caught something firing during measurement; pass it through
# so neither CI nor a person can mistake a contaminated run for a baseline
if [ "${STATUS:-0}" -ne 0 ]; then
	echo >&2
	echo "warning: the run was not clean — see the message above. Do not keep this as a baseline." >&2
	exit "$STATUS"
fi
