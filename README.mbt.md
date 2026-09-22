# spell.mbt

[![CI](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml)

A pure-MoonBit spell checker compatible with the **Hunspell `.aff` / `.dic` dictionary
format** — it parses real-world dictionaries (e.g. `en_US`), applies the affix rules
defined in the `.aff` file, and judges words the way Hunspell does.

> This file is `README.mbt.md` — MoonBit type-checks `.mbt.md` files, so any MoonBit
> code block below is verified by `moon check`. `README.md` is a symlink to this file
> so that GitHub renders it.

> **Status: 0.1.0.** The `.aff`/`.dic` parsers, the affix engine, the `spell()`
> judgement engine, the public API and the `check` CLI are implemented and tested on
> all four backends. Suggestion generation (`suggest()`) is **not** implemented — see
> [Not implemented yet](#not-implemented-yet).

## Conformance

Measured against the official Hunspell test corpus (`hunspell/hunspell` → `tests/`, 154
suites with `.good`/`.wrong` files) by `bash conformance/run.sh`. The corpus is fetched
at run time and is **not** redistributed with this repository (Hunspell is LGPL-2.1;
this project is Apache-2.0 — see [NOTICE](NOTICE)). The numbers below come from an
actual run of the harness, not an estimate.

| Metric | Passing | Total | Pass rate |
|---|---|---|---|
| `.good` (must be accepted) | 459 | 848 | 54.1% |
| `.wrong` (must be rejected) | 570 | 613 | 93.0% |
| `.sug` (expected suggestions) | not implemented | 37 files | out of scope for v1 |

The remaining `.good` gap is dominated by features this release deliberately leaves out:
`COMPOUNDRULE`/`COMPOUNDBEGIN`/`CHECKCOMPOUNDPATTERN` and the German compounding suites,
affix continuation flags (`SFX A 0 s/123 .`, i.e. twofold suffix stripping), `IGNORE`
characters, `COMPLEXPREFIXES`, and full Unicode case folding (German `ß` → `SS`). The
`.wrong` column is the stronger result: only 43 of 613 words that must be rejected are
wrongly accepted. Run `bash conformance/run.sh` locally to reproduce.

## Why

MoonBit's package registry has no spell-checking library at all — no Hunspell-format
parser, no affix morphology, no spell judgement. Related packages solve different
problems (`moonlexicon` is multi-pattern string matching; `moonnlp` and
`tokenizers-moonbit` are NLP/LLM tokenizers). This project fills that gap.

## Install

```bash
moon add Careylq/spell
```

## Quick start

Load a dictionary once, then judge as many words as you like. The module root
re-exports the public API, so `import { "Careylq/spell" }` is enough:

```mbt check
///|
test {
  let dictionary = @spell.load("SET UTF-8\nSFX S Y 1\nSFX S 0 s .", "1\ncat/S")
  assert_true(@spell.check(dictionary, "cat"))
  assert_true(@spell.check(dictionary, "cats"))
  assert_false(@spell.check(dictionary, "dog"))
  assert_eq(@spell.rule_count(dictionary), 1)
}
```

`load` raises `SpellError` when either text is malformed; when reading files, prefer
`moon run cmd/main` (below), which reports the failing file and line on stderr.

### Command line

```bash
moon run cmd/main -- check --aff en_US.aff --dic en_US.dic --words -
```

* `--words -` reads one word per line from stdin; `--words <file>` reads a file.
* Prints one line per input word — `1` (correct) or `0` (incorrect) — in input order.
  Empty input lines produce no output at all, so the output lines up one-to-one with
  the non-empty input lines.
* The dictionary is parsed and indexed **once**, then every word is checked against it.
* If the `.aff` or `.dic` cannot be read or parsed the command prints a message on
  stderr and exits non-zero — it never silently prints `0`s.

### Runnable example

```bash
moon run examples/basic
```

`examples/basic` embeds a small `.aff` + `.dic` pair written for the example, prints
the detected encoding, flag mode, affix-rule count and entry count, and then judges a
list of words including affix-derived forms (`cats`, `boxes`, `happied`, `undos`,
`unhappy`) and special-flag cases (`EBOOK` rejected because `ebook` is `KEEPCASE`). See
[examples/README.md](examples/README.md).

## Scope

### Implemented

- **`.aff` parser** — `SET`, `FLAG`, `AF`, `AM`, `PFX`, `SFX`, `REP`, `TRY`, `KEY`,
  `IGNORE`, `WORDCHARS`, `COMPOUND*`, and the special-flag directives (`NOSUGGEST`,
  `KEEPCASE`, `FORBIDDENWORD`, `NEEDAFFIX`, `CIRCUMFIX`, `ONLYINCOMPOUND`).
  Unmodelled directives are collected in an `unrecognized` list rather than dropped.
  Errors carry 1-based line numbers.
- **`.dic` parser** — entry count (text after the count on the same line is ignored, as
  Hunspell does), `word/FLAGS`, optional morphological fields, `\/` escaping, and flag
  decoding for all four `FLAG` modes (single-char, `long`, `num`, `UTF-8`).
- **Affix rule engine** — `matches_condition` (Hunspell's simplified pattern language:
  `.`, `[abc]`, `[^abc]`, literals; anchored to the start for prefixes and the end for
  suffixes) and `apply_rule` (condition then strip then add).
  Unicode-correct: matching iterates code points, so non-BMP characters work.
- **`spell()` judgement** — the correctness core:
  * direct dictionary hits;
  * affix-derived forms found by **reverse lookup** (reconstruct the candidate stem from
    the word, check the stem's flag and the rule condition, then re-apply the rule as a
    guard) rather than by generating every form;
  * one prefix **and** one suffix on the same stem when both blocks declare
    `cross_product`;
  * capitalisation rules: all-lowercase, `Capitalised`, `ALL CAPS` and mixed case (mixed
    case must match exactly);
  * special flags `FORBIDDENWORD`, `KEEPCASE`, `NEEDAFFIX`, `ONLYINCOMPOUND`;
  * a trailing `.` is accepted for abbreviations when `WORDCHARS` declares `.`;
  * the basic two-word compound (`COMPOUNDFLAG`, `COMPOUNDMIN`, default `3`).
- **Encodings at the CLI** — the `SET` directive is sniffed from the `.aff` bytes and
  used to decode the `.aff`, the `.dic` and the word input: UTF-8, ISO8859-1, ISO8859-15
  (the eight code points that differ from Latin-1) and other single-byte encodings as
  Latin-1. A UTF-8 input file next to a legacy-encoded dictionary is detected and decoded
  as UTF-8, and a leading UTF-8 BOM is stripped.
- **Public façade** — `src/api` plus a re-export from the module root: `load`, `check`,
  `encoding`, `flag_type_name`, `rule_count`, `entry_count`.
- **Runnable example** in `examples/basic`.

**Build status:** `moon check` reports 0 errors and 0 warnings; the test suite passes on
each of wasm, wasm-gc, js and native.

### Not implemented yet

- **Suggestion generation** (`suggest()`) — edit distance, `REP`/`TRY`/`KEY` ranking.
  The `.sug` corpus is therefore out of scope for this release.
- **Compounds beyond the basic two-part case** — `COMPOUNDRULE`, `COMPOUNDBEGIN`/
  `COMPOUNDEND`/`COMPOUNDMIDDLE`, `CHECKCOMPOUNDPATTERN`, `CHECKCOMPOUNDDUP`/`TRIPLE`
  and the German compounding suites are not applied. A word is accepted as a compound
  when it splits into exactly two plain dictionary words that both carry
  `COMPOUNDFLAG`; affixed parts are not tried.
- **Affix continuation flags / twofold affix stripping** — in `SFX A 0 s/123 .` the
  flags after `/` are ignored, so only the first affix is applied. This is why the
  `flag`, `flaglong`, `flagnum`, `flagutf8`, `alias*`, `needaffix*` and `zeroaffix`
  suites still lose words.
- **`IGNORE` characters** — the directive is parsed but ignored characters are not
  removed before matching.
- **`COMPLEXPREFIXES`**, `CHECKSHARPS`, `FORCEUCASE`, and `NOSUGGEST` semantics at
  lookup time.
- **Full Unicode case folding** — lowercasing uses `moonbitlang/x/unicode`, but
  upper-casing is ASCII-only, so a German `ß` does not expand to `SS` and a non-ASCII
  first letter is not capitalised.
- **`FULLSTRIP` and `PSEUDOROOT`** handling, and Hunspell's word splitting for corpus
  lines that contain spaces.
- FFI bindings to the Hunspell C++ library (this is a pure MoonBit implementation).
- Any UI / editor plugin.

**Known limitations:** the ligature/mapping directives (`MAP`, `ICONV`, `OCONV`) only
participate in suggestion generation, which is out of scope, so they are parsed but not
applied.

## Design

```
src/aff/      .aff lexer + parser -> typed AST
src/dic/      .dic parser + dictionary storage
src/affix/    affix rule engine (condition matching, strip/add)
src/spell/    spell() judgement: indexed dictionary, reverse lookup, case rules
src/api/      public facade: load, check, metadata
cmd/main/     CLI (the `check` subcommand)
examples/     runnable examples
conformance/  conformance harness against the Hunspell corpus
```

## Development

```bash
moon check      # type / lint check
moon build      # build
moon test       # run tests
moon fmt        # format
moon info       # regenerate .mbti interfaces
```

## License

Apache-2.0. See [LICENSE](LICENSE).

This is an independent implementation based on the Hunspell file-format specification
and its observable behaviour. **No Hunspell source code was copied.** See
[NOTICE](NOTICE) for the full reference and licence disclosure.
