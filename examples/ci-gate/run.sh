#!/usr/bin/env bash
#
# examples/ci-gate/run.sh — prove, offline and in one command, that `doccheck`'s exit
# status can gate a CI step.
#
#   bash examples/ci-gate/run.sh
#
# Why this example exists
# -----------------------
# This project's application form promised, as its second usage scenario, a tool whose
# "exit status can be embedded in a pipeline to intercept spelling errors
# automatically". `examples/doccheck` implements that contract:
#
#   0  no misspelling left after the allowlist
#   1  misspellings found
#   2  usage or I/O error
#
# A promise in prose is not a demonstration, so this script runs the cases for real and
# asserts each exit status. It needs NO network and NO vendored data — the dictionary is
# written from scratch below.
#
# Exit status: 0 when every case behaved as documented, 1 otherwise, so this script can
# itself be used from CI.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.moon/bin:$PATH"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

hr() { printf -- '--------------------------------------------------------------------------------\n'; }

# ------------------------------------------------------------------ fixtures
# A five-word dictionary. "delibberate" is deliberately absent from it, and `notes`
# is present because the Markdown heading below is prose that gets checked too.
printf 'SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\n' > "$TMP/tiny.aff"
printf '5\nhello\nworld\nclean\ntext\nnotes\n' > "$TMP/tiny.dic"
mkdir -p "$TMP/docs"

DICT=(--aff "$TMP/tiny.aff" --dic "$TMP/tiny.dic")
RC=0
FAILED=0

write_clean() { printf '# Notes\n\nhello world clean text\n' > "$TMP/docs/doc.md"; }
write_typo()  { printf '# Notes\n\nhello delibberate world\n' > "$TMP/docs/doc.md"; }

expect() { # <label> <expected-rc>
  local label="$1" expected="$2"
  if [ "$RC" = "$expected" ]; then
    printf '  %-42s expected %s  got %s  ok\n' "$label" "$expected" "$RC"
  else
    printf '  %-42s expected %s  got %s  UNEXPECTED\n' "$label" "$expected" "$RC"
    sed 's/^/      | /' "$TMP/out.txt"
    FAILED=1
  fi
}

hr
echo "spell.mbt — doccheck as a CI gate"
hr
echo "dictionary : written from scratch in this script (offline, nothing vendored)"
echo "contract   : 0 clean / 1 misspellings / 2 usage or I/O error"
echo
echo "cases:"

# 1. A clean tree passes — which is what makes the step usable as a gate at all.
write_clean
moon run examples/doccheck -- "${DICT[@]}" "$TMP/docs" > "$TMP/out.txt" 2>&1
RC=$?
expect "clean tree" 0

# 2. A typo fails the step. This is the promise being kept.
write_typo
moon run examples/doccheck -- "${DICT[@]}" "$TMP/docs" > "$TMP/out.txt" 2>&1
RC=$?
expect "one typo present" 1

# 3. --no-fail opts out, for callers that only want the numbers (which is how the
#    measurements recorded in examples/README.md are taken).
moon run examples/doccheck -- "${DICT[@]}" --no-fail "$TMP/docs" > "$TMP/out.txt" 2>&1
RC=$?
expect "one typo present, --no-fail" 0

# 4. A missing dictionary is a TOOL error, not a typo. It must be 2 and not 1, or a
#    broken setup would be indistinguishable from a documentation problem.
moon run examples/doccheck -- --aff "$TMP/nope.aff" --dic "$TMP/tiny.dic" "$TMP/docs" \
  > "$TMP/out.txt" 2>&1
RC=$?
expect "missing dictionary file" 2

# 5. No arguments at all is a usage error, and must also be 2.
moon run examples/doccheck -- > "$TMP/out.txt" 2>&1
RC=$?
expect "no arguments" 2

# ------------------------------------------------- the CLI's own exit statuses
#
# `cmd/main` is a *different* contract from `doccheck`: it prints one verdict per input
# line and exits 0 even when a word is rejected, because the conformance and benchmark
# harnesses read that verdict stream and would break otherwise. What it does use a
# non-zero status for is being *called wrong* -- and those paths had no gate at all,
# which is how `spell --help` could answer "unknown subcommand" unnoticed. These cases
# are here because the status is the contract.

hr
echo "the CLI's own exit statuses (cmd/main):"
echo

moon run cmd/main -- --help > "$TMP/out.txt" 2>&1
RC=$?
expect "spell --help" 0

moon run cmd/main -- check --help > "$TMP/out.txt" 2>&1
RC=$?
expect "spell check --help" 0

moon run cmd/main -- suggest -h > "$TMP/out.txt" 2>&1
RC=$?
expect "spell suggest -h" 0

# Requesting help writes to stdout so it can be piped; an error writes to stderr, so a
# caller can still separate the two. Both halves are asserted, because getting the
# wrong stream is the kind of bug a status check alone would not catch.
moon run cmd/main -- --help > "$TMP/out.txt" 2> "$TMP/err.txt"
if [ -s "$TMP/out.txt" ] && [ ! -s "$TMP/err.txt" ]; then
  printf '  %-42s expected %s  got %s  ok\n' "--help on stdout, nothing on stderr" "yes" "yes"
else
  printf '  %-42s expected %s  got %s  UNEXPECTED\n' "--help on stdout, nothing on stderr" "yes" "no"
  FAILED=1
fi

moon run cmd/main -- check --aff > "$TMP/out.txt" 2>&1
RC=$?
expect "flag with no value" 2

moon run cmd/main -- nosuchcommand > "$TMP/out.txt" 2>&1
RC=$?
expect "unknown subcommand" 2

moon run cmd/main -- > "$TMP/out.txt" 2>&1
RC=$?
expect "no arguments" 2



echo
echo "the gate written the way a workflow would use it:"
echo
echo "  - name: Spell-check the documentation"
echo "    run: bash examples/doccheck/run.sh --quiet"
echo
hr
if [ "$FAILED" = "0" ]; then
  echo "every case behaved as documented."
  exit 0
fi
echo "SOME CASES DID NOT BEHAVE AS DOCUMENTED." >&2
exit 1
