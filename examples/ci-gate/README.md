# `examples/ci-gate` — using `doccheck` as a CI step

This example demonstrates the second usage scenario of the project: *run a command-line
tool over Markdown files, get a list of suspect words **and an exit status**, and embed
it in a pipeline so spelling mistakes are intercepted automatically.*

`examples/doccheck` answers that contract:

| exit status | meaning |
|---|---|
| `0` | no misspelling left after the allowlist |
| `1` | misspellings found |
| `2` | usage or I/O error |
| `3` | `run.sh` could not obtain the dictionary (no network, no cache) |

`2` is deliberately separate from `1`: a broken setup (missing dictionary, bad flag) must
not look like a documentation problem, or a red CI step would be misdiagnosed.

## Run the proof

```bash
bash examples/ci-gate/run.sh
```

It writes a five-word dictionary from scratch, so it needs **no network and vendors
nothing**, then asserts five cases:

| case | expected | why it matters |
|---|---|---|
| clean tree | `0` | without this the step could never pass |
| one typo present | `1` | the promise being kept |
| one typo present, `--no-fail` | `0` | callers that only want the numbers can opt out |
| missing dictionary file | `2` | a tool error is not a typo |
| no arguments | `2` | ditto for a usage error |

The script exits `0` only when every case behaved as documented, so it can itself be a CI
step.

## Drop it into a workflow

This is the job this repository actually runs (`.github/workflows/ci.yml`, the
"Spell-check this repository's own documentation" step):

```yaml
name: docs

on:
  push:
    branches: [main]
  pull_request:

jobs:
  spellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Install MoonBit toolchain
        run: |
          curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
          echo "$HOME/.moon/bin" >> "$GITHUB_PATH"

      # Fetches en_US at run time into a cache directory; the dictionary is never
      # committed. Set SPELL_DICT_DIR to reuse a local copy.
      - name: Spell-check the documentation
        run: |
          rc=0
          bash examples/doccheck/run.sh --quiet || rc=$?
          # 3 = the wrapper could not fetch the dictionary. Tolerate it, so a network
          # flake is not reported as a documentation problem; fail on everything else.
          if [ "$rc" = "3" ]; then
            echo "::warning::could not obtain the dictionary; doccheck was skipped"
            exit 0
          fi
          if [ "$rc" != "0" ]; then
            echo "::error::doccheck exited $rc"
          fi
          exit "$rc"
```

A failing step prints every hit with its file and line, so the log is the fix list:

```
README.mbt.md:42: delibberate
CHANGELOG.md:15: labelled
```

## As a pre-commit hook

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
set -e
exec bash examples/doccheck/run.sh --quiet
```

## Two things worth knowing before you wire it up

**A general English dictionary flags a lot of correct technical prose.** That is not a
bug in the tool, it is what a size-60 SCOWL word list does to a repository full of
identifiers, proper nouns and British spellings. Run it once, read the list, and put the
words you actually mean into an allowlist:

```bash
bash examples/doccheck/run.sh            # see what it flags
# then add the legitimate ones to examples/doccheck/allowlist.txt
```

The numbers from doing exactly that on this repository are in
[`examples/README.md`](../README.md#examplesdoccheck): the first run flags **128 distinct
words** (a count that grows with the prose, so it is not pinned), **none of which is a real
typo**, and the allowlist brings it to **0**.

**`cmd/main check` is not the gate, and that is on purpose.** It prints one verdict per
input line (`1` correct, `0` incorrect) and exits `0` even when a word is rejected, because
the conformance and benchmark harnesses read that verdict stream and would break if a
rejected word failed the process. Gating is `doccheck`'s job. See
[`docs/MOONBIT_GOTCHAS.md`](../../docs/MOONBIT_GOTCHAS.md) and the `## Native code` section
of the main README for the CLI's own contract.
