// Whitebox tests for the line-level lexer internals.
//
// These exercise `lex_aff`, `strip_line` and `tokenize` directly, including the
// line numbers and token arrays that the parser relies on.

///|
test "blank and comment lines are dropped but line numbers are kept" {
  let text =
    #|SET UTF-8
    #|
    #|# a full-line comment
    #|   # an indented comment
    #|TRY abc
  let lines = lex_aff(text)
  @debug.debug_inspect(lines.length(), content="2")
  @debug.debug_inspect(lines[0].number, content="1")
  @debug.debug_inspect(
    lines[0].text,
    content=(
      #|"SET UTF-8"
    ),
  )
  @debug.debug_inspect(lines[0].tokens, content="[\"SET\", \"UTF-8\"]")
  @debug.debug_inspect(lines[1].number, content="5")
  @debug.debug_inspect(lines[1].tokens, content="[\"TRY\", \"abc\"]")
}

///|
test "CRLF line endings get correct line numbers and tokens" {
  let lines = lex_aff("SET UTF-8\r\nTRY abc\r\nREP f ph\r\n")
  @debug.debug_inspect(lines.length(), content="3")
  @debug.debug_inspect(lines[0].number, content="1")
  @debug.debug_inspect(lines[0].tokens, content="[\"SET\", \"UTF-8\"]")
  @debug.debug_inspect(lines[1].number, content="2")
  @debug.debug_inspect(lines[1].tokens, content="[\"TRY\", \"abc\"]")
  @debug.debug_inspect(lines[2].number, content="3")
  @debug.debug_inspect(lines[2].tokens, content="[\"REP\", \"f\", \"ph\"]")
}

///|
test "lone CR line endings also split lines" {
  let lines = lex_aff("SET UTF-8\rTRY abc")
  @debug.debug_inspect(lines.length(), content="2")
  @debug.debug_inspect(lines[0].tokens, content="[\"SET\", \"UTF-8\"]")
  @debug.debug_inspect(lines[1].number, content="2")
  @debug.debug_inspect(lines[1].tokens, content="[\"TRY\", \"abc\"]")
}

///|
test "trailing whitespace and tabs are trimmed away" {
  let lines = lex_aff("TRY abc   \n\tSET\tUTF-8\t \n")
  @debug.debug_inspect(lines.length(), content="2")
  @debug.debug_inspect(
    lines[0].text,
    content=(
      #|"TRY abc"
    ),
  )
  @debug.debug_inspect(lines[0].tokens, content="[\"TRY\", \"abc\"]")
  @debug.debug_inspect(lines[1].tokens, content="[\"SET\", \"UTF-8\"]")
}

///|
test "a trailing newline does not create a line" {
  let lines = lex_aff("SET UTF-8\n")
  @debug.debug_inspect(lines.length(), content="1")
}

///|
test "an empty string has no lines" {
  let lines = lex_aff("")
  @debug.debug_inspect(lines.length(), content="0")
}

///|
test "mid-line hash is preserved (documented limitation)" {
  let lines = lex_aff("REP a #b\n")
  @debug.debug_inspect(lines.length(), content="1")
  @debug.debug_inspect(lines[0].tokens, content="[\"REP\", \"a\", \"#b\"]")
}

///|
test "tokenize splits on runs of whitespace" {
  @debug.debug_inspect(tokenize("a  b\tc"), content="[\"a\", \"b\", \"c\"]")
  @debug.debug_inspect(tokenize("   "), content="[]")
  @debug.debug_inspect(tokenize(""), content="[]")
}

///|
test "strip_line drops comments and keeps data" {
  @debug.debug_inspect(
    strip_line("   # comment"),
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(
    strip_line("  REP f ph  "),
    content=(
      #|"REP f ph"
    ),
  )
  @debug.debug_inspect(
    strip_line(""),
    content=(
      #|""
    ),
  )
}

///|
test "AF alias index 1 is the first body line even with comments interleaved" {
  let text =
    #|AF 2
    #|AF 11
    #|# comment between entries
    #|AF 22
  let lines = lex_aff(text)
  // The parser reads `lines[0].tokens[1]` as the count and then the next two
  // logical lines as aliases, so the comment must not occupy a slot.
  @debug.debug_inspect(lines.length(), content="3")
  @debug.debug_inspect(lines[0].tokens, content="[\"AF\", \"2\"]")
  @debug.debug_inspect(lines[1].tokens, content="[\"AF\", \"11\"]")
  @debug.debug_inspect(lines[2].number, content="4")
  @debug.debug_inspect(lines[2].tokens, content="[\"AF\", \"22\"]")
}
