// Whitebox tests for the `doccheck` extractor.
//
// The spelling decision itself belongs to the library and is covered by its
// own tests; these tests pin down what the example feeds it, which is where
// the false positives documented in examples/README.md come from.

///|
test "clean_line removes inline code, link targets and paths" {
  assert_eq(collect_words(clean_line("keep `drop_me` this")), ["keep", "this"])
  // A link's text survives; its target does not.
  assert_eq(
    collect_words(clean_line("see [the docs](https://example.com/a/b)")),
    ["see", "the", "docs"],
  )
  // A whitespace-separated token containing `/` is a path or a URL.
  assert_eq(collect_words(clean_line("the file src/api/main.mbt is here")), [
    "the", "file", "here",
  ])
  assert_eq(clean_line("<!-- hidden --> visible"), "  visible")
}

///|
test "an unmatched backtick does not swallow the rest of the line" {
  assert_eq(strip_code_spans("keep `hidden"), "keep hidden")
  // ... which is a known false-positive source: the leaked text is checked.
  assert_eq(collect_words(strip_code_spans("keep `hidden")), ["keep", "hidden"])
}

///|
test "collect_words skips code, acronyms and non-Latin script" {
  // A run touching a digit, `.` or `_` is part of an identifier or a version.
  assert_eq(collect_words("flagutf8 UTF-8 API the"), ["the"])
  assert_eq(collect_words("moon.pkg and en_US"), ["and"])
  // A sentence-ending period is not code, so the last word survives.
  assert_eq(collect_words("the file ends here."), [
    "the", "file", "ends", "here",
  ])
  // An ALL-CAPS run is an identifier, not prose.
  assert_eq(collect_words("PFX and SFX rule"), ["and", "rule"])
  // Accented and non-Latin words belong to quoted examples, not to English.
  assert_eq(collect_words("façade straße café 一"), [])
  // Two-letter words are skipped to avoid `e.g.` and `i.e.` fragments.
  assert_eq(collect_words("is to of the"), ["the"])
}

///|
test "possessives are reduced to their base; contractions are skipped" {
  assert_eq(strip_possessive("manual's"), "manual")
  assert_eq(strip_possessive("parts'"), "parts")
  assert_eq(strip_possessive("'quoted'"), "quoted")
  assert_eq(collect_words("the manual's parts' 'quoted' text"), [
    "the", "manual", "parts", "quoted", "text",
  ])
  assert_eq(collect_words("don't is a"), [])
  assert_eq(accept_word("a"), None)
  assert_eq(accept_word("won't"), None)
}

///|
test "comment_body recognises `///` and `//` and nothing else" {
  assert_eq(comment_body("  /// Hello"), Some(" Hello"))
  assert_eq(comment_body("\t// Hello"), Some(" Hello"))
  assert_eq(comment_body("let x = 1 // not a comment line"), None)
  assert_eq(comment_body(""), None)
}

///|
test "fences are recognised in Markdown and in `///` blocks" {
  assert_true(is_fence_line("```mbt check"))
  assert_true(is_fence_line("   ~~~"))
  assert_false(is_fence_line("a code span"))
}

///|
test "the walker's file and directory filters" {
  assert_true(is_candidate("README.mbt.md", false))
  assert_true(is_candidate("main.mbt", false))
  assert_false(is_candidate("main_test.mbt", false))
  assert_false(is_candidate("main_wbtest.mbt", false))
  assert_true(is_candidate("main_wbtest.mbt", true))
  assert_false(is_candidate("notes.txt", false))
  assert_false(should_descend(".git"))
  assert_false(should_descend("_build"))
  assert_false(should_descend("node_modules"))
  assert_true(should_descend("src"))
}

///|
test "allowlist entries join the dictionary in both cases" {
  assert_eq(with_allowlist("2\nfoo\nbar", []), "2\nfoo\nbar")
  assert_eq(
    with_allowlist("2\nfoo\nbar", ["MoonBit"]),
    "4\nfoo\nbar\nMoonBit\nmoonbit\n",
  )
  // A trailing newline in the source `.dic` must not be doubled.
  assert_eq(with_allowlist("1\nfoo\n", ["hunspell"]), "2\nfoo\nhunspell\n")
  assert_eq(lowercase_word("MoonBit"), "moonbit")
  assert_eq(lowercase_word("WASM"), "wasm")
}

///|
test "drop_slash_tokens keeps the other words on the line" {
  assert_eq(drop_slash_tokens("see src/api and docs/x.md now"), "see  and  now")
  assert_eq(drop_slash_tokens("no paths here"), "no paths here")
}
