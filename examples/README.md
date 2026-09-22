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

## Adding another example

Create `examples/<name>/` with a `moon.pkg` declaring
`pkgtype(kind: "executable")` and an import of `"Careylq/spell"`, plus a
`main.mbt` with a `fn main`. It will then be picked up by `moon check` and can be
run with `moon run examples/<name>`.
