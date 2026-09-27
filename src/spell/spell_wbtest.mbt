// Whitebox tests for the internal helpers of the judgement engine.

///|
/// Render the private `CaseKind` so it can be compared without deriving traits.
fn case_name(kind : CaseKind) -> String {
  match kind {
    NoLetters => "none"
    Lower => "lower"
    Capitalized => "capitalized"
    AllCaps => "allcaps"
    Mixed => "mixed"
  }
}

///|
test "classify_case covers every shape" {
  assert_eq(case_name(classify_case("hello", false)), "lower")
  assert_eq(case_name(classify_case("café", false)), "lower")
  assert_eq(case_name(classify_case("Hello", false)), "capitalized")
  assert_eq(case_name(classify_case("HELLO", false)), "allcaps")
  assert_eq(case_name(classify_case("A", false)), "allcaps")
  assert_eq(case_name(classify_case("iPhone", false)), "mixed")
  assert_eq(case_name(classify_case("ABc", false)), "mixed")
  assert_eq(case_name(classify_case("cAt", false)), "mixed")
  assert_eq(case_name(classify_case("123", false)), "none")
  assert_eq(case_name(classify_case("--", false)), "none")
  assert_eq(case_name(classify_case("", false)), "none")
  // Under CHECKSHARPS `ß` is a lower-case letter, so an otherwise uppercase
  // word containing it is mixed case and may only match exactly.
  assert_eq(case_name(classify_case("MÜßIG", true)), "mixed")
  assert_eq(case_name(classify_case("MÜSSIG", true)), "allcaps")
  assert_eq(case_name(classify_case("Müßig", true)), "capitalized")
}

///|
test "fold_lower and fold_capitalise" {
  assert_eq(fold_lower("HELLO", false), "hello")
  assert_eq(fold_lower("iPhone", false), "iphone")
  assert_eq(fold_lower("café", false), "café")
  assert_eq(fold_capitalise("HELLO", false), "Hello")
  assert_eq(fold_capitalise("iphone", false), "Iphone")
  assert_eq(fold_capitalise("", false), "")
  // A Turkish capital dotted `İ` is preserved as the first character.
  assert_eq(fold_capitalise("İZMİR", false), "İzmir")
  assert_eq(fold_lower("I", true), "ı")
  assert_eq(fold_lower("İ", true), "i")
  assert_eq(fold_capitalise("iç", true), "İç")
  assert_eq(fold_capitalise("ışık", true), "Işık")
}

///|
test "normalise_affix treats 0 and the empty string alike" {
  assert_eq(normalise_affix("0"), "")
  assert_eq(normalise_affix(""), "")
  assert_eq(normalise_affix("re"), "re")
}

///|
test "has_flag ignores an absent flag directive" {
  let flags : Array[String] = ["S", "K"]
  assert_true(has_flag(Some("S"), flags))
  assert_false(has_flag(Some("X"), flags))
  assert_false(has_flag(None, flags))
}

///|
test "chars_to_string slices by code point" {
  let chars = "a😀bc".to_array()
  assert_eq(chars_to_string(chars, 0, 1), "a")
  assert_eq(chars_to_string(chars, 1, 2), "😀")
  assert_eq(chars_to_string(chars, 1, 4), "😀bc")
  assert_eq(chars_to_string(chars, 4, 4), "")
}

///|
/// Build a conversion table the way `parse_aff` does, so these tests exercise the
/// same ordering the dictionary hands to `apply_conversion`.
fn conv_table(pairs : Array[(String, String)]) -> Array[@aff.Conversion] {
  let table : Array[@aff.Conversion] = []
  for pair in pairs {
    let (from, to) = pair
    table.push({ from, to, })
  }
  prepare_conversions(table)
}

///|
test "apply_conversion returns the text unchanged for an empty table or text" {
  let empty : Array[@aff.Conversion] = []
  assert_eq(apply_conversion(empty, "café"), "café")
  assert_eq(apply_conversion(conv_table([("’", "'")]), ""), "")
}

