// Blackbox tests for the public `@spell` API.
//
// Every fixture below is written from scratch for this project; no Hunspell test
// data is copied (Hunspell is LGPL-2.1, this project is Apache-2.0).

///|
/// Build a dictionary, turning an unexpected `SpellError` into a test failure.
fn load(
  aff : String,
  dic : String,
) -> @spell.Dictionary raise @spell.SpellError {
  @spell.Dictionary::from_text(aff, dic)
}

///|
test "direct hits and single affix rules" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|SFX S Y 2
    #|SFX S 0 s [^s]
    #|SFX S 0 es [s]
    #|PFX U Y 1
    #|PFX U 0 un .
  let dic =
    #|7
    #|cat/S
    #|dog/S
    #|do/US
    #|happy/U
    #|unhappy
    #|House
    #|iPhone
  let dictionary = load(aff, dic)
  // direct
  assert_true(dictionary.check("cat"))
  assert_true(dictionary.check("happy"))
  assert_false(dictionary.check("ca"))
  // suffixes, with the condition deciding which `add` applies
  assert_true(dictionary.check("cats"))
  assert_true(dictionary.check("dogs"))
  assert_false(dictionary.check("doges"))
  assert_false(dictionary.check("cates"))
  // prefixes
  assert_true(dictionary.check("undo"))
  assert_true(dictionary.check("unhappy"))
  assert_false(dictionary.check("undog"))
  // one prefix plus one suffix on the same cross-product stem
  assert_true(dictionary.check("undos"))
  assert_false(dictionary.check("undogs"))
}

///|
test "capitalisation rules" {
  let aff =
    #|SET UTF-8
    #|SFX S Y 1
    #|SFX S 0 s .
  let dic =
    #|5
    #|cat/S
    #|House
    #|iPhone
    #|London/S
    #|x
  let dictionary = load(aff, dic)
  // Capitalised: the word itself or its lower-case form
  assert_true(dictionary.check("Cat"))
  assert_true(dictionary.check("House"))
  assert_true(dictionary.check("Cats"))
  assert_false(dictionary.check("house"))
  // ALL CAPS: the word, its lower-case form, or its Capitalised form
  assert_true(dictionary.check("CAT"))
  assert_true(dictionary.check("HOUSE"))
  assert_true(dictionary.check("LONDON"))
  assert_true(dictionary.check("LONDONS"))
  // mixed case only ever matches exactly
  assert_true(dictionary.check("iPhone"))
  assert_false(dictionary.check("IPHONE"))
  assert_false(dictionary.check("iphone"))
  assert_false(dictionary.check("iPHONE"))
  assert_false(dictionary.check("cAt"))
  // a word with no cased letters matches exactly; a single upper-case letter
  // is ALL CAPS, so it also accepts the lower-case entry
  assert_true(dictionary.check("x"))
  assert_true(dictionary.check("X"))
  assert_false(dictionary.check("y"))
}

///|
test "strip and add are both applied in the right direction" {
  let aff =
    #|SET UTF-8
    #|SFX A Y 1
    #|SFX A y ied [^aeiou]y
  let dic =
    #|2
    #|happy/A
    #|cry/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("happy"))
  assert_true(dictionary.check("cry"))
  assert_true(dictionary.check("happied"))
  assert_true(dictionary.check("cried"))
  assert_false(dictionary.check("happyed"))
  assert_false(dictionary.check("cryed"))
}

///|
test "special flags: FORBIDDENWORD, KEEPCASE, NEEDAFFIX, ONLYINCOMPOUND" {
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD F
    #|KEEPCASE K
    #|NEEDAFFIX N
    #|ONLYINCOMPOUND O
    #|SFX S Y 1
    #|SFX S 0 s [^s]
  let dic =
    #|5
    #|bad/F
    #|iPhone/K
    #|need/NS
    #|part/O
    #|word
  let dictionary = load(aff, dic)
  // FORBIDDENWORD rejects the entry and its derivations
  assert_false(dictionary.check("bad"))
  assert_false(dictionary.check("bads"))
  // KEEPCASE only matches the exact case
  assert_true(dictionary.check("iPhone"))
  assert_false(dictionary.check("IPHONE"))
  assert_false(dictionary.check("iphone"))
  // NEEDAFFIX rejects the bare stem but accepts the derived form
  assert_false(dictionary.check("need"))
  assert_true(dictionary.check("needs"))
  // ONLYINCOMPOUND rejects the standalone word
  assert_false(dictionary.check("part"))
  assert_true(dictionary.check("word"))
}

///|
test "two-part compounds with COMPOUNDFLAG and COMPOUNDMIN" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
  let dic =
    #|4
    #|foo/C
    #|bar/C
    #|ab/C
    #|cd/C
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo"))
  assert_true(dictionary.check("foobar"))
  assert_true(dictionary.check("abcd"))
  assert_false(dictionary.check("foobaz"))
  assert_false(dictionary.check("f"))
  // only the simple two-part case is implemented
  assert_false(dictionary.check("foobarfoo"))
}

