// Blackbox tests for the public `@aff.parse_aff` API.

///|
/// Run `parse_aff` and normalize its outcome so a test can assert on either
/// branch: `(-1, "no error")` on success.
fn first_error(text : String) -> (Int, String) {
  try {
    let _ = @aff.parse_aff(text)
    (-1, "no error")
  } catch {
    @aff.AffParseError(line~, message~) => (line, message)
  }
}

///|
test "parse a realistic en_US-style snippet" {
  let text =
    #|SET UTF-8
    #|FLAG num
    #|AF 2
    #|AF 100
    #|AF 200
    #|AM 2
    #|AM po:noun
    #|AM is:plural
    #|PFX 1 Y 1
    #|PFX 1 0 re .
    #|SFX 2 N 2
    #|SFX 2 0 ing [^e] is:plural
    #|SFX 2 0 ed .
    #|REP 2
    #|REP f ph
    #|REP shun tion
    #|TRY esiarntolcdugmphbyfvkwzxjq
    #|KEY qwertyuiop|asdfghjkl|zxcvbnm
    #|NOSUGGEST 100
    #|COMPOUNDMIN 1
    #|FOOBAR alpha beta
  let aff = @aff.parse_aff(text)
  @debug.debug_inspect(
    aff.encoding,
    content=(
      #|"UTF-8"
    ),
  )
  @debug.debug_inspect(aff.flag_type, content="Num")
  @debug.debug_inspect(aff.flag_aliases.length(), content="2")
  @debug.debug_inspect(
    aff.flag_aliases[0],
    content=(
      #|"100"
    ),
  )
  @debug.debug_inspect(
    aff.flag_aliases[1],
    content=(
      #|"200"
    ),
  )
  @debug.debug_inspect(
    aff.morph_aliases,
    content="[\"po:noun\", \"is:plural\"]",
  )
  @debug.debug_inspect(aff.affix_headers.length(), content="2")
  @debug.debug_inspect(aff.affix_headers[0].kind, content="Prefix")
  @debug.debug_inspect(
    aff.affix_headers[0].flag,
    content=(
      #|"100"
    ),
  )
  @debug.debug_inspect(aff.affix_headers[0].cross_product, content="true")
  @debug.debug_inspect(aff.affix_headers[0].count, content="1")
  @debug.debug_inspect(aff.affix_headers[1].kind, content="Suffix")
  @debug.debug_inspect(
    aff.affix_headers[1].flag,
    content=(
      #|"200"
    ),
  )
  @debug.debug_inspect(aff.affix_headers[1].cross_product, content="false")
  @debug.debug_inspect(aff.affix_headers[1].count, content="2")
  @debug.debug_inspect(aff.affix_rules.length(), content="3")
  @debug.debug_inspect(aff.affix_rules[0].kind, content="Prefix")
  @debug.debug_inspect(
    aff.affix_rules[0].flag,
    content=(
      #|"100"
    ),
  )
  @debug.debug_inspect(aff.affix_rules[0].cross_product, content="true")
  @debug.debug_inspect(
    aff.affix_rules[0].strip,
    content=(
      #|"0"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[0].add,
    content=(
      #|"re"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[0].condition,
    content=(
      #|"."
    ),
  )
  @debug.debug_inspect(aff.affix_rules[0].morph, content="[]")
  @debug.debug_inspect(aff.affix_rules[1].kind, content="Suffix")
  @debug.debug_inspect(
    aff.affix_rules[1].flag,
    content=(
      #|"200"
    ),
  )
  @debug.debug_inspect(aff.affix_rules[1].cross_product, content="false")
  @debug.debug_inspect(
    aff.affix_rules[1].strip,
    content=(
      #|"0"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[1].add,
    content=(
      #|"ing"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[1].condition,
    content=(
      #|"[^e]"
    ),
  )
  @debug.debug_inspect(aff.affix_rules[1].morph, content="[\"is:plural\"]")
  @debug.debug_inspect(
    aff.affix_rules[2].add,
    content=(
      #|"ed"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[2].condition,
    content=(
      #|"."
    ),
  )
  @debug.debug_inspect(aff.replacements.length(), content="2")
  @debug.debug_inspect(
    aff.replacements[0].from,
    content=(
      #|"f"
    ),
  )
  @debug.debug_inspect(
    aff.replacements[0].to,
    content=(
      #|"ph"
    ),
  )
  @debug.debug_inspect(
    aff.replacements[1].from,
    content=(
      #|"shun"
    ),
  )
  @debug.debug_inspect(
    aff.replacements[1].to,
    content=(
      #|"tion"
    ),
  )
  @debug.debug_inspect(
    aff.try_chars,
    content=(
      #|"esiarntolcdugmphbyfvkwzxjq"
    ),
  )
  @debug.debug_inspect(
    aff.keyboard,
    content=(
      #|"qwertyuiop|asdfghjkl|zxcvbnm"
    ),
  )
  @debug.debug_inspect(aff.compound_min, content="1")
  @debug.debug_inspect(aff.special_flags.nosuggest, content="Some(\"100\")")
  @debug.debug_inspect(aff.special_flags.keepcase, content="None")
  @debug.debug_inspect(aff.unrecognized.length(), content="1")
  @debug.debug_inspect(
    aff.unrecognized[0].name,
    content=(
      #|"FOOBAR"
    ),
  )
  @debug.debug_inspect(
    aff.unrecognized[0].args,
    content="[\"alpha\", \"beta\"]",
  )
  @debug.debug_inspect(aff.unrecognized[0].line, content="21")
}

///|
test "default single-character flags and Y/N cross product" {
  let text =
    #|SET UTF-8
    #|PFX A Y 1
    #|PFX A 0 un .
    #|SFX B N 1
    #|SFX B 0 s .
  let aff = @aff.parse_aff(text)
  @debug.debug_inspect(aff.flag_type, content="SingleChar")
  @debug.debug_inspect(aff.flag_aliases, content="[]")
  @debug.debug_inspect(
    aff.affix_headers[0].flag,
    content=(
      #|"A"
    ),
  )
  @debug.debug_inspect(
    aff.affix_headers[1].flag,
    content=(
      #|"B"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[0].flag,
    content=(
      #|"A"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[0].add,
    content=(
      #|"un"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[0].condition,
    content=(
      #|"."
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[1].flag,
    content=(
      #|"B"
    ),
  )
  @debug.debug_inspect(
    aff.affix_rules[1].add,
    content=(
      #|"s"
    ),
  )
}

///|
test "FLAG long and FLAG UTF-8 are recognized" {
  @debug.debug_inspect(@aff.parse_aff("FLAG long\n").flag_type, content="Long")
  @debug.debug_inspect(@aff.parse_aff("FLAG UTF-8\n").flag_type, content="Utf8")
}

///|
test "an empty file yields an empty AST" {
  let aff = @aff.parse_aff("")
  @debug.debug_inspect(
    aff.encoding,
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(aff.flag_type, content="SingleChar")
  @debug.debug_inspect(aff.affix_rules.length(), content="0")
  @debug.debug_inspect(aff.compound_min, content="0")
  @debug.debug_inspect(aff.compound_flag, content="None")
  @debug.debug_inspect(aff.unrecognized.length(), content="0")
}

///|
test "AF/AM alias 1 is the first body line and comments do not shift it" {
  let text =
    #|# an alias table
    #|AF 3
    #|AF 11
    #|# a comment inside the table is dropped by the lexer
    #|AF 22
    #|AF 33
    #|AM 1
    #|AM st:root
  let aff = @aff.parse_aff(text)
  @debug.debug_inspect(aff.flag_aliases.length(), content="3")
  @debug.debug_inspect(
    aff.flag_aliases[0],
    content=(
      #|"11"
    ),
  )
  @debug.debug_inspect(
    aff.flag_aliases[1],
    content=(
      #|"22"
    ),
  )
  @debug.debug_inspect(
    aff.flag_aliases[2],
    content=(
      #|"33"
    ),
  )
  @debug.debug_inspect(
    aff.morph_aliases[0],
    content=(
      #|"st:root"
    ),
  )
}

///|
test "cross-product suffix rules and extra compound directives" {
  let text =
    #|COMPOUNDMIN 2
    #|COMPOUNDFLAG C
    #|COMPOUNDBEGIN A
    #|COMPOUNDEND Z
    #|COMPOUNDMIDDLE M
    #|COMPOUNDRULE 1
    #|COMPOUNDRULE n*1t
    #|CHECKCOMPOUNDDUP
    #|CHECKCOMPOUNDTRIPLE
    #|CHECKCOMPOUNDREPEAT
    #|CHECKCOMPOUNDSIMPLIFIEDTRIPLE
    #|CHECKCOMPOUNDPATTERN 1
    #|CHECKCOMPOUNDPATTERN a/b
    #|ONLYINCOMPOUND X
    #|IGNORE ’
    #|WORDCHARS 0123456789
  let aff = @aff.parse_aff(text)
  @debug.debug_inspect(aff.compound_min, content="2")
  @debug.debug_inspect(aff.compound_flag, content="Some(\"C\")")
  @debug.debug_inspect(aff.compound_begin, content="Some(\"A\")")
  @debug.debug_inspect(aff.compound_end, content="Some(\"Z\")")
  @debug.debug_inspect(aff.compound_middle, content="Some(\"M\")")
  @debug.debug_inspect(aff.compound_rules, content="[\"n*1t\"]")
  @debug.debug_inspect(aff.check_compound_dup, content="true")
  @debug.debug_inspect(aff.check_compound_triple, content="true")
  @debug.debug_inspect(aff.check_compound_repeat, content="true")
  @debug.debug_inspect(aff.check_compound_simplified_triple, content="true")
  @debug.debug_inspect(aff.check_compound_pattern, content="[\"a/b\"]")
  @debug.debug_inspect(aff.special_flags.onlyincompound, content="Some(\"X\")")
  @debug.debug_inspect(
    aff.ignore_chars,
    content=(
      #|"’"
    ),
  )
  @debug.debug_inspect(
    aff.word_chars,
    content=(
      #|"0123456789"
    ),
  )
  @debug.debug_inspect(aff.unrecognized.length(), content="0")
}

///|
test "error: unparsable PFX count reports its line" {
  let text =
    #|SET UTF-8
    #|PFX A Y x
  let (line, message) = first_error(text)
  @debug.debug_inspect(line, content="2")
  @debug.debug_inspect(
    message,
    content=(
      #|"PFX: expected a count, found \"x\""
    ),
  )
}

///|
test "error: modelled directive with a missing argument reports its line" {
  let text =
    #|SET UTF-8
    #|# a comment
    #|
    #|TRY
  let (line, message) = first_error(text)
  @debug.debug_inspect(line, content="4")
  @debug.debug_inspect(
    message,
    content=(
      #|"TRY: missing argument in \"TRY\""
    ),
  )
}

///|
test "error: truncated AF table reports the header line" {
  let text =
    #|AF 2
    #|AF A
  let (line, message) = first_error(text)
  @debug.debug_inspect(line, content="1")
  @debug.debug_inspect(
    message,
    content=(
      #|"AF: declared 2 entries but only 1 line(s) follow"
    ),
  )
}

///|
test "error: a foreign line inside a block reports that line" {
  let text =
    #|PFX A Y 2
    #|PFX A 0 un .
    #|SFX B N 1
  let (line, message) = first_error(text)
  @debug.debug_inspect(line, content="3")
  @debug.debug_inspect(
    message,
    content=(
      #|"PFX: expected an entry line, found \"SFX\""
    ),
  )
}

///|
test "error: invalid cross product and unknown flag mode" {
  let (line, message) = first_error("PFX A Q 1")
  @debug.debug_inspect(line, content="1")
  @debug.debug_inspect(
    message,
    content=(
      #|"PFX: expected Y or N, found \"Q\""
    ),
  )
  let (line, message) = first_error("FLAG bogus")
  @debug.debug_inspect(line, content="1")
  @debug.debug_inspect(
    message,
    content=(
      #|"FLAG: unknown flag mode \"bogus\" (expected long, num or UTF-8)"
    ),
  )
}

///|
test "error: out-of-range AF alias in a PFX flag" {
  let text =
    #|AF 1
    #|AF A
    #|PFX 7 Y 1
    #|PFX 7 0 un .
  let (line, message) = first_error(text)
  @debug.debug_inspect(line, content="3")
  @debug.debug_inspect(
    message,
    content=(
      #|"PFX: flag alias 7 is out of range (1..1)"
    ),
  )
}
