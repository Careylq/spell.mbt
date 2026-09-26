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
test "CHECKSHARPS is a modelled directive, not an unknown one" {
  let aff = @aff.parse_aff("SET UTF-8\nCHECKSHARPS\n")
  @debug.debug_inspect(aff.check_sharps, content="true")
  @debug.debug_inspect(aff.unrecognized.length(), content="0")
  // absent: off, and still nothing unknown
  let plain = @aff.parse_aff("SET UTF-8\n")
  @debug.debug_inspect(plain.check_sharps, content="false")
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

///|
test "MAP is parsed into verbatim groups" {
  let aff =
    #|SET UTF-8
    #|MAP 3
    #|MAP uü
    #|MAP oóö
    #|MAP ß(ss)
    #|TRY abc
  let parsed = @aff.parse_aff(aff)
  assert_eq(parsed.map_groups, ["uü", "oóö", "ß(ss)"])
  // a `MAP 0` table is legal and leaves the list empty
  let empty = @aff.parse_aff("MAP 0")
  assert_eq(empty.map_groups, ([] : Array[String]))
}

///|
test "PHONE is parsed into pattern/replacement rules" {
  let aff =
    #|PHONE 3
    #|PHONE C K
    #|PHONE TT- _
    #|PHONE A(HR)^ *
  let parsed = @aff.parse_aff(aff)
  assert_eq(parsed.phone_rules.length(), 3)
  assert_eq(parsed.phone_rules[0].pattern, "C")
  assert_eq(parsed.phone_rules[0].replacement, "K")
  assert_eq(parsed.phone_rules[1].pattern, "TT-")
  assert_eq(parsed.phone_rules[1].replacement, "_")
  assert_eq(parsed.phone_rules[2].pattern, "A(HR)^")
  // neither directive lands in `unrecognized` any more
  for directive in parsed.unrecognized {
    assert_false(directive.name == "MAP" || directive.name == "PHONE")
  }
}

///|
test "permit/forbid flags, word max, syllable and the small directives" {
  let text =
    #|SET UTF-8
    #|LANG tr
    #|COMPOUNDPERMITFLAG P
    #|COMPOUNDFORBIDFLAG Z
    #|COMPOUNDWORDMAX 2
    #|COMPOUNDSYLLABLE 6 aeiou
    #|FORCEUCASE F
    #|CHECKCOMPOUNDCASE
    #|CHECKCOMPOUNDREP
    #|SIMPLIFIEDTRIPLE
    #|COMPOUNDLAST L
    #|PSEUDOROOT X
  let aff = @aff.parse_aff(text)
  @debug.debug_inspect(aff.lang, content="\"tr\"")
  @debug.debug_inspect(aff.compound_permit, content="Some(\"P\")")
  @debug.debug_inspect(aff.compound_forbid, content="Some(\"Z\")")
  @debug.debug_inspect(aff.compound_word_max, content="2")
  @debug.debug_inspect(aff.compound_syllable_max, content="6")
  @debug.debug_inspect(aff.compound_syllable_vowels, content="\"aeiou\"")
  @debug.debug_inspect(aff.forceucase, content="Some(\"F\")")
  @debug.debug_inspect(aff.check_compound_case, content="true")
  @debug.debug_inspect(aff.check_compound_repeat, content="true")
  @debug.debug_inspect(aff.check_compound_simplified_triple, content="true")
  @debug.debug_inspect(aff.compound_end, content="Some(\"L\")")
  @debug.debug_inspect(aff.special_flags.needaffix, content="Some(\"X\")")
  @debug.debug_inspect(aff.unrecognized.length(), content="0")
}

///|
test "an affix rule condition may be omitted" {
  let text =
    #|SFX A N 1
    #|SFX A us orum
  let aff = @aff.parse_aff(text)
  @debug.debug_inspect(aff.affix_rules.length(), content="1")
  @debug.debug_inspect(aff.affix_rules[0].strip, content="\"us\"")
  @debug.debug_inspect(aff.affix_rules[0].add, content="\"orum\"")
  // the omitted condition defaults to `.`
  @debug.debug_inspect(aff.affix_rules[0].condition, content="\".\"")
}
