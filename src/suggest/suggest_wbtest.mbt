// Whitebox tests for the string helpers the suggestion generators are built
// from. They are pure functions, so they need no dictionary.

///|
test "dedupe_chars keeps the first-seen order" {
  assert_eq(dedupe_chars("aabbc"), ['a', 'b', 'c'])
  assert_eq(dedupe_chars(""), ([] : Array[Char]))
  assert_eq(dedupe_chars("aba"), ['a', 'b'])
}

///|
test "first_difference locates a replacement, insertion and deletion" {
  assert_eq(first_difference("cat", "cut"), (1, Some('a'), Some('u')))
  assert_eq(first_difference("cat", "cats"), (3, None, Some('s')))
  assert_eq(first_difference("cats", "cat"), (3, Some('s'), None))
  assert_eq(first_difference("cat", "cat"), (3, None, None))
}

///|
test "the string builders edit exactly one place" {
  let chars = "abcd".to_array()
  assert_eq(slice_string(chars, 1, 3), "bc")
  assert_eq(remove_one(chars, 0), "bcd")
  assert_eq(remove_two(chars, 1, 3), "ac")
  assert_eq(swap_two(chars, 0, 3), "dbca")
  assert_eq(replace_one(chars, 1, 'x'), "axcd")
  assert_eq(insert_one(chars, 0, 'z'), "zabcd")
  assert_eq(insert_one(chars, 4, 'z'), "abcdz")
  assert_eq(move_one(chars, 0, 3), "bcad")
  assert_eq(replace_range(chars, 1, 2, "XY"), "aXYd")
}

///|
test "matches_at compares a run of code points" {
  let chars = "hello".to_array()
  assert_true(matches_at(chars, "ell".to_array(), 1))
  assert_false(matches_at(chars, "ell".to_array(), 2))
}

///|
test "REP fields are split and `_` becomes a space" {
  assert_eq(rep_field("ph"), ("ph", false, false))
  assert_eq(rep_field("^alot$"), ("alot", true, true))
  assert_eq(rep_field("shun$"), ("shun", false, true))
  assert_eq(rep_field("_"), (" ", false, false))
  assert_eq(underscore_to_space("a_lot"), "a lot")
}

///|
test "KEY rows are split on the pipe" {
  let rows = parse_key_rows("abc|de")
  assert_eq(rows.length(), 2)
  assert_eq(rows[0], ['a', 'b', 'c'])
  assert_eq(rows[1], ['d', 'e'])
  assert_eq(parse_key_rows("").length(), 1)
}

///|
test "MAP groups split single characters and parenthesized sequences" {
  assert_eq(parse_map_group("uü"), ["u", "ü"])
  assert_eq(parse_map_group("ß(ss)"), ["ß", "ss"])
  assert_eq(parse_map_group("(ọ́)o"), ["ọ́", "o"])
  assert_eq(parse_map_group("a"), ["a"])
  // an unclosed group runs to the end of the line
  assert_eq(parse_map_group("x(yz"), ["x", "yz"])
  assert_eq(parse_map_group(""), ([] : Array[String]))
  // a group with fewer than two alternatives cannot substitute anything
  assert_eq(parse_map_groups(["a"]).length(), 0)
  assert_eq(parse_map_groups(["ab", "c"]).length(), 1)
}

///|
/// `Ranker::adjacent` is the whole of the `KEY` ranking rule, and it had no test: the
/// README listed "keyboard-adjacent (via `KEY`)" as a ranking source while nothing
/// pinned what "adjacent" means for the staggered layout the code is written for.
test "adjacent covers in-row and staggered cross-row neighbours" {
  // The bottom row is deliberately one column shorter than the others, which is where
  // an off-by-one in the column window shows up.
  let r : Ranker = {
    try_array: [],
    key_rows: parse_key_rows("qwertyuiop|asdfghjkl|zxcvbnm"),
    map_groups: [],
  }
  // the same row, both directions
  assert_true(r.adjacent('q', 'w'))
  assert_true(r.adjacent('w', 'q'))
  // the row below: same column, and one column of offset either way
  assert_true(r.adjacent('q', 'a'))
  assert_true(r.adjacent('q', 's'))
  // the short bottom row against the row above it
  assert_true(r.adjacent('z', 'a'))
  assert_true(r.adjacent('m', 'j'))
  // far apart in the same row block, and five columns offset
  assert_false(r.adjacent('q', 'h'))
  assert_false(r.adjacent('p', 'a'))
  // a key is not its own neighbour
  assert_false(r.adjacent('a', 'a'))
  // characters that are not on the layout at all
  assert_false(r.adjacent('1', '2'))
}

///|
test "edit_alphabet falls back to ASCII when the .aff declares no TRY" {
  assert_eq(default_alphabet(), "abcdefghijklmnopqrstuvwxyz")
  // No TRY: the generator must still have an alphabet to edit with, and it must be
  // the documented default rather than an empty one.
  let without = @spell.Dictionary::from_text("SET UTF-8", "1\nhello")
  assert_eq(edit_alphabet(without), dedupe_chars(default_alphabet()))
  // A TRY line, with a duplicate, replaces the default rather than adding to it.
  let with_try = @spell.Dictionary::from_text("SET UTF-8\nTRY abca", "1\nhello")
  assert_eq(edit_alphabet(with_try), ['a', 'b', 'c'])
}
