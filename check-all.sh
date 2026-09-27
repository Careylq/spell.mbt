#!/usr/bin/env bash
#
# check-all.sh — one command for the pre-submission check.
#
#   bash check-all.sh              # writes reports into .final-check/
#   bash check-all.sh /tmp/report  # ...or into a directory you choose
#
# It exists because the numbers in this repository's documentation are re-measured
# before every submission: this project's history includes a performance figure that had
# silently drifted 2.3×, a conformance figure that was 1.9 points too low for weeks, and
# a doccheck figure invalidated by the documentation it described. All three were found
# by re-running the measurement, none by reading the code.
#
# The two phases are deliberately different:
#
#   Phase 1 — GATES. If any of these fails the script exits non-zero, because they are
#             correctness, not measurement. Offline.
#   Phase 2 — MEASUREMENTS. Always run, saved to files, drift is reported and never
#             fatal. Some need the network and a system `hunspell`; a skipped one says so.
#
# Exit status: 0 when every gate passed (measurements may still have drifted), 1 when a
# gate failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.moon/bin:$PATH"

OUT="${1:-$REPO_ROOT/.final-check}"
mkdir -p "$OUT"

hr() { printf -- '--------------------------------------------------------------------------------\n'; }
GATES_FAILED=0

gate() { # <label> <command...>
  local label="$1"; shift
  printf '  %-46s ' "$label"
  if "$@" > "$OUT/gate-$(printf '%s' "$label" | tr ' /' '__').txt" 2>&1; then
    echo "ok"
  else
    echo "FAILED"
    tail -12 "$OUT/gate-$(printf '%s' "$label" | tr ' /' '__').txt" | sed 's/^/      | /'
    GATES_FAILED=1
  fi
}

hr
echo "spell.mbt — pre-submission check"
hr
echo "date      : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "commit    : $(git rev-parse --short HEAD 2>/dev/null || echo '(not a git checkout)')"
echo "version   : $(grep '^version' moon.mod 2>/dev/null | head -1)"
echo "reports   : $OUT"
echo
echo "phase 1 — gates (must pass)"

gate "moon check --deny-warn --target all" moon check --deny-warn --target all
gate "moon fmt --check" moon fmt --check
gate "moon test --target all" moon test --target all

# `.mbti` (the generated public interface) must not change: a diff there means the change
# was NOT the internal refactor it was described as.
printf '  %-46s ' "public interface unchanged (.mbti)"
moon info > "$OUT/gate-moon-info.txt" 2>&1
MBTI_DIFF="$(git diff --stat -- '*.mbti' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$MBTI_DIFF" = "0" ]; then
  echo "ok"
else
  echo "CHANGED"
  git diff --stat -- '*.mbti' | sed 's/^/      | /'
  GATES_FAILED=1
fi

gate "doccheck exit-status contract (offline)" bash examples/ci-gate/run.sh

echo
echo "phase 2 — measurements (reported, never fatal)"

measure() { # <label> <outfile> <command...>
  local label="$1" out="$2"; shift 2
  printf '  %-46s ' "$label"
  if "$@" > "$OUT/$out" 2>&1; then
    echo "done -> $out"
  else
    local rc=$?
    # 3 from doccheck's wrapper means "no dictionary", not a failure.
    if [ "$rc" = "3" ]; then
      echo "SKIPPED (no dictionary) -> $out"
    else
      echo "exited $rc -> $out"
    fi
  fi
}

measure "doccheck on this repository" doccheck.txt bash examples/doccheck/run.sh --quiet
measure "conformance (.good / .wrong)" conformance.txt bash conformance/run.sh
measure "suggestion quality (.sug)" suggest.txt bash conformance/suggest.sh
measure "differential vs real hunspell" differential.txt bash conformance/differential.sh
measure "performance and artifacts" bench.txt bash bench/run.sh

# ------------------------------------------------------------------- summary
hr
echo "headline numbers (copied from the reports above, not recomputed)"

show() { # <file> <grep-pattern> [max-lines]
  local n="${3:-4}"
  [ -f "$OUT/$1" ] || return 0
  grep -E "$2" "$OUT/$1" 2>/dev/null | sed 's/^/  /' | head -"$n"
}

if [ -f "$OUT/conformance.txt" ]; then
  echo
  echo "conformance:"
  show conformance.txt 'good +pass rate|wrong +pass rate|^TOTAL'
fi
if [ -f "$OUT/differential.txt" ]; then
  echo
  echo "differential:"
  show differential.txt 'FALSE REJECTS|FALSE ACCEPTS|total disagreement|words judged'
fi
if [ -f "$OUT/doccheck.txt" ]; then
  echo
  echo "dogfooding:"
  show doccheck.txt 'words checked|misspelled tokens|distinct words'
fi
if [ -f "$OUT/bench.txt" ]; then
  echo
  echo "performance (native vs hunspell):"
  # Take the labelled rows only: the section headers make the two bare "per word"
  # rows unambiguous, and matching them keeps the wasm section out of the summary.
  show bench.txt 'load only \(s\)|all hits \(the dictionary|all misses \(each entry|per word \(µs\)|^  235976 words' 8
fi

# ------------------------------------------------------------------- warnings
# Phase 2 never fails the run, but one of its measurements IS a gate in CI: the
# documentation's own spell check. Say so loudly here rather than burying it.
WARNED=0
if [ -f "$OUT/doccheck.txt" ]; then
  TOKENS="$(awk -F: '/misspelled tokens/ { gsub(/ /, "", $2); print $2 }' "$OUT/doccheck.txt")"
  if [ -n "$TOKENS" ] && [ "$TOKENS" != "0" ]; then
    echo
    echo "WARNING: this repository's own prose has $TOKENS flagged token(s):"
    sed -n '/distinct misspelled words/,$p' "$OUT/doccheck.txt" | sed 's/^/  /' | head -12
    echo "  Either add the legitimate ones to examples/doccheck/allowlist.txt or reword."
    echo "  This is a BLOCKING step in .github/workflows/ci.yml, so CI will be red."
    WARNED=1
  fi
fi

hr
if [ "$GATES_FAILED" = "0" ] && [ "$WARNED" = "0" ]; then
  echo "every gate passed. Copy the headline numbers into README.mbt.md, ACCEPTANCE.md"
  echo "and the submission notes before submitting — do not reuse last time's figures."
  exit 0
fi
if [ "$GATES_FAILED" = "0" ]; then
  echo "every gate passed, with the warning(s) above to resolve before submitting."
  exit 0
fi
echo "A GATE FAILED. Fix that before looking at any measurement." >&2
exit 1
