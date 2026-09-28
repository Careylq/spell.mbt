// Blackbox tests for the public `@spell` API.
//
// The fixtures below were written for this project. They are not guaranteed to be
// free of upstream overlap, and an audit found some that is: of the 374 `#|` fixture
// lines here in total, 70 are byte-identical to a line in Hunspell's `tests/` that
// does not also appear in `hunspell(5)` — mostly single directive lines (a flag letter
// is the only free choice) and a few sample words. No corpus *file* is redistributed;
// see NOTICE, "关于测试夹具", for the method and the judgement.
// (Hunspell is tri-licensed MPL-1.1/GPL-2.0/LGPL-2.1; this project is Apache-2.0.)

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
  // compounds of three parts and more are handled by the recursive engine
  assert_true(dictionary.check("foobarfoo"))
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
test "a FORBIDDENWORD homonym leaves the root homonyms alone" {
  // The manual's "excepts with root homonyms": a spelling listed once as a root
  // and once as forbidden stays correct through the root.
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD F
  let dic =
    #|2
    #|bad/F
    #|bad
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("bad"))
}

///|
test "a FORBIDDENWORD-only spelling is rejected" {
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD F
  let dic =
    #|1
    #|bad/F
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
  // any number of separators, but never adjacent and never at an end
  assert_true(dictionary.check("1.2.3"))
  assert_true(dictionary.check("1.2.3.4"))
  assert_true(dictionary.check("2026.1.1"))
  assert_false(dictionary.check("1..2"))
  assert_false(dictionary.check("1,,2"))
  assert_false(dictionary.check("1.,2"))
  assert_false(dictionary.check("1,.2"))
  // a leading or trailing separator is not a number (`,1` cannot be rescued by
  // a break, unlike `-1`, which the default `^-` break strips)
  assert_false(dictionary.check(",1"))
  assert_false(dictionary.check("1,"))
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

///|
test "COMPLEXPREFIXES stacks two prefixes on one stem" {
  let aff =
    #|SET UTF-8
    #|COMPLEXPREFIXES
    #|PFX B Y 1
    #|PFX B 0 met/A .
    #|PFX A Y 1
    #|PFX A 0 tek .
  let dic =
    #|1
    #|root/B
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("root"))
  assert_true(dictionary.check("metroot"))
  // the inner prefix hands its continuation flag `A` to the outer prefix
  assert_true(dictionary.check("tekmetroot"))
  // `A` is not licensed on the bare stem, and `B` is not handed out by `A`
  assert_false(dictionary.check("tekroot"))
  assert_false(dictionary.check("mettekroot"))
}

///|
test "COMPLEXPREFIXES keeps a single suffix level" {
  let aff =
    #|SET UTF-8
    #|COMPLEXPREFIXES
    #|SFX A Y 1
    #|SFX A 0 x/B .
    #|SFX B Y 1
    #|SFX B 0 y .
  let dic =
    #|1
    #|root/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("rootx"))
  // twofold suffix stripping is traded away for the prefix level
  assert_false(dictionary.check("rootxy"))
}

///|
test "three-part compounds use COMPOUNDBEGIN/MIDDLE/END" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDBEGIN B
    #|COMPOUNDMIDDLE M
    #|COMPOUNDEND E
    #|COMPOUNDMIN 1
  let dic =
    #|3
    #|aa/B
    #|bb/M
    #|cc/E
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("aabbcc"))
  // `bb` is not a first part, `aa` is not a last part
  assert_false(dictionary.check("bbaacc"))
  assert_false(dictionary.check("aabb"))
}

///|
test "an interior affix in a compound needs COMPOUNDPERMITFLAG" {
  let with_permit =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|COMPOUNDPERMITFLAG P
    #|SFX S Y 1
    #|SFX S 0 suf/CP .
  let without_permit =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|SFX S Y 1
    #|SFX S 0 suf/C .
  let dic =
    #|2
    #|aa/CS
    #|bb/C
  assert_true(load(with_permit, dic).check("aasufbb"))
  assert_false(load(without_permit, dic).check("aasufbb"))
}

///|
test "COMPOUNDFORBIDFLAG forbids compounding an affixed form" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDFORBIDFLAG Z
    #|SFX S Y 1
    #|SFX S 0 suf/CZ .
  let dic =
    #|2
    #|aa/CS
    #|bb/C
  let dictionary = load(aff, dic)
  // the affixed form itself is a word ...
  assert_true(dictionary.check("aasuf"))
  // ... but it may not be a compound part
  assert_false(dictionary.check("aasufbb"))
}

///|
test "CHECKCOMPOUNDPATTERN forbids a boundary" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|CHECKCOMPOUNDPATTERN 1
    #|CHECKCOMPOUNDPATTERN b c
  let dic =
    #|3
    #|ab/C
    #|cd/C
    #|ef/C
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("abcd"))
  assert_true(dictionary.check("abef"))
}

