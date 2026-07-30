#!/usr/bin/env bash
#
# The gate. Everything that has to be true before a commit is allowed out.
#
# Run it by hand any time; the pre-push hook runs it for you. It is deliberately one
# script with no dependencies beyond bash and Godot, so it behaves identically on this
# Mac, on a Linux box, and inside GitHub Actions later — `.github/workflows/ci.yml`
# exists already and does nothing except call this file.
#
# Every check runs even if an earlier one fails. Finding out about three problems at once
# beats finding out about them one push at a time.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAX_LINES=300
FAILED=0
CHECK_NO=0

if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; DIM=''; OFF=''
fi

start() { CHECK_NO=$((CHECK_NO + 1)); printf '\n%s[%d] %s%s\n' "$DIM" "$CHECK_NO" "$1" "$OFF"; }
pass()  { printf '    %sok%s   %s\n' "$GREEN" "$OFF" "$1"; }
fail()  { printf '    %sFAIL%s %s\n' "$RED" "$OFF" "$1"; FAILED=$((FAILED + 1)); }
skip()  { printf '    %sskip%s %s\n' "$YELLOW" "$OFF" "$1"; }

# ---------------------------------------------------------------- finding Godot
# Kept as a search rather than a hardcoded path because this has to run unchanged on the
# Mac it is developed on and the Linux container it is verified in.
find_godot() {
  if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
  for candidate in godot47 godot4 godot \
      "/Applications/Godot.app/Contents/MacOS/Godot" \
      "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
    if command -v "$candidate" >/dev/null 2>&1; then echo "$candidate"; return; fi
    if [ -x "$candidate" ]; then echo "$candidate"; return; fi
  done
}
GODOT_BIN="$(find_godot)"

echo "BRICK WARS — check.sh"
echo "${DIM}$(date '+%Y-%m-%d %H:%M')  ·  godot: ${GODOT_BIN:-NOT FOUND}${OFF}"

# ------------------------------------------------------------------- 1. file size
# The 300-line rule is the whole reason this project is being rebuilt. The old build's
# main.gd reached 1,500 lines without anyone deciding it should; it got there one
# reasonable-looking line at a time, and every one of those lines had a good excuse.
# So the limit is mechanical, and it applies to code, not to prose.
start "no source file over $MAX_LINES lines"
OVERSIZE=0
while IFS= read -r f; do
  n=$(wc -l < "$f")
  if [ "$n" -gt "$MAX_LINES" ]; then
    fail "$f is $n lines — split it, or argue with CORE-SPEC §2 about where the seam goes"
    OVERSIZE=$((OVERSIZE + 1))
  fi
done < <(find game tools -type d -name '.godot' -prune -o \
           -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.sh' \) -print | sort)
if [ "$OVERSIZE" -eq 0 ]; then
  BIGGEST=$(find game tools -type d -name '.godot' -prune -o \
              -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.sh' \) -print \
            | xargs wc -l | sort -rn | sed -n '2p' | awk '{print $2" ("$1" lines)"}')
  pass "largest is $BIGGEST"
fi

# -------------------------------------------------------------- 2. manifest is honest
# Modules are listed in core/manifest.gd rather than discovered by scanning, so that
# adding one to the game is a decision visible in a diff. That only holds if a module
# file that never got listed is an error rather than a thing that quietly does nothing.
start "every core module is in the manifest"
MISSING=0
while IFS= read -r f; do
  rel="res://${f#game/}"
  if ! grep -q "\"$rel\"" game/core/manifest.gd; then
    fail "$f exists but is not in core/manifest.gd — nothing will ever load it"
    MISSING=$((MISSING + 1))
  fi
done < <(find game/core -type f -name '*_module.gd' | sort)
COUNT=$(find game/core -type f -name '*_module.gd' | wc -l | tr -d ' ')
[ "$MISSING" -eq 0 ] && pass "$COUNT modules, all listed"

# ---------------------------------------------------------------- 3. headless tests
start "headless test suite"
if [ -z "$GODOT_BIN" ]; then
  fail "no Godot binary found — set GODOT=/path/to/godot and run this again"
else
  TEST_LOG="$(mktemp)"
  "$GODOT_BIN" --headless --path game res://tests/test_main.tscn >"$TEST_LOG" 2>&1
  TEST_EXIT=$?
  SUMMARY=$(grep '^TEST_DONE' "$TEST_LOG" | tail -1)
  if [ -z "$SUMMARY" ]; then
    fail "the suite never printed TEST_DONE — it crashed or hung before finishing"
    sed -e 's/^/      /' "$TEST_LOG" | tail -25
  elif [ "$TEST_EXIT" -ne 0 ] || ! echo "$SUMMARY" | grep -q 'failed=0'; then
    fail "$SUMMARY"
    grep -E '^  FAIL|^          - ' "$TEST_LOG" | sed -e 's/^/      /'
  else
    pass "$SUMMARY"
  fi
  rm -f "$TEST_LOG"
fi

# ------------------------------------------------------- 4. the blast, when there is one
# This is the check that matters most and it cannot run yet, because C0 has no blast in
# it. The reference capture exists — blast-fixture/reference/macos-20260729/ — and the
# comparison tool exists, and the moment C5 puts an explosion back in the game this turns
# on and starts refusing changes that alter how it feels.
#
# It says so out loud on every single run on purpose. A dormant check that stays quiet is
# a check that gets forgotten, and this one is guarding the only thing in the old project
# that could not be rebuilt from notes.
start "blast feel matches the reference capture"
REFERENCE=blast-fixture/reference/macos-20260729/blast_baseline.json
if [ -f "$REFERENCE" ]; then
  skip "dormant until C5 — the rebuild has no blast in it yet to compare"
  printf '         %sreference captured and waiting: %s%s\n' "$DIM" "$REFERENCE" "$OFF"
else
  fail "$REFERENCE is missing — that file is the definition of what the blast feels like"
fi

# ------------------------------------------------------------------------- verdict
echo
if [ "$FAILED" -eq 0 ]; then
  printf '%sall checks passed%s\n' "$GREEN" "$OFF"
  exit 0
fi
printf '%s%d check(s) failed%s\n' "$RED" "$FAILED" "$OFF"
exit 1
