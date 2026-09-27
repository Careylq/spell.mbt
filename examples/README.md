# examples/

Runnable examples for `spell.mbt`. Each example is a real MoonBit executable
package (not a snippet), so it is type-checked by `moon check` and can be run
from the repository root.

## `examples/basic`

```bash
moon run examples/basic
```

It embeds a tiny `.aff` + `.dic` pair (written from scratch for this project —
no Hunspell test data is copied) and then:

1. loads the dictionary once with `@spell.load`,
2. prints the detected `SET` encoding, the `FLAG` mode, the number of affix
   rules and the number of dictionary entries,
3. judges a list of words, including affix-derived forms:
   * `cats`, `boxes` — regular plurals from `SFX S`
   * `happied` — a stripping rule (`SFX D y ied [^aeiou]y`)
   * `undos` — one prefix plus one suffix (`PFX U` + `SFX S`) on the same stem
   * `unhappy` — a prefix on a dictionary stem
4. shows the capitalisation and special-flag rules: `Cat` is accepted, `EBOOK`
   is rejected because `ebook` carries `KEEPCASE`, and `catss` is rejected
   because no affix rule produces it.

Expected output:

```
spell.mbt — tiny dictionary written for this example

encoding           : UTF-8
flag type          : single character
affix rules        : 4
dictionary entries : 7

word         correct?
  cat     yes
  cats    yes
  box     yes
  boxes   yes
  happy   yes
  happied yes
  unhappy yes
  undos   yes
  ebook   yes
  EBOOK   no
  Cat     yes
  catss   no
  nope    no
```

## `examples/doccheck`

```bash
bash examples/doccheck/run.sh                    # scan this repository
bash examples/doccheck/run.sh path/to/repo       # scan another tree
bash examples/doccheck/run.sh --include-tests    # also scan *_test.mbt
bash examples/doccheck/run.sh --quiet            # summary only
```

This is the dogfooding example: the library spell-checks the prose of a MoonBit
project. It reads Markdown (`.md`, `.mbt.md`) and MoonBit comments (`///`, `//`),
turns them into candidate English words, and asks `@spell.check` about each one.
The spelling decision is always the library's — no external speller is called.

The dictionary is `en_US` from LibreOffice's `dictionaries` repository (built
from SCOWL, size 60). `run.sh` fetches it from jsDelivr into a cache directory at
run time; it is **never** copied into this repository (the SCOWL/Ispell licences
are not this project's Apache-2.0). Point `SPELL_DICT_DIR` at a directory holding
`en_US.aff`/`en_US.dic` to run offline.

### Extraction rules

* **Files** — `*.md` (including `*.mbt.md`) and `*.mbt`. `*_test.mbt` and
  `*_wbtest.mbt` are skipped unless `--include-tests` is given, because test
  comments deliberately contain misspelled fixture words
  (`permenant`, `wrold`, `vacacation`, `sxzh`, ...).
* **Markdown** — fenced code blocks (```` ``` ```` / `~~~`), inline code spans,
  HTML comments, link targets, and whitespace-separated tokens containing `/`
  (paths and URLs) are removed before tokenising.
* **MoonBit** — only lines whose first non-space characters are `///` or `//` are
  read, and a code fence inside a `///` block is skipped (so the `mbt check`
  examples in the API docs are not treated as prose).
* **Candidate words** — a run of letters (or `'`) with no non-ASCII character.
  A run that touches a digit, `.` or `_` is dropped (identifiers, file names,
  versions, hex), and so is an ALL-CAPS run. Possessives (`word's`) are reduced
  to the base word; any other word with an apostrophe is skipped. Words shorter
  than three letters are skipped, which is what keeps `e.g.` and `i.e.` quiet.
* Identical files are scanned once, so the `README.md` → `README.mbt.md` symlink
  does not double every number.

### Allowlist

`examples/doccheck/allowlist.txt` holds words a general English dictionary does
not know but this project legitimately uses (`Hunspell`, `MoonBit`, `mooncakes`,
`aff`, `wasm`, British spellings, ...). Each entry is inserted into the `.dic`
text before `@spell.load`, verbatim and in lower case, so it goes through the
library's own capitalisation rules rather than around them. A mixed-case spelling
(`MoonBit`, `macOS`) needs its own line, because the library's rule maps a
capitalised word to a lower-case entry, not to a mixed-case one.

**An allowlist is required for real prose.** The first run over this repository
is not clean, and the numbers below are from actual runs, not estimates.

### Measured on this repository (moon 0.1.20260920, en_US SCOWL size 60)

| run | files | words checked | misspelled tokens | distinct words |
|---|---|---|---|---|
| first run, no allowlist | 32 | 16,602 | 461 | 110 |
| after `allowlist.txt` (101 entries) | 32 | 16,602 | **0** | **0** |
| `--include-tests` (allowlist on) | 46 | 18,042 | 14 | 11 |

All 110 distinct words the first run flagged were reviewed by hand: **none was a
typo.** 110 of 110 were false positives of a general dictionary on a technical
repository — project vocabulary (`wasm`, `stdin`, `backend`, `aff`, `dic`), the
Hunspell/affix terminology this project is about (`Fuge`, `endchars`,
`circumfix`, `ngram`, `checksharps`), MoonBit and third-party proper nouns
(`MoonBit`, `macOS`, `jsDelivr`, `WordNet`, `aspell`, `nuspell`), British
spellings (`judgement`, `licence`, `behaviour`, `capitalised`, `modelled`), and
ordinary English words a size-60 SCOWL list simply omits (`seekable`, `runnable`,
`matcher`, `lookups`, `substring`, `unclosed`, `misclassifies`). They are all in
the allowlist.

With `--include-tests` the remaining 11 are the deliberate fixtures and suffix
fragments in test comments (`abc`, `aeiou`, `krom`, `sxzh`, `-ication`, ...);
that is exactly why the default scope leaves test files out.

### Known false positives and false negatives

The extractor is deliberately thin, so it misclassifies some text:

* an unclosed backtick or code fence can leak code into the text under test;
* a `//` line inside a multi-line string literal would be read as a comment;
* hyphenated words are checked as two separate words;
* a word immediately before a dot is kept only when the dot ends a sentence
  (`the end.`), so `moon` in `moon.pkg` is dropped but a bare `moon` is checked;
* correctly-spelled-but-wrong words (`form` for `from`) are invisible to any
  spell checker, and so are typos in ALL-CAPS or camelCase identifiers, which
  this extractor skips on purpose.

The last point is the honest engineering finding: a general en_US dictionary
gives a technical repository ~100% false positives on its first run, so the
allowlist is not a nicety — it is the mechanism that makes the tool usable at
all.

## Adding another example

Create `examples/<name>/` with a `moon.pkg` declaring
`pkgtype(kind: "executable")` and an import of `"Careylq/spell"`, plus a
`main.mbt` with a `fn main`. It will then be picked up by `moon check` and can be
run with `moon run examples/<name>`.