///|
test "apply_conversion replaces every occurrence of an unanchored pattern" {
  assert_eq(
    apply_conversion(conv_table([("’", "'")]), "it’s a ’test’"),
    "it's a 'test'",
  )
}

///|
test "apply_conversion: a trailing _ anchors the pattern to the end of the word" {
  let table = conv_table([("e_", "E")])
  assert_eq(apply_conversion(table, "cafe"), "cafE")
  // The same character away from the end of the word is left alone.
  assert_eq(apply_conversion(table, "cafe au lait"), "cafe au lait")
  assert_eq(apply_conversion(table, "ee"), "eE")
}

///|
test "apply_conversion prefers the longest pattern, then the anchored one" {
  // `prepare_conversions` puts the longest pattern first. Without that ordering
  // the one-character rule would win and `ae` would never be converted.
  let longest = conv_table([("a", "A"), ("ae", "Æ")])
  assert_eq(apply_conversion(longest, "aet"), "Æt")
  assert_eq(apply_conversion(longest, "bat"), "bAt")
  // Same length: the end-anchored `s_` is tried before the bare `s`, but it only
  // wins where it can match at the end.
  let anchored = conv_table([("s_", "Z"), ("s", "S")])
  assert_eq(apply_conversion(anchored, "st"), "St")
  assert_eq(apply_conversion(anchored, "ss"), "SZ")
}

///|
test "apply_conversion skips a pattern with an empty body instead of matching everywhere" {
  // A bare `_` is an anchor with nothing to match: it must consume no input and
  // the scan has to fall through to the next rule.
  assert_eq(apply_conversion(conv_table([("_", "!"), ("a", "A")]), "ab"), "Ab")
  // A table of nothing but empty patterns leaves the text alone.
  assert_eq(apply_conversion(conv_table([("_", "!")]), "ab"), "ab")
}

///|
test "apply_conversion does not rescan the text it has already produced" {
  let table = conv_table([("a", "b"), ("b", "c")])
  assert_eq(apply_conversion(table, "a"), "b")
  assert_eq(apply_conversion(table, "ab"), "bc")
}

///|
test "apply_conversion replaces a multi-character pattern anywhere in the word" {
  assert_eq(
    apply_conversion(conv_table([("ph", "f")]), "photograph"),
    "fotograf",
  )
}

///|
test "apply_conversion matches on code points, not bytes" {
  assert_eq(apply_conversion(conv_table([("😀", ":)")]), "a😀b"), "a:)b")
  assert_eq(apply_conversion(conv_table([("ß", "ss")]), "straße"), "strasse")
}

///|
test "apply_conversion leaves text that shares no starting character untouched" {
  // The no-match fast path must return the text itself, character for character,
  // when no pattern can start anywhere in it.
  assert_eq(
    apply_conversion(conv_table([("’", "'")]), "plain ascii"),
    "plain ascii",
  )
  assert_eq(apply_conversion(conv_table([("é", "e")]), "cafe"), "cafe")
  // A pattern whose first character does occur still goes through the full scan.
  assert_eq(apply_conversion(conv_table([("é", "e")]), "café"), "cafe")
}

///|
test "has_whitespace is the cheap guard for the word-group path" {
  // A single word — the CLI's one-word-per-line case — must be rejected without
  // allocating anything.
  assert_false(has_whitespace("drink"))
  assert_false(has_whitespace(""))
  assert_false(has_whitespace("café"))
  assert_true(has_whitespace("drink eat"))
  assert_true(has_whitespace("drink\teat"))
  assert_true(has_whitespace(" drink  eat "))
  // Whitespace alone is only the NECESSARY condition: this line has whitespace
  // and is still not a word group, so it must fall through to the normal path.
  assert_true(has_whitespace("  drink  "))
}
