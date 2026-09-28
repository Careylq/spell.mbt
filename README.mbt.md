# spell.mbt

[![CI](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml)

A pure-MoonBit spell checker compatible with the **Hunspell `.aff` / `.dic` dictionary
format** — it parses real-world dictionaries (e.g. `en_US`), applies the affix rules
defined in the `.aff` file, judges words the way Hunspell does, and suggests corrections
for the words it rejects.

> **For reviewers.** This repository *is* the submission — acceptance reads the git
> snapshot, so everything needed is in-tree:
>
> | | |
> |---|---|
> | Conformance (official Hunspell corpus, corpus pinned to tag `v1.7.4`) | `.good` **847/854 = 99.2%** · `.wrong` **611/613 = 99.7%** |
> | Differential test vs hunspell 1.7.3 | 235,976 real words: **199 disagreements = 0.084%** |
> | Tests | **200** (wasm / wasm-gc / js) · **204** (native) |
> | Direct lookup vs hunspell | **parity** (0.32–0.38 vs 0.36–0.38 µs/word; the ratio crosses 1.0 both ways) |
> | wasm artifact | **142.2 KiB**, with no C++ runtime |
>
> [`ACCEPTANCE.md`](ACCEPTANCE.md) is the requirement-by-requirement self-check against all
> five acceptance yardsticks — charter stage three (9 items), charter chapter seven (10
> items), the website's 6 standards, the organisers' 4 review dimensions, and this project's
> own proposal. It also names which proposal commitments were **exceeded** and which single
> commitment turned out to be **untrue and was fixed**. Every figure above comes from a
> script in this repository: `bash check-all.sh` re-runs all of them (it needs network, and a
> system `hunspell` plus `/usr/share/dict/words` for the differential row — the per-command
> prerequisites are tabulated in [`ACCEPTANCE.md`](ACCEPTANCE.md#八如何复现) §八).

> This file is `README.mbt.md` — MoonBit type-checks `.mbt.md` files, so every block
> below marked `mbt check` is compiled by `moon check` (an unmarked block is not).
> `README.md` is a symlink to this file so that GitHub renders it.

> **Status: 0.9.6.** The `.aff`/`.dic` parsers, the affix engine, the `spell()`
> judgement engine, the suggestion engine, the public API and the `check` /
> `suggest` CLI subcommands are implemented and tested on all four backends. See
> [Not implemented yet](#not-implemented-yet) for what suggestion generation
> still leaves out (ngram/`MAXNGRAMSUGS` candidates in particular).

## Contents

- [Conformance](#conformance) — 99.2% on the official Hunspell corpus, and the
  [differential test](#differential-test-against-the-real-hunspell) behind that number
- [Performance](#performance) — load, throughput, artifact sizes, and
  [what is *not* measured](#what-is-not-measured)
- [Why](#why) — the gap in the MoonBit ecosystem this fills
- [Ecosystem relevance](#ecosystem-relevance) — including the
  [dogfooding run](#what-the-dogfooding-run-found)
- [Install](#install) and [Quick start](#quick-start) — with the `moon.pkg` wiring, the
  [CLI](#command-line) and a [runnable example](#runnable-example)
- [Scope](#scope) — [what is implemented](#implemented), and
  [what deliberately is not](#not-implemented-yet)
- [Native code](#native-code) — the single 46-line C shim, and why it exists
- [Design](#design) · [Development](#development)
- [Community articles](#community-articles) · [License](#license)

## Conformance

Measured against the official Hunspell test corpus (`hunspell/hunspell` → `tests/`, 155
suites with `.good`/`.wrong` files) by `bash conformance/run.sh`. The corpus is fetched
at run time, **pinned to the tag `v1.7.4`** (`HUNSPELL_REF=` overrides), and is **not**
redistributed with this repository (Hunspell is tri-licensed MPL-1.1 / GPL-2.0 / LGPL-2.1;
this project is Apache-2.0 — see [NOTICE](NOTICE)).

Pinning is not decoration: upstream master moves, and a new upstream suite silently changes
every absolute count here. On 2026-09-28 upstream gained `compoundaffixmorph` (6 `.good`
lines, all passing in this library), which moved the total from 848 to 854 **without
changing the pass rate**. The pin makes the numbers below reproducible.

| Metric | Passing | Total | Pass rate |
|---|---|---|---|
| `.good` (must be accepted) | 847 | 854 | 99.2% |
| `.wrong` (must be rejected) | 611 | 613 | 99.7% |
| `.sug` (expected best suggestion produced) | 141 | 173 | 81.5% |

The `.sug` row is measured by `bash conformance/suggest.sh`, which is **additive** and
never touches the `.good`/`.wrong` computation. A `.sug` line holds the suggestions
Hunspell produced for one misspelled word, best first, joined by `, `; the corpus files
are generated from `.wrong` with the words that produced **no** suggestion omitted, so a
line-by-line positional pairing is impossible. Exactly what was counted:

* **Total** = every non-empty `.sug` line (173 across the 37 `.sug` files).
* **Passing** = the line's **first** (best) suggestion occurs somewhere in the
  suggestion list this library returned for some wrong word, matched to a **distinct**
  wrong word in input order (a maximum monotone matching, so each expected line is used
  at most once and ordering is respected). Ranking within our list is therefore not
  required to pass this row. 141/173 = 81.5%.
* For reference, the stricter "our first suggestion equals the expected best
  suggestion" is 124/173 = 71.7%, and reproducing a whole `.sug` file exactly —
  Hunspell's own test criterion, in order and with no extra suggestion — holds for
  **7/37 suites** (18.9%).

The `MAP` related-character groups and the `ph:`/`PHONE` phonetic passes are
implemented, which is where most of the suggestion improvement came from: `map` and
`maputf` went from 0/3 to 3/3 each, `ph` from 3/11 to 11/11 and `ph2` from 1/14 to
14/14. The remaining `.sug` gap is dominated by passes that are still out of scope:
the n-gram candidate generator and `FORCEUCASE`-driven suggestions. Where the corpus
needs those, the library returns fewer (or no) suggestions; it never invents one
`check` rejects.

The three `.aff` directives that configure the n-gram pass — `MAXNGRAMSUGS`,
`MAXDIFF` and `ONLYMAXDIFF` — are now parsed and recorded on the AST
(`AffFile::max_ngram_sugs`, `AffFile::max_diff`, `AffFile::only_max_diff`) instead of
landing in `AffFile::unrecognized`. The pass itself is deliberately **not**
implemented: the `hunspell(5)` manual does not define its similarity score, so there
is nothing to implement it from without guessing (see
[Not implemented yet](#not-implemented-yet)). These conformance numbers were
re-measured after that parser change and are unchanged.

The remaining `.good` gap is exactly **7 verdicts**, all of them casing idioms the
`hunspell(5)` manual records only as flags and never as an algorithm: matching an
ALL-CAPS input against a mixed-case dictionary form such as `OpenOffice.org` or
`iPod` (`allcaps`, `allcaps_utf` and `allcaps2` — 6 verdicts over 4 distinct
spellings: `OPENOFFICE.ORG`, `UNICEF'S`, `L'AFRIQUE`, `IPOD`) and the Hungarian
"moving rule" for a `COMPOUNDFORBIDFLAG` stem (`hu`, 1 word:
`forróvíz-tartály`). The `.wrong` column is 611/613 = 99.7%: only `allcaps2`'s
`iPodos` and `limit-multiple-compounding`'s `foobarbaz` are wrongly accepted. Run
`bash conformance/run.sh` locally to reproduce — it prints every failing suite.

> Measurement note: the harness emits exactly one verdict per non-empty input line
> and **counts** those verdicts, so a corpus line that itself contains a space is
> now scored correctly. Earlier runs paired the two streams positionally with
> `paste -d' '`, which silently misaligned every line containing a space —
> `morph.good` has 16 of them (`drink eat`, …) — and scored them as failures
> whatever the engine said. `conformance/run.sh` counts verdicts and *also* prints
> the historical positional totals (`831/854`, `611/613`) next to the counted ones
> so the two stay comparable; the 16-verdict difference between `831` and `847` is
> the size of that measurement artefact, not a behaviour change. Tab-terminated
> lines such as `utf8_bom.good`'s are unaffected either way, because `awk` splits
> on tabs as well as spaces.

### Differential test against the real hunspell

The corpus above is hand-written cases. `bash conformance/differential.sh` is the
complementary measurement — a whole real word list judged by both engines, with
every disagreement printed:

| on `/usr/share/dict/words` (235,976 words, `en_US`) | count | share |
|---|---|---|
| we accept, hunspell rejects (**false accepts**) | 198 | 0.084% |
| we reject, hunspell accepts (**false rejects**) | 1 | 0.000% |
| total disagreement | 199 | 0.084% |

Read the two rows in the direction they are defined, because they point opposite ways.
The single **false reject** is `Jean-Christophe` — the one word where this library is
*stricter* than Hunspell. The 198 **false accepts** are the other direction: words
Hunspell rejects and this library accepts, i.e. here **this library is the more permissive
one** (`sparingness`, `winkered`, `towser`, `yester`, … — `-ness`/`-er`/`-ed` derivations
that its affix engine allows on stems Hunspell does not). They are **not** a regression:
the same measurement re-run in a `git worktree` at the commit before the compound work
gives an identical 198/1 — zero new, zero fixed. `run.sh` and `differential.sh` both
report; neither treats a disagreement as a harness failure.

## Performance

One command reproduces everything below:

```bash
bash bench/run.sh
```

It builds all four backends in release mode, fetches the real `en_US` dictionary
into a temp directory at run time (it is never vendored), measures it, generates
deterministic **synthetic** dictionaries for a scaling curve, compares against a
system `hunspell`, and prints the machine/toolchain header next to every table.
Method, caveats and the deliberately-omitted measurements:
[`bench/README.md`](bench/README.md).

**Machine:** Apple M5 (10 cores), 16 GiB, macOS **26.7 (25G229)**, arm64.
**Toolchain:** `moon 0.1.20260920`, `moonc v0.10.14+7d59c7ec9`, `moonrun 0.1.20260920`.
**Dictionary:** LibreOffice `en_US` (SCOWL size 60), **49,568 entries**, fetched
from jsDelivr at run time (`.aff` sha256 `e746c882…`, `.dic` sha256 `f0b1a234…`).
These are **end-to-end wall-clock medians** on one machine — process startup is
included wherever a row says so — and are not a cross-machine claim.

### Loading a real dictionary vs checking words

`moon run cmd/main -- check ...` is timed at three points: a no-argument run
(process start), an empty word list (start + parse + index), and 49,568 words
(the dictionary's own entries, i.e. all direct hits). Medians over 9 / 5
repetitions; `load = empty − start`, `check = N-words − empty`.

| step | wasm debug (`moon run`) | wasm release (`moon run --release`) |
|---|---|---|
| process start | 0.0210 s | 0.0210 s |
| start + load (49,568 entries) | 0.1390 s | 0.1190 s |
| **load only** | **0.1180 s** | **0.0980 s** |
| 49,568-word run (all hits) | 0.1970 s | 0.1640 s |
| **checking only** | **0.0580 s** | **0.0450 s** |
| per-word check | 1.17 µs | 0.91 µs |
| throughput, end-to-end | 251,614 words/s | 302,244 words/s |
| throughput, checking only | 854,621 words/s | 1,101,511 words/s |

Plain `moon run` compiles **debug** wasm; the release column is the same backend
compiled like the native binary. Here release is ahead on both ends (it loads in
0.0980 s vs 0.1180 s and checks in 0.0450 s vs 0.0580 s), which is the expected
direction and worth noting because in an earlier run of this same harness the two
columns **reversed** on the checking row — that reversal was an artefact of deriving
"checking" by subtracting an empty-word-list measurement that carries process-start
noise. Read the two columns as *the same backend compiled two ways, one run*, not as
a stable ordering.
All 49,568 entries load; 49,565 are accepted standalone and the 3
rejected (`1th`, `2th`, `3th`) all carry `ONLYINCOMPOUND`, which Hunspell also
rejects standalone — the harness derives that from the `.aff` instead of
hard-coding it.

### Head-to-head with Hunspell (native vs native)

The other natural comparison — `moon run` wasm against a native C++ binary — is
not apples-to-apples, so this compares **two native executables** on the same
`.aff`/`.dic` bytes and the same word lists: our
`moon build --target native --release` binary against `hunspell 1.7.3`.

| workload | ours native | hunspell | ratio |
|---|---|---|---|
| process start | 0.0020 s | 0.0030 s | 0.67× |
| dictionary load only | 0.0300 s | 0.0070 s | 4.29× |
| 49,568 all-hit words: total | 0.0490 s | 0.0280 s | 1.75× |
| 49,568 all-hit words: **checking only** | **0.0170 s** | **0.0180 s** | 0.94× |
| 49,568 all-hit words: **per word** | **0.34 µs** | **0.36 µs** | 0.94× |
| 49,568 all-miss words: total | 0.5180 s | 0.0840 s | 6.17× |
| 49,568 all-miss words: checking only | 0.4860 s | 0.0740 s | 6.57× |
| 49,568 all-miss words: per word | 9.80 µs | 1.49 µs | 6.58× |
| 235,976 mixed words (`/usr/share/dict/words`, 18.4% hits) | 1.8400 s | 0.2890 s | 6.37× |
| 235,976 mixed words: throughput | 128,248 words/s | 816,526 words/s | |

The aggregate ratios hide the interesting part. On **hits** the two engines are
level per word — across runs this library has been both marginally ahead and marginally
behind, and that the ratio crosses 1.0 in both directions is the point — so our end-to-end
gap on that row is almost entirely dictionary load (30 ms vs 7 ms); while on **misses** we
are **about 6× slower per word**, because a rejected word runs the reverse affix lookup over every suffix
rule, every prefix rule, the prefix×suffix cross product and the two-suffix
families (`affix_hit` in `src/spell/lookup.mbt`), whereas a hit is one map
access (`direct_hit`). Real text is miss-dominated here: `/usr/share/dict/words`
is only 18.4% hits. **The miss path and dictionary load are the optimisation
targets; direct lookup is already at parity.**

> **Run-to-run range, so no single ratio is over-read.** Repeated `bash bench/run.sh`
> runs on this machine have put the direct-hit row between **0.84× and 1.06×** — that is,
> **on both sides of parity** (ours 0.32–0.38 µs/word, hunspell 0.36–0.38) — and the
> all-miss row between **5.9× and 6.6×** (ours 9.2–9.8 µs/word, hunspell 1.49–1.57). Each
> re-run has widened the range rather than narrowing it, which is why this section claims
> **the shape, not a decimal**: hits are at parity, misses are *about six times* slower,
> dictionary load *about four times*. The table above is one run — not the best one, and
> not a claim about the code's ratio. **If you need a ratio for a decision, re-run the
> harness; do not lift one from here.**

As a cross-backend data point on the same 235,976 words: native release 1.840 s
is **2.25×** faster than release wasm (4.146 s) and **2.51×** faster than the
debug wasm that plain `moon run` builds (4.621 s).

### Scaling on synthetic dictionaries

Deterministic `.aff`/`.dic` pairs (no RNG; 5 blocks / 8 affix rules) generated by
`bench/gen_dict.sh`, **not real language data**. Every size is checked against
the *same* 100,000-word workload so the per-word columns are comparable, and the
generator is verified byte-reproducible during the run.

| entries | .dic KiB | load | hit | miss | hit end-to-end | miss end-to-end |
|---|---|---|---|---|---|---|
| 1,000 | 17.6 | 1.00 ms | 0.24 µs/word | 0.81 µs/word | 3,703,704 w/s | 1,190,476 w/s |
| 10,000 | 181.6 | 7.00 ms | 0.26 µs/word | 0.85 µs/word | 2,857,143 w/s | 1,063,830 w/s |
| 50,000 | 940.4 | 35.00 ms | 0.30 µs/word | 0.88 µs/word | 1,492,537 w/s | 800,000 w/s |
| 200,000 | 3,817.6 | 144.00 ms | 0.28 µs/word | 0.94 µs/word | 574,713 w/s | 416,667 w/s |

Load grows linearly (≈0.7 µs per entry), but **per-word checking does not follow
the dictionary size**: across a 200× range the hit path moves only 0.24 → 0.28 µs
and the miss path 0.81 → 0.94 µs. The end-to-end words/s columns fall only because
they include the load. (The synthetic affix set has 8 rules against real
`en_US`'s 50, so synthetic miss *absolute* values are not comparable with the
table above; the trend is the result.)

### Release artifact size

| target | bytes |
|---|---|
| wasm (`cmd/main`) | 145,655 (142.2 KiB) |
| wasm-gc | 113,333 |
| js | 469,140 |
| native | 761,128 |

The wasm CLI is ~142 KiB with no C++ runtime — that is the payload a wasm host
downloads and runs.

### What is *not* measured

Suggestion-engine speed, peak memory, other spell checkers (aspell/nuspell/…),
threads, and any browser or edge-worker runtime. Those are listed with reasons
in [`bench/README.md`](bench/README.md#what-is-deliberately-not-measured); no
number is invented for them.

## Why

When this project was proposed (September 2026), searching mooncakes.io for `hunspell`,
  `spell`, `affix`, `stemmer`, `snowball`, `hyphenation` and `thesaurus` returned **no
  hits**: the registry had no Hunspell-format parser, no affix morphology and no spell
  judgement. Related packages solved different problems (`moonlexicon` is multi-pattern
  string matching; `moonnlp` and `tokenizers-moonbit` are NLP/LLM tokenizers).

**That is no longer literally true, and this file should say so.** On 2026-09-27 —
after this project's first release on 2026-09-22 — a second package with the same
positioning appeared: [`wccerty/moonspell`](https://mooncakes.io/docs/wccerty/moonspell)
("A pure-MoonBit Hunspell-compatible spelling engine", Apache-2.0). It is an independent
implementation; this project did not exist alongside it when it started. Two
implementations of a standard format in one registry is a normal and healthy outcome, so
the honest claim is not "we are the only one" but **what this one verifiably does**:

| | this project | `wccerty/moonspell` |
|---|---|---|
| First release | 2026-09-22 | 2026-09-27 |
| Releases | 15 (0.1.0 → 0.9.6) | 1 (0.1.0) |
| Official-corpus conformance | `.good` 847/854 = 99.2%, `.wrong` 611/613 = 99.7%, `.sug` 141/173 = 81.5% | not stated on its package page |
| Differential test vs hunspell on 235,976 real words | published, 0.084% disagreement | not published |
| Licence | Apache-2.0 | Apache-2.0 |

The numbers in the third row are this repository's; the other package is new and may well
publish equivalents. The point of the comparison is only that the ecosystem now has a
choice, and this entry's case rests on measured conformance rather than on being first.

## Ecosystem relevance

The contribution this project makes to MoonBit is not only "a spell checker exists".
It is that a real, standard, data-driven text task runs in pure MoonBit, on every
backend, with the ecosystem's own tools:

* **Pure MoonBit, no FFI.** All six library packages (`src/aff`, `src/dic`, `src/affix`,
  `src/spell`, `src/suggest`, `src/api`) are MoonBit only. The library is therefore
  usable from wasm, wasm-gc, js and native alike — the test suite passes on each of the
  four backends.
* **A real dictionary format, not a toy word list.** It reads the Hunspell
  `.aff`/`.dic` files that LibreOffice, Firefox and macOS already ship, so a MoonBit
  program can consume existing language data instead of a bespoke format.
* **A wasm-first text component.** `preferred_target = "wasm"`; the CLI is **142.2 KiB**
  of wasm with no C++ runtime, which is the shape a browser or edge-worker text feature
  wants.
* **An API a MoonBit developer can actually read.** `moon doc` / the mooncakes.io page
  carries a `///` comment for every public item, and the module root
  (`import { "Careylq/spell" }`) is a nine-item facade — `load`, `check`, `suggest`
  and four metadata accessors.
* **Dogfooding.** `examples/doccheck` uses this library, through its own public API, to
  spell-check the prose of a MoonBit repository: it extracts candidate words from
  Markdown and from `///` / `//` comments and reports what the library rejects, with
  file and line. It is a working demonstration of the library as a component, not a
  snippet.

### What the dogfooding run found

```bash
bash examples/doccheck/run.sh          # scans this repository
```

It exits **1 when anything is still misspelled**, so a CI step can gate on a typo
without parsing the output (`0` clean, `1` misspellings found, `2` usage/I-O error; the
wrapper adds `3` for "could not obtain the dictionary", so an environment failure cannot
look like a documentation problem; `--no-fail` forces `0` for callers that only want the
numbers). [`examples/ci-gate`](examples/ci-gate) verifies the contract offline, and this
repository's own CI gates on it.

Measured on this repository (`moon 0.1.20260920`, en_US from LibreOffice/SCOWL size 60,
fetched at run time and never vendored):

| claim | value |
|---|---|
| files scanned | **34** |
| distinct words the first run flags | **128** (grows with the prose — not a stable figure) |
| …of those, real typos | **0** |
| after `examples/doccheck/allowlist.txt` | **0** |
| with `--include-tests` (all deliberate fixtures) | 13 tokens / 10 distinct |

**Every one of them is a false positive of a general English dictionary on technical prose.** They are
project vocabulary (`wasm`, `backend`, `aff`), Hunspell terminology (`Fuge`, `endchars`,
`ngram`), MoonBit and third-party proper nouns (`MoonBit`, `macOS`, `jsDelivr`), British
spellings (`judgement`, `licence`, `modelled`) and ordinary words this SCOWL size omits
(`seekable`, `matcher`, `substring`). All of them are now in the allowlist. That is the
honest result: a general English dictionary is a poor fit for a technical repository, and the
allowlist is what makes the tool usable, not a formality.

> **These counts are deliberately not pinned**, and the flagged-word count above is marked as
> unstable on purpose. They move with this file's own prose: the repository carries roughly
> 21,700 checked words today and carried ~18,300 during 0.9.x, and the number of words the first
> run flags has **already moved once — 118 → 128** — for exactly that reason. An earlier version
> of this section quoted 118 as a figure that "has not moved"; that claim was itself the same
> mistake this project keeps removing, and an audit caught it. What the claim actually rests on
> is the one number the gate re-checks on every run: **0 genuine typos among the flagged words.**
> The full extraction rules, the `--include-tests` breakdown and the known false positives are in
> [examples/README.md](examples/README.md#examplesdoccheck).

## Install

```bash
moon add Careylq/spell
```

`moon add` only records the dependency in `moon.mod`. The package that **uses** the
library must also import it in its own `moon.pkg`:

```text
import {
  "Careylq/spell",
}
```

A blackbox test file (`*_test.mbt`) is a separate scope, so declare the import for it
with `for "test"`. Without that, `moon check --deny-warn` fails with
`unused_package` even though the tests pass:

```text
import {
  "Careylq/spell",
} for "test"
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

`load` raises `SpellError` when either text is malformed, so handle it where you load —
the same `catch` works inside an ordinary `main`:

```mbt check
///|
test {
  let dictionary = @spell.load("SET UTF-8", "1\ncat") catch {
    error => abort("could not load the dictionary: \{error.to_string()}")
  }
  assert_true(@spell.check(dictionary, "cat"))
}
```

Alternatively declare the entry point as `fn main raise` and let the error propagate.
[`examples/basic`](examples/basic/main.mbt) is the runnable version of both patterns.
When reading dictionaries from files, prefer `moon run cmd/main` (below), which reports
the failing file and line on stderr.

Once a word is judged wrong, `suggest` returns the corrections `check` itself accepts,
best first:

```mbt check
///|
test {
  let dictionary = @spell.load(
    "SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\nREP 1\nREP ph f", "3\nform\nhello\nphantom",
  )
  assert_true(@spell.check(dictionary, "form"))
  assert_eq(@spell.suggest(dictionary, "phorm", 5), ["form"])
  // a correct word needs no correction
  assert_eq(@spell.suggest(dictionary, "hello", 5), [])
}
```

### Command line

`cmd/main` is this module's own executable package, so these commands run from inside
a clone of this repository. A project that depends on the library cannot `moon run` it
by path.

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

The suggestion engine has its own subcommand, with the same file and encoding handling:

```bash
moon run cmd/main -- suggest --aff en_US.aff --dic en_US.dic --words -
```

* One line per non-empty input word, holding its suggestions joined by `, ` (an empty
  line when there is none), in input order.
* The input word itself is never among its suggestions, and every suggestion is a word
  `check` accepts.

### Runnable example

```bash
moon run examples/basic
```

`examples/basic` embeds a small `.aff` + `.dic` pair written for the example, prints
the detected encoding, flag mode, affix-rule count and entry count, and then judges a
list of words including affix-derived forms (`cats`, `boxes`, `happied`, `undos`,
`unhappy`) and special-flag cases (`EBOOK` rejected because `ebook` is `KEEPCASE`). See
[examples/README.md](examples/README.md).

The second example, `examples/doccheck`, spell-checks a whole MoonBit project's
documentation and comments with this library:

```bash
bash examples/doccheck/run.sh
```

It is the dogfooding example described under
[Ecosystem relevance](#ecosystem-relevance); see
[examples/README.md](examples/README.md#examplesdoccheck) for its extraction rules, its
allowlist and the measured numbers.

## Scope

### Implemented

- **`.aff` parser** — `SET`, `LANG`, `FLAG`, `AF`, `AM`, `PFX`, `SFX`, `REP`, `TRY`,
  `KEY`, `IGNORE`, `WORDCHARS`, `CHECKSHARPS`, `COMPLEXPREFIXES`, `BREAK`,
  `ICONV`/`OCONV`, every `COMPOUND*` and `CHECKCOMPOUND*` directive, and the
  special-flag directives (`NOSUGGEST`, `KEEPCASE`, `FORBIDDENWORD`, `NEEDAFFIX`,
  `PSEUDOROOT`, `CIRCUMFIX`, `ONLYINCOMPOUND`). An affix rule's condition may be
  omitted (it then matches every stem).
  Unmodelled directives are collected in an `unrecognized` list rather than dropped.
  Errors carry 1-based line numbers.
- **`.dic` parser** — entry count (text after the count on the same line is ignored, as
  Hunspell does), `word/FLAGS`, optional morphological fields, `\/` escaping (a leading
  `/`, as in `/usr/share/myspell/`, belongs to the word), and flag
  decoding for all four `FLAG` modes (single-char, `long`, `num`, `UTF-8`).
- **Affix rule engine** — `matches_condition` (Hunspell's simplified pattern language:
  `.`, `[abc]`, `[^abc]`, literals; anchored to the start for prefixes and the end for
  suffixes) and `apply_rule` (condition then strip then add).
  Unicode-correct: matching iterates code points, so non-BMP characters work.
- **`spell()` judgement** — the correctness core:
  * direct dictionary hits, with **homonyms treated as alternatives** (`foo`, `foo/X`
    and `foo/Y` make `foo` correct, while a `FORBIDDENWORD` homonym rejects it);
  * affix-derived forms found by **reverse lookup** (reconstruct the candidate stem from
    the word, check the stem's flag and the rule condition, then re-apply the rule as a
    guard) rather than by generating every form;
  * one prefix **and** one suffix on the same stem when both blocks declare
    `cross_product`, including the case where the prefix is licensed by the suffix's
    continuation flags (`undrinkable` from `drink/RQ` and `SFX R 0 able/PS .`);
  * **affix continuation flags / twofold suffix stripping** — `SFX A 0 s/123 .` gives the
    derived form the flags `1`, `2` and `3`, so a second suffix can be chained onto it and
    a prefix can sit in front of the pair (`unfoosbar`);
  * `AF` alias entries expand to the flag **vectors** they name, in the `.dic` and in
    continuation-flag lists alike;
  * `NEEDAFFIX` and `ONLYINCOMPOUND` are honoured on dictionary entries and on affix
    continuation classes alike (`foos` is not a word when `SFX A 0 s/XB .` gives it
    `NEEDAFFIX`; `foosbar` is);
  * capitalisation rules: all-lowercase, `Capitalised`, `ALL CAPS` and mixed case (mixed
    case must match exactly), plus the upper-cased first letter of a mixed-case word
    (`ULinda` finds `uLinda`) and the `LANG tr`/`az`/`crh` dotted/dotless `I` casing
    (`İZMİR` finds `İzmir`, `Işık` finds `ışık`);
  * `CHECKSHARPS`: an uppercased word may spell a dictionary `ß` as `SS`
    (`PROZESSIONSSTRASSE` finds `Prozessionsstraße`), a capital sharp s (`ẞ`, U+1E9E)
    folds to `ß`, and a `KEEPCASE` word containing `ß` may be capitalised or uppercased
    with `SS` but not with a sharp s (`MÜßIG` stays wrong);
  * special flags `FORBIDDENWORD` (a root homonym survives a forbidden one),
    `KEEPCASE` (including on compound parts), `NEEDAFFIX` (with `PSEUDOROOT` as its
    deprecated spelling), `ONLYINCOMPOUND` and `CIRCUMFIX` (an affix with the flag
    needs an affix of the opposite kind with it);
  * `IGNORE` characters are dropped from dictionary entries, from affix `strip`/`add`
    text and from the checked word before any comparison (Arabic harakat, right-to-left
    marks);
  * a trailing `.` is accepted for abbreviations when `WORDCHARS` declares `.`, and a
    number (ASCII or Arabic-Indic digits) is accepted when `WORDCHARS` declares its
    separators (`.`, `,`, `-`) — **however many separators there are**, as long as none is
    adjacent to another and none sits at either end (`1.12345`, `4,2`, `42-42`, `1.2.3`,
    `2026.1.1`, but not `1..2`, `1.,2`, `,1` or `1,`);
  * `BREAK` splitting, recursively: the declared break points, or Hunspell's defaults
    `-`, `^-` and `-$` (`foo-bar-foo-bar`), with `BREAK 0` switching breaking off;
  * a line of whitespace-separated words is correct when every word on it is correct,
    and a `.dic` word pair (`compound word`) blocks the space-free compound;
  * compounds of two or more parts, recursive over the whole word:
    `COMPOUNDFLAG`/`COMPOUNDBEGIN`/`COMPOUNDMIDDLE`/`COMPOUNDEND`/`COMPOUNDLAST` choose
    the flag each position needs, `COMPOUNDMIN` (default `3`) the minimum part length,
    and a part may itself be affixed — its compound flag comes from the stem or from the
    affix's continuation class, an affix "inside" the word needs `COMPOUNDPERMITFLAG`,
    `COMPOUNDFORBIDFLAG` removes the derived form (or the plain first/middle word) from
    compounding, and a suffix whose continuation class carries `ONLYINCOMPOUND` is a
    Fuge-element that must be followed by another part;
  * `COMPLEXPREFIXES` trades the second suffix level for a second *prefix* level, so
    `tekmetouro` is reachable when the inner prefix hands the outer one its flag;
  * `CHECKCOMPOUNDPATTERN` boundaries (`endchars[/flag] beginchars[/flag]`, the special
    `0` unmodified-stem pattern, and the optional replacement that allows the simplified
    form), `CHECKCOMPOUNDDUP`, `CHECKCOMPOUNDTRIPLE` with `SIMPLIFIEDTRIPLE`,
    `CHECKCOMPOUNDCASE`, `CHECKCOMPOUNDREP`, `COMPOUNDWORDMAX` and `COMPOUNDSYLLABLE`
    (the Hungarian "more words when few syllables" exception), and `FORCEUCASE` (a
    compound whose last part carries it must be capitalised);
  * `COMPOUNDRULE` patterns over the parts' compound flags, with `*` (zero or more),
    `?` (zero or one) and parenthesized multi-character flags, matched by recursive
    decomposition of the word (so `1*`-style rules such as `n*mp` accept `100th`).
- **Encodings at the CLI** — the `SET` directive is sniffed from the `.aff` bytes and
  used to decode the `.aff`, the `.dic` and the word input: UTF-8, ISO8859-1, ISO8859-15
  (the eight code points that differ from Latin-1) and other single-byte encodings as
  Latin-1. A UTF-8 input file next to a legacy-encoded dictionary is detected and decoded
  as UTF-8, and a leading UTF-8 BOM is stripped.
- **`suggest()` suggestion engine** (`src/suggest`):
  * a correct word (`check` accepts it) needs no correction, so the result is empty;
  * **`REP` replacements** from the `.aff`, applied at every occurrence, on the word and
    its lower-case form, with `^`/`$` anchors and `_` as a space (`phorm` → `form`,
    `alot` → `a lot`);
  * the **`ph:` "inner REP table"** — every `.dic` field `ph:value` becomes a
    replacement rule `value` → the entry's word, in dictionary order, in the capitalised
    and ALL-CAPS spellings too. The manual's three forms are handled: plain
    (`which ph:wich`), the trailing `*` that strips the last character of both sides
    (`pretty ph:prity*` behaves as `prit` → `prett`) and the explicit `->` form
    (`happy ph:hepi->happi`). A word pair is a real word with a space
    (`a lot ph:alot` suggests `a lot`, and its flags come from its last token);
  * **`MAP` related-character groups** — each group (`MAP uü`, `MAP ß(ss)`) lets any
    member be replaced by any other member, at several positions of the same word, so
    `Fruhstuck` → `Frühstück` (two `u` → `ü`) and `gross` → `groß` (`ss` → `ß`) are
    reachable. A parenthesized run is one multi-character alternative, and the recursion
    is budgeted so a pathological table cannot stall the engine;
  * **edit distance 1** — deletions, adjacent transpositions, replacements and insertions,
    with replacements/insertions restricted to the `TRY` characters (an ASCII alphabet when
    `TRY` is absent);
  * **case variations** — lower-case, `Capitalised`, ALL CAPS, the possessive stem
    (`Unicef's` → `UNICEF's`) and the `CHECKSHARPS` `SS` spelling (`MÜßIG` → `MÜSSIG`);
  * **splitting into two words**, and with a hyphen when `TRY`/`WORDCHARS` declares `-`;
  * a **bounded edit distance 2**: double deletion, long swap, single-character move and
    two independent adjacent transpositions — the kinds the manual names, O(n²) rather
    than O(n²·|TRY|²), so it stays cheap;
  * the **`PHONE` phonetic pass** — the Aspell-derived table-driven transcription is
    implemented (character classes, `-` retention, `<` re-scan, `^`/`$` anchors, `_` as
    the empty output) and every dictionary word is indexed by its key
    once at load time; a `.dic` `ph:` field is that entry's key (`xxxxxxxxxx ph:Brasilia`
    is pronounced like `Brasilia`). Candidates are dressed in the input's capitalisation
    (`kt` → `cat`, `Kt` → `Cat`, `KT` → `CAT`). A dictionary with no `PHONE` line skips
    the pass and pays nothing;
  * **ranking and filtering** — every candidate must be accepted by `check` and must not be
    a `NOSUGGEST` entry; results are deduplicated, the input word is never returned,
    `REP`/`ph:` hits rank first, then keyboard-adjacent (via `KEY`) typos, then early `TRY`
    characters, then shorter edit distance, with the phonetic candidates last, and an
    alphabetical tiebreak.
  * **no n-gram tier** — `MAXNGRAMSUGS`, `MAXDIFF` and `ONLYMAXDIFF` are parsed into the
    AST, but no n-gram candidate is generated, because the `hunspell(5)` manual does not
    define the similarity score (see [Not implemented yet](#not-implemented-yet)). A
    future tier would be a *fallback* below the passes above, not a replacement for them.
- **Public façade** — `src/api` plus a re-export from the module root: `load`, `check`,
  `suggest`, `encoding`, `flag_type_name`, `rule_count`, `entry_count`.
- **Runnable examples** — `examples/basic` (the API end to end) and `examples/doccheck`
  (the library spell-checking a MoonBit repository's own prose).

**Build status:** `moon check` reports 0 errors and 0 warnings; the test suite passes on
each of wasm, wasm-gc, js and native.

### Not implemented yet

- **ALL-CAPS input against a mixed-case dictionary form** — Hunspell matches
  `OPENOFFICE.ORG` to `OpenOffice.org`, `UNICEF'S` to `UNICEF's` and `IPOD` to `iPod`.
  The library only folds an ALL-CAPS word to its lowercase and capitalised spellings, so
  those (`allcaps`, `allcaps_utf`, `allcaps2` — 6 verdicts over 4 distinct spellings)
  are still lost, and one
  `allcaps2` forbidden word (`iPodos`) is consequently accepted. The `hunspell(5)` manual
  documents the *flags* (`KEEPCASE`, `CHECKSHARPS`) but not the casing algorithm itself.
- **The Hungarian "moving rule"** — `LANG hu` activates a hard-wired rule that lets a
  `COMPOUNDFORBIDFLAG` stem rebuild itself inside a hyphenated compound
  (`forróvíz-tartály`). `COMPOUNDWORDMAX`/`COMPOUNDSYLLABLE` are implemented, so this one
  word is all that `hu` still misses; the manual only names the rule, it does not define
  the rebuild.
- **`limit-multiple-compounding`'s three-part typo check** — that corpus expects a
  three-or-more-part compound to be rejected when it is one edit away from a dictionary
  word (`foobarbaz` vs `goobarbaz`). No directive requests it and the manual does not
  describe it, so it is not guessed at.
- **`COMPOUNDROOT` / `SYLLABLENUM`** — collected in `AffFile::unrecognized` rather than
  modelled on the AST, and not applied; no corpus suite exercises them.
- **Behavioural deviations found by an independent audit (2026-09-28).** The audit compared
  this library against hunspell 1.7.3 on synthetic dictionaries and found six places where
  behaviour differed from the reference *without* being covered by the list above.
  **Three are fixed as of this commit** — each with a mutation-tested unit test and each
  re-checked against `hunspell 1.7.3` on the same synthetic dictionary — and one was
  **attempted and reverted on measurement**:
  - **Multi-separator numbers** — Hunspell accepts `1.2.3` and `2026.1.1` when the separators
    are neither adjacent nor at either end; this library allowed only **one** separator.
    Fixed. The implementation's own comment had always stated the correct rule, and the test
    that asserted `1.2.3` was *false* **encoded the bug** — so the assertion was turned into
    `assert_true` rather than weakening the implementation (see `AGENTS.md` rule 4).
  - **Compound length** — an absent `COMPOUNDWORDMAX` means *unlimited* (`hunspell(5)`:
    "Default is unlimited."), but the default branch and the `COMPOUNDSYLLABLE` exception
    both fall back to 8 parts, so compounds of nine or more parts are rejected. **Attempted,
    measured, reverted.** Raising the ceiling to the word's length makes the backtracking
    search exponential: upstream's `tests/timelimit` is one 22-character word, and with the
    higher ceiling it ran past 20 s here against 7 ms for `hunspell 1.7.3`, hanging the
    conformance run. Hunspell survives the same input only with an undocumented hard-coded
    wall-clock limit. The ceiling is now a named `compound_part_ceiling()` carrying that
    measurement; closing this needs a search budget or memoisation, not a bigger number.
    (While measuring: with the ceiling back at 8, that word still takes ~3.1 s, because the
    search enumerates every decomposition instead of stopping at the first.)
  - **`CHECKCOMPOUNDTRIPLE` scope** — it was applied to non-ASCII characters although the
    code's own comment, and `hunspell(5)`, say ASCII-only — the manual records that as a
    limitation of the reference implementation ("Bug: missing multi-byte character support
    in UTF-8 encoding"). Fixed to match the reference, since matching it is the point.
  - **The CLI's UTF-8 sniffer** — accepted overlong encodings and surrogates while its own
    comment claimed it rejected them. Fixed, and it now has a test; it had none, because the
    CLI as a whole was outside `moon test`.
- **Three deviations remain open, deliberately:**
  - **`PHONE` digit priorities** — parsed into the AST and never read, so they cannot
    influence the `<` re-scan (the claim that they do has been removed above).
  - **`AM` morphological aliases** — parsed and never consumed; nothing reads the
    morphological fields they would populate.
  - **The CLI's UTF-8 sniffer** — accepts overlong encodings and surrogates although its
    comment says it rejects them; it had no test of its own.
- **The n-gram candidate generator** — Hunspell's last suggestion channel is absent.
  The `.aff` directives that configure it are parsed into the AST
  (`AffFile::max_ngram_sugs`, `AffFile::max_diff`, `AffFile::only_max_diff`), but no
  candidate is generated from them. The reason is that the `hunspell(5)` manual —
  checked in every published form available: the English text in 1.7.0, 1.7.2 and
  1.7.3, the corpus's own `man/hunspell.5`, and its Hungarian translation
  (`man/hu/hunspell.5`, which alone names a default of `5` for `MAXNGRAMSUGS`; the
  English text names none) — describes the pass only as a "similarity search through
  the dictionary words based on common 1-, 2-, 3-, and 4-character sequences", and
  gives `MAXDIFF`'s default (`5`) and range (`0`-`10`) plus `ONLYMAXDIFF`'s "remove
  all bad n-gram suggestions". It never defines the score itself: the per-order n-gram
  weights, the normalisation, the cutoff `MAXDIFF` selects, the default
  `MAXNGRAMSUGS`, or what counts as a "bad" suggestion. That algorithm exists only in
  Hunspell's LGPL-2.1 `suggestmgr.cxx`, which this Apache-2.0 project must not copy, so
  the scorer is not guessed at. The gap is also not uniform across the corpus:
  `MAXNGRAMSUGS 0` switches the pass off in 12 of the 37 `.sug` suites, `1463589`,
  `1463589_utf` and `base_utf` set it to `1`, and the rest leave it at the default — so
  a guessed scorer risks regressing at least the twelve that switch it off, rather than
  only adding suggestions.
- **Other suggestion refinements still out of scope** — `FORCEUCASE` is parsed and used
  for judgement but does not drive a suggestion. Edit distance 2 is only the bounded
  O(n²) subset listed above (no two arbitrary replacements, no
  replacement-plus-insertion). The `PHONE` pass treats a `^^` pattern as a plain start
  anchor followed by re-scanning from the end of the match instead of a fully separate
  sub-word (no corpus table uses `^^`). One `COMPOUNDRULE`-style case also remains: a
  `CHECKCOMPOUNDPATTERN` replacement is not tried when the *endchars* leave a doubled
  letter across the join (a contrived `kroom`+`om b` case), matching Hunspell only for
  the corpus shapes. This is why `.sug` is at 81.5% rather than higher.
- **Unicode upper-casing beyond the special cases** — upper-casing is ASCII-only plus the
  explicit `İ`/`ı` and `ß` rules; a fully general Unicode case table is not shipped.
  `FULLSTRIP` needs no special code (a rule may already strip the whole stem) and
  `PSEUDOROOT` is accepted as the deprecated spelling of `NEEDAFFIX`.
- FFI bindings to the Hunspell C++ library. The parsing, affix, judgement and suggestion
  logic is written from scratch in MoonBit and links against no speller — see
  [Native code](#native-code) for the one exception, a small stdin shim in the CLI.
- Any UI / editor plugin.

## Native code

Every library package (`src/aff`, `src/dic`, `src/affix`, `src/spell`, `src/suggest`,
`src/api`) is **pure MoonBit**: no `extern`, no C, no FFI, and no Hunspell code or bindings.
That is why the four backends behave identically.

The only C in the repository is `cmd/main/stdin_native.c` — 46 lines that `fread` stdin in
64 KiB chunks. It exists because the native backend otherwise cannot read `--words -` from a
pipe: the whole-file reader in `moonbitlang/x/fs` seeks to size its buffer, and a pipe is not
seekable (`Illegal seek`). Nothing else about the CLI is backend-specific, and the other
three backends keep using the unmodified whole-file path. `moonbitlang/x/fs` and
`moonbitlang/x/sys` take the same approach for the same reason.

## Design

```
src/aff/      .aff lexer + parser -> typed AST
src/dic/      .dic parser + dictionary storage
src/affix/    affix rule engine (condition matching, strip/add)
src/spell/    spell() judgement: indexed dictionary, reverse lookup, case rules
src/suggest/  suggest(): REP, edit distance 1/2, case, splitting, ranking
src/api/      public facade: load, check, suggest, metadata
cmd/main/     CLI (the `check` and `suggest` subcommands)
examples/     runnable examples (`basic`, `doccheck`)
conformance/  conformance harnesses (`run.sh` for .good/.wrong, `suggest.sh` for .sug)
```

## Development

```bash
moon check      # type / lint check
moon build      # build
moon test       # run tests
moon fmt        # format
moon info       # regenerate .mbti interfaces
```

Before a submission, one command runs every gate and re-measures every published number,
so the documentation cannot quietly go stale:

```bash
bash check-all.sh          # reports land in .final-check/
```

The two phases are different on purpose. **Phase 1 gates** — `moon check --deny-warn`,
`moon fmt --check`, `moon test`, an unchanged `.mbti`, and the offline `doccheck`
exit-status contract — and exits non-zero if any of them fails. **Phase 2 only reports** —
conformance, `.sug`, the differential test, the benchmark and `doccheck` on this repository —
saving each output to a file and never failing on drift. Nothing in either phase invents a
number: a measurement that cannot run says so instead.

This exists because each of the three stale figures in this project's history was found by
re-running a measurement, never by reading the code.

The examples are [`examples/basic`](examples/basic) (runnable end to end),
[`examples/doccheck`](examples/doccheck) (spell-checks this repository's own prose, and exits
non-zero when it finds a typo) and [`examples/ci-gate`](examples/ci-gate) (proves that exit
status gates a build, offline).

A Chinese companion README lives at [`README.zh.md`](README.zh.md). It is a `.mbt.md` file
too, so its code blocks are compiled and its examples executed — the Chinese documentation
cannot drift away from the code.

## Community articles

- **《AI 写了 7300 行 MoonBit：编译器能验的，和验不了的》** — how this library was built
  with an AI assistant, and the part that matters more: the three verification layers,
  and why a 2.31× performance regression *and* a 1.9-point conformance understatement
  both survived a green `moon check`, a green test suite and an unchanged conformance
  number. The fix in both cases was re-measuring, not adding features.
  - 知乎 — https://zhuanlan.zhihu.com/p/2087606024068976886
  - 掘金 — https://juejin.cn/post/7689644399769796649

  (Chinese. Every measured number in it was taken from this repository, but some have
  moved since publication: the article and the cover say **178 / 182** tests, and the
  repository now has **200 / 204**. The increments come from two sources. First, `mbt check`
  blocks added to the Quick start above and to `README.zh.mbt.md`: a block containing a
  `test` is executed by `moon test`, so documenting a behaviour now enforces it. Second,
  tests added after an independent audit found features this README *claimed* while nothing
  pinned them: `ICONV`/`OCONV` had no test at all, and `src/api`'s metadata accessors, the
  CLI's option parser, `KEY` adjacency and the missing-`TRY` fallback were equally
  unpinned — every one of those was mutation-tested, by breaking the code and confirming
  the new test fails. Where the article and this repository ever disagree, this file and
  the scripts that produce it win — which is the article's own point.)

## License

Apache-2.0. See [LICENSE](LICENSE).

This is an independent implementation based on the Hunspell file-format specification
and its observable behaviour. **No Hunspell source code was copied.** See
[NOTICE](NOTICE) for the full reference and licence disclosure.
