# Changelog

All notable changes to this project are documented here.
Versions follow [Semantic Versioning](https://semver.org/); this project is pre-1.0, so
minor versions may still change behaviour.

## [0.3.0] — 2026-09-22

Conformance work: `.good` rises from **54.1%** to **84.7%**, `.wrong` from **93.0%** to
**94.5%**, measured on the full Hunspell corpus (154 suites) with an unchanged harness.
Tests grow from 80 to **102**, passing on wasm, wasm-gc, js and native.

### Added
- `IGNORE` character filtering, applied consistently to dictionary entries, affix
  strip/add values and the word being checked.
- `CHECKSHARPS`: German sharp s handling — `ß` ↔ `SS` folding in upper-cased words,
  capital `ẞ` (U+1E9E), and the `KEEPCASE` interaction.
- `COMPOUNDRULE` pattern engine: patterns over compound flags with `*`, `?` and
  parenthesised multi-character flags, plus full compound decomposition.
- `BREAK` recursive word splitting, with Hunspell's default break points and `BREAK 0`.
- `COMPOUNDBEGIN` / `COMPOUNDEND` for two-part compounds, respecting `KEEPCASE`.
- Affix continuation flags (twofold suffix stripping), `AF` flag vectors, and
  `NEEDAFFIX` / `ONLYINCOMPOUND` carried by derived forms.
- Integer words containing a single internal separator, gated on `WORDCHARS`.

### Fixed
- `FLAG UTF-8` without a `SET` line was decoded as Latin-1, which made the `.aff` and
  `.dic` flag tokenisation disagree and silently broke matching.
- `AF` alias values were treated as a single flag rather than the flag vector they name.
- Duplicate `.dic` entries were merged into a flag union, so a `NEEDAFFIX` homonym could
  poison an otherwise valid homonym. Entries are now stored as homonyms.
- Compounds bypassed `FORBIDDENWORD`, and compound parts ignored `KEEPCASE`.
- `is_lower_char` was ASCII-only, so `ß` made upper-cased words classify as all-caps.

## [0.2.0] — 2026-09-22

### Added
- `spell()` judgement engine (`src/spell`): reverse lookup with capitalisation rules,
  `FORBIDDENWORD` / `KEEPCASE` / `NEEDAFFIX` / `ONLYINCOMPOUND`, and basic
  `COMPOUNDFLAG` compounds. The dictionary index is built once, never per word.
- Public facade (`src/api`) re-exported from the module root.
- `check` subcommand: `moon run cmd/main -- check --aff <a.aff> --dic <d.dic> --words -`.
- `examples/basic`, a runnable end-to-end example.
- First measured conformance numbers from the full corpus: `.good` 459/848 = 54.1%,
  `.wrong` 570/613 = 93.0%.

## [0.1.0] — 2026-09-22

### Added
- `.aff` parser: `SET`, `FLAG`, `AF`, `AM`, `PFX`, `SFX`, `REP`, `TRY`, `KEY`, `IGNORE`,
  `WORDCHARS`, `COMPOUND*` and the special-flag directives. Unmodelled directives are
  collected rather than dropped; errors carry 1-based line numbers.
- `.dic` parser: entry count, `word/FLAGS`, optional morphological fields, `\/` escaping,
  and flag decoding for the single-character, `long`, `num` and `UTF-8` modes.
- Affix rule engine: Hunspell's condition pattern language, anchored per affix kind,
  processing characters by Unicode code point.
- Conformance harness against the Hunspell test corpus (corpus fetched at run time and
  never redistributed, since it is LGPL-2.1 while this project is Apache-2.0).
