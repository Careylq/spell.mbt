#!/usr/bin/env bash
#
# conformance/run.sh — run this library against the official Hunspell test corpus
# and print a pass-rate report.
#
# The corpus (hunspell/hunspell, tests/) is LGPL-2.1. This project is Apache-2.0, so the
# corpus is NEVER vendored into this repository: it is cloned into a temporary directory
# at run time and only the resulting numbers are kept.
#
# Usage:
#   bash conformance/run.sh                       # clone the corpus to a temp dir
#   HUNSPELL_DIR=/path/to/hunspell bash conformance/run.sh
#   CONFORMANCE_REQUIRE_CLI=1 bash conformance/run.sh   # fail instead of skipping
#
# Exit status:
#   0  report produced (or skipped when the CLI is not ready yet)
#   1  a real failure (or a skip when CONFORMANCE_REQUIRE_CLI=1)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.moon/bin:$PATH"

# ---------------------------------------------------------------- locate corpus
CLEANUP=""
if [ -n "${HUNSPELL_DIR:-}" ]; then
  TESTS="$HUNSPELL_DIR/tests"
  if [ ! -d "$TESTS" ]; then
    echo "ERROR: HUNSPELL_DIR=$HUNSPELL_DIR has no tests/ directory" >&2
    exit 1
  fi
else
  TMP="$(mktemp -d)"
  CLEANUP="$TMP"
  echo "Cloning hunspell test corpus into $TMP ..."
  if ! git clone --depth 1 --quiet https://github.com/hunspell/hunspell "$TMP/hunspell"; then
    echo "ERROR: could not clone the corpus. Set HUNSPELL_DIR to a local checkout." >&2
    exit 1
  fi
  TESTS="$TMP/hunspell/tests"
fi
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT

# ---------------------------------------------------- check the CLI is available
# Contract (see conformance/README.md):
#   moon run cmd/main -- check --aff <a.aff> --dic <d.dic> --words -
#   reads words from stdin, prints one "1" (correct) or "0" (incorrect) per line.
PROBE_AFF="$(find "$TESTS" -name '*.aff' | head -1)"
PROBE_DIC="${PROBE_AFF%.aff}.dic"
CLI_OK=0
if [ -n "$PROBE_AFF" ] && [ -f "$PROBE_DIC" ] && [ -d cmd/main ]; then
  if printf 'the\nthe\n' | moon run cmd/main -- check --aff "$PROBE_AFF" --dic "$PROBE_DIC" --words - \
       >/dev/null 2>&1; then
    CLI_OK=1
  fi
fi

if [ "$CLI_OK" -ne 1 ]; then
  echo
  echo "SKIP: the 'check' subcommand is not available yet, so no conformance numbers can be produced."
  echo "      Implement cmd/main 'check' per conformance/README.md, then re-run this script."
  if [ "${CONFORMANCE_REQUIRE_CLI:-0}" = "1" ]; then
    echo "FAIL: CONFORMANCE_REQUIRE_CLI=1 but the CLI is not ready." >&2
    exit 1
  fi
  exit 0
fi

# ------------------------------------------------------------------- run suites
printf '%-34s %-16s %-16s\n' "suite" "good" "wrong"
printf -- '----------------------------------------------------------------------\n'

total_good_pass=0; total_good=0
total_wrong_pass=0; total_wrong=0
suites=0

run_words() {   # $1=aff $2=dic $3=words-file  -> prints one 1/0 per input line
  moon run cmd/main -- check --aff "$1" --dic "$2" --words - < "$3" 2>/dev/null
}

for aff in $(find "$TESTS" -name '*.aff' | sort); do
  base="${aff%.aff}"
  dic="$base.dic"
  [ -f "$dic" ] || continue

  good="$base.good"; wrong="$base.wrong"
  [ -f "$good" ] || [ -f "$wrong" ] || continue

  g_pass=0; g_tot=0
  w_pass=0; w_tot=0

  if [ -f "$good" ]; then
    got="$(run_words "$aff" "$dic" "$good")"
    # compare line by line against the expectation "1"
    g_tot=$(grep -c . "$good")
    g_pass=$(paste -d' ' <(grep . "$good") <(printf '%s\n' "$got") 2>/dev/null | awk '$2==1' | wc -l | tr -d ' ')
  fi

  if [ -f "$wrong" ]; then
    got="$(run_words "$aff" "$dic" "$wrong")"
    w_tot=$(grep -c . "$wrong")
    w_pass=$(paste -d' ' <(grep . "$wrong") <(printf '%s\n' "$got") 2>/dev/null | awk '$2==0' | wc -l | tr -d ' ')
  fi

  suites=$((suites + 1))
  total_good_pass=$((total_good_pass + g_pass));  total_good=$((total_good + g_tot))
  total_wrong_pass=$((total_wrong_pass + w_pass)); total_wrong=$((total_wrong + w_tot))

  printf '%-34s %-16s %-16s\n' \
    "$(basename "$base")" \
    "${g_pass}/${g_tot}" \
    "${w_pass}/${w_tot}"
done

printf -- '----------------------------------------------------------------------\n'
printf '%-34s %-16s %-16s\n' "TOTAL ($suites suites)" \
  "${total_good_pass}/${total_good}" "${total_wrong_pass}/${total_wrong}"

pct() { [ "$2" -eq 0 ] && echo "n/a" || awk "BEGIN{printf \"%.1f%%\", 100*$1/$2}"; }
echo
echo "good  pass rate: $(pct "$total_good_pass" "$total_good")"
echo "wrong pass rate: $(pct "$total_wrong_pass" "$total_wrong")"
echo
echo "Copy these numbers into the Conformance table in README.mbt.md — do not estimate them."
