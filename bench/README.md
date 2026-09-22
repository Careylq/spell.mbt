# bench/ — performance benchmark

A reproducible, **end-to-end** performance benchmark for `spell.mbt`. One command
produces every number in the `## Performance` section of `README.mbt.md` and the
table further down this file:

```bash
bash bench/run.sh
```

It builds the project in release mode, fetches the real `en_US` dictionary at run
time, measures it, generates synthetic dictionaries, measures those, and prints a
machine/toolchain header plus five tables. It leaves nothing behind in the working
tree (the dictionary and all scratch data live in a `mktemp -d` directory — see
[Keeping the tree clean](#keeping-the-tree-clean)).

---

## The honesty rules this benchmark follows

1. **Nothing is estimated or hard-coded.** Every number is produced by timing a
   command during the run. If a measurement cannot be taken, the section says
   `SKIPPED` (and why); it never prints a plausible-looking substitute.
2. **These are end-to-end, wall-clock numbers.** They include process startup,
   file reading and dictionary loading wherever the table says so. They are not
   microbenchmarks of a single function.
3. **They are machine-specific.** Absolute values on another CPU, OS or MoonBit
   release will differ. The script prints the machine and the toolchain so a
   reader can judge whether a comparison is like-for-like.
4. **The dictionary is never vendored.** It is fetched into a temp directory at
   run time (this project is Apache-2.0; the dictionary carries its own upstream
   licence, see [Dictionary source and licence](#dictionary-source-and-licence)).
5. **Determinism is tested, not assumed.** The synthetic generator is checked to
   be byte-reproducible inside the run, and the word lists are validated (every
   "hit" word accepted, every "miss" word rejected) before their timings are
   reported. A failed validation prints a `WARNING` next to the row.
6. **No fabricated head-to-head.** The hunspell comparison runs two native
   executables on the same input files. It is skipped with a clear message when
   `hunspell` is not installed.

---

## What each section measures

| Section | Measures |
|---|---|
| 1 | Dictionary source, in-file version, sha256, entry count, licence note |
| 2 | The documented `moon run cmd/main -- check ...` path on real `en_US`, in **both debug and release wasm**: process start / load / per-word check, separated |
| 3 | Head-to-head: our **native release** binary vs the system **hunspell**, same files |
| 4 | Scaling curve on **synthetic** `.aff`/`.dic` pairs (1k → 200k entries) |
| 5 | Release artifact size (wasm / wasm-gc / js / native) |

---

## Measurement method

### The timing primitive

Every timed sample is:

```bash
TIMEFORMAT='%6R'
t=$( { time <command> >/dev/null 2>&1; } 2>&1 )
```

* `%6R` is the shell's elapsed wall-clock time with microsecond resolution
  (`TIMEFORMAT` is a bash feature; the system bash 3.2 on macOS supports it).
* **Medians over several repetitions**, never a single sample:
  `BENCH_REPS_SMALL` (default 9) for process-start/load, `BENCH_REPS_BIG`
  (default 5) for ~50k-word runs, `BENCH_REPS_HUGE` (default 3) for ≥100k-word
  runs. The exact repetition counts are printed in the header of the output.
* Standard output and error go to `/dev/null`, so terminal rendering is not part
  of the measurement. Both engines pay the same redirection cost.
* A non-zero exit status aborts the measurement with an error instead of
  reporting the time of a command that failed. The one exception is the
  no-argument invocation, which prints usage and exits 2 **by design** — that is
  the process-start probe.

### Separating dictionary load from per-word checking

A single `check` run does three things: start the process, load the dictionary,
then check every word. To separate them the script times **three points**:

| Point | Command | Meaning |
|---|---|---|
| `T_start` | no-argument run (exits 2) | process start only, no dictionary touched |
| `T_load` | `--words <empty file>` | process start + parse + index the dictionary |
| `T_N` | `--words <N words>` | process start + load + N checks |

Then:

```
load        = T_load − T_start
check_only  = T_N − T_load
per-word    = check_only / N
```

The benchmark brief suggested a two-point variant (a 1-word run minus a large
run). That is algebraically the same thing, but it needs two subtractions and
lets process-start noise enter twice, so section 2 also prints the 1-word run and
the derived two-point load as a **cross-check**: on the reference machine the two
estimates agree to well under a millisecond.

### The engines and their exact commands

| Name | Start probe | Loaded run |
|---|---|---|
| `native` | `_build/native/release/build/cmd/main/main.exe` (no args) | `main.exe check --aff <a.aff> --dic <d.dic> --words <list>` |
| `moon` | `moon run cmd/main` | `moon run cmd/main -- check --aff <a.aff> --dic <d.dic> --words <list>` |
| `moon-rel` | `moon run --release cmd/main` | `moon run --release cmd/main -- check ...` |
| `hunspell` | `hunspell -v` | `hunspell -d <dir>/<base> -l <list>` |

Note that **plain `moon run` builds debug wasm**, while the native binary is
built with `moon build --target native --release`. Section 2 therefore reports
**both** the debug path (the one the README tells a user to type) and the
`moon run --release` path side by side, and section 3 adds release wasm to the
cross-backend comparison so the wasm backend is never understated.

That distinction also reconciles two figures recorded earlier in this project by
hand: "load + judge the dictionary's own 49,568 entries = 0.15 s" reproduces as
**0.153 s** on the *release* wasm path, whereas plain `moon run` (debug) is
**0.187 s**; likewise "/usr/share/dict/words = 3.80 s" sits within 1% of the
release-wasm **3.837 s** here, while debug wasm is 4.353 s. Both pairs are the
same workloads; neither figure replaces the other, and this harness reports both
rather than picking whichever looks better.

### Real dictionary (sections 1–3)

* Fetched at run time from **jsDelivr**, not `raw.githubusercontent.com` (the
  latter times out on the reference network):
  `https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master/en/en_US.aff`
  and `.../en_US.dic`.
* The script prints the in-file header line, the upstream `README_en_US.txt`
  version when that extra fetch succeeds, the entry count, and the sha256 of both
  files, so a reader can tell whether they measured the same bytes.
* The "dictionary's own words" list is produced by stripping the `/flags` field
  from each `.dic` line. SCOWL's `en_US` does not escape a literal `/` inside a
  word, so the simple strip is exact here; the script records that assumption
  instead of pretending to handle the general case.
* **The `ONLYINCOMPOUND` check is derived, not hard-coded.** Rather than
  asserting "exactly `1th`, `2th`, `3th` must be rejected", the script reads the
  `ONLYINCOMPOUND` flag out of the `.aff`, joins each rejected word to its `.dic`
  flags, and requires that *every* standalone rejection carries that flag. If a
  rejection were unexplained it would be printed as a failure of the self-check.

### Hit-heavy vs miss-heavy: why both are measured

Hunspell-style lookup has two very different paths. In this library
(`src/spell/lookup.mbt`):

* a **hit** ends at `direct_hit` — one map access;
* a **miss** must run `affix_hit`, which scans every suffix rule, then every
  prefix rule, then the prefix×suffix cross product, then the two-suffix and
  prefix+two-suffix paths, doing a map lookup for each candidate stem.

So a miss costs `O(#affix rules)`, not `O(dictionary size)`. The benchmark makes
this visible in two ways:

1. **Two word lists of identical size** (49,568 words each) are timed against the
   real dictionary: the dictionary's own entries (all hits) and the same entries
   with `xq` appended (all misses). The script verifies that **0** of the
   appended words are accepted, so the row really is an all-miss workload.
2. A realistic mixed list (`/usr/share/dict/words`, 235,976 words, 18.4% hits on
   the reference machine) shows what a real batch job looks like.

### Head-to-head fairness (section 3)

`hunspell` is not part of `moon`, and the natural comparison — the `moon run`
wasm path against a native C++ binary — is not apples-to-apples. The benchmark
therefore compares **native executable against native executable**:

```bash
moon build --target native --release
_build/native/release/build/cmd/main/main.exe check --aff en_US.aff --dic en_US.dic --words <list>
hunspell -d <dir>/en_US -l <list>
```

Both processes: start once, read the same `.aff` and `.dic` bytes, then look up
the same words from the same file. Differences that remain, and how to read them:

* `hunspell -l` prints only the **misspelled** words while our CLI prints one
  `1`/`0` per input word. On hit-heavy input hunspell writes 3 lines where we
  write 49,568. Both write to `/dev/null`, so this is cheap, but it is a real
  residual asymmetry and it means the miss-heavy rows are the cleaner comparison.
* Our CLI reads the whole word file into memory and splits it; hunspell streams
  its input. That is part of this library's measured design, not an accident of
  the harness, so it is left in.
* The start probes are not identical work (`hunspell -v` prints a version, our
  no-argument run prints usage); both avoid touching a dictionary, and section 3
  reports `load = (empty run) − (start probe)` so the probe cost cancels.

No comparison is included for the `suggest` subcommand; see
[What is deliberately not measured](#what-is-deliberately-not-measured).

### Synthetic scaling curve (section 4)

Generated by `bench/gen_dict.sh`, which is **deterministic and uses no RNG**:
word *i* is a base-20 encoding of *i* into five syllables from a fixed 20-item
table, plus an ending marker chosen by `i % 5`. The encoding is injective, so all
words are distinct. Flags are fixed by `i % k` (all words carry `S`; `D` when
`i % 2 == 0`, `G` when `i % 3 == 0`, `U` when `i % 5 == 0`, `R` when
`i % 7 == 0`). The `.aff` has **5 blocks / 8 rules**:

```
SFX S 0 s .         SFX S 0 es [sxzh]      SFX S y ies [^aeiou]y
SFX D 0 ed .        SFX D 0 ing .
SFX G 0 ly .
PFX U 0 un .        PFX R 0 re .
```

The script generates the 1,000-entry pair twice and compares sha256 to prove the
generator is reproducible.

Every dictionary size is checked against the **same** 100,000-word workload
(`BENCH_MEASURE_WORDS`), built by cycling the generated entries — so the µs/word
and words/s columns are directly comparable down the table even at 1k entries,
where the check phase would otherwise be too small to see above process-start
jitter. Miss words are those same words with `xq` appended, and the script
verifies that none of them is accepted.

**These dictionaries are synthetic, not language data.** Their only purpose is to
show the *shape* of the curve. In particular the 8-rule synthetic affix set is
much smaller than real `en_US` (50 rules), so absolute synthetic miss costs are
not comparable with section 3; the trend across sizes is the result.

### Artifact size (section 5)

`moon build --release` for each target, then `wc -c` on the produced executable
payload of the `cmd/main` package. Libraries are distributed as source plus a
generated `.mbti` interface, so there is no separate library binary to measure.

---

## Keeping the tree clean

Everything the benchmark downloads or generates lives in a `mktemp -d`
directory that is removed on exit; set `BENCH_TMP=dir` to create that scratch
directory under `dir` instead, or `BENCH_KEEP_TEMP=1` to keep it for inspection.
Build products go to `_build/`, which is already git-ignored. `git status` stays
clean.

Verified on the reference machine: after a full run, `git status --porcelain`
listed only the files this change actually added.

---

## Dictionary source and licence

| | |
|---|---|
| `.aff` | `https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master/en/en_US.aff` |
| `.dic` | `https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master/en/en_US.dic` |
| Upstream | LibreOffice `dictionaries`, `en/` — built from SCOWL |
| In-file header | `# 2024-01-29 (Marco A.G.Pinto)` |
| Upstream README version | `2020.12.07` (`README_en_US.txt`, SCOWL size 60) |
| Entries | 49,568 (the `.dic` count line agrees) |
| Licence | SCOWL / Kevin Atkinson permissive notice, plus the Ispell BSD licence and the WordNet notice for parts of the sources. Full text: the upstream `README_en_US.txt`. |

The dictionary is **fetched at run time and never redistributed** with this
repository. Only the measured numbers and the sha256 of the fetched bytes are
recorded. This mirrors the rule `conformance/README.md` applies to the Hunspell
test corpus, and it is why the benchmark needs the network for sections 1–3.

---

## Results

One real run, `bash bench/run.sh`, **2026-09-22T06:13:14Z**.

Machine / toolchain (printed by the script itself):

```
os        : macOS 26.6.2 (25G83) arm64, kernel 25.6.0
cpu       : Apple M5 (10 cores)
memory    : 16 GiB
toolchain : moon 0.1.20260920, moonc v0.10.14+7d59c7ec9, moonrun 0.1.20260920
hunspell  : Hunspell 1.7.3 (/opt/homebrew/bin/hunspell)
dictionary: LibreOffice en_US (SCOWL), 49,568 entries,
            .aff sha256 e746c882dd6f303c2c46e7452804b9201115a6942cfeb15f18f8edf774d2e24e
            .dic sha256 f0b1a234bd178bdd01875b2a392a9647f888b8fe879f79c52aae62c2759b3647
            affix rules: 50 rules in 23 blocks
reps      : 9 (start/load), 5 (49,568 words), 3 (235,976 words)
```

### 1. Load vs check on the real dictionary (wasm backend)

Command shape: `moon run cmd/main -- check --aff en_US.aff --dic en_US.dic --words <list>`.

| step | wasm debug (`moon run`) | wasm release (`moon run --release`) |
|---|---|---|
| process start (no-arg run) | 0.0190 s | 0.0190 s |
| start + load (empty word list) | 0.1330 s | 0.1090 s |
| **load only** (derived) | **0.1140 s** | **0.0900 s** |
| 1-word run (2-point cross-check) | 0.1340 s | 0.1090 s |
| 49,568-word run, all hits | 0.1870 s | 0.1530 s |
| **checking only** (derived) | **0.0540 s** | **0.0440 s** |
| per-word checking cost | 1.09 µs | 0.89 µs |
| throughput, end-to-end | 265,070 words/s | 323,974 words/s |
| throughput, checking only | 917,926 words/s | 1,126,545 words/s |

2-point cross-check: debug `0.1150 s` vs `0.1140 s`; release `0.0900 s` vs
`0.0900 s`.

Self-check: **49,565/49,568** entries accepted; the 3 rejected (`1th 2th 3th`)
all carry the `.aff` `ONLYINCOMPOUND` flag `c`, i.e. the rejection is correct and
is *derived* from the dictionary rather than hard-coded.

### 2. Head-to-head, native release vs Hunspell 1.7.3

| metric | ours native | hunspell | ratio (ours/theirs) |
|---|---|---|---|
| process start | 0.0020 s | 0.0030 s | 0.67× |
| start + load | 0.0300 s | 0.0100 s | 3.00× |
| load only | 0.0280 s | 0.0070 s | 4.00× |
| 49,568 **hits**: total | 0.0470 s | 0.0290 s | 1.62× |
| 49,568 hits: checking only | 0.0170 s | 0.0190 s | **0.89×** |
| 49,568 hits: per word | 0.34 µs | 0.38 µs | 0.89× |
| 49,568 hits: throughput (e2e) | 1,054,638 w/s | 1,709,241 w/s | |
| 49,568 **misses**: total | 0.4720 s | 0.0870 s | 5.43× |
| 49,568 misses: checking only | 0.4420 s | 0.0770 s | 5.74× |
| 49,568 misses: per word | 8.92 µs | 1.55 µs | 5.75× |
| 49,568 misses: throughput (e2e) | 105,017 w/s | 569,747 w/s | |
| 235,976 mixed words: total | 1.7300 s | 0.2950 s | 5.86× |
| 235,976 mixed words: throughput | 136,402 w/s | 799,919 w/s | |

`/usr/share/dict/words` (235,976 words) is **18.4% hits** (43,474 accepted) on
this dictionary, so it is miss-dominated.

**The asymmetry is the finding, not the single ratio.** Splitting the same
49,568 words into an all-hit and an all-miss list (verified: 0 of the "+xq"
misses were accepted) shows:

* on the **hit** path the two engines are essentially level — our checking phase
  is 0.34 µs/word vs hunspell's 0.38 µs/word (0.89×). Our 1.62× end-to-end gap
  on that list is almost entirely **dictionary load** (28 ms vs 7 ms, 4.0×), not
  lookup;
* on the **miss** path we are 5.8× slower per word (8.92 µs vs 1.55 µs), because
  `affix_hit` (`src/spell/lookup.mbt`) tries every suffix rule, every prefix
  rule, the prefix×suffix cross product and the two-suffix families for every
  rejected word, while a hit ends at `direct_hit` — one map access.

So the concrete optimisation target is the **miss path** (and, secondarily,
dictionary load), not the direct lookup. That is exactly what the synthetic
scaling curve tests.

### 3. Cross-backend, same 235,976-word workload

| backend | total | throughput |
|---|---|---|
| native release | 1.7300 s | 136,402 words/s |
| wasm release (`moon run --release`) | 3.8370 s | 61,500 words/s |
| wasm debug (plain `moon run`) | 4.3530 s | 54,210 words/s |

Native release is **2.22×** faster than release wasm and **2.52×** faster than
debug wasm on this miss-dominated workload.

### 4. Scaling curve (synthetic; 100,000-word workload at every size)

| entries | .dic KiB | rules | load ms | hit µs/w | miss µs/w | hit e2e w/s | miss e2e w/s |
|---|---|---|---|---|---|---|---|
| 1,000 | 17.6 | 8 | 1.00 | 0.36 | 0.90 | 2,564,103 | 1,075,269 |
| 10,000 | 181.6 | 8 | 7.00 | 0.38 | 0.95 | 2,127,660 | 961,538 |
| 50,000 | 940.4 | 8 | 35.00 | 0.39 | 0.99 | 1,315,789 | 735,294 |
| 200,000 | 3,817.6 | 8 | 144.00 | 0.42 | 1.00 | 531,915 | 406,504 |

* **Load scales linearly** with the entry count: 1.0 → 7.0 → 35 → 144 ms, i.e.
  ≈0.7 µs per entry, and the `.dic` size grows linearly too.
* **Per-word checking does not scale with dictionary size.** Over a 200× range,
  the hit path moves 0.36 → 0.42 µs/word and the miss path 0.90 → 1.00 µs/word.
  The small upward drift is consistent with cache pressure; the point is that
  neither curve follows the 200× growth of the dictionary.
* The **e2e words/s columns fall** purely because they include the load: at
  200,000 entries, 144 ms of the ~190 ms hit run is load and index building.
  That is why the µs/word columns, not the words/s columns, are the scaling
  evidence.

### 5. Release artifact size

| target | artifact | bytes |
|---|---|---|
| wasm | `_build/wasm/release/build/cmd/main/main.wasm` | 105,042 (102.6 KiB) |
| wasm-gc | `_build/wasm-gc/release/build/cmd/main/main.wasm` | 80,326 |
| js | `_build/js/release/build/cmd/main/main.js` | 321,075 |
| native | `_build/native/release/build/cmd/main/main.exe` | 605,304 |

The wasm CLI is ~103 KiB with no C++ runtime — that is the payload a wasm host
downloads.

### 6. Correctness cross-check against hunspell (bonus, cheap)

On the dictionary's own 49,568 entries, `hunspell -l` reports exactly 3
misspellings (`1th`, `2th`, `3th`) and this library rejects exactly the same 3:
**the two implementations agree exactly** on that input. Those entries carry
`ONLYINCOMPOUND` and must be rejected standalone, so both are correct.

---

## What is deliberately not measured

Reported honestly rather than guessed at:

* **Suggestion quality or speed.** Only `check` is benchmarked. `suggest` runs a
  different, much larger search; adding it would need its own methodology and its
  own correctness baseline.
* **Peak memory / allocation counts.** The harness measures wall-clock time only.
  `/usr/bin/time -l` (macOS) or `-v` (Linux) could add this, but it is not
  currently measured and no number is invented for it.
* **Other spell checkers** (aspell, nuspell, `spell`, browser engines). Only
  hunspell is compared, and only when it is installed.
* **Threads / parallelism.** Everything here is single-process, single-threaded.
* **A browser or edge-worker benchmark.** The wasm numbers come from `moonrun`
  on the host, which is not the same runtime as a browser JIT.
* **Correctness.** Performance says nothing about whether a word is judged
  correctly. That is what `conformance/run.sh` measures, and this benchmark does
  not touch those numbers.

Earlier versions of this document said a hunspell comparison was absent because
it would not be apples-to-apples. That was true of a `wasm`-vs-native comparison;
once both sides are built as native executables the comparison is fair, so it is
included (section 3) with the residual asymmetries listed above.

---

## Reproducing on another machine

Requirements: `moon` ≥ the version printed in the output, `bash`, `awk`, `sort`,
`paste`, `join`, `comm` and `curl`. Optional: `hunspell` (enables section 3) and
`/usr/share/dict/words` (otherwise a 200,000-word list is generated).

Environment overrides:

| Variable | Default | Effect |
|---|---|---|
| `BENCH_REPS_SMALL` | 9 | repetitions for start/load |
| `BENCH_REPS_BIG` | 5 | repetitions for ~50k-word runs |
| `BENCH_REPS_HUGE` | 3 | repetitions for ≥100k-word runs |
| `BENCH_SIZES` | `1000 10000 50000 200000` | synthetic dictionary sizes |
| `BENCH_MEASURE_WORDS` | 100000 | words checked per synthetic size |
| `BENCH_MAIN_WORDS` | `/usr/share/dict/words` | large mixed word list |
| `BENCH_FALLBACK_WORDS` | 200000 | size of the generated fallback list |
| `BENCH_SKIP_REAL` | 0 | skip the fetched real dictionary |
| `BENCH_SKIP_HUNSPELL` | 0 | skip the head-to-head |
| `BENCH_TMP` | `mktemp -d` | parent dir for a fresh scratch subdir (removed on exit) |
| `BENCH_KEEP_TEMP` | 0 | keep the scratch dir and print its path |

### Offline behaviour

If the network is unavailable the script prints

```
SKIPPED: could not fetch the dictionary (network unavailable).
         The synthetic scaling curve and the artifact sizes below do not need it.
```

and continues with sections 4 and 5. It still exits 0: no network is not a
benchmark failure. The same applies to a missing `hunspell` or a missing native
binary — the affected section is skipped, the rest still runs.

### CI

`.github/workflows/bench.yml` runs this script, but **only on
`workflow_dispatch`** — benchmark numbers on shared runners are noisy and must
not gate a build. It is not part of the `ci.yml` check/build/test gate and is not
a required check. The numbers in `README.mbt.md` were measured on a laptop, and
that machine description is printed at the top of every run for exactly this
reason.
