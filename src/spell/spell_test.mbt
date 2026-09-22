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
test "affix continuation flags chain a second affix" {
  // `SFX A 0 s/123 .` adds `s` and gives the derived form the flags 1, 2 and 3,
  // so a rule signed with one of those flags can be attached to it.
  let aff =
    #|SET UTF-8
    #|SFX A Y 1
    #|SFX A 0 s/123 .
    #|SFX 1 Y 1
    #|SFX 1 0 bar .
    #|SFX 2 Y 1
    #|SFX 2 0 baz .
    #|PFX 3 Y 1
    #|PFX 3 0 un .
  let dic =
    #|1
    #|foo/A3
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo"))
  assert_true(dictionary.check("foos"))
  // the continuation flags of A license a second suffix on `foos`
  assert_true(dictionary.check("foosbar"))
  assert_true(dictionary.check("foosbaz"))
  // ...and the prefix `un-`, which is signed with flag 3
  assert_true(dictionary.check("unfoo"))
  assert_true(dictionary.check("unfoos"))
  // a prefix plus two suffixes
  assert_true(dictionary.check("unfoosbar"))
  assert_true(dictionary.check("unfoosbaz"))
  // `add` is still read as `s`, not `s/123`
  assert_false(dictionary.check("foos/123"))
}

///|
test "continuation flags cannot chain a third suffix" {
  let aff =
    #|SET UTF-8
    #|SFX A Y 1
    #|SFX A 0 s/AB .
    #|SFX B Y 1
    #|SFX B 0 y/B .
  let dic =
    #|1
    #|foo/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foos"))
  assert_true(dictionary.check("foosy"))
  // three suffixes deep is past the twofold limit
  assert_false(dictionary.check("foosyy"))
}

///|
test "a leading UTF-8 BOM is ignored" {
  let aff = "\u{FEFF}SET UTF-8"
  let dic = "\u{FEFF}1\ncat"
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("cat"))
}

///|
test "IGNORE characters are dropped from entries, affixes and checked words" {
  // `IGNORE` lists characters Hunspell treats as invisible. They are removed
  // from `.dic` entries, from a rule's `strip`/`add` text and from the word
  // being checked, so a dictionary written without the ignored characters still
  // accepts them.
  let aff =
    #|SET UTF-8
    #|IGNORE aeiou
    #|PFX P Y 1
    #|PFX P 0 pre .
  let dic =
    #|2
    #|cnsnnt/P
    #|rhythm
  let dictionary = load(aff, dic)
  // the entry without its ignored vowels
  assert_true(dictionary.check("cnsnnt"))
  assert_true(dictionary.check("consonant"))
  // an entry with no ignored characters is unaffected
  assert_true(dictionary.check("rhythm"))
  // the prefix rule's `add` text is cleaned as well (`pre` -> `pr`), so the
  // spelled-out and the reduced spellings of the same word both match
  assert_true(dictionary.check("preconsonant"))
  assert_true(dictionary.check("prcnsnnt"))
  // characters that are not listed still have to match
  assert_false(dictionary.check("postconsonant"))
  assert_false(dictionary.check("consonants"))
  assert_false(dictionary.check("consonantx"))
  assert_eq(dictionary.entry_count(), 2)
}

///|
test "an IGNORE-only word is never correct" {
  // Removing the ignored characters can leave an empty string; that must not be
  // accepted just because it matched nothing.
  let aff =
    #|SET UTF-8
    #|IGNORE xy
  let dic =
    #|1
    #|cat
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("cat"))
  assert_false(dictionary.check("xy"))
  assert_false(dictionary.check("x"))
}

///|
test "CHECKSHARPS lets SS spell a dictionary sharp s in an uppercased word" {
  let aff =
    #|SET UTF-8
    #|CHECKSHARPS
    #|KEEPCASE k
  let dic =
    #|3
    #|Straße
    #|Fußweg
    #|müßig/k
  let dictionary = load(aff, dic)
  // exact forms still work
  assert_true(dictionary.check("Straße"))
  assert_true(dictionary.check("Fußweg"))
  // uppercased: `ß` is spelled `SS`
  assert_true(dictionary.check("STRASSE"))
  assert_true(dictionary.check("FUSSWEG"))
  // a capital sharp s (`ẞ`, U+1E9E) folds to `ß`, so it works in `ALL CAPS`
  assert_true(dictionary.check("STRAẞE"))
  // `CHECKSHARPS` also lets a `KEEPCASE` word with `ß` be capitalised and
  // uppercased, as long as the uppercased form uses `SS`
  assert_true(dictionary.check("müßig"))
  assert_true(dictionary.check("Müßig"))
  assert_true(dictionary.check("MÜSSIG"))
  // ...but an uppercased word of a `KEEPCASE` entry may not keep a sharp s
  assert_false(dictionary.check("MÜßIG"))
  // and `ss` in a merely capitalised word is still not a sharp s
  assert_false(dictionary.check("Müssig"))
  assert_false(dictionary.check("Strassse"))
}

