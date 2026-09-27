# Changelog

All notable changes to this project are documented here.
Versions follow [Semantic Versioning](https://semver.org/); this project is pre-1.0, so
minor versions may still change behaviour.

## [0.9.5] — 2026-09-27

Documentation, examples and CI. No library code or interface change.
Tests 179/183 -> **182/186**, all three additions coming from `mbt check` blocks in the new
Chinese README being executed by `moon test` (wasm, wasm-gc, js / native).

### Added
- **`README.zh.mbt.md` + `README.zh.md` symlink** — a Chinese companion to the README.
  It is a `.mbt.md` file rather than plain Markdown on purpose: its code blocks are then
  compiled by `moon check` and its `test` blocks executed by `moon test`, so the Chinese
  documentation cannot rot independently of the code it documents. The English README
  stays authoritative and says so.
- **`examples/ci-gate`** — an offline, self-contained demonstration that `doccheck`'s exit
  status really gates a build. It writes a five-word dictionary from scratch (no network,
  nothing vendored) and asserts five cases, then prints the workflow snippet it is
  describing. This exists because the project's application form promised a tool whose
  "exit status can be embedded in a pipeline to intercept spelling errors
  automatically", and a promise in prose is not a demonstration.
- **`check-all.sh`** — one command for the pre-submission check. Phase 1 is gates
  (`moon check`, `fmt`, `test`, an unchanged `.mbti`, and the offline exit-status
  contract); phase 2 re-measures everything and reports drift without failing. This
  repository's history includes a 2.3x performance figure that had silently drifted, a
  conformance figure 1.9 points too low for weeks, and a doccheck figure invalidated by
  the documentation it described — all three were found by re-running a measurement.

### Fixed
- `examples/doccheck/run.sh` returned **1** when it could not fetch the dictionary, which
  collides with `1` = "misspellings found" and would report an environment failure as a
  documentation problem. It now returns **3** for that case; the contract is
  0 clean / 1 misspellings / 2 usage or I-O error / 3 no dictionary. Verified reachable by
  hiding the cache and pointing the fetch at a dead port.
- `.github/workflows/ci.yml` now runs **two more steps**, both blocking: the repository's
  own prose is spell-checked (tolerating only exit 3, so a network flake is not reported
  as a typo), and the offline exit-status contract is asserted.
- The Performance section now states the **run-to-run range** of the ratios it quotes
  (direct hits 0.89x-1.06x, misses 6.30x-6.44x) instead of leaving one run's ratio to be
  read as a property of the code.
- `misconfiguration` was flagged by our own gate while the new prose was being written and
  was added to the allowlist — the workflow that `examples/ci-gate/README.md` tells users
  to follow, followed by us.

## [0.9.4] — 2026-09-27

Documentation only. No code, test or interface change.

### Fixed
- **The README's first five minutes were broken.** Verified by building a real consumer
  project (`moon new` → `moon add Careylq/spell` → copy the README) and hitting the
  failures one by one:
  - `moon add` only writes `moon.mod`; the README never mentioned `moon.pkg`, so copying
    the Quick start failed with `Package "spell" not found in the loaded packages`. The
    required `moon.pkg` snippet is now shown.
  - A blackbox test file needs the import declared `for "test"`; without it
    `moon check --deny-warn` fails with `unused_package` even though the tests pass.
    Now shown next to the other snippet.
  - `load` raises, so it cannot be called from a plain `fn main` (error 4122). The README
    now shows the `catch` form as a checked block and mentions `fn main raise`;
    `examples/basic` was already the runnable version.
  - The CLI section did not say that `moon run cmd/main` only works inside a clone of this
    repository — from a dependent project the path does not resolve.
- The self-verification note at the top claimed "any MoonBit code block below is verified
  by `moon check`". Only blocks tagged `mbt check` are compiled (confirmed by mutating
  one and watching `moon check` fail, then mutating an unmarked block and watching it
  pass). The note now says what is actually true.

