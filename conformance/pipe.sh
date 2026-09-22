#!/usr/bin/env bash
#
# conformance/pipe.sh — regression check for `--words -` reading from a *pipe*.
#
# Why this exists: on the native backend the word list used to be read with
# `moonbitlang/x/fs.read_file_to_bytes("/dev/stdin")`, which seeks to the end of
# the stream to size its buffer. A pipe is not seekable, so
#
#   printf 'hello\n' | main.exe check ... --words -   # Illegal seek, rc=1
#
# failed while the same command under `moon run` (wasm) worked. See
# docs/MOONBIT_GOTCHAS.md #33. `moon test` cannot create a pipe, so the fix is
# guarded here instead.
#
# Usage:
#   bash conformance/pipe.sh          # native only (the backend that was broken)
#   bash conformance/pipe.sh --all    # also wasm / wasm-gc / js through `moon run`
#
# Exit status: 0 when every check passes, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.moon/bin:$PATH"

ALL=0
[ "${1:-}" = "--all" ] && ALL=1

NATIVE="$REPO_ROOT/_build/native/release/build/cmd/main/main.exe"
FAILED=0

check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s\n        expected: %s\n        actual  : %s\n' "$1" "$2" "$3"
    FAILED=1
  fi
}

check_rc() { # <label> <expected-rc> <actual-rc>
  check "$1" "$2" "$3"
}

# ------------------------------------------------------------------ fixtures
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\n' > "$TMP/p.aff"
printf '2\nhello\nworld\n' > "$TMP/p.dic"
printf 'hello\nzzzz\n' > "$TMP/w.txt"

# ------------------------------------------------------------------- native
echo "building native release ..."
if ! moon build --target native --release >/dev/null; then
  echo "FAIL: moon build --target native --release" >&2
  exit 1
fi
if [ ! -x "$NATIVE" ]; then
  echo "FAIL: no native binary at $NATIVE" >&2
  exit 1
fi

printf 'hello\nzzzz\n' | "$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - \
  > "$TMP/pipe.out" 2> "$TMP/pipe.err"
check_rc "native pipe: exit status" "0" "$?"
check "native pipe: output is 1 then 0" "$(printf '1\n0')" "$(cat "$TMP/pipe.out")"
check "native pipe: nothing on stderr" "" "$(cat "$TMP/pipe.err")"

"$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - < "$TMP/w.txt" \
  > "$TMP/redir.out" 2> "$TMP/redir.err"
check_rc "native '< file': exit status" "0" "$?"
check "native '< file': output is 1 then 0" "$(printf '1\n0')" "$(cat "$TMP/redir.out")"

"$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words "$TMP/w.txt" \
  > "$TMP/file.out" 2> "$TMP/file.err"
check_rc "native '--words <file>': exit status" "0" "$?"
check "native '--words <file>': output is 1 then 0" "$(printf '1\n0')" "$(cat "$TMP/file.out")"

printf '' | "$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - \
  > "$TMP/empty.out" 2> "$TMP/empty.err"
check_rc "native empty pipe: exit status" "0" "$?"
check "native empty pipe: no output" "" "$(cat "$TMP/empty.out")"

printf 'hello' | "$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - \
  > "$TMP/nonl.out" 2> "$TMP/nonl.err"
check_rc "native pipe without trailing newline: exit status" "0" "$?"
check "native pipe without trailing newline: one verdict" "1" "$(cat "$TMP/nonl.out")"

printf 'helo\nzzzz\n' | "$NATIVE" suggest --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - \
  > "$TMP/sug.out" 2> "$TMP/sug.err"
check_rc "native 'suggest' pipe: exit status" "0" "$?"
check "native 'suggest' pipe: first word has a suggestion" "hello" "$(sed -n 1p "$TMP/sug.out")"

"$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/nope.dic" --words - < "$TMP/w.txt" \
  > "$TMP/bad.out" 2> "$TMP/bad.err"
if [ "$?" -eq 0 ]; then
  echo "FAIL  native bad .dic: expected a non-zero exit status"
  FAILED=1
else
  echo "ok    native bad .dic: non-zero exit status"
fi
check "native bad .dic: empty stdout" "" "$(cat "$TMP/bad.out")"
if [ -s "$TMP/bad.err" ]; then
  echo "ok    native bad .dic: message on stderr"
else
  echo "FAIL  native bad .dic: no message on stderr"
  FAILED=1
fi

# A large pipe has to cross many 64 KiB chunks. Use the system word list when
# there is one; otherwise skip rather than invent a number.
WORDS_FILE=""
for candidate in /usr/share/dict/words /usr/dict/words; do
  [ -f "$candidate" ] && WORDS_FILE="$candidate" && break
done
if [ -n "$WORDS_FILE" ]; then
  cat "$WORDS_FILE" | "$NATIVE" check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - \
    > "$TMP/large.out" 2> "$TMP/large.err"
  check_rc "native large pipe: exit status" "0" "$?"
  check "native large pipe: one verdict per input word" \
    "$(grep -c . "$WORDS_FILE")" "$(grep -cE '^[01]$' "$TMP/large.out")"
else
  echo "skip  native large pipe (no /usr/share/dict/words)"
fi

# ------------------------------------------------- wasm / wasm-gc / js (optional)
if [ "$ALL" = "1" ]; then
  for target in wasm wasm-gc js; do
    if [ "$target" = "wasm" ]; then
      run_backend() { moon run cmd/main -- "$@"; }
    else
      run_backend() { moon run --target "$target" cmd/main -- "$@"; }
    fi
    printf 'hello\nzzzz\n' | run_backend check --aff "$TMP/p.aff" --dic "$TMP/p.dic" --words - \
      > "$TMP/$target.out" 2> "$TMP/$target.err"
    check_rc "$target pipe: exit status" "0" "$?"
    check "$target pipe: output is 1 then 0" "$(printf '1\n0')" "$(cat "$TMP/$target.out")"
  done
fi

echo
if [ "$FAILED" = "0" ]; then
  if [ "$ALL" = "1" ]; then
    echo "PASS: '--words -' reads a pipe on native, wasm, wasm-gc and js."
  else
    echo "PASS: '--words -' reads a pipe on native."
  fi
  exit 0
fi
echo "FAIL: see the checks above." >&2
exit 1
