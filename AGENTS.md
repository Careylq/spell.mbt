# Working in this repository

How to make a change here **without breaking a claim**. The first half is specific to this
project; the second half is the generic MoonBit convention that came with the template.

This file is written to be read by an AI coding agent, because that is how this project was
built — see [AI assistance](#ai-assistance-what-it-did-and-how-it-was-checked).

## What this repository is

A pure-MoonBit library that parses Hunspell `.aff`/`.dic` dictionaries, applies the affix
rules, judges words and suggests corrections. `src/` holds six library packages
(`aff` `dic` `affix` `spell` `suggest` `api`); `cmd/main` is the CLI; `examples/` holds three
runnable examples. [`README.mbt.md`](README.mbt.md) is the authoritative description and
[`ACCEPTANCE.md`](ACCEPTANCE.md) is the requirement-by-requirement self-check.

## How work gets verified here

There is one command. Run it before claiming anything works:

```bash
bash check-all.sh          # gates fail loudly; measurements report into .final-check/
```

Phase 1 **gates** (must pass, offline): `moon check --deny-warn --target all`,
`moon fmt --check`, `moon test --target all`, an unchanged `.mbti`, and the offline
`doccheck` exit-status contract. Phase 2 **measures** (conformance, `.sug`, the differential
test, the benchmark, `doccheck` on this repository) and never fails on drift.

The rule this project keeps relearning:

> **Re-measure. Do not copy a number out of a document — including one this repository
> wrote.** Every stale figure in this project's history was found by re-running a
> measurement, never by reading the code: a direct-hit performance figure that had drifted
> 2.31×, a conformance figure that was 1.9 points too low for weeks because of a harness
> pairing bug, and a doccheck figure invalidated by the documentation it described.

Corollary, learned the hard way: **quote measurements that are stable.** A number that moves
whenever someone edits prose must not be pinned in prose. That is why the dogfooding section
quotes "118 distinct words flagged, 0 of them real typos" and not a word total.

## Where to look when something is unclear

| Question | Read |
|---|---|
| What does this `.aff`/`.dic` directive mean? | the `hunspell(5)` man page — **the manual is the specification**, not this code |
| Is a behaviour *implemented*? | README's [Not implemented yet](README.md#not-implemented-yet) — if it is listed there, it is out of scope on purpose |
| Why is the code shaped this way? | [`DEVLOG.md`](DEVLOG.md), one entry per working day with the tradeoff |
| Has this toolchain gotcha bitten us before? | [`docs/MOONBIT_GOTCHAS.md`](docs/MOONBIT_GOTCHAS.md) — 43 entries, each verified by the compiler, a warning, or a measurement |
| What changed, and why? | [`CHANGELOG.md`](CHANGELOG.md) |

## Rules this project holds itself to

1. **Do not guess underspecified behaviour.** The n-gram suggestion pass is unimplemented
   because `hunspell(5)` never defines its similarity score; the algorithm exists only in
   Hunspell's LGPL source, which this project must not copy. Guessing would have been easy
   and would have been wrong. When a rule cannot be derived, **write down why and leave the
   gap visible.**
2. **Keep the "not implemented" list closed.** Every failing official-corpus case must map to
   an entry in README's *Not implemented yet*. If a case fails for an unlisted reason, that is
   a documentation bug.
3. **Do not copy Hunspell's code.** Reference format specifications and observable behaviour;
   see [`NOTICE`](NOTICE). Corpora and dictionaries are fetched at run time and never
   committed.
4. **Do not weaken a test to make it pass.** Two tests in this repository were *corrected*
   after an audit showed the assertion — not the implementation — was wrong. Say so in the
   commit message when that happens.
5. **A green gate is not a result.** A change is done when the measurement that matters has
   been re-run and the number reported is the one it produced.

## AI assistance: what it did and how it was checked

This project was built with an AI coding agent in the loop. The workflow, in the order it
was actually applied:

1. **The human sets direction and accepts or rejects results.** Scope, what to build next,
   what to cut, and whether a result was good enough were decisions taken by the entrant,
   not inferred by the agent.
2. **One function (or one document change) at a time, verified before moving on.** The agent
   wrote the code and its tests; the acceptance signal was `moon check` / `moon test`, not the
   agent's own claim that it was fixed.
3. **Measured, not asserted.** Every number in README and ACCEPTANCE comes from a script in
   this repository. Where a figure could not be measured, it says so instead of being
   estimated.
4. **The process is recorded.** [`DEVLOG.md`](DEVLOG.md) logs each working day's design
   tradeoffs and the measured deltas; [`docs/MOONBIT_GOTCHAS.md`](docs/MOONBIT_GOTCHAS.md)
   collects toolchain traps, each with the evidence that established it; the commit history is
   grouped by feature rather than by session.

The part worth being explicit about: **the agent's failures are recorded too.** The DEVLOG
lists, among others, a probe script that silently did not run (so a false conclusion was
drawn from its silence), a set of review materials written into a directory no reviewer would
read, and a push-retry loop that read its exit status from the wrong end of a pipe and
reported success while the push was failing. Each is there because the same shape of mistake
— trusting an indirect signal — is the one this codebase is most likely to repeat.

---

## MoonBit conventions (from the project template)

This is a [MoonBit](https://docs.moonbitlang.com) project. Extra skills:
<https://github.com/moonbitlang/skills>.

### Structure

- Packages are per directory; each has a `moon.pkg` listing its dependencies. A package's
  files, blackbox tests (`_test.mbt`) and whitebox tests (`_wbtest.mbt`) live together.
- The module root has `moon.mod` (metadata) and `moon.pkg`; the root package is a re-export
  facade over `src/api`.

### Coding convention

- Code is organised in blocks separated by `///|`; block order is irrelevant, and in some
  refactorings blocks can be processed independently.
- Keep deprecated blocks in a `deprecated.mbt` in each directory.

### Tooling

- `moon fmt` formats; `moon info` regenerates the `.mbti` interfaces. **Run
  `moon info && moon fmt` last** and check the `.mbti` diff: if nothing there changed, the
  change did not alter the package's visible interface and is usually a safe refactoring.
- `moon test` runs tests; snapshot tests refresh with `moon test --update`.
- Prefer `assert_eq`, or `assert_true(pattern is Pattern(...))`, for results that are stable.
  For snapshot tests of structured debugging output, derive `Debug` and use `debug_inspect`
  rather than deriving `Show`.
- `moon coverage analyze > uncovered.log` shows uncovered code.
- `moon ide` provides `peek-def`, `outline` and `find-references`. See
  `$moonbit-agent-guide`.
