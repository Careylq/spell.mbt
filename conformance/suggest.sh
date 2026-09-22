#!/usr/bin/env bash
#
# conformance/suggest.sh — measure the suggestion engine against the corpus `.sug` files.
#
# This script is ADDITIVE. It never touches the `.good`/`.wrong` computation in
# `conformance/run.sh`; run that script separately for the judgement numbers.
#
# The corpus (hunspell/hunspell, tests/) is LGPL-2.1. This project is Apache-2.0, so the
# corpus is NEVER vendored into this repository: it is cloned into a temporary directory
# at run time and only the resulting numbers are kept.
#
# Usage:
#   bash conformance/suggest.sh                       # clone the corpus to a temp dir
#   HUNSPELL_DIR=/path/to/hunspell bash conformance/suggest.sh
#   CONFORMANCE_REQUIRE_CLI=1 bash conformance/suggest.sh   # fail instead of skipping
#
# Exit status:
#   0  report produced (or skipped when the CLI is not ready)
#   1  a real failure (or a skip when CONFORMANCE_REQUIRE_CLI=1)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.moon/bin:$PATH"

# ---------------------------------------------------- check the CLI is available
# Contract:
#   moon run cmd/main -- suggest --aff <a.aff> --dic <d.dic> --words -
#   reads words from stdin, prints one line per input word: the suggestions
#   joined by ", ", or an empty line when there are none.
PROBE_DIR="$(mktemp -d)"
cat > "$PROBE_DIR/probe.aff" <<'PROBE_AFF_EOF'
SET UTF-8
TRY abcdefghijklmnopqrstuvwxyz
REP 1
REP ph f
PROBE_AFF_EOF
cat > "$PROBE_DIR/probe.dic" <<'PROBE_DIC_EOF'
3
form
hello
world
PROBE_DIC_EOF

CLI_OK=0
if [ -d cmd/main ]; then
  # The last word deliberately has a suggestion so that the empty line for the
  # middle word is not a *trailing* empty line (command substitution strips
  # those, which would make the probe blind to them).
  probe_out="$(printf 'phorm\nzzzz\nhelo\n' \
    | moon run cmd/main -- suggest --aff "$PROBE_DIR/probe.aff" --dic "$PROBE_DIR/probe.dic" --words - 2>/dev/null)"
  n_lines="$(printf '%s\n' "$probe_out" | wc -l | tr -d ' ')"
  if [ "$n_lines" = "3" ] \
     && [ "$(printf '%s\n' "$probe_out" | sed -n 1p)" = "form" ] \
     && [ "$(printf '%s\n' "$probe_out" | sed -n 2p)" = "" ] \
     && [ "$(printf '%s\n' "$probe_out" | sed -n 3p)" = "hello" ]; then
    CLI_OK=1
  fi
fi
rm -rf "$PROBE_DIR"

if [ "$CLI_OK" -ne 1 ]; then
  echo
  echo "SKIP: the 'suggest' subcommand is missing or does not follow the contract,"
  echo "      so no .sug numbers can be produced."
  echo "      Expected: 'phorm' -> form, 'zzzz' -> empty, 'helo' -> hello."
  if [ "${CONFORMANCE_REQUIRE_CLI:-0}" = "1" ]; then
    echo "FAIL: CONFORMANCE_REQUIRE_CLI=1 but the CLI is not ready." >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------- locate corpus
CLEANUP=""
if [ -n "${HUNSPELL_DIR:-}" ]; then
  TESTS="$HUNSPELL_DIR/tests"
  if [ ! -d "$TESTS" ]; then
    echo "ERROR: HUNSPELL_DIR=$HUNSPELL_DIR has no tests/ directory" >&2
    exit 1
  fi
else
  TMP_CLONE="$(mktemp -d)"
  CLEANUP="$TMP_CLONE"
  echo "Cloning hunspell test corpus into $TMP_CLONE ..."
  if ! git clone --depth 1 --quiet https://github.com/hunspell/hunspell "$TMP_CLONE/hunspell"; then
    echo "ERROR: could not clone the corpus. Set HUNSPELL_DIR to a local checkout." >&2
    exit 1
  fi
  TESTS="$TMP_CLONE/hunspell/tests"
fi
WORK="$(mktemp -d)"
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"; rm -rf "$WORK"' EXIT

# ------------------------------------------------------------------- run suites
# For each suite, write one file with our suggestion lines (one per non-empty
# `.wrong` line) and record the paths in a manifest. The metric itself is
# computed by the embedded Python program, which also decodes the `.sug` files
# with the same encoding rules the CLI uses for word input.
MANIFEST="$WORK/manifest.tsv"
: > "$MANIFEST"
suites=0
for sug in $(find "$TESTS" -name '*.sug' | sort); do
  base="${sug%.sug}"
  name="$(basename "$base")"
  [ -f "$base.aff" ] || continue
  [ -f "$base.dic" ] || continue
  [ -f "$base.wrong" ] || continue
  ours="$WORK/$name.ours"
  moon run cmd/main -- suggest --aff "$base.aff" --dic "$base.dic" --words - \
    < "$base.wrong" > "$ours" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$name" "$base.aff" "$sug" "$ours" >> "$MANIFEST"
  suites=$((suites + 1))
done

echo
echo "suggestion metric over $suites corpus suites (.sug files)"
echo

python3 - "$MANIFEST" <<'PYEOF'
import sys

manifest = sys.argv[1]

