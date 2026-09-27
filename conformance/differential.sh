#!/usr/bin/env bash
#
# conformance/differential.sh — differential test against the real hunspell binary.
#
#   bash conformance/differential.sh [word-list]
#
# The Hunspell test corpus (`conformance/run.sh`) is a set of hand-written cases.
# This script is the complementary measurement: a whole real word list, judged by
# both engines, with every disagreement printed. It answers "how often do we
# actually differ from Hunspell on real words", which the corpus cannot.
#
# What it does
# ------------
#   1. Fetches the LibreOffice en_US dictionary into a temp dir (never vendored).
#   2. Judges the word list with THIS library and with `hunspell -l`.
#   3. Prints the disagreements in both directions and a rate.
#
# The two directions mean different things:
#   * we reject, hunspell accepts  -> a FALSE REJECT (we are too strict)
#   * we accept, hunspell rejects  -> a FALSE ACCEPT (we are too lax)
#
# Exit status
# -----------
#   0  a measurement was produced (disagreements are a FINDING, not a failure)
#   1  the measurement could not be taken (no dictionary, no hunspell, CLI broken)
#
# Nothing is written into the repository; the dictionary and the verdict files live
# in a temp directory that is removed on exit.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.moon/bin:$PATH"

WORDS="${1:-/usr/share/dict/words}"
DICT_AFF_URL="https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master/en/en_US.aff"
DICT_DIC_URL="https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master/en/en_US.dic"