///|
test "CHECKCOMPOUNDPATTERN allows the replacement form" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|CHECKCOMPOUNDPATTERN 1
    #|CHECKCOMPOUNDPATTERN om b Q
  let dic =
    #|2
    #|krom/C
    #|blip/C
  let dictionary = load(aff, dic)
  // krom + blip is forbidden at the `om`+`b` boundary ...
  assert_false(dictionary.check("kromblip"))
  // ... but its simplified form drops `om` and `b` and inserts `Q`
  assert_true(dictionary.check("krQlip"))
}

///|
test "CHECKCOMPOUNDPATTERN flags come from a continuation class" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDPERMITFLAG P
    #|CHECKCOMPOUNDPATTERN 1
    #|CHECKCOMPOUNDPATTERN /A /B
    #|SFX S Y 1
    #|SFX S 0 suf/CPA .
    #|SFX T Y 1
    #|SFX T 0 t/CPB .
  let dic =
    #|2
    #|aa/CS
    #|bb/CT
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("aasufbbt"))
}

///|
test "CHECKCOMPOUNDDUP forbids a repeated last part" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|CHECKCOMPOUNDDUP
  let dic =
    #|2
    #|aa/C
    #|bb/C
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("aabb"))
  assert_false(dictionary.check("aaaa"))
  assert_false(dictionary.check("aabbbb"))
}

///|
test "CHECKCOMPOUNDTRIPLE forbids three equal letters at the boundary" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|CHECKCOMPOUNDTRIPLE
  let dic =
    #|2
    #|bell/C
    #|lamp/C
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("belllamp"))
  assert_true(dictionary.check("lampbell"))
}

///|
test "SIMPLIFIEDTRIPLE accepts the two-letter form" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|CHECKCOMPOUNDTRIPLE
    #|SIMPLIFIEDTRIPLE
  let dic =
    #|2
    #|bell/C
    #|lamp/C
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("belllamp"))
  assert_true(dictionary.check("bellamp"))
}

///|
test "CHECKCOMPOUNDCASE forbids an upper-case letter at a boundary" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|CHECKCOMPOUNDCASE
  let dic =
    #|2
    #|abc/C
    #|Zap/C
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("abcZap"))
  assert_true(dictionary.check("Zapabc"))
}

///|
test "COMPOUNDWORDMAX limits the number of parts" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 1
    #|COMPOUNDWORDMAX 2
  let dic =
    #|3
    #|aa/C
    #|bb/C
    #|cc/C
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("aabb"))
  assert_false(dictionary.check("aabbcc"))
}

///|
test "COMPOUNDSYLLABLE allows more parts when the vowel count is low" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 1
    #|COMPOUNDWORDMAX 2
    #|COMPOUNDSYLLABLE 3 aeiou
  let dic =
    #|3
    #|aa/C
    #|bb/C
    #|cc/C
  let dictionary = load(aff, dic)
  // `aabbcc` has two vowels, so the word-count limit is lifted
  assert_true(dictionary.check("aabbcc"))
}

///|
test "FORCEUCASE forces a capitalised compound" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|FORCEUCASE F
  let dic =
    #|2
    #|aa/C
    #|bb/CF
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("aabb"))
  assert_true(dictionary.check("Aabb"))
  assert_true(dictionary.check("AABB"))
}

///|
test "PSEUDOROOT is the old name of NEEDAFFIX" {
  let aff =
    #|SET UTF-8
    #|PSEUDOROOT X
    #|SFX A Y 1
    #|SFX A 0 s .
  let dic =
    #|1
    #|root/XA
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("root"))
  assert_true(dictionary.check("roots"))
}

///|
test "CIRCUMFIX needs an affix of the opposite kind" {
  let aff =
    #|SET UTF-8
    #|CIRCUMFIX X
    #|PFX P Y 1
    #|PFX P 0 pre/X .
    #|SFX S Y 1
    #|SFX S 0 suf/X .
  let dic =
    #|1
    #|root/PS
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("root"))
  assert_false(dictionary.check("preroot"))
  assert_false(dictionary.check("rootsuf"))
  assert_true(dictionary.check("prerootsuf"))
}

///|
test "LANG tr uses the Turkic dotted/dotless I casing" {
  let aff =
    #|SET UTF-8
    #|LANG tr
  let dic =
    #|2
    #|iç
    #|ışık
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("iç"))
  assert_true(dictionary.check("İç"))
  assert_true(dictionary.check("ışık"))
  assert_true(dictionary.check("Işık"))
  assert_false(dictionary.check("Iç"))
  assert_false(dictionary.check("İşık"))
}

///|
test "a .dic word pair blocks the space-free compound" {
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
  let dic =
    #|3
    #|aa/C
    #|bb/C
    #|aa bb
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("aa bb"))
  assert_true(dictionary.check("bbaa"))
  assert_false(dictionary.check("aabb"))
}

///|
test "an affix rule may omit its condition" {
  let aff =
    #|SET UTF-8
    #|SFX A Y 1
    #|SFX A 0 ing
  let dic =
    #|1
    #|go/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("going"))
}