///|
test "without CHECKSHARPS a sharp s is not spelled SS" {
  let aff =
    #|SET UTF-8
    #|KEEPCASE k
  let dic =
    #|2
    #|Straße
    #|müßig/k
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("Straße"))
  assert_false(dictionary.check("STRASSE"))
  assert_false(dictionary.check("MÜSSIG"))
  // `KEEPCASE` still blocks the capitalised form
  assert_false(dictionary.check("Müßig"))
  // the exact `KEEPCASE` form is correct
  assert_true(dictionary.check("müßig"))
}

///|
test "COMPOUNDRULE patterns use *, ? and literal flags" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDMIN 1
    #|COMPOUNDRULE 1
    #|COMPOUNDRULE A*B?C
  let dic =
    #|3
    #|a/A
    #|b/B
    #|c/C
  let dictionary = load(aff, dic)
  // `A*` is zero or more parts, `B?` is zero or one, `C` is exactly one
  assert_true(dictionary.check("ac"))
  assert_true(dictionary.check("aac"))
  assert_true(dictionary.check("abc"))
  assert_true(dictionary.check("aabc"))
  assert_true(dictionary.check("bc"))
  // every part has to be consumed, in pattern order
  assert_false(dictionary.check("ab"))
  assert_false(dictionary.check("ca"))
  assert_false(dictionary.check("acc"))
  assert_false(dictionary.check("abbc"))
  assert_false(dictionary.check("acb"))
}

///|
test "COMPOUNDRULE parenthesized atoms for FLAG long" {
  let aff =
    #|SET UTF-8
    #|FLAG long
    #|COMPOUNDMIN 1
    #|COMPOUNDRULE 1
    #|COMPOUNDRULE (nn)*(tt)?(pp)
  let dic =
    #|4
    #|n/nn
    #|x/nn
    #|t/tt
    #|p/pp
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("ntp"))
  assert_true(dictionary.check("nxp"))
  assert_true(dictionary.check("np"))
  assert_true(dictionary.check("tp"))
  assert_false(dictionary.check("tnp"))
  assert_false(dictionary.check("nt"))
  assert_false(dictionary.check("ntpp"))
}

///|
test "COMPOUNDRULE parts respect ONLYINCOMPOUND and FORBIDDENWORD" {
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD F
    #|ONLYINCOMPOUND O
    #|COMPOUNDMIN 1
    #|COMPOUNDRULE 1
    #|COMPOUNDRULE A*B
  let dic =
    #|4
    #|a/A
    #|b/BO
    #|ab/F
    #|bob
  let dictionary = load(aff, dic)
  // a part flagged ONLYINCOMPOUND is usable inside a compound...
  assert_true(dictionary.check("aab"))
  // ...but not on its own
  assert_false(dictionary.check("b"))
  assert_true(dictionary.check("bob"))
  // a FORBIDDENWORD entry is subtracted even though the pattern would match
  assert_false(dictionary.check("ab"))
}

///|
test "AF aliases expand to flag vectors, including in continuation flags" {
  // `AF PQ` is two flags, and `SFX Q 0 er/2 .` names alias 2 (flag `P`) as the
  // continuation flag of the derived form.
  let aff =
    #|SET UTF-8
    #|AF 2
    #|AF PQ
    #|AF P
    #|SFX P Y 1
    #|SFX P 0 ing .
    #|SFX Q Y 1
    #|SFX Q 0 er/2 .
  let dic =
    #|1
    #|walk/1
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("walk"))
  assert_true(dictionary.check("walking"))
  assert_true(dictionary.check("walker"))
  assert_true(dictionary.check("walkering"))
  assert_false(dictionary.check("walkerings"))
}

