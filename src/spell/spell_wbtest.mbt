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
test "lower_word and capitalise_word" {
  assert_eq(lower_word("HELLO"), "hello")
  assert_eq(lower_word("iPhone"), "iphone")
  assert_eq(lower_word("café"), "café")
  assert_eq(capitalise_word("HELLO"), "Hello")
  assert_eq(capitalise_word("iphone"), "Iphone")
  assert_eq(capitalise_word(""), "")
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
