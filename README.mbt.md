# spell.mbt

[![CI](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml)

A pure-MoonBit spell checker compatible with the **Hunspell `.aff` / `.dic` dictionary
format** — it parses real-world dictionaries (e.g. `en_US`) and applies the affix rules
defined in the `.aff` file.

> This file is `README.mbt.md` — MoonBit type-checks `.mbt.md` files, so any MoonBit
> code block below is verified by `moon check`. `README.md` is a symlink to this file
> so that GitHub renders it.

> **Status: 0.1.0 — work in progress.** This release provides the `.aff` and `.dic`
> parsers plus the affix rule engine. `spell()` judgement, the CLI and the suggestion
> engine are **not implemented yet** (see [Not implemented yet](#not-implemented-yet)),
> which is why the conformance numbers below cannot be produced yet.

## Conformance

Measured against the official Hunspell test corpus (`hunspell/hunspell` → `tests/`).
The corpus is fetched at CI time and is **not** redistributed with this repository
(Hunspell is LGPL-2.1; this project is Apache-2.0 — see [NOTICE](NOTICE)).

| Suite | Passing | Total | Notes |
|---|---|---|---|
| `.good` (must be accepted) | _not measured yet_ | 135 | |
| `.wrong` (must be rejected) | _not measured yet_ | 115 | |
| `.sug` (expected suggestions) | not implemented | 37 | out of scope for v1 |

> The numbers above are updated from the actual CI run. Run `bash conformance/run.sh`
> locally to reproduce.

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

<!-- TODO(day 3): replace with a verified MoonBit snippet. Because `.mbt.md` files
     are type-checked by `moon check`, this block must actually compile. -->

## Scope

### Implemented

- **`.aff` parser** — `SET`, `FLAG`, `AF`, `AM`, `PFX`, `SFX`, `REP`, `TRY`, `KEY`,
  `IGNORE`, `WORDCHARS`, `COMPOUND*`, and the special-flag directives (`NOSUGGEST`,
  `KEEPCASE`, `FORBIDDENWORD`, `NEEDAFFIX`, `CIRCUMFIX`, `ONLYINCOMPOUND`).
  Unmodelled directives are collected in an `unrecognized` list rather than dropped.
  Errors carry 1-based line numbers.
- **`.dic` parser** — entry count, `word/FLAGS`, optional morphological fields, `\/`
  escaping, and flag decoding for all four `FLAG` modes (single-char, `long`, `num`, `UTF-8`).
- **Affix rule engine** — `matches_condition` (Hunspell's simplified pattern language:
  `.`, `[abc]`, `[^abc]`, literals; anchored to the start for prefixes and the end for
  suffixes) and `apply_rule` (condition then strip then add).
  Unicode-correct: matching iterates code points, so non-BMP characters work.

**Build status:** `moon check` reports 0 errors and 0 warnings; **55 tests pass on each of
wasm, wasm-gc, js and native.**

### Not implemented yet

- **`spell()` orchestration** — wiring the dictionary and affix engine together, plus the
  capitalisation rules and the `KEEPCASE` / `FORBIDDENWORD` / `NOSUGGEST` semantics applied
  at lookup time. This is the next step; until it lands the conformance numbers above
  cannot be produced.
- **CLI** (`cmd/main`) — the `check` subcommand described in `conformance/README.md`.
- **Suggestion generation** (`suggest()`) — edit distance, `REP`/`TRY`/`KEY` ranking.
  Planned for the next round.
- Full compound-word support (only the basic `COMPOUNDMIN` / `COMPOUNDFLAG` cases).
- FFI bindings to the Hunspell C++ library (this is a pure MoonBit implementation).
- Any UI / editor plugin.

**Known limitations:** a UTF-8 BOM at the start of a `.dic` file is not stripped; `FLAG num`
values are stored verbatim without decimal validation.

## Design

```
src/aff/      .aff lexer + parser -> typed AST
src/dic/      .dic parser + dictionary storage
src/affix/    affix rule engine (condition matching, strip/add)
src/check/    spell() judgement (case rules, special flags)
src/api/      public API: load dictionary, check
cmd/main/     CLI
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