# ---------------------------------------------------------------- encoding
def detect_aff_encoding(path):
    """The CLI's rule: `SET` decides; otherwise `FLAG UTF-8` means UTF-8;
    otherwise Hunspell's documented default ISO8859-1."""
    data = open(path, "rb").read()
    text = data.decode("latin-1")
    flag_utf8 = False
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("SET") and len(stripped) > 3 and stripped[3:4].isspace():
            name = stripped.split(None, 1)[1]
            if "UTF" in name.upper():
                return "utf-8"
            if "8859-15" in name:
                return "iso8859-15"
            return "latin-1"
        if stripped.startswith("FLAG") and len(stripped) > 4 and stripped[4:5].isspace():
            if stripped.split(None, 1)[1].strip().lower() == "utf-8":
                flag_utf8 = True
    return "utf-8" if flag_utf8 else "latin-1"


def valid_utf8(data):
    try:
        data.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def decode_wordlist(data, aff_encoding):
    """Mirror the CLI's `decode_words`: a word list that is valid UTF-8 is
    decoded as UTF-8, otherwise with the dictionary's single-byte encoding."""
    if aff_encoding == "utf-8":
        return data.decode("utf-8")
    if valid_utf8(data):
        return data.decode("utf-8")
    return data.decode(aff_encoding)


def read_expected(sug_path, aff_path):
    encoding = detect_aff_encoding(aff_path)
    raw = open(sug_path, "rb").read()
    return decode_wordlist(raw, encoding).split("\n")


def read_our_lines(ours_path):
    text = open(ours_path, "rb").read().decode("utf-8")
    return text.split("\n")


def nonempty(lines):
    # Drop the trailing newline element and any line that is empty: Hunspell's
    # own harness keeps only the words that produced at least one suggestion.
    out = []
    for line in lines:
        if line != "":
            out.append(line)
    return out


def suggestions_by_word(our_lines):
    """One list of suggestions per input word (empty list when the line was
    empty). The CLI prints a line for every non-empty input line, but the final
    split element after the trailing newline is not an input line."""
    lines = our_lines
    if lines and lines[-1] == "":
        lines = lines[:-1]
    out = []
    for line in lines:
        if line.strip() == "":
            out.append([])
        else:
            out.append([part for part in line.split(", ")])
    return out


def aligned_matches(expected_first, our_by_word, strict):
    """Maximum number of expected (best) suggestions that can be matched, in
    order, to distinct wrong words. `strict` also requires the expected
    suggestion to be *the* first suggestion we returned for that word.

    The corpus `.sug` file omits wrong words that produced no suggestion, so a
    plain positional pairing is impossible; this monotone alignment is the
    well-defined substitute. Each expected line is used at most once."""
    e = len(expected_first)
    w = len(our_by_word)
    if e == 0 or w == 0:
        return 0
    # dp[k][i]: best using expected[0..k) and words[0..i)
    previous = [0] * (w + 1)
    for k in range(e):
        current = [0] * (w + 1)
        for i in range(1, w + 1):
            best = current[i - 1]
            if previous[i] > best:
                best = previous[i]
            first = expected_first[k]
            ours = our_by_word[i - 1]
            hit = first in ours
            if strict:
                hit = len(ours) > 0 and ours[0] == first
            if hit and previous[i - 1] + 1 > best:
                best = previous[i - 1] + 1
            current[i] = best
        previous = current
    return previous[w]


rows = []
exact_total = 0
best_hits = 0
strict_hits = 0
expected_total = 0
for line in open(manifest, "r", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    name, aff_path, sug_path, ours_path = line.split("\t")
    expected = nonempty(read_expected(sug_path, aff_path))
    ours = nonempty(read_our_lines(ours_path))
    exact = expected == ours
    if exact:
        exact_total += 1
    our_by_word = suggestions_by_word(read_our_lines(ours_path))
    expected_first = []
    for entry in expected:
        expected_first.append(entry.split(", ")[0])
    best = aligned_matches(expected_first, our_by_word, False)
    strict = aligned_matches(expected_first, our_by_word, True)
    best_hits += best
    strict_hits += strict
    expected_total += len(expected_first)
    rows.append((name, exact, best, strict, len(expected_first)))

print("%-28s %-7s %-12s %-12s %s" % ("suite", "exact", "best", "as-first", "expected"))
print("-" * 68)
for name, exact, best, strict, total in rows:
    print("%-28s %-7s %-12s %-12s %s" % (
        name, "yes" if exact else "-", "%d/%d" % (best, total),
        "%d/%d" % (strict, total), total))
print("-" * 68)
print("%-28s %-7s %-12s %-12s %s" % (
    "TOTAL", "%d/%d" % (exact_total, len(rows)),
    "%d/%d" % (best_hits, expected_total), "%d/%d" % (strict_hits, expected_total),
    expected_total))
print()
def pct(n, d):
    return "n/a" if d == 0 else "%.1f%%" % (100.0 * n / d)
print("exact suggestion list reproduced (Hunspell's own .sug criterion): %d/%d suites"
      % (exact_total, len(rows)))
print("expected best suggestion present in our list (order-aligned):      %d/%d = %s"
      % (best_hits, expected_total, pct(best_hits, expected_total)))
print("expected best suggestion is our first suggestion (same alignment):  %d/%d = %s"
      % (strict_hits, expected_total, pct(strict_hits, expected_total)))
PYEOF

if [ $? -ne 0 ]; then
  echo "FAIL: the metric computation failed (is python3 installed?)" >&2
  exit 1
fi