### Changed
- Tests 178 → **179** (wasm, wasm-gc, js) and 182 → **183** (native). Not a new test file:
  the `mbt check` block added to the README's Quick start contains a `test`, and `moon test`
  executes it. The README's documented behaviour is now enforced by the suite instead of
  merely compiled.

### Added
- **Community articles**: the published 知乎 and 掘金 write-ups are now linked from the
  README, with the note that where the article and this repository disagree, the
  repository and the scripts that produce it win.



Documentation only. No code, test or interface change.

### Fixed
- The `doccheck` figures quoted in README.mbt.md and examples/README.md were measured
  before 0.9.2's own prose was added, so they had gone stale — the same class of mistake
  this release series has been removing. They are now the **0.9.2 tree** snapshot and are
  labeled as such, because the word count necessarily grows with the repository's own
  prose and would otherwise be invalidated by every future edit.



Makes the dogfooding example's exit code usable as a CI gate. Library code is
untouched, so conformance and benchmark numbers cannot change and were not re-run.

### Added
- `examples/doccheck` now exits **1 when anything is still misspelled** after the
  allowlist, `0` when clean, and `2` on a usage or I/O error; `--no-fail` forces `0`
  for callers that only want the numbers (which is how the recorded measurements are
  taken). The wrapper `run.sh` passes `--no-fail` through — without that it would have
  been read as the target directory.
- 2 whitebox tests: `exit_status` and the `--no-fail` parse (including that a trailing
  directory after the flag is still the directory). Tests 176 → 178 (wasm, wasm-gc,
  js), 180 → 182 (native).

### Why
The project application form's second usage scenario promises a tool whose "exit status
can be embedded in a pipeline to intercept spelling errors automatically". Before this
change `doccheck` returned `0` no matter how many misspellings it found, so the claim
was not actually true — the exit code only reported argument and I/O failures. The
library CLI (`cmd/main check`) deliberately still exits `0` on a rejected word: it
reports one verdict per line, and the conformance and benchmark harnesses read that
stream and would break if a rejected word failed the process. Gating is `doccheck`'s job.



Measurement correction, two performance fixes, and tests for a previously untested
function. **No spelling judgement changed** — confirmed by the full suite, the full
conformance corpus and the differential test (below).

### Fixed
- **`conformance/run.sh` scored space-containing corpus lines as failures.** It paired the
  input and verdict streams positionally with `paste -d' '`, which silently misaligns any
  line that contains a space (`morph.good` has 16, e.g. `drink eat`) and scored them as
  failures whatever the engine said. It now emits one verdict per non-empty input line and
  **counts** them, and still prints the historical positional totals so the two stay
  comparable. Corrected result: `.good` **825/848 (97.3%) → 841/848 (99.2%)**. The 16-verdict
  difference is the measurement artefact, not a behaviour change. `.wrong` 611/613 (99.7%)
  and `.sug` 141/173 (81.5%) were already counted correctly and are unchanged.
- **`apply_conversion` re-parsed every pattern at every input position.** The patterns were
  split and turned into code points *inside* the per-character loop, so checking one word
  allocated "word length × pattern count" arrays — even though `prepare_conversions`' own
  doc comment promises "a linear scan without re-parsing the patterns". The patterns are now
  prepared once per call, plus an allocation-free pre-scan that returns the text unchanged
  when no pattern can start anywhere in it.
- **`check_word_group` allocated three times per word to reject the common case.** It built a
  parts array, a `StringBuilder` and then a copy of the word, only to discover there was a
  single part. It now rejects "contains no whitespace at all" first, with an allocation-free
  scan (`has_whitespace`).