///|
test "COMPOUNDMIN defaults to 3 when the .aff does not declare it" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
  let dic =
    #|2
    #|ab/C
    #|cd/C
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("abcd"))
}

///|
test "AF aliases resolve in both the .aff rules and the .dic flags" {
  let aff =
    #|SET UTF-8
    #|FLAG num
    #|AF 2
    #|AF S
    #|AF U
    #|SFX 1 Y 1
    #|SFX 1 0 s .
    #|PFX 2 Y 1
    #|PFX 2 0 un .
  let dic =
    #|1
    #|cat/1,2
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("cat"))
  assert_true(dictionary.check("cats"))
  assert_true(dictionary.check("uncat"))
  assert_true(dictionary.check("uncats"))
}

///|
test "duplicate .dic entries merge their flags" {
  let aff =
    #|SET UTF-8
    #|SFX S Y 1
    #|SFX S 0 s .
    #|PFX U Y 1
    #|PFX U 0 un .
  let dic =
    #|3
    #|cat/S
    #|cat/U
    #|cat
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("cats"))
  assert_true(dictionary.check("uncat"))
  assert_true(dictionary.check("cat"))
  assert_eq(dictionary.entry_count(), 1)
}

///|
test "accessors report the loaded .aff metadata" {
  let aff =
    #|SET UTF-8
    #|FLAG long
    #|SFX AB Y 1
    #|SFX AB 0 s .
  let dic =
    #|1
    #|cat/AB
  let dictionary = load(aff, dic)
  assert_eq(dictionary.encoding(), "UTF-8")
  assert_eq(dictionary.flag_type(), @aff.Long)
  @debug.debug_inspect(dictionary.flag_type(), content="Long")
  assert_eq(dictionary.rule_count(), 1)
  assert_eq(dictionary.entry_count(), 1)
  assert_true(dictionary.check("cats"))
}

///|
test "malformed input surfaces the failing parser" {
  let aff_error : String = try {
    let _ = @spell.Dictionary::from_text("PFX 1 Y nope", "1\nx")
    "no error"
  } catch {
    @spell.SpellError::AffParse(_) => "aff"
    @spell.SpellError::DicParse(_) => "dic"
  }
  assert_eq(aff_error, "aff")
  let dic_error : String = try {
    let _ = @spell.Dictionary::from_text("SET UTF-8", "not a count")
    "no error"
  } catch {
    @spell.SpellError::AffParse(_) => "aff"
    @spell.SpellError::DicParse(_) => "dic"
  }
  assert_eq(dic_error, "dic")
}

///|
test "SpellError renders with the file kind and line number" {
  let rendered : String = try {
    let _ = @spell.Dictionary::from_text("SET UTF-8", "not a count")
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_true(rendered.contains(".dic: line 1"))
}

///|
test "the empty word is never correct" {
  let aff =
    #|SET UTF-8
  let dic =
    #|1
    #|cat
  let dictionary = load(aff, dic)
  assert_false(dictionary.check(""))
}

///|
test "a trailing dot is accepted when WORDCHARS declares it" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS .'
  let dic =
    #|4
    #|etc
    #|Text
    #|NASA
    #|Hunspell
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("etc."))
  assert_true(dictionary.check("HUNSPELL..."))
  assert_true(dictionary.check("Text."))
  assert_true(dictionary.check("NASA."))
  assert_true(dictionary.check("TEXT."))
  assert_false(dictionary.check("nope."))
}

///|
test "a trailing dot is not special without WORDCHARS" {
  let aff =
    #|SET UTF-8
  let dic =
    #|1
    #|etc
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("etc"))
  assert_false(dictionary.check("etc."))
}

///|
test "affix continuation flags are cut off the add field" {
  // `SFX A 0 s/123 .` adds `s` and gives the result flags 1, 2 and 3. Chaining a
  // second affix through those flags is not implemented, but the first affix has
  // to work, which means `add` must be read as `s`, not `s/123`.
  let aff =
    #|SET UTF-8
    #|SFX A Y 1
    #|SFX A 0 s/123 .
    #|SFX 1 Y 1
    #|SFX 1 0 bar .
  let dic =
    #|1
    #|foo/A3
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo"))
  assert_true(dictionary.check("foos"))
  // the chained form is the documented limitation
  assert_false(dictionary.check("foosbar"))
}

///|
test "a leading UTF-8 BOM is ignored" {
  let aff = "\u{FEFF}SET UTF-8"
  let dic = "\u{FEFF}1\ncat"
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("cat"))
}

///|
test "text after the .dic count on the same line is ignored" {
  let aff =
    #|SET UTF-8
  let dic =
    #|2 # two entries, source: example
    #|cat
    #|dog
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("cat"))
  assert_true(dictionary.check("dog"))
  assert_eq(dictionary.entry_count(), 2)
}