///|
test "a leading slash in a .dic entry is part of the word" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS /
    #|SFX A Y 1
    #|SFX A 0 a .
  let dic =
    #|2
    #|/aa
    #|/bb/A
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("/aa"))
  assert_true(dictionary.check("/bb"))
  assert_true(dictionary.check("/bba"))
  assert_false(dictionary.check("/aaa"))
}

///|
test "non-ASCII decimal digits count as a number word" {
  let aff =
    #|SET UTF-8
    #|WORDCHARS ۰۱۲۳
  let dic =
    #|1
    #|hello
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("۱۲"))
  assert_false(dictionary.check("۱۲a"))
}

///|
test "an affixed form of a forbidden word is forbidden" {
  let aff =
    #|SET UTF-8
    #|FORBIDDENWORD F
    #|SFX A Y 1
    #|SFX A 0 s .
  let dic =
    #|1
    #|banned/FA
  let dictionary = load(aff, dic)
  assert_false(dictionary.check("banned"))
  assert_false(dictionary.check("banneds"))
}

///|
/// `ICONV` rewrites the **input** word before any matching. The `.aff` directives that
/// configure it were parsed and wired into the lookup path, but no test exercised that
/// path — this and the two tests below are that test.
test "ICONV converts the input word before lookup" {
  // The dictionary stores the straight apostrophe; the user types the curly one.
  let d = load("SET UTF-8\nICONV 1\nICONV ’ '", "1\ndon't")
  assert_true(d.check("don't"))
  assert_true(d.check("don’t"))
  // Control: with no ICONV the very same input must be rejected, so the assertion
  // above is testing the conversion and not some other acceptance path.
  let plain = load("SET UTF-8", "1\ndon't")
  assert_false(plain.check("don’t"))
}

///|
test "ICONV applies the longest matching pattern first" {
  // `ab` must become `c` (longest wins) rather than `bb` (shortest first), so a
  // dictionary holding `b` and `c` accepts `a` and `ab` but would reject `ab` if the
  // shorter pattern were applied first.
  let d = load("SET UTF-8\nICONV 2\nICONV a b\nICONV ab c", "2\nb\nc")
  assert_true(d.check("a"))
  assert_true(d.check("ab"))
}

///|
test "ICONV honours the end-of-word marker" {
  // `ICONV x_ y` only rewrites an `x` that is the last character. So `ax` becomes `ay`
  // while `xa` keeps its `x` (and is then not a word).
  let d = load("SET UTF-8\nICONV 1\nICONV x_ y", "1\nay")
  assert_true(d.check("ax"))
  assert_false(d.check("xa"))
  assert_false(d.check("axx"))
}

///|
test "the compound part ceiling is 8, a disclosed deviation from the manual" {
  // `hunspell(5)` says an absent `COMPOUNDWORDMAX` is *unlimited*; this library stops at
  // `compound_part_ceiling()` parts instead, because the backtracking search is
  // exponential without a bound. That is recorded in README "Not implemented yet" and
  // `ACCEPTANCE.md` 7.2 -- this test pins the *documented* behaviour so that raising the
  // ceiling is a deliberate act with a measurement behind it, not a silent change.
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 1
  let dic =
    #|1
    #|a/C
  let dictionary = load(aff, dic)
  assert_true(dictionary.check("aaaaaaaa"))
  assert_false(dictionary.check("aaaaaaaaa"))
  assert_false(dictionary.check("aaaaaaaaaaaa"))
  // An explicit limit is passed through, so the directive's parameter path works.
  let limited = load(aff + "\nCOMPOUNDWORDMAX 2", dic)
  assert_false(limited.check("aaaaaaaaa"))
  let generous = load(aff + "\nCOMPOUNDWORDMAX 12", dic)
  assert_true(generous.check("aaaaaaaaaaaa"))
}

///|
test "CHECKCOMPOUNDTRIPLE is ASCII-only, like the reference implementation" {
  // `hunspell(5)` documents the reference as ASCII-only -- "Bug: missing multi-byte
  // character support in UTF-8 encoding (works only for 7-bit ASCII characters)" -- so
  // a non-ASCII triple is ACCEPTED there and must be accepted here too.
  let aff =
    #|SET UTF-8
    #|COMPOUNDFLAG C
    #|COMPOUNDMIN 2
    #|CHECKCOMPOUNDTRIPLE
  // `abb` + `bcd` meets at a triple `b`, so it is forbidden; `abc` + `def` is the
  // control that a compound with no triple is still accepted.
  let ascii = load(aff, "4\nabb/C\nbcd/C\nabc/C\ndef/C")
  assert_false(ascii.check("abbbcd"))
  assert_true(ascii.check("abcdef"))
  // The same shape with `é` instead of `b`: the reference accepts it because its check
  // is ASCII-only, so this library accepts it too.
  let utf8 = load(aff, "2\nabéé/C\nécd/C")
  assert_true(utf8.check("abééécd"))
}