### Performance
A/B on the same machine, same command, medians of 9 runs, on the dictionary's own 49,568
`en_US` entries (all direct hits): **0.746 µs/word → 0.323 µs/word (2.31×)**; all-miss words
9.81 → 9.28 µs/word. The direct-hit path is now at parity with native `hunspell 1.7.3`
(0.38 vs 0.36 µs/word, 1.06×, inside run-to-run variance). The synthetic scaling curve
improves on hits from 0.36–0.42 to 0.24–0.28 µs/word. Neither problem was visible to the
compiler or to the test suite — only to timing a real dictionary.

### Added
- `conformance/differential.sh` — differential test against the real `hunspell` binary over a
  whole word list, printing every disagreement in both directions. On
  `/usr/share/dict/words` (235,976 words, `en_US`): **198 false accepts (0.084%)**, **1 false
  reject** (`Jean-Christophe`), 199 total (0.084%). Re-running the same measurement in a
  `git worktree` at the commit before the compound work gives an identical 198/1, so that
  work introduced no regression. It is deliberately **not** wired into CI: it needs a system
  `hunspell` and reports rather than gates.
- **10 whitebox tests for `apply_conversion`**, which had **none** despite implementing
  `ICONV`/`OCONV`. They pin the longest-then-anchored ordering, the end-of-word `_` anchor,
  the empty-pattern skip, the "output is never rescanned" rule, code-point (not byte)
  matching, and the no-match fast path. Tests 166 → 176 (wasm/wasm-gc/js), 170 → 180 (native).
- `docs/MOONBIT_GOTCHAS.md` entries **#42** and **#43**, both explicitly marked as
  runtime/measurement-verified: loop-invariant `to_array()` allocation, and using an
  allocation-free check for a necessary condition instead of building the object first.

### Verification
The two performance changes touch `ICONV`/`OCONV` and word-group handling, so they were
confirmed three independent ways: the whole suite (176/176 on wasm, wasm-gc and js;
180/180 native), the full conformance corpus (identical `841/848`, `611/613`) and the
differential test (identical 198/1). The new tests were also **mutation-checked** — making
the fast path inspect only the first character fails 5 of them. The hunspell `iconv`,
`iconv2`, `iconv3`, `oconv`, `oconv2` and `iconv_break_overflow` suites pass 100%
(6/6, 4/4, 1/1, 2/2 + 3/3, 1/1, 1/1).

## [0.9.0] — 2026-09-27

Final closeout. No behaviour change; `.good` 825/848 (97.3%), `.wrong` 611/613 (99.7%) and
`.sug` 141/173 (81.5%) are unchanged. Tests 164 → 166 (wasm/wasm-gc/js) and 168 → 170 (native).

### Added
- Parsed `MAXNGRAMSUGS`, `MAXDIFF` and `ONLYMAXDIFF` into the `.aff` AST
  (`max_ngram_sugs : Int?`, `max_diff : Int?`, `only_max_diff : Bool`) instead of leaving them in
  `unrecognized`. `Int?` distinguishes "absent" from a declared `0`.

### Not implemented, deliberately not guessed
- **The n-gram similarity scorer.** `hunspell(5)` specifies only that the pass is "similarity search
  through the dictionary words based on common 1-, 2-, 3-, and 4-character sequences", plus the three
  directive names. It defines **no** scoring function: no per-order weights, no normalisation, no
  threshold formula, and no definition of what makes a suggestion "bad" — that exists only in
  Hunspell's LGPL-2.1 `suggestmgr.cxx`, which this project must not copy. A scorer written from the
  manual would be invention, so the gap is left open and documented. (Also relevant: 12 of the 37
  `.sug` suites set `MAXNGRAMSUGS 0`, i.e. switch the pass *off*, so a guessed default-on scorer would
  likely regress them.)
- `FORCEUCASE`-driven suggestions, `ALL-CAPS` input against a mixed-case dictionary form, and the
  Hungarian `LANG hu` moving rule — all named in the README with the reason each is not implemented.

## [0.8.0] — 2026-09-27

