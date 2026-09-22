// Blackbox tests for the public `@dic.parse_dic` API.
//
// Every dictionary snippet here is written from scratch; no test data from the
// Hunspell repository is copied.

///|
/// Run `parse_dic` and normalize its outcome so a test can assert on either
/// branch: `(-1, "no error")` on success.
fn first_error(text : String, flag_type : @aff.FlagType) -> (Int, String) {
  try {
    let _ = @dic.parse_dic(text, flag_type)
    (-1, "no error")
  } catch {
    @dic.DicParseError(line~, message~) => (line, message)
  }
}

///|
test "count line and one entry per non-empty line" {
  let text =
    #|2
    #|hello
    #|world/A
  let dic = @dic.parse_dic(text, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 2)
  @debug.assert_eq(dic.entries.length(), 2)
  @debug.assert_eq(dic.entries[0].word, "hello")
  @debug.assert_eq(dic.entries[0].flags, ([] : Array[String]))
  @debug.assert_eq(dic.entries[0].morph, ([] : Array[String]))
  @debug.assert_eq(dic.entries[1].word, "world")
  @debug.assert_eq(dic.entries[1].flags, ["A"])
}

///|
test "text after the count on the same line is ignored" {
  let text =
    #|3 # Old Persian numbers, source: Wikipedia
    #|cat
    #|dog
    #|bird
  let dic = @dic.parse_dic(text, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 3)
  @debug.assert_eq(dic.entries.length(), 3)
  @debug.assert_eq(dic.entries[0].word, "cat")
}

///|
test "single-character flags split one flag per Unicode scalar value" {
  let text =
    #|3
    #|cat/ABC
    #|dog/AB
    #|bird
  let dic = @dic.parse_dic(text, @aff.SingleChar)
  @debug.assert_eq(dic.entries[0].flags, ["A", "B", "C"])
  @debug.assert_eq(dic.entries[1].flags, ["A", "B"])
  @debug.assert_eq(dic.entries[2].flags, ([] : Array[String]))
}

///|
test "FLAG UTF-8 flags are decoded per Unicode character" {
  let text =
    #|2
    #|café/éü
    #|naïve/ï
  let dic = @dic.parse_dic(text, @aff.Utf8)
  @debug.assert_eq(dic.entries[0].word, "café")
  @debug.assert_eq(dic.entries[0].flags, ["é", "ü"])
  @debug.assert_eq(dic.entries[1].flags, ["ï"])
}

///|
test "FLAG long flags are two characters each" {
  let text =
    #|2
    #|cat/ABCD
    #|dog/ABC
  let dic = @dic.parse_dic(text, @aff.Long)
  @debug.assert_eq(dic.entries[0].flags, ["AB", "CD"])
  // A trailing odd character cannot form a flag and is ignored.
  @debug.assert_eq(dic.entries[1].flags, ["AB"])
}

///|
test "FLAG num flags are comma-separated decimal numbers" {
  let text =
    #|3
    #|cat/1,2,30
    #|dog/7
    #|bird/1,,2,
  let dic = @dic.parse_dic(text, @aff.Num)
  @debug.assert_eq(dic.entries[0].flags, ["1", "2", "30"])
  @debug.assert_eq(dic.entries[1].flags, ["7"])
  // Empty fields between commas carry no flag.
  @debug.assert_eq(dic.entries[2].flags, ["1", "2"])
}

///|
test "morphological fields follow the word and its flags" {
  let text =
    #|2
    #|run/A po:verb is:present
    #|walk po:noun
  let dic = @dic.parse_dic(text, @aff.SingleChar)
  @debug.assert_eq(dic.entries[0].word, "run")
  @debug.assert_eq(dic.entries[0].flags, ["A"])
  @debug.assert_eq(dic.entries[0].morph, ["po:verb", "is:present"])
  @debug.assert_eq(dic.entries[1].word, "walk")
  @debug.assert_eq(dic.entries[1].flags, ([] : Array[String]))
  @debug.assert_eq(dic.entries[1].morph, ["po:noun"])
}

///|
test "a literal slash in a word is written `\\/`" {
  let text =
    #|4
    #|a\/b/A
    #|x\/y
    #|z\/\/w
    #|\/root/A
  let dic = @dic.parse_dic(text, @aff.SingleChar)
  @debug.assert_eq(dic.entries[0].word, "a/b")
  @debug.assert_eq(dic.entries[0].flags, ["A"])
  @debug.assert_eq(dic.entries[1].word, "x/y")
  @debug.assert_eq(dic.entries[1].flags, ([] : Array[String]))
  @debug.assert_eq(dic.entries[2].word, "z//w")
  @debug.assert_eq(dic.entries[3].word, "/root")
  @debug.assert_eq(dic.entries[3].flags, ["A"])
}

///|
test "the declared count is stored but never enforced" {
  let too_few =
    #|5
    #|a
    #|b
  let dic = @dic.parse_dic(too_few, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 5)
  @debug.assert_eq(dic.entries.length(), 2)
  let too_many =
    #|1
    #|a
    #|b
    #|c
  let dic = @dic.parse_dic(too_many, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 1)
  @debug.assert_eq(dic.entries.length(), 3)
}

///|
test "blank lines are ignored and CRLF/CR line endings are accepted" {
  let crlf = "2\r\n\r\nhello\r\nworld/A\r\n"
  let dic = @dic.parse_dic(crlf, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 2)
  @debug.assert_eq(dic.entries.length(), 2)
  @debug.assert_eq(dic.entries[1].word, "world")
  let cr = "1\rhello\r"
  let dic = @dic.parse_dic(cr, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 1)
  @debug.assert_eq(dic.entries.length(), 1)
  @debug.assert_eq(dic.entries[0].word, "hello")
}

///|
test "surrounding whitespace and tabs are trimmed" {
  let text = "  2  \n\thello\t\n  world/A  \n"
  let dic = @dic.parse_dic(text, @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 2)
  @debug.assert_eq(dic.entries[0].word, "hello")
  @debug.assert_eq(dic.entries[1].word, "world")
  @debug.assert_eq(dic.entries[1].flags, ["A"])
}

///|
test "a zero count yields no entries" {
  let dic = @dic.parse_dic("0\n", @aff.SingleChar)
  @debug.assert_eq(dic.declared_count, 0)
  @debug.assert_eq(dic.entries.length(), 0)
}

///|
test "`#` is ordinary data in a .dic entry" {
  let dic = @dic.parse_dic("1\n#hash/A\n", @aff.SingleChar)
  @debug.assert_eq(dic.entries[0].word, "#hash")
  @debug.assert_eq(dic.entries[0].flags, ["A"])
}

///|
test "error: an empty file has no count line" {
  let (line, message) = first_error("", @aff.SingleChar)
  @debug.assert_eq(line, 1)
  @debug.assert_eq(message, "missing entry count line")
}

///|
test "error: a non-numeric count line reports its line" {
  let text =
    #|SET this is not a count
    #|hello
  let (line, message) = first_error(text, @aff.SingleChar)
  @debug.assert_eq(line, 1)
  @debug.assert_eq(
    message, "expected an entry count, found \"SET this is not a count\"",
  )
}

///|
test "error: a negative count line reports its line" {
  let text =
    #|
    #|-3
  let (line, message) = first_error(text, @aff.SingleChar)
  @debug.assert_eq(line, 2)
  @debug.assert_eq(message, "entry count must not be negative, found \"-3\"")
}
