#!/usr/bin/env bash
#
# examples/basic/demo.sh — the ten-second demo, offline and in one command.
#
#   bash examples/basic/demo.sh
#
# It writes its own three-entry dictionary (nothing vendored, no network), then runs the
# two CLI commands a user actually types: one verdict per word, then the suggestions for
# the words that were rejected. The transcript in `docs/demo.png` is this script's output.
#
# Why a demo script exists at all: the library's value is easy to state and hard to see.
# `docs/demo.png` in the README is a picture of exactly this run, and a picture that
# cannot be reproduced is a claim, not evidence.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.moon/bin:$PATH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A dictionary small enough to read: three entries, one suffix rule, one replacement rule.
#   `cat/S` + `SFX S 0 s .`  makes `cats` a word although only `cat` is listed.
#   `REP ph f`               is what turns `phorm` into `form`.
printf 'SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\nREP 1\nREP ph f\nSFX S Y 1\nSFX S 0 s .\n' \
  > "$TMP/demo.aff"
printf '3\nform\nphantom\ncat/S\n' > "$TMP/demo.dic"
printf 'form\nphorm\nfrm\ncatz\n' > "$TMP/words.txt"

echo "\$ cat words.txt"
cat "$TMP/words.txt"
echo
echo "\$ spell check --aff demo.aff --dic demo.dic --words words.txt"
moon run cmd/main -- check --aff "$TMP/demo.aff" --dic "$TMP/demo.dic" --words "$TMP/words.txt"
echo
echo "\$ spell suggest --aff demo.aff --dic demo.dic --words words.txt"
moon run cmd/main -- suggest --aff "$TMP/demo.aff" --dic "$TMP/demo.dic" --words "$TMP/words.txt"
echo
echo "read it as: 1 = correct, 0 = not a word; the suggest lines are the candidates for"
echo "each word in the same order (blank = the word was already correct)."
