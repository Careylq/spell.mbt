// Blackbox tests for the public `@suggest` API.
//
// Every fixture below is written from scratch for this project; no Hunspell
// test data is copied (Hunspell is LGPL-2.1, this project is Apache-2.0).

///|
/// Build a dictionary, turning an unexpected `SpellError` into a test failure.
fn load(
  aff : String,
  dic : String,
) -> @spell.Dictionary raise @spell.SpellError {
  @spell.Dictionary::from_text(aff, dic)
}

///|
test "a correct word needs no correction" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
  let dic =
    #|2
    #|hello
    #|world
  let dictionary = load(aff, dic)
  assert_eq(@suggest.suggest(dictionary, "hello", 5), [])
  assert_eq(@suggest.suggest(dictionary, "world", 5), [])
  // the empty word has no suggestions either
  assert_eq(@suggest.suggest(dictionary, "", 5), [])
  // a non-positive limit asks for nothing
  assert_eq(@suggest.suggest(dictionary, "helo", 0), [])
}

///|
test "REP replacements are generated and ranked first" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|REP 2
    #|REP ph f
    #|REP alot a_lot
  let dic =
    #|5
    #|form
    #|phantom
    #|a
    #|lot
    #|hello
  let dictionary = load(aff, dic)
  // `ph` -> `f`: the `phorm` -> `form` correction.
  assert_eq(@suggest.suggest(dictionary, "phorm", 5), ["form"])
  // `REP alot a_lot` writes the space form directly, and a `REP` hit outranks
  // the plain "delete the a" candidate `lot`.
  assert_eq(@suggest.suggest(dictionary, "alot", 5), ["a lot", "lot"])
}

///|
test "edit distance one, one kind at a time" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
  let dic =
    #|6
    #|hello
    #|world
    #|cat
    #|dog
    #|help
    #|wolf
  let dictionary = load(aff, dic)
  let contains = fn(haystack : Array[String], needle : String) -> Bool {
    haystack.contains(needle)
  }
  // insertion (`helo` -> `hello`) and transposition (`hlelo` -> `hello`)
  assert_true(contains(@suggest.suggest(dictionary, "helo", 10), "hello"))
  assert_true(contains(@suggest.suggest(dictionary, "hlelo", 10), "hello"))
  // transposition (`wrold` -> `world`) and (`cta` -> `cat`)
  assert_true(contains(@suggest.suggest(dictionary, "wrold", 10), "world"))
  assert_true(contains(@suggest.suggest(dictionary, "cta", 10), "cat"))
  // replacement (`cet` -> `cat`) and deletion (`wolfs` -> `wolf`)
  assert_true(contains(@suggest.suggest(dictionary, "cet", 10), "cat"))
  assert_true(contains(@suggest.suggest(dictionary, "wolfs", 10), "wolf"))
}

///|
test "case variations cover lower, Capitalised and ALL CAPS" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|KEEPCASE K
  let dic =
    #|3
    #|foo/K
    #|Bar
    #|NASA
  let dictionary = load(aff, dic)
  // `foo` is KEEPCASE, so `Foo` must be corrected back to the entry's case
  assert_eq(@suggest.suggest(dictionary, "Foo", 5), ["foo"])
  assert_eq(@suggest.suggest(dictionary, "FOO", 5), ["foo"])
  // a Capitalised entry is reachable from its lower-case spelling (`BAR` is
  // accepted too, because `check` folds ALL CAPS, so assert containment)
  let bar = @suggest.suggest(dictionary, "bar", 5)
  assert_true(bar.contains("Bar"))
  // and an ALL CAPS entry from its lower-case spelling
  assert_eq(@suggest.suggest(dictionary, "nasa", 5), ["NASA"])
}

///|
test "splitting into two words, with and without a hyphen" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz-
  let dic =
    #|5
    #|rotten
    #|day
    #|a
    #|lot
    #|scot-free
  let dictionary = load(aff, dic)
  let both = @suggest.suggest(dictionary, "rottenday", 10)
  assert_true(both.contains("rotten day"))
  assert_true(both.contains("rotten-day"))
  // the hyphen form is only offered when the alphabet declares `-`
  let aff_no_dash =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
  let dic_no_dash =
    #|2
    #|rotten
    #|day
  let no_dash = load(aff_no_dash, dic_no_dash)
  let spaced = @suggest.suggest(no_dash, "rottenday", 10)
  assert_true(spaced.contains("rotten day"))
  assert_false(spaced.contains("rotten-day"))
}

///|
test "a NOSUGGEST entry is never offered" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|NOSUGGEST N
  let dic =
    #|3
    #|secret/N
    #|public
    #|hello
  let dictionary = load(aff, dic)
  let suggestions = @suggest.suggest(dictionary, "secet", 10)
  assert_false(suggestions.contains("secret"))
}

///|
test "possessive casing and the CHECKSHARPS sharp s" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|CHECKSHARPS
    #|WORDCHARS ß.
    #|SFX S Y 1
    #|SFX S 0 's .
  let dic =
    #|3
    #|UNICEF/S
    #|müßig
    #|hello
  let dictionary = load(aff, dic)
  // the stem is cased and the `'s` kept, so the ALL CAPS entry is reachable
  assert_true(@suggest.suggest(dictionary, "Unicef's", 5).contains("UNICEF's"))
  // `ß` upper-cases to `SS`, so the mixed-case word reaches its uppercase form
  assert_true(@suggest.suggest(dictionary, "MÜßIG", 5).contains("MÜSSIG"))
}

///|
test "bounded edit distance two" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
  let dic =
    #|4
    #|permanent
    #|vacation
    #|Gandhi
    #|hello
  let dictionary = load(aff, dic)
  // long swap / move: `permenant` -> `permanent`
  assert_true(
    @suggest.suggest(dictionary, "permenant", 10).contains("permanent"),
  )
  // double deletion: `vacacation` -> `vacation`
  assert_true(
    @suggest.suggest(dictionary, "vacacation", 10).contains("vacation"),
  )
  // single-character move: `Ghandi` -> `Gandhi`
  assert_true(@suggest.suggest(dictionary, "Ghandi", 10).contains("Gandhi"))
}

///|
test "results are deduplicated, never the input, and truncated to the limit" {
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|REP 1
    #|REP helo hello
  let dic =
    #|2
    #|hello
    #|help
  let dictionary = load(aff, dic)
  let all = @suggest.suggest(dictionary, "helo", 10)
  // `REP`, insertion and transposition can all reach `hello`; it appears once.
  let mut count = 0
  for word in all {
    if word == "hello" {
      count = count + 1
    }
  }
  assert_eq(count, 1)
  assert_false(all.contains("helo"))
  let limited = @suggest.suggest(dictionary, "helo", 1)
  assert_eq(limited.length(), 1)
}
