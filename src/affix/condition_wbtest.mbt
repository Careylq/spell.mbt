// Whitebox tests for the condition parser and atom matcher.

///|
test "parse_condition splits a condition into one atom per character" {
  @debug.assert_eq(parse_condition("").length(), 0)
  @debug.assert_eq(parse_condition(".").length(), 1)
  @debug.assert_eq(parse_condition("[abc]").length(), 1)
  @debug.assert_eq(parse_condition("[^ab]").length(), 1)
  @debug.assert_eq(parse_condition("[]").length(), 1)
  @debug.assert_eq(parse_condition("x[ab]y").length(), 3)
  @debug.assert_eq(parse_condition("a.b").length(), 3)
  // An unclosed `[` is malformed input; it degrades to a literal `[` so that
  // `matches_condition` (which cannot raise) stays total. The rest of the text
  // is then parsed normally, so `[^a` is three literal atoms.
  @debug.assert_eq(parse_condition("[a").length(), 2)
  @debug.assert_eq(parse_condition("[^a").length(), 3)
}

///|
test "atom_matches covers all four atom kinds" {
  assert_true(atom_matches(Any, 'q'))
  assert_true(atom_matches(Any, 'é'))
  assert_true(atom_matches(Literal('a'), 'a'))
  assert_false(atom_matches(Literal('a'), 'b'))
  assert_true(atom_matches(InSet(['a', 'b']), 'b'))
  assert_false(atom_matches(InSet(['a', 'b']), 'c'))
  assert_true(atom_matches(NotInSet(['a', 'b']), 'c'))
  assert_false(atom_matches(NotInSet(['a', 'b']), 'a'))
  // An empty positive set matches nothing; an empty negated set matches all.
  assert_false(atom_matches(InSet([]), 'a'))
  assert_true(atom_matches(NotInSet([]), 'a'))
}

///|
test "a closed class may contain `.`, `^` and a leading `]`-like character" {
  // `.` inside a class is a literal, not a wildcard.
  assert_true(atom_matches(InSet(['.']), '.'))
  assert_false(atom_matches(InSet(['.']), 'a'))
  // `^` only negates as the first character of the class.
  let atoms = parse_condition("[a^b]")
  @debug.assert_eq(atoms.length(), 1)
  assert_true(atom_matches(atoms[0], '^'))
}

///|
test "matches_condition aligns a suffix pattern with the stem end" {
  // "crab" + suffix condition "ab" sees the last two characters.
  assert_true(matches_condition("ab", "crab", @aff.Suffix))
  assert_false(matches_condition("ab", "crab", @aff.Prefix))
  // A pattern longer than the stem can never match.
  assert_false(matches_condition("abc", "ab", @aff.Suffix))
  assert_true(matches_condition("abc", "abc", @aff.Suffix))
  assert_true(matches_condition("abc", "abc", @aff.Prefix))
}