DEFAULT_WORDS=1
[ $# -gt 0 ] && DEFAULT_WORDS=0

have() { command -v "$1" >/dev/null 2>&1; }

hr() { printf -- '--------------------------------------------------------------------------------\n'; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

hr
echo "spell.mbt — differential test against the system hunspell"
hr

if ! have hunspell; then
  echo "ERROR: hunspell is not on PATH; there is nothing to compare against." >&2
  echo "       (macOS: brew install hunspell; Debian/Ubuntu: apt install hunspell)" >&2
  exit 1
fi

# ---------------------------------------------------------------- word list
if [ "$DEFAULT_WORDS" = "1" ] && [ ! -r "$WORDS" ]; then
  echo "ERROR: no word list at $WORDS and none was given." >&2
  echo "       Pass one explicitly: bash conformance/differential.sh <word-list>" >&2
  exit 1
fi
if [ ! -r "$WORDS" ]; then
  echo "ERROR: cannot read the word list '$WORDS'." >&2
  exit 1
fi

# The CLI emits one verdict per NON-EMPTY line, so blank lines are dropped here and
# the verdicts are paired with the remaining lines by index. Nothing else is
# normalised: a differential test must not quietly rewrite its own input.
grep . "$WORDS" > "$TMP/words.txt"
N_WORDS="$(wc -l < "$TMP/words.txt" | tr -d ' ')"
if [ "$N_WORDS" = "0" ]; then
  echo "ERROR: '$WORDS' has no non-empty lines." >&2
  exit 1
fi

# ---------------------------------------------------------------- dictionary
if ! have curl; then
  echo "ERROR: curl is needed to fetch the dictionary (it is never vendored)." >&2
  exit 1
fi

echo "word list : $WORDS ($N_WORDS non-empty lines)"
echo "hunspell  : $(hunspell -v 2>&1 | grep -o 'Hunspell [0-9][0-9.]*' | head -1) at $(command -v hunspell)"
echo "fetching the en_US dictionary from jsDelivr ..."

fetch() { # <url> <out>
  local attempt
  for attempt in 1 2 3; do
    if curl -fsSL --max-time 120 -o "$2" "$1" 2>/dev/null; then return 0; fi
    sleep 3
  done
  return 1
}
if ! fetch "$DICT_AFF_URL" "$TMP/en_US.aff" || ! fetch "$DICT_DIC_URL" "$TMP/en_US.dic"; then
  echo "ERROR: could not fetch the dictionary (network unavailable)." >&2
  exit 1
fi
echo "dictionary: $TMP/en_US.aff + en_US.dic"

# The dictionaries are never written into the repository, so this script leaves no
# artefact behind but the findings it prints.
if [ ! -f "$TMP/en_US.dic" ]; then
  echo "ERROR: the dictionary fetch produced no .dic." >&2
  exit 1
fi

# ---------------------------------------------------------------- our verdicts
# `--words -` streams the list on stdin, which keeps this independent of the
# backend's argv handling. The CLI contract is asserted before the numbers are
# trusted: an empty or truncated output would otherwise read as "everything is
# rejected" and fabricate a huge false-reject count.
OURS="$TMP/ours.txt"

PROBE_DIR="$TMP/probe"; mkdir -p "$PROBE_DIR"
printf 'SET UTF-8\n' > "$PROBE_DIR/p.aff"
printf '2\nhello\nworld\n' > "$PROBE_DIR/p.dic"
printf 'hello\nzzzz\n' > "$PROBE_DIR/p.words"
PROBE_OUT="$(moon run cmd/main -- check --aff "$PROBE_DIR/p.aff" --dic "$PROBE_DIR/p.dic" --words - < "$PROBE_DIR/p.words" 2>/dev/null)"
if [ "$PROBE_OUT" != "$(printf '1\n0')" ]; then
  echo "ERROR: the 'check' CLI does not follow the conformance contract; no comparison is meaningful." >&2
  echo "       Got: $(printf '%s' "$PROBE_OUT" | tr '\n' ' ')" >&2
  exit 1
fi

moon run cmd/main -- check --aff "$TMP/en_US.aff" --dic "$TMP/en_US.dic" --words - \
  < "$TMP/words.txt" 2>/dev/null | grep . > "$OURS"
N_OURS="$(wc -l < "$OURS" | tr -d ' ')"
if [ "$N_OURS" != "$N_WORDS" ]; then
  echo "ERROR: $N_OURS verdicts for $N_WORDS input lines; the pairing would be wrong." >&2
  exit 1
fi

# Pair by LINE NUMBER, not with a delimiter: a word may itself contain a tab (the
# corpus has such cases), and any `paste`/`awk -F` pairing would then split it into
# the wrong fields. Reading the two files positionally cannot make that mistake.
awk 'NR == FNR { word[FNR] = $0; next } $0 == 0 { print word[FNR] }' \
  "$TMP/words.txt" "$OURS" | sort -u > "$TMP/ours-rejected.txt"

# ---------------------------------------------------------------- their verdicts
hunspell -d "$TMP/en_US" -l "$TMP/words.txt" 2>/dev/null | sort -u > "$TMP/hun-rejected.txt"

OURS_N="$(wc -l < "$TMP/ours-rejected.txt" | tr -d ' ')"
HUN_N="$(wc -l < "$TMP/hun-rejected.txt" | tr -d ' ')"

comm -23 "$TMP/ours-rejected.txt" "$TMP/hun-rejected.txt" > "$TMP/false-reject.txt"
comm -13 "$TMP/ours-rejected.txt" "$TMP/hun-rejected.txt" > "$TMP/false-accept.txt"
FR="$(wc -l < "$TMP/false-reject.txt" | tr -d ' ')"
FA="$(wc -l < "$TMP/false-accept.txt" | tr -d ' ')"

pct() { awk -v a="$1" -v b="$2" 'BEGIN{ if (b <= 0) printf "n/a"; else printf "%.3f%%", 100 * a / b }'; }

# ---------------------------------------------------------------------- report
echo
hr
printf '  %-34s %10s\n' "words judged" "$N_WORDS"
printf '  %-34s %10s\n' "rejected by this library" "$OURS_N"
printf '  %-34s %10s\n' "rejected by hunspell" "$HUN_N"
echo
printf '  %-34s %10s  %s\n' "FALSE REJECTS (we reject, they accept)" "$FR" "$(pct "$FR" "$N_WORDS")"
printf '  %-34s %10s  %s\n' "FALSE ACCEPTS (we accept, they reject)" "$FA" "$(pct "$FA" "$N_WORDS")"
printf '  %-34s %10s  %s\n' "total disagreement" "$((FR + FA))" "$(pct "$((FR + FA))" "$N_WORDS")"

if [ "$FA" -gt 0 ]; then
  echo
  echo "false accepts (this library too lax):"
  sed 's/^/    /' "$TMP/false-accept.txt"
fi
if [ "$FR" -gt 0 ]; then
  echo
  echo "false rejects (this library too strict):"
  sed 's/^/    /' "$TMP/false-reject.txt"
fi

echo
hr
echo "Every count above is measured here. A non-zero disagreement count is a"
echo "RESULT, not a harness failure: the two engines are independent"
echo "implementations and some corpus words exercise behaviour the hunspell(5)"
echo "manual documents only by flag. Reproduce with:"
echo "  bash conformance/differential.sh"
exit 0
