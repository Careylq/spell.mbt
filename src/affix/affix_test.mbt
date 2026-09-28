// Blackbox tests for the public `@affix` API.
//
// The rule table is derived from the *shapes* of rules found in real `en_US`
// affix files; the dictionaries here are written from scratch. An audit of all
// fixtures found no upstream line overlap in this file; overlap does exist in
// others — see NOTICE, "关于测试夹具".

///|
/// Build an `AffixRule` with the fields under test; flag and morphological data
/// are irrelevant to `apply_rule`, which ignores `cross_product` too.
fn rule(
  kind : @aff.AffixKind,
  strip : String,
  add : String,
  condition : String,
) -> @aff.AffixRule {
  { kind, strip, add, condition, flag: "X", cross_product: false, morph: [], }
}

///|
test "real-world en_US suffix and prefix rule shapes" {
  // SFX y ied [^aeiou]y  ->  imply/implied
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "y", "ied", "[^aeiou]y"), "imply"),
    Some("implied"),
  )
  // SFX 0 ed [^ey]  ->  look/looked
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "ed", "[^ey]"), "look"),
    Some("looked"),
  )
  // SFX 0 ed [aeiou]y  ->  convey/conveyed
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "ed", "[aeiou]y"), "convey"),
    Some("conveyed"),
  )
  // SFX 0 s [^sxzhy]  ->  text/texts
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "s", "[^sxzhy]"), "text"),
    Some("texts"),
  )
  // SFX 0 es [sxzh]  ->  six/sixes
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "es", "[sxzh]"), "six"),
    Some("sixes"),
  )
  // SFX e ion e  ->  create/creation
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "e", "ion", "e"), "create"),
    Some("creation"),
  )
  // SFX y ication y  ->  imply/`impl` + `ication` = "implication".
  // Note the rule table's "implification" is *not* what this rule yields: that
  // word needs the real en_US `ification` addition, asserted right after.
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "y", "ication", "y"), "imply"),
    Some("implication"),
  )
  // SFX y ification y  ->  imply/implification
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "y", "ification", "y"), "imply"),
    Some("implification"),
  )
  // PFX 0 re .  ->  create/recreate
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Prefix, "0", "re", "."), "create"),
    Some("recreate"),
  )
  // SFX 0 ed [^ey]  ->  create: condition fails because the stem ends in `e`.
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "ed", "[^ey]"), "create"),
    None,
  )
  // SFX 0 ed [^ey]  ->  imply: condition fails because the stem ends in `y`.
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "ed", "[^ey]"), "imply"),
    None,
  )
}

///|
test "a suffix condition is anchored at the end of the stem" {
  assert_false(@affix.matches_condition("e", "eat", @aff.Suffix))
  assert_true(@affix.matches_condition("e", "eat", @aff.Prefix))
  assert_true(@affix.matches_condition("cr", "create", @aff.Prefix))
  assert_false(@affix.matches_condition("cr", "create", @aff.Suffix))
  assert_true(@affix.matches_condition("te", "create", @aff.Suffix))
  assert_false(@affix.matches_condition("te", "create", @aff.Prefix))
}

///|
test "character classes, positive and negated" {
  // [^aeiou]y
  assert_false(@affix.matches_condition("[^aeiou]y", "play", @aff.Suffix))
  assert_true(@affix.matches_condition("[^aeiou]y", "happy", @aff.Suffix))
  assert_true(@affix.matches_condition("[^aeiou]y", "imply", @aff.Suffix))
  // [abc]
  assert_true(@affix.matches_condition("[abc]", "crab", @aff.Suffix))
  assert_false(@affix.matches_condition("[abc]", "cry", @aff.Suffix))
  // [^abc]
  assert_false(@affix.matches_condition("[^abc]", "crab", @aff.Suffix))
  assert_true(@affix.matches_condition("[^abc]", "cry", @aff.Suffix))
  // A class still consumes exactly one character.
  assert_false(@affix.matches_condition("[abc]", "", @aff.Suffix))
  assert_false(@affix.matches_condition("[abc]x", "ab", @aff.Suffix))
}

///|
test "`.` matches exactly one character and not an empty stem" {
  assert_true(@affix.matches_condition(".", "a", @aff.Suffix))
  assert_true(@affix.matches_condition(".", "a", @aff.Prefix))
  assert_false(@affix.matches_condition(".", "", @aff.Suffix))
  assert_false(@affix.matches_condition(".", "", @aff.Prefix))
  assert_true(@affix.matches_condition("..", "ab", @aff.Suffix))
  assert_false(@affix.matches_condition("..", "a", @aff.Suffix))
}

///|
test "multi-character literal conditions" {
  assert_true(@affix.matches_condition("ee", "tree", @aff.Suffix))
  assert_false(@affix.matches_condition("ee", "tre", @aff.Suffix))
  assert_false(@affix.matches_condition("ee", "tree", @aff.Prefix))
  assert_true(@affix.matches_condition("tr", "tree", @aff.Prefix))
}

///|
test "an empty condition matches every stem, including the empty one" {
  assert_true(@affix.matches_condition("", "", @aff.Suffix))
  assert_true(@affix.matches_condition("", "", @aff.Prefix))
  assert_true(@affix.matches_condition("", "anything", @aff.Suffix))
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "0", "0", ""), "word"),
    Some("word"),
  )
}

///|
test "a strip that the stem does not carry makes the rule fail" {
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "y", "ied", "."), "look"),
    None,
  )
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Prefix, "un", "re", "."), "create"),
    None,
  )
}

///|
test "an add of `0` appends nothing" {
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "s", "0", "[s]"), "class"),
    Some("clas"),
  )
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Prefix, "un", "0", "un"), "undo"),
    Some("do"),
  )
}

///|
test "non-ASCII and non-BMP characters count as single condition characters" {
  // A BMP accented character.
  assert_true(@affix.matches_condition("é", "café", @aff.Suffix))
  assert_false(@affix.matches_condition("é", "cafe", @aff.Suffix))
  assert_true(@affix.matches_condition("[éè]", "cafè", @aff.Suffix))
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "é", "es", "é"), "café"),
    Some("cafes"),
  )
  // A non-BMP character is a surrogate pair in UTF-16 but one condition char.
  assert_true(@affix.matches_condition(".", "😀", @aff.Suffix))
  assert_true(@affix.matches_condition("😀", "a😀", @aff.Suffix))
  assert_false(@affix.matches_condition("😀", "😀a", @aff.Suffix))
  @debug.assert_eq(
    @affix.apply_rule(rule(@aff.Suffix, "😀", "s", "."), "a😀"),
    Some("as"),
  )
}

///|
test "rules parsed from .aff text work end to end" {
  let text =
    #|SFX Y N 3
    #|SFX Y y ied [^aeiou]y
    #|SFX Y 0 ed [^ey]
    #|SFX Y 0 s [^sxzhy]
    #|PFX R N 1
    #|PFX R 0 re .
  let aff = @aff.parse_aff(text)
  @debug.assert_eq(aff.affix_rules.length(), 4)
  @debug.assert_eq(
    @affix.apply_rule(aff.affix_rules[0], "imply"),
    Some("implied"),
  )
  @debug.assert_eq(
    @affix.apply_rule(aff.affix_rules[1], "look"),
    Some("looked"),
  )
  @debug.assert_eq(@affix.apply_rule(aff.affix_rules[2], "text"), Some("texts"))
  @debug.assert_eq(
    @affix.apply_rule(aff.affix_rules[3], "create"),
    Some("recreate"),
  )
}