Ecosystem work. No functional change; `.good` 825/848, `.wrong` 611/613 and `.sug` 141/173 are
unchanged. Tests 154 → 164 (wasm/wasm-gc/js) and 158 → 168 (native).

### Added
- **`///` documentation for every public item**, including the previously undocumented public
  fields of `AffFile`, `SpecialFlags`, `Replacement`, `PhoneRule`, `Conversion`, `AffixKind`,
  `AffixHeader.kind`, `AffixRule.kind` and `DicFile.declared_count`, plus a compiling example on
  `api.suggest`. `moon doc` and the mooncakes.io page now describe the whole API.
- **`examples/doccheck`** — a MoonBit executable that uses this library's public API to spell-check
  the prose of a MoonBit repository: it extracts candidate words from Markdown and `///` / `//`
  comments, skips fenced blocks, inline code, paths and identifiers, and reports what the library
  rejects with file and line. Run with `bash examples/doccheck/run.sh`. It fetches en_US at run time
  and never vendors it.
- An allowlist mechanism for domain vocabulary, with the categories documented.

### Measured
On this repository: 32 files, 16,602 words, **461 flagged tokens / 110 distinct words** on the first
run; 0 after applying the 101-entry allowlist. **Of the 110, none were real typos — all were false
positives** of a general English dictionary on technical prose. That is reported as the actual
result: the allowlist is what makes the tool usable, not a formality.

## [0.7.0] — 2026-09-27

Conformance closeout. `.good` **730/848 → 825/848 (97.3%)**, `.wrong` **579/613 → 611/613 (99.7%)**,
`.sug` **133/173 → 141/173 (81.5%)**. Tests 128 → 154 (wasm/wasm-gc/js) and 132 → 158 (native).

### Added
- **`COMPLEXPREFIXES`**: twofold prefix stripping with a single suffix level.
- **Compound engines**: n-part recursion, `COMPOUNDMIDDLE`, affixed parts inside compounds,
  `COMPOUNDPERMITFLAG` / `COMPOUNDFORBIDFLAG`, the `ONLYINCOMPOUND` Fuge rule, `FORCEUCASE`,
  `CHECKCOMPOUNDPATTERN` (including flags, `0` and replacement forms), `CHECKCOMPOUNDDUP`,
  `CHECKCOMPOUNDTRIPLE` / `SIMPLIFIEDTRIPLE`, `CHECKCOMPOUNDCASE`, `CHECKCOMPOUNDREP`,
  `.dic` word-pair blocking, and `CIRCUMFIX`.
- **German compounding**, implemented from the "German compounding" section of the `hunspell(5)`
  manual (the decapitalising `PFX D A a/PX A …` construction, `LANG de_DE` only affects `ß`).
  `germancompounding` 20/20, `germancompoundingold` 14/14, both `.wrong` 50/50. An earlier pass had
  concluded the rule was not derivable from the corpus — that conclusion was wrong.
- `PSEUDOROOT`, `COMPOUNDWORDMAX` / `COMPOUNDSYLLABLE` (Hungarian), `LANG tr` Turkic casing
  (`İ`/`ı`), leading `/` in `.dic` words, and Arabic-Indic digits.

### Fixed
- An affix line with the condition omitted (e.g. `SFX A us orum`) made the whole `.aff` fail to
  load, so that suite silently scored 0. The parser now defaults the condition to `.`.
