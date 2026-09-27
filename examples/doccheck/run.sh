#!/usr/bin/env bash
#
# examples/doccheck/run.sh — spell-check this repository's own prose with the
# library it ships. One command, no vendored data.
#
#   bash examples/doccheck/run.sh                       # scan this repository
#   bash examples/doccheck/run.sh path/to/other/repo    # scan another tree
#   bash examples/doccheck/run.sh --include-tests       # also scan *_test.mbt
#   bash examples/doccheck/run.sh --quiet               # summary only
#   bash examples/doccheck/run.sh --no-fail             # always exit 0
#
# Exit status (so a CI step can gate on a typo without parsing the output):
#   0  no misspelling left after the allowlist
#   1  misspellings found                       <- the gate
#   2  usage or I/O error (bad flag, unreadable file, not a directory)
#   3  this WRAPPER could not obtain the dictionary (no network, no cache)
#
# 3 exists so that an environment failure cannot masquerade as a documentation
# problem: a CI step can fail on 1 and 2 while tolerating 3, which is exactly what
# .github/workflows/ci.yml does. The program itself never returns 3.
#
# The English dictionary is en_US from LibreOffice's `dictionaries` repository
# (built from SCOWL, size 60). It is fetched from jsDelivr at run time into a
# cache directory and is NEVER copied into this repository — the SCOWL licence
# is not this project's licence, and the dictionary must not be redistributed
# here. Set SPELL_DICT_DIR to a directory holding en_US.aff/en_US.dic to run
# offline; /tmp/endict is used when it already exists.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.moon/bin:$PATH"

# ------------------------------------------------------------- dictionary
DICT_DIR="${SPELL_DICT_DIR:-}"
if [ -z "$DICT_DIR" ] && [ -f /tmp/endict/en_US.aff ] && [ -f /tmp/endict/en_US.dic ]; then
  DICT_DIR=/tmp/endict
fi
if [ -z "$DICT_DIR" ]; then
  DICT_DIR="${XDG_CACHE_HOME:-${TMPDIR:-/tmp}}/spell-doccheck-en_US"
  if [ ! -f "$DICT_DIR/en_US.aff" ] || [ ! -f "$DICT_DIR/en_US.dic" ]; then
    BASE="https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master/en"
    echo "doccheck: fetching en_US.aff / en_US.dic from jsDelivr into $DICT_DIR" >&2
    mkdir -p "$DICT_DIR"
    if ! curl -fsSL "$BASE/en_US.aff" -o "$DICT_DIR/en_US.aff" \
       || ! curl -fsSL "$BASE/en_US.dic" -o "$DICT_DIR/en_US.dic"; then
      echo "doccheck: could not fetch the dictionary." >&2
      echo "          Set SPELL_DICT_DIR to a directory with en_US.aff/en_US.dic." >&2
      # 3, not 1: this is an environment failure, not a spelling result. See the
      # header for why that distinction has to survive to the caller.
      exit 3
    fi
  fi
fi

# ------------------------------------------- options and the scanned tree
TARGET="$REPO_ROOT"
PASS=()
for arg in "$@"; do
  case "$arg" in
    --include-tests | --quiet | --no-fail) PASS+=("$arg") ;;
    -h | --help) exec moon run examples/doccheck -- --help ;;
    *) TARGET="$arg" ;;
  esac
done

ARGS=(
  --aff "$DICT_DIR/en_US.aff"
  --dic "$DICT_DIR/en_US.dic"
  --allowlist "$REPO_ROOT/examples/doccheck/allowlist.txt"
  "$TARGET"
)
# Appending an empty array needs a guard on bash 3.2 (`set -u`).
if [ "${#PASS[@]}" -gt 0 ]; then
  ARGS+=("${PASS[@]}")
fi

exec moon run examples/doccheck -- "${ARGS[@]}"
