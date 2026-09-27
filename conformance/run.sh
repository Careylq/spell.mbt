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

# ---------------------------------------------------- check the CLI is available
# Contract (see conformance/README.md):
#   moon run cmd/main -- check --aff <a.aff> --dic <d.dic> --words -
#   reads words from stdin, prints one "1" (correct) or "0" (incorrect) per line.
#
# The probe uses a synthetic dictionary created right here, so that skipping never
# touches the network. It also verifies the OUTPUT SHAPE: a program that ignores its
# arguments and prints nothing must not be mistaken for a working CLI — otherwise an
# empty run would be reported as a genuine 0% pass rate.
PROBE_DIR="$(mktemp -d)"
cat > "$PROBE_DIR/probe.aff" <<'PROBE_AFF_EOF'
SET UTF-8
TRY abcdefghijklmnopqrstuvwxyz
PROBE_AFF_EOF
cat > "$PROBE_DIR/probe.dic" <<'PROBE_DIC_EOF'
2
hello
world
PROBE_DIC_EOF

CLI_OK=0
if [ -d cmd/main ]; then
  probe_out="$(printf 'hello\nzzzz\n' \
    | moon run cmd/main -- check --aff "$PROBE_DIR/probe.aff" --dic "$PROBE_DIR/probe.dic" --words - 2>/dev/null)"
  n_lines="$(printf '%s\n' "$probe_out" | grep -cE '^[01]$' || true)"
  if [ "$n_lines" = "2" ] \
     && [ "$(printf '%s\n' "$probe_out" | sed -n 1p)" = "1" ] \
     && [ "$(printf '%s\n' "$probe_out" | sed -n 2p)" = "0" ]; then
    CLI_OK=1
  fi
fi
rm -rf "$PROBE_DIR"

if [ "$CLI_OK" -ne 1 ]; then
  echo
  echo "SKIP: the 'check' subcommand is missing or does not follow the contract,"
  echo "      so no conformance numbers can be produced."
  echo "      Expected: 'hello' then 'zzzz' on stdin -> two lines of 0/1, i.e. 1 then 0."
  echo "      See conformance/README.md for the CLI contract."
  if [ "${CONFORMANCE_REQUIRE_CLI:-0}" = "1" ]; then
    echo "FAIL: CONFORMANCE_REQUIRE_CLI=1 but the CLI is not ready." >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------- locate corpus
# Fetched only once the CLI is known to work, so skipping costs no network.
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

# ------------------------------------------------------------------- run suites
printf '%-34s %-16s %-16s\n' "suite" "good" "wrong"
printf -- '----------------------------------------------------------------------\n'

total_good_pass=0; total_good=0
total_wrong_pass=0; total_wrong=0
# Positional (historical) figures, see the note under the totals.
total_good_pass_pos=0
total_wrong_pass_pos=0
mismatched=0
suites=0

run_words() {   # $1=aff $2=dic $3=words-file  -> prints one 1/0 per input line
  moon run cmd/main -- check --aff "$1" --dic "$2" --words - < "$3" 2>/dev/null
}

# The CLI emits exactly one verdict per NON-EMPTY input line, in input order, so the
# verdicts can simply be counted -- no positional pairing is needed. The older
# implementation paired the two streams with `paste -d' '`, which silently
# misaligns whenever a corpus line contains a space (e.g. morph.good's "drink eat"
# lines), so those lines were scored as failures no matter what the engine said.
# The positional figure is still computed and reported for comparability.
score() {       # $1=words-file $2=expected-verdict(1|0) $3=actual-output  -> pass count
  local in_lines out_lines pass
  in_lines=$(grep -c . "$1" || true)
  out_lines=$(printf '%s\n' "$3" | grep -c . || true)
  if [ "$in_lines" = "$out_lines" ]; then
    pass=$(printf '%s\n' "$3" | grep -c "^$2\$" || true)
  else
    echo "  ! $(basename "${1%.*}")"": $out_lines verdicts for $in_lines input lines" >&2
    mismatched=$((mismatched + 1))
    pass=$(paste -d' ' <(grep . "$1") <(printf '%s\n' "$3") 2>/dev/null \
           | awk -v e="$2" '$2==e' | wc -l | tr -d ' ')
  fi
  printf '%s' "${pass:-0}"
}

for aff in $(find "$TESTS" -name '*.aff' | sort); do
  base="${aff%.aff}"
  dic="$base.dic"
  [ -f "$dic" ] || continue

  good="$base.good"; wrong="$base.wrong"
  [ -f "$good" ] || [ -f "$wrong" ] || continue

  g_pass=0; g_tot=0; g_pass_pos=0
  w_pass=0; w_tot=0; w_pass_pos=0

  if [ -f "$good" ]; then
    got="$(run_words "$aff" "$dic" "$good")"
    g_tot=$(grep -c . "$good" || true)
    g_pass=$(score "$good" 1 "$got")
    g_pass_pos=$(paste -d' ' <(grep . "$good") <(printf '%s\n' "$got") 2>/dev/null | awk '$2==1' | wc -l | tr -d ' ')
  fi

  if [ -f "$wrong" ]; then
    got="$(run_words "$aff" "$dic" "$wrong")"
    w_tot=$(grep -c . "$wrong" || true)
    w_pass=$(score "$wrong" 0 "$got")
    w_pass_pos=$(paste -d' ' <(grep . "$wrong") <(printf '%s\n' "$got") 2>/dev/null | awk '$2==0' | wc -l | tr -d ' ')
  fi

  suites=$((suites + 1))
  total_good_pass=$((total_good_pass + g_pass));  total_good=$((total_good + g_tot))
  total_wrong_pass=$((total_wrong_pass + w_pass)); total_wrong=$((total_wrong + w_tot))
  total_good_pass_pos=$((total_good_pass_pos + g_pass_pos))
  total_wrong_pass_pos=$((total_wrong_pass_pos + w_pass_pos))

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
echo "Counted per verdict (the figures above). One verdict is emitted per non-empty"
echo "input line, in order, so counting is exact even for corpus lines containing a"
echo "space (morph.good has 16 of them)."
echo
echo "For comparability with earlier runs, the historical POSITIONAL figures were:"
echo "  good  ${total_good_pass_pos}/${total_good}  ($(pct "$total_good_pass_pos" "$total_good"))"
echo "  wrong ${total_wrong_pass_pos}/${total_wrong}  ($(pct "$total_wrong_pass_pos" "$total_wrong"))"
echo "Those paired the two streams with 'paste -d\" \"', which silently misaligns any"
echo "line containing a space, so such lines were always scored as failures. The gap"
echo "between the two figures is the size of that measurement artefact, not a"
echo "behaviour difference."
if [ "$mismatched" -gt 0 ]; then
  echo
  echo "WARNING: $mismatched suite(s) emitted a different number of verdicts than input"
  echo "lines; those fell back to the positional comparison. See the messages above." >&2
fi
echo
echo "Copy these numbers into the Conformance table in README.mbt.md — do not estimate them."
