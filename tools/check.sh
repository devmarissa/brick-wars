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

# ------------------------------------------------------------------ time limits
# Nothing here should ever sit forever. The test runner already learned this lesson once —
# a case that would not parse killed the coroutine before `quit()`, and one red line became
# a CI timeout, which is a far worse thing to be greeted by. The same reasoning applies one
# level up: if Godot wedges, the gate says so in a minute rather than in the morning.
#
# `timeout(1)` is not on a stock macOS, so this is the bash version. It has to work on
# bash 3.2, which is what /bin/bash still is on a Mac.
IMPORT_LIMIT=600      # first import of a cold project, generously
TEST_LIMIT=180        # the suite runs in about four seconds

run_with_limit() {
  local limit=$1; shift
  "$@" & local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

echo "BRICK WARS — check.sh"
echo "${DIM}$(date '+%Y-%m-%d %H:%M')  ·  godot: ${GODOT_BIN:-NOT FOUND}${OFF}"

# The project is developed and verified against 4.7.1. A 4.6 binary will import this
# project, run the suite, and fail in ways that read as "the code is broken" rather than
# "you are on the wrong Godot" — so the version gets said out loud before anything else
# has a chance to produce a confusing red line.
if [ -n "$GODOT_BIN" ]; then
  GODOT_VERSION="$("$GODOT_BIN" --version 2>/dev/null | tail -1)"
  case "$GODOT_VERSION" in
    4.7.*) printf '%sversion: %s%s\n' "$DIM" "$GODOT_VERSION" "$OFF" ;;
    "")    printf '%s%s--version said nothing — carrying on, but that is odd%s\n' \
             "$YELLOW" "" "$OFF" ;;
    *)     printf '%sversion: %s — expected 4.7.x. Set GODOT=/path/to/4.7 if you have one;%s\n' \
             "$YELLOW" "$GODOT_VERSION" "$OFF"
           printf '%s         anything red below may be the version rather than the code.%s\n' \
             "$YELLOW" "$OFF" ;;
  esac
fi

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
  # A fresh clone has no game/.godot, so the first thing Godot does is import the entire
  # project — minutes, on no display, with every line of it going into the log file this
  # check redirects to. The gate looks frozen. It is not frozen; it is importing, and the
  # first person that happened to reasonably assumed it had hung.
  #
  # CI has always done this as a separate step before calling check.sh. That was the bug:
  # a gate that only works when something else went first is not the same gate, and the
  # only machine where the difference shows is a brand new clone — which is exactly the
  # machine you least want lying to you.
  if [ ! -d game/.godot ]; then
    printf '    %simporting the project for the first time — a few minutes, once ever%s\n' \
      "$DIM" "$OFF"
    IMPORT_LOG="$(mktemp)"
    run_with_limit "$IMPORT_LIMIT" \
      "$GODOT_BIN" --headless --path game --import >"$IMPORT_LOG" 2>&1
    IMPORT_EXIT=$?
    if [ "$IMPORT_EXIT" -eq 124 ]; then
      fail "the import did not finish inside ${IMPORT_LIMIT}s — killed it"
      sed -e 's/^/      /' "$IMPORT_LOG" | tail -15
    elif [ ! -d game/.godot ]; then
      fail "the import ran but produced no game/.godot — Godot is not happy with this project"
      sed -e 's/^/      /' "$IMPORT_LOG" | tail -15
    else
      printf '    %simported%s\n' "$DIM" "$OFF"
    fi
    rm -f "$IMPORT_LOG"
  fi

  TEST_LOG="$(mktemp)"
  run_with_limit "$TEST_LIMIT" \
    "$GODOT_BIN" --headless --path game res://tests/test_main.tscn >"$TEST_LOG" 2>&1
  TEST_EXIT=$?
  SUMMARY=$(grep '^TEST_DONE' "$TEST_LOG" | tail -1)
  if [ "$TEST_EXIT" -eq 124 ]; then
    fail "the suite was still running after ${TEST_LIMIT}s — killed it. It takes about 4."
    sed -e 's/^/      /' "$TEST_LOG" | tail -25
  elif [ -z "$SUMMARY" ]; then
    fail "the suite never printed TEST_DONE — it crashed or hung before finishing"
    sed -e 's/^/      /' "$TEST_LOG" | tail -25
  elif [ "$TEST_EXIT" -ne 0 ] || ! echo "$SUMMARY" | grep -q 'failed=0'; then
    fail "$SUMMARY"
    grep -E '^  FAIL|^          - ' "$TEST_LOG" | sed -e 's/^/      /'
  elif grep -qE "Parse Error|Nonexistent function|Invalid call|Invalid access|Invalid get index|Trying to (call|assign)" "$TEST_LOG"; then
    # A green suite is not the same as a suite that ran. When GDScript hits a runtime error it
    # prints, abandons the current function, and returns to the caller — so a case whose body dies
    # halfway through reports as PASSED with fewer checks than it should have had, and nothing says
    # so. That happened at C4: `case_fire.gd` called a method that does not exist on `ResolvedAsset`,
    # four of its five sections died on their first line, and the suite said `ok fire 9 checks`.
    #
    # `Parse Error` is in the list because of a second way the suite can be green and wrong: a
    # script the tests never touch can fail to compile entirely, and nothing notices. That happened
    # at C4b to `play_setup.gd` — the whole file was broken, the gate was green, and the only
    # symptom was the game not starting.
    #
    # Only errors that are never deliberate are listed here. Cases that provoke `push_error` on
    # purpose — the module boundary refusals, the validator's — do not match, because those are
    # error *messages* rather than the engine reporting that the script itself is wrong.
    fail "the suite is green but a case crashed on its way through — a passing case that never ran"
    grep -E "Parse Error|Nonexistent function|Invalid call|Invalid access|Invalid get index|Trying to (call|assign)" -A 2 "$TEST_LOG" \
      | sed -e 's/^/      /' | head -20
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
