// Blackbox tests for the public facade in `src/api`.
//
// `api.mbt` is deliberately thin — the types are re-exported and the functions are
// conveniences over `@spell.Dictionary` — so these tests pin the parts a user of the
// *facade* actually calls, which the package's other tests never touched: the four
// metadata accessors, and the promise that `suggest` only ever returns words `check`
// accepts. The `load`/`check`/`suggest` happy paths are already covered by the
// `mbt check` blocks in the documentation comments, which `moon test` runs.

///|
test "encoding reports the SET directive, and is empty when there is none" {
  let with_set = @api.load("SET UTF-8\nTRY abc", "1\nhello")
  assert_eq(@api.encoding(with_set), "UTF-8")
  // `.aff` without `SET`: the accessor must not invent a default.
  let without = @api.load("TRY abc", "1\nhello")
  assert_eq(@api.encoding(without), "")
}

///|
test "flag_type_name names each of the four FLAG modes" {
  let with_flag = fn(mode : String) raise {
    @api.load("SET UTF-8\n" + mode, "1\nhello")
  }
  assert_eq(@api.flag_type_name(with_flag("")), "single character")
  assert_eq(@api.flag_type_name(with_flag("FLAG long")), "FLAG long")
  assert_eq(@api.flag_type_name(with_flag("FLAG num")), "FLAG num")
  assert_eq(@api.flag_type_name(with_flag("FLAG UTF-8")), "FLAG UTF-8")
}

///|
test "rule_count counts PFX/SFX rule lines, not blocks" {
  // Two blocks, one rule line each: the count must be 2, so a reader can tell
  // "how many rules" from the number rather than guessing what a block is.
  let d = @api.load(
    "SET UTF-8\nSFX A Y 1\nSFX A 0 s .\nPFX B Y 1\nPFX B 0 un .", "2\ncat/A\ndog/B",
  )
  assert_eq(@api.rule_count(d), 2)
}

///|
test "entry_count counts distinct words, not lines" {
  let d = @api.load("SET UTF-8", "3\ncat\ndog\nbird")
  assert_eq(@api.entry_count(d), 3)
}

///|
test "every suggestion is a word check accepts" {
  let d = @api.load(
    "SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\nREP 1\nREP ph f", "2\nform\nphantom",
  )
  let suggestions = @api.suggest(d, "phorm", 5)
  assert_true(suggestions.length() > 0)
  for word in suggestions {
    assert_true(@api.check(d, word))
  }
}

///|
test "suggest returns nothing for a word that is already correct" {
  let d = @api.load("SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz", "1\nform")
  assert_eq(@api.suggest(d, "form", 5), [])
}
