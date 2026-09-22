// Whitebox tests for the entry-line internals.

///|
test "split_word_flags splits at the first unescaped slash" {
  @debug.assert_eq(split_word_flags("word"), ("word", (None : String?)))
  @debug.assert_eq(split_word_flags("word/A"), ("word", Some("A")))
  @debug.assert_eq(split_word_flags("a\\/b/A"), ("a/b", Some("A")))
  @debug.assert_eq(split_word_flags("a\\/b"), ("a/b", (None : String?)))
  @debug.assert_eq(split_word_flags("a//"), ("a", Some("/")))
  @debug.assert_eq(split_word_flags("\\/"), ("/", (None : String?)))
  // A backslash that does not escape a slash is kept verbatim.
  @debug.assert_eq(split_word_flags("a\\"), ("a\\", (None : String?)))
  @debug.assert_eq(split_word_flags("a\\\\b"), ("a\\\\b", (None : String?)))
}

///|
test "decode_flags implements each flag mode" {
  @debug.assert_eq(decode_flags("", @aff.SingleChar), ([] : Array[String]))
  @debug.assert_eq(decode_flags("ABC", @aff.SingleChar), ["A", "B", "C"])
  @debug.assert_eq(decode_flags("ABC", @aff.Utf8), ["A", "B", "C"])
  @debug.assert_eq(decode_flags("éü", @aff.Utf8), ["é", "ü"])
  @debug.assert_eq(decode_flags("ABC", @aff.Long), ["AB"])
  @debug.assert_eq(decode_flags("ABCD", @aff.Long), ["AB", "CD"])
  @debug.assert_eq(decode_flags("ABCDE", @aff.Long), ["AB", "CD"])
  @debug.assert_eq(decode_flags("1,2,30", @aff.Num), ["1", "2", "30"])
  @debug.assert_eq(decode_flags("1,,2,", @aff.Num), ["1", "2"])
  @debug.assert_eq(decode_flags(" 1 , 2 ", @aff.Num), ["1", "2"])
  @debug.assert_eq(decode_flags("", @aff.Num), ([] : Array[String]))
}

///|
test "preprocess trims, drops blanks and keeps source line numbers" {
  let lines = preprocess("2\r\n\r\n  hello  \r\nworld")
  @debug.assert_eq(lines.length(), 3)
  @debug.assert_eq(lines[0].number, 1)
  @debug.assert_eq(lines[0].text, "2")
  @debug.assert_eq(lines[1].number, 3)
  @debug.assert_eq(lines[1].text, "hello")
  @debug.assert_eq(lines[2].number, 4)
  @debug.assert_eq(lines[2].text, "world")
}

///|
test "split_whitespace splits on runs of Unicode whitespace" {
  @debug.assert_eq(split_whitespace("a  b\tc"), ["a", "b", "c"])
  @debug.assert_eq(split_whitespace("   "), ([] : Array[String]))
  @debug.assert_eq(split_whitespace(""), ([] : Array[String]))
  @debug.assert_eq(split_whitespace("a\u{00A0}b"), ["a", "b"])
}
