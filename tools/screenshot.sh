#!/usr/bin/env bash
#
# Take one screenshot of the game as it currently is.
#
#   tools/screenshot.sh                       → game/docs/latest.png
#   tools/screenshot.sh docs/c0_greybox.png   → path is relative to game/
#   tools/screenshot.sh docs/x.png 8          → wait 8 seconds before the shot
#
# Screenshots cannot be taken headless — the viewport has to actually draw. On a Mac that
# means a window opens for a few seconds, which is fine. On a Linux box or in CI there may
# be no display at all, so this falls back to a virtual one if xvfb is installed.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-docs/latest.png}"
SETTLE="${2:-4}"
shift 2 2>/dev/null || shift $# 
# Anything left over is passed straight through to the game, so `tools/screenshot.sh out.png 4
# --play` photographs it as somebody playing rather than with the fixed milestone framing.
EXTRA=("$@")

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for candidate in godot47 godot4 godot \
      "/Applications/Godot.app/Contents/MacOS/Godot" \
      "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
      GODOT="$candidate"; break
    fi
  done
fi
if [ -z "$GODOT" ]; then
  echo "no Godot binary found — set GODOT=/path/to/godot" >&2
  exit 1
fi

mkdir -p "game/$(dirname "$OUT")"

# Godot's own flags go before `--`; everything after it is the game's, and `core/cli.gd`
# parses it. That split is why `--rendering-driver` is inserted rather than appended: on the
# far side of `--` it was being handed to the game, which quite rightly did not know it.
GODOT_ARGS=(--path game res://tools/screenshot.tscn)
if [ -z "${DISPLAY:-}" ] && [ "$(uname)" != "Darwin" ] && command -v xvfb-run >/dev/null 2>&1; then
  GODOT_ARGS+=(--rendering-driver opengl3)
  RUN=(xvfb-run -a -s "-screen 0 1440x900x24" "$GODOT" "${GODOT_ARGS[@]}")
else
  RUN=("$GODOT" "${GODOT_ARGS[@]}")
fi
RUN+=(-- --shot "$OUT" --settle "$SETTLE" "${EXTRA[@]}")

"${RUN[@]}"
