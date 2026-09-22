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