- Two existing tests asserted behaviour contradicted by the reference: a three-part compound was
  expected to be rejected (`CHECKCOMPOUNDDUP` only forbids when the *last two* parts are identical),
  and a `FORBIDDENWORD` homonym was expected to forbid the root spelling (the manual's "excepts with
  root homonyms" says it stays correct through the root). Both were corrected against the manual and
  the corpus, not deleted.

### Not implemented
`ALL-CAPS` input against a mixed-case dictionary form (`allcaps*`, 6 words — the manual documents the
flags but not the casing algorithm), the Hungarian `LANG hu` "moving rule" for the
`COMPOUNDFORBIDSPECIAL` stem (1 word), and `limit-multiple-compounding`'s three-part typo check
(1 word). None were guessed at.

## [0.6.0] — 2026-09-27

### Added
- **`MAP`** character-group substitution (recursive, so `Fruhstuck` reaches `Frühstück`) and the
  **`PHONE`** phonetic pass (classes, `-` retention and rescan, `<` rescan, digit priorities,
  `^`/`$`, `_` = empty, unmatched characters dropped) with a load-time phonetic index, plus the
  `ph:` inner REP table in its plain, trailing-`*` and `->` forms and `.dic` `ph:` keys.

  `.sug`: 108/173 (62.4%) → **133/173 (76.9%)**; as-first 93/173 → 118/173; exact suites 5/37 → 7/37.
  The real `en_US` dictionary ships no `PHONE` or `MAP`, so the shipped cost is zero; a synthetic
  105-rule `PHONE` table raises load from 61 ms to 127 ms over 49,568 entries and per-suggestion cost
  by about 1%. `PHONE`'s own contribution to the corpus score is zero — the `phone` suite already
  passed — and is documented as such.

## [0.5.0] — 2026-09-27

### Added
- **`ICONV` / `OCONV` conversion tables.** `ICONV` normalises the word before lookup;
  `OCONV` rewrites suggestion output. The `.aff` parser reads the `ICONV n` / `OCONV n`
  header and its declared pairs, including the trailing `_` end-of-word marker, and
  `lookup` applies `ICONV` **before** `IGNORE` filtering (the order matters).

  This is a real-world fix rather than test-suite polish: the LibreOffice `en_US`
  dictionary declares `ICONV 1` / `ICONV ’ '`, so without it a typographic apostrophe
  produced a false rejection. Verified against that dictionary — `don't` and `don’t`
  are now both accepted.

### Changed
- Conformance: `.good` rises from **718/848 (84.7%)** to **730/848 (86.1%)**;
  `.wrong` is unchanged at **579/613 (94.5%)**.

## [0.4.0] — 2026-09-22

### Added
- **Suggestion engine** (`src/suggest`): `suggest(dict, word, limit)`, using Hunspell's
  approach — `REP` substitutions, edit distance 1 restricted to the `TRY` character set,
  a bounded distance 2, case variants (including the possessive stem and `CHECKSHARPS`),
  two-word and hyphenated splits — then ranking by `REP`, `KEY` adjacency, `TRY` order,
  distance and finally alphabetically. Every candidate must pass `check()`; `NOSUGGEST`
  candidates are filtered and the input word is never returned.
- `suggest` is reachable from `src/api`, the module root re-export, and a new CLI
  subcommand: `moon run cmd/main -- suggest --aff <a.aff> --dic <d.dic> --words -`.
- `conformance/suggest.sh`, an additive measurement of the corpus `.sug` files that does
  not touch the `.good`/`.wrong` computation. The README defines the metric explicitly,
  because `.sug` files omit words that produced no suggestion and therefore cannot be
  paired positionally:
  - exact `.sug` file reproduced (Hunspell's own criterion): **5/37 suites**
  - expected best suggestion present, order-aligned: **108/173 = 62.4%**
  - expected best suggestion is our first: **93/173 = 53.8%**
- New `Dictionary` accessors: `try_chars`, `keyboard`, `word_chars`, `replacements`,
  `is_no_suggest`.

Tests grow from 102 to **118**, passing on wasm, wasm-gc, js and native.

### Not implemented (suggestion quality)
`PHONE`/`ph:`, `MAP`, `OCONV`, `FORCEUCASE`-driven suggestions and ngram generation are
deliberately out of scope; they account for 65 of the 65 misses. Distance 2 is a bounded
O(n²) subset, not a complete distance 2.

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
