// Hunspell affix-condition matcher.
//
// This is an independent, clean-room implementation of the condition language
// documented in the Hunspell manual. No Hunspell (LGPL-2.1) source code was
// consulted or copied; this project is Apache-2.0.
//
// A condition is a tiny regular expression whose elements each consume exactly
// one character:
//
//   `.`        any single character
//   `[abc]`    one character from the set
//   `[^abc]`   one character outside the set
//   anything   that literal character
//
// The expression is anchored: a suffix condition must match at the *end* of the
// stem, a prefix condition at the *start*. An empty condition matches any stem.
//
// Matching is done over `Char` values (Unicode scalar values). MoonBit `String`
// is a UTF-16 code-unit sequence, but `String::to_array` decodes surrogate
// pairs, so a non-BMP character counts as one atom here — which is what the
// format means by "character". `apply_rule` handles stripping separately.

///|
/// One element of a parsed condition; each atom consumes one stem character.
priv enum CondAtom {
  /// `.` — any single character.
  Any
  /// A literal condition character.
  Literal(Char)
  /// `[...]` — one character from this set.
  InSet(Array[Char])
  /// `[^...]` — one character outside this set.
  NotInSet(Array[Char])
}

///|
/// Parse a condition string into atoms, left to right.
///
/// A `[` that is never closed has no defined meaning in the format, so it is
/// treated as a literal `[` (and the rest of the text is parsed normally);
/// this keeps `matches_condition` total, since it cannot report an error.
fn parse_condition(condition : String) -> Array[CondAtom] {
  let chars = condition.to_array()
  let atoms : Array[CondAtom] = []
  let mut index = 0
  while index < chars.length() {
    let c = chars[index]
    if c == '.' {
      atoms.push(Any)
      index = index + 1
    } else if c == '[' {
      let mut cursor = index + 1
      let negated = cursor < chars.length() && chars[cursor] == '^'
      if negated {
        cursor = cursor + 1
      }
      let members : Array[Char] = []
      let mut closed = false
      let mut scan = cursor
      while scan < chars.length() && !closed {
        if chars[scan] == ']' {
          closed = true
        } else {
          members.push(chars[scan])
          scan = scan + 1
        }
      }
      if closed {
        atoms.push(if negated { NotInSet(members) } else { InSet(members) })
        index = scan + 1
      } else {
        atoms.push(Literal('['))
        index = index + 1
      }
    } else {
      atoms.push(Literal(c))
      index = index + 1
    }
  }
  atoms
}

///|
/// Does one atom accept character `c`?
fn atom_matches(atom : CondAtom, c : Char) -> Bool {
  match atom {
    Any => true
    Literal(expected) => c == expected
    InSet(members) => members.contains(c)
    NotInSet(members) => !members.contains(c)
  }
}

///|
/// Does `stem` satisfy `condition` when anchored at the given end?
///
/// The condition is read left to right and its *last* atom is aligned with the
/// last character of `stem` for `Suffix`; for `Prefix` its first atom is
/// aligned with the first character. A condition with more atoms than the stem
/// has characters cannot match, which is why `.` does not match an empty stem.
/// An empty condition matches every stem, including the empty one.
pub fn matches_condition(
  condition : String,
  stem : String,
  kind : @aff.AffixKind,
) -> Bool {
  let atoms = parse_condition(condition)
  if atoms.length() == 0 {
    return true
  }
  let chars = stem.to_array()
  if atoms.length() > chars.length() {
    return false
  }
  // Aligning the pattern's end with the stem's end handles both anchors: for a
  // prefix the offset is zero, for a suffix it is the amount of stem left over.
  let offset = match kind {
    @aff.Prefix => 0
    @aff.Suffix => chars.length() - atoms.length()
  }
  let mut index = 0
  while index < atoms.length() {
    if !atom_matches(atoms[index], chars[offset + index]) {
      return false
    }
    index = index + 1
  }
  true
}