///|
test "homonym entries are alternatives, not a union of flags" {
  // `work` occurs twice: once as a virtual stem (`NEEDAFFIX`) and once as a
  // plain word. The plain homonym makes `work` correct; `note` only occurs with
  // `NEEDAFFIX`, so it stays a virtual stem.
  let aff =
    #|SET UTF-8
    #|NEEDAFFIX X
    #|SFX S Y 1
    #|SFX S 0 s .
  let dic =
    #|3
    #|work/X
    #|work
    #|note/XS
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("work"))
  assert_false(dictionary.check("note"))
  assert_true(dictionary.check("notes"))
  assert_eq(dictionary.entry_count(), 2)
}

///|
test "a FORBIDDENWORD homonym forbids the whole word" {
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD F
  let dic =
    #|2
    #|bad/F
    #|bad
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("bad"))
}

///|
test "NEEDAFFIX on an affix makes the derived form a virtual stem" {
  // `SFX A 0 s/XB .` hands the derived form both `B` and `NEEDAFFIX` (`X`), so
  // `foos` is not a word on its own but `foosbar` is.
  let aff =
    #|SET UTF-8
    #|NEEDAFFIX X
    #|SFX A Y 1
    #|SFX A 0 s/XB .
    #|SFX B Y 1
    #|SFX B 0 bar .
  let dic =
    #|1
    #|foo/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo"))
  assert_false(dictionary.check("foos"))
  assert_true(dictionary.check("foosbar"))
}

///|
test "ONLYINCOMPOUND on an affix keeps the derived form out of standalone use" {
  let aff =
    #|SET UTF-8
    #|ONLYINCOMPOUND X
    #|SFX A Y 1
    #|SFX A 0 s/X .
  let dic =
    #|1
    #|foo/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo"))
  assert_false(dictionary.check("foos"))
}

///|
test "numbers with separators are accepted when the separators sit between digits" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS 0123456789.-,
  let dic =
    #|1
    #|foo
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("1"))
  assert_true(dictionary.check("1234567"))
  assert_true(dictionary.check("1.1"))
  assert_true(dictionary.check("1234567.123456"))
  assert_true(dictionary.check("4,2"))
  assert_true(dictionary.check("42-42"))
  // at most one separator, and never adjacent or at an end
  assert_false(dictionary.check("1..2"))
  assert_false(dictionary.check("1,,2"))
  assert_false(dictionary.check("1.,2"))
  assert_false(dictionary.check("1,.2"))
  // a leading or trailing separator is not a number (`,1` cannot be rescued by
  // a break, unlike `-1`, which the default `^-` break strips)
  assert_false(dictionary.check(",1"))
  assert_false(dictionary.check("1,"))
  assert_false(dictionary.check("1.2.3"))
  assert_false(dictionary.check("1a"))
  assert_true(dictionary.check("foo"))
}

///|
test "numbers are only recognised where WORDCHARS declares the separator" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS .
    #|BREAK 0
  let dic =
    #|1
    #|foo
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("1"))
  assert_true(dictionary.check("1.5"))
  // `,` and `-` are not declared among the word characters
  assert_false(dictionary.check("1,5"))
  assert_false(dictionary.check("1-5"))
}

///|
test "a line of whitespace-separated correct words is correct" {
  let aff =
    #|SET UTF-8
  let dic =
    #|3
    #|drink
    #|eat
    #|able
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("drink eat"))
  assert_true(dictionary.check("drink   eat\table"))
  assert_false(dictionary.check("drink sleep"))
  assert_false(dictionary.check("drink eat sleep"))
}

///|
test "BREAK splits a word at the declared break points" {
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD !
    #|BREAK 1
    #|BREAK -
    #|WORDCHARS -
  let dic =
    #|4
    #|foo
    #|bar
    #|baz
    #|foo-bar/!
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo-bar-baz"))
  assert_true(dictionary.check("baz-foo"))
  // a FORBIDDENWORD entry still wins over the break
  assert_false(dictionary.check("foo-bar"))
  // with an explicit BREAK list the default `^-` and `-$` are gone
  assert_false(dictionary.check("-foo"))
  assert_false(dictionary.check("foo-"))
}

///|
test "the default break points are -, ^- and -$" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS -
  let dic =
    #|2
    #|foo
    #|bar
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("foo-bar"))
  assert_true(dictionary.check("foo-bar-foo-bar"))
  assert_true(dictionary.check("-foo"))
  assert_true(dictionary.check("foo-"))
  assert_false(dictionary.check("-"))
  assert_false(dictionary.check("foo-baz"))
}

///|
test "BREAK 0 switches word breaking off" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS -
    #|BREAK 0
  let dic =
    #|2
    #|foo
    #|bar
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("foo-bar"))
  assert_false(dictionary.check("-foo"))
  assert_false(dictionary.check("foo-"))
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
