# spell.mbt

[![CI](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/Careylq/spell.mbt/actions/workflows/ci.yml)

A pure-MoonBit spell checker compatible with the **Hunspell `.aff` / `.dic` dictionary
format** — it parses real-world dictionaries (e.g. `en_US`), applies the affix rules
defined in the `.aff` file, judges words the way Hunspell does, and suggests corrections
for the words it rejects.

> This file is `README.mbt.md` — MoonBit type-checks `.mbt.md` files, so any MoonBit
> code block below is verified by `moon check`. `README.md` is a symlink to this file
> so that GitHub renders it.

> **Status: 0.5.0.** The `.aff`/`.dic` parsers, the affix engine, the `spell()`
> judgement engine, the suggestion engine, the public API and the `check` /
> `suggest` CLI subcommands are implemented and tested on all four backends. See
> [Not implemented yet](#not-implemented-yet) for what suggestion generation
> still leaves out (phonetic/ngram candidates in particular).

## Conformance

Measured against the official Hunspell test corpus (`hunspell/hunspell` → `tests/`, 154
suites with `.good`/`.wrong` files) by `bash conformance/run.sh`. The corpus is fetched
at run time and is **not** redistributed with this repository (Hunspell is LGPL-2.1;
this project is Apache-2.0 — see [NOTICE](NOTICE)). The numbers below come from an
actual run of the harness, not an estimate.

| Metric | Passing | Total | Pass rate |
|---|---|---|---|
| `.good` (must be accepted) | 730 | 848 | 86.1% |
| `.wrong` (must be rejected) | 579 | 613 | 94.5% |
| `.sug` (expected best suggestion produced) | 108 | 173 | 62.4% |

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
  required to pass this row. 108/173 = 62.4%.
* For reference, the stricter "our first suggestion equals the expected best
  suggestion" is 93/173 = 53.8%, and reproducing a whole `.sug` file exactly —
  Hunspell's own test criterion, in order and with no extra suggestion — holds for
  **5/37 suites** (13.5%).

The row is partial because Hunspell's extra suggestion passes are deliberately out of
scope: the phonetic `ph:`/`PHONE` tables (`ph`, `ph2`, `phone`, 21 of the 65 misses),
`MAP` accents (`map`/`maputf`, 6), `OCONV` (`oconv`, 3), `FORCEUCASE` (`forceucase`, 2)
and the ngram/`MAXNGRAMSUGS` candidate generator. Where the corpus needs those the
library returns fewer (or no) suggestions; it never invents one `check` rejects.

The remaining `.good` gap is dominated by the compound engines this release still
leaves partial: `COMPOUNDMIDDLE`, `CHECKCOMPOUNDPATTERN`, affixed parts inside
compounds and the German `COMPOUNDBEGIN`/`COMPOUNDMIDDLE`/`COMPOUNDEND` suites
(`germancompounding` and `germancompoundingold` alone account for 26 of the 118
missing words). After that come `COMPLEXPREFIXES` (twofold prefix stripping) and
the Hungarian `COMPOUNDSYLLABLE`/`COMPOUNDFORBIDFLAG` rules. The `.wrong` column is
the stronger result: only 34 of 613 words that must be rejected are wrongly
accepted. Run `bash conformance/run.sh` locally to reproduce.

> Measurement caveat: the harness pairs each `.good` line with the verdict of the
> matching input line using `paste -d' '`, so a corpus line that itself contains a
> space is misaligned. `morph.good` has 16 such lines (`drink eat`, …); the
> library accepts all of them (they are checked as whitespace-separated groups,
> and each word in the group is correct), but the harness can only report 10 of
> the 26 `morph.good` lines. That is a limitation of the measurement, not of the
> library, and the harness was deliberately left untouched so the numbers stay
> comparable.

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

**Machine:** Apple M5 (10 cores), 16 GiB, macOS 26.6.2 (25G83), arm64.
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
| process start | 0.0190 s | 0.0190 s |
| start + load (49,568 entries) | 0.1330 s | 0.1090 s |
| **load only** | **0.1140 s** | **0.0900 s** |
| 49,568-word run (all hits) | 0.1870 s | 0.1530 s |
| **checking only** | **0.0540 s** | **0.0440 s** |
| per-word check | 1.09 µs | 0.89 µs |
| throughput, end-to-end | 265,070 words/s | 323,974 words/s |
| throughput, checking only | 917,926 words/s | 1,126,545 words/s |

Plain `moon run` compiles **debug** wasm; the release column is the same backend
compiled like the native binary, and its 0.153 s is the "≈0.15 s to load the
dictionary and judge its own 49,568 entries" figure recorded earlier in this
project. All 49,568 entries load; 49,565 are accepted standalone and the 3
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
| dictionary load only | 0.0280 s | 0.0070 s | 4.00× |
| 49,568 all-hit words: total | 0.0470 s | 0.0290 s | 1.62× |
| 49,568 all-hit words: **checking only** | 0.0170 s | 0.0190 s | **0.89×** |
| 49,568 all-hit words: **per word** | **0.34 µs** | **0.38 µs** | 0.89× |
| 49,568 all-miss words: total | 0.4720 s | 0.0870 s | 5.43× |
| 49,568 all-miss words: checking only | 0.4420 s | 0.0770 s | 5.74× |
| 49,568 all-miss words: per word | 8.92 µs | 1.55 µs | 5.75× |
| 235,976 mixed words (`/usr/share/dict/words`, 18.4% hits) | 1.7300 s | 0.2950 s | 5.86× |
| 235,976 mixed words: throughput | 136,402 words/s | 799,919 words/s | |

The aggregate ratios hide the interesting part. On **hits** the two engines are
level per word (0.34 µs vs 0.38 µs) — our 1.62× there is almost entirely
dictionary load (28 ms vs 7 ms) — while on **misses** we are 5.8× slower per
word, because a rejected word runs the reverse affix lookup over every suffix
rule, every prefix rule, the prefix×suffix cross product and the two-suffix
families (`affix_hit` in `src/spell/lookup.mbt`), whereas a hit is one map
access (`direct_hit`). Real text is miss-dominated here: `/usr/share/dict/words`
is only 18.4% hits. **The miss path and dictionary load are the optimisation
targets; direct lookup is already competitive.**

As a cross-backend data point on the same 235,976 words: native release 1.730 s
is **2.22×** faster than release wasm (3.837 s) and **2.52×** faster than the
debug wasm that plain `moon run` builds (4.353 s).

### Scaling on synthetic dictionaries

Deterministic `.aff`/`.dic` pairs (no RNG; 5 blocks / 8 affix rules) generated by
`bench/gen_dict.sh`, **not real language data**. Every size is checked against
the *same* 100,000-word workload so the per-word columns are comparable, and the
generator is verified byte-reproducible during the run.

| entries | .dic KiB | load | hit | miss | hit end-to-end | miss end-to-end |
|---|---|---|---|---|---|---|
| 1,000 | 17.6 | 1.00 ms | 0.36 µs/word | 0.90 µs/word | 2,564,103 w/s | 1,075,269 w/s |
| 10,000 | 181.6 | 7.00 ms | 0.38 µs/word | 0.95 µs/word | 2,127,660 w/s | 961,538 w/s |
| 50,000 | 940.4 | 35.00 ms | 0.39 µs/word | 0.99 µs/word | 1,315,789 w/s | 735,294 w/s |
| 200,000 | 3,817.6 | 144.00 ms | 0.42 µs/word | 1.00 µs/word | 531,915 w/s | 406,504 w/s |

Load grows linearly (≈0.7 µs per entry), but **per-word checking does not follow
the dictionary size**: across a 200× range the hit path moves 0.36 → 0.42 µs and
the miss path 0.90 → 1.00 µs. The end-to-end words/s columns fall only because
they include the load. (The synthetic affix set has 8 rules against real
`en_US`'s 50, so synthetic miss *absolute* values are not comparable with the
table above; the trend is the result.)

### Release artifact size

| target | bytes |
|---|---|
| wasm (`cmd/main`) | 105,042 (102.6 KiB) |
| wasm-gc | 80,326 |
| js | 321,075 |
| native | 605,304 |

The wasm CLI is ~103 KiB with no C++ runtime — that is the payload a wasm host
downloads and runs.

### What is *not* measured

Suggestion-engine speed, peak memory, other spell checkers (aspell/nuspell/…),
threads, and any browser or edge-worker runtime. Those are listed with reasons
in [`bench/README.md`](bench/README.md#what-is-deliberately-not-measured); no
number is invented for them.

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

## Scope

### Implemented

- **`.aff` parser** — `SET`, `FLAG`, `AF`, `AM`, `PFX`, `SFX`, `REP`, `TRY`, `KEY`,
  `IGNORE`, `WORDCHARS`, `CHECKSHARPS`, `BREAK`, `ICONV`/`OCONV`, `COMPOUND*`, and the
  special-flag directives (`NOSUGGEST`, `KEEPCASE`, `FORBIDDENWORD`, `NEEDAFFIX`,
  `CIRCUMFIX`, `ONLYINCOMPOUND`).
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
    case must match exactly);
  * `CHECKSHARPS`: an uppercased word may spell a dictionary `ß` as `SS`
    (`PROZESSIONSSTRASSE` finds `Prozessionsstraße`), a capital sharp s (`ẞ`, U+1E9E)
    folds to `ß`, and a `KEEPCASE` word containing `ß` may be capitalised or uppercased
    with `SS` but not with a sharp s (`MÜßIG` stays wrong);
  * special flags `FORBIDDENWORD`, `KEEPCASE` (including on compound parts),
    `NEEDAFFIX`, `ONLYINCOMPOUND`;
  * `IGNORE` characters are dropped from dictionary entries, from affix `strip`/`add`
    text and from the checked word before any comparison (Arabic harakat, right-to-left
    marks);
  * a trailing `.` is accepted for abbreviations when `WORDCHARS` declares `.`, and a
    number with one separator (`.`, `,`, `-`) between digits is accepted when
    `WORDCHARS` declares that separator (`1.12345`, `4,2`, `42-42`);
  * `BREAK` splitting, recursively: the declared break points, or Hunspell's defaults
    `-`, `^-` and `-$` (`foo-bar-foo-bar`), with `BREAK 0` switching breaking off;
  * a line of whitespace-separated words is correct when every word on it is correct;
  * two-part compounds whose parts carry `COMPOUNDFLAG`, `COMPOUNDBEGIN` or
    `COMPOUNDEND` (`COMPOUNDMIN`, default `3`);
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
  * **edit distance 1** — deletions, adjacent transpositions, replacements and insertions,
    with replacements/insertions restricted to the `TRY` characters (an ASCII alphabet when
    `TRY` is absent);
  * **case variations** — lower-case, `Capitalised`, ALL CAPS, the possessive stem
    (`Unicef's` → `UNICEF's`) and the `CHECKSHARPS` `SS` spelling (`MÜßIG` → `MÜSSIG`);
  * **splitting into two words**, and with a hyphen when `TRY`/`WORDCHARS` declares `-`;
  * a **bounded edit distance 2**: double deletion, long swap, single-character move and
    two independent adjacent transpositions — the kinds the manual names, O(n²) rather
    than O(n²·|TRY|²), so it stays cheap;
  * **ranking and filtering** — every candidate must be accepted by `check` and must not be
    a `NOSUGGEST` entry; results are deduplicated, the input word is never returned, and
    `REP` hits rank first, then keyboard-adjacent (via `KEY`) typos, then early `TRY`
    characters, then shorter edit distance, with an alphabetical tiebreak.
- **Public façade** — `src/api` plus a re-export from the module root: `load`, `check`,
  `suggest`, `encoding`, `flag_type_name`, `rule_count`, `entry_count`.
- **Runnable example** in `examples/basic`.

**Build status:** `moon check` reports 0 errors and 0 warnings; the test suite passes on
each of wasm, wasm-gc, js and native.

### Not implemented yet

- **Compounds of three or more parts, and affixed parts inside a compound** — the
  two-part case is handled, and `COMPOUNDRULE` decomposition is recursive, but a compound
  part must be a plain dictionary entry. `COMPOUNDMIDDLE`, `COMPOUNDPERMITFLAG`/
  `COMPOUNDFORBIDFLAG`, `CHECKCOMPOUNDPATTERN`, `CHECKCOMPOUNDDUP`/`TRIPLE`,
  `COMPOUNDWORDMAX`/`COMPOUNDSYLLABLE` and `CHECKCOMPOUNDREP` are parsed but not applied,
  which is why the German `germancompounding*` suites and `limit-multiple-compounding`
  still lose words.
- **`COMPLEXPREFIXES`** (twofold prefix stripping, needed by `alias3` and
  `complexprefixes*`).
- **`FORCEUCASE`** and `NOSUGGEST` semantics at lookup time (both are parsed; `NOSUGGEST`
  is honoured when filtering suggestion candidates).
- **`FULLSTRIP`, `PSEUDOROOT` and `COMPOUNDROOT`** handling.
- **Unicode upper-casing** — lowercasing uses `moonbitlang/x/unicode`, but upper-casing
  is ASCII-only, so a non-ASCII first letter is not capitalised (`dotless_i` and the
  Turkish/Azeri casing rules). `CHECKSHARPS` covers German `ß` explicitly.
- **Suggestion quality beyond the implemented passes** — the phonetic `PHONE`/`ph:` tables
  and `MAP` accents are not used, `OCONV` is not applied, `FORCEUCASE` does not drive a
  suggestion, and there is no ngram/`MAXNGRAMSUGS` candidate generator. Edit distance 2 is
  only the bounded O(n²) subset listed above (no two arbitrary replacements, no
  replacement-plus-insertion). This is why `.sug` is at 62.4% rather than higher.
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
examples/     runnable examples
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

## License

Apache-2.0. See [LICENSE](LICENSE).

This is an independent implementation based on the Hunspell file-format specification
and its observable behaviour. **No Hunspell source code was copied.** See
[NOTICE](NOTICE) for the full reference and licence disclosure.
