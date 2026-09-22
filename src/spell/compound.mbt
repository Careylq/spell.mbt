// `COMPOUNDRULE` support.
//
// Clean-room implementation of the compound pattern language documented in the
// Hunspell manual. No Hunspell (LGPL-2.1) source code was consulted or copied;
// this project is Apache-2.0.
//
// `COMPOUNDRULE n*1t` declares a pattern over the *compound flags* of the words
// a compound is built from, and a compound is correct when the sequence of its
// parts matches one of the patterns:
//
//   `F`    exactly one part carrying flag `F`
//   `F*`   zero or more parts carrying `F`
//   `F?`   zero or one part carrying `F`
//   `(F)`  the flag `F` when it is multi-character (`FLAG long` / `FLAG num`)
//
// Every part has to be accounted for by exactly one atom, so the pattern must
// match the whole word. A compound needs at least two parts.

///|
/// How often the flag before a repeating marker may occur.
priv enum CpdRepeat {
  /// The bare flag: exactly one part.
  Once
  /// `F*`: zero or more parts.
  Star
  /// `F?`: zero or one part.
  Question
}

///|
/// One atom of a compound pattern: a flag and how often it may repeat.
priv struct CpdAtom {
  flag : String
  repeat : CpdRepeat
}

///|
/// Parse one `COMPOUNDRULE` pattern into atoms, left to right.
///
/// A flag is one character, or everything between `(` and `)` for the
/// multi-character flag modes. A trailing `*` or `?` is the repeat marker. An
/// unterminated `(` is treated as a literal `(` so that a malformed pattern
/// cannot make matching fail with an error.
fn parse_compound_rule(pattern : String) -> Array[CpdAtom] {
  let chars = pattern.to_array()
  let atoms : Array[CpdAtom] = []
  let mut index = 0
  while index < chars.length() {
    let (flag, next) = if chars[index] == '(' {
      let buffer = StringBuilder()
      let mut cursor = index + 1
      let mut closed = false
      while cursor < chars.length() && !closed {
        if chars[cursor] == ')' {
          closed = true
        } else {
          buffer.write_char(chars[cursor])
          cursor = cursor + 1
        }
      }
      if closed {
        (buffer.to_string(), cursor + 1)
      } else {
        ("(", index + 1)
      }
    } else {
      (chars[index].to_string(), index + 1)
    }
    let repeat = if next < chars.length() && chars[next] == '*' {
      Star
    } else if next < chars.length() && chars[next] == '?' {
      Question
    } else {
      Once
    }
    let following = match repeat {
      Once => next
      Star | Question => next + 1
    }
    atoms.push({ flag, repeat, })
    index = following
  }
  atoms
}

///|
/// May this repeat marker match more than one part?
fn repeats(repeat : CpdRepeat) -> Bool {
  match repeat {
    Once => false
    Star | Question => true
  }
}

///|
/// Does `word` decompose into at least two dictionary words whose flags match
/// one of the `.aff` file's `COMPOUNDRULE` patterns?
///
/// The parts must be plain dictionary entries (affixed parts are not tried).
/// `NEEDAFFIX` and `FORBIDDENWORD` disqualify a part; `ONLYINCOMPOUND` does not,
/// because a compound is exactly where such an entry is allowed.
fn Dictionary::check_compound_rule(
  self : Dictionary,
  word : String,
  mode : MatchCase,
) -> Bool {
  if self.compound_rules.length() == 0 {
    return false
  }
  let chars = word.to_array()
  if chars.length() < 2 {
    return false
  }
  for text in self.compound_rules {
    let pattern = parse_compound_rule(text)
    if self.matches_compound_pattern(chars, 0, pattern, 0, 0, mode) {
      return true
    }
  }
  false
}

///|
/// Try to match `pattern` from `atom_index` against `chars` from `position`.
///
/// `parts` counts the parts consumed so far, so the caller can insist on a real
/// compound (two or more parts) rather than a single dictionary word.
fn Dictionary::matches_compound_pattern(
  self : Dictionary,
  chars : Array[Char],
  position : Int,
  pattern : Array[CpdAtom],
  atom_index : Int,
  parts : Int,
  mode : MatchCase,
) -> Bool {
  if atom_index >= pattern.length() {
    return position >= chars.length() && parts >= 2
  }
  let atom = pattern[atom_index]
  // A repeating atom may always match nothing.
  if repeats(atom.repeat) &&
    self.matches_compound_pattern(
      chars,
      position,
      pattern,
      atom_index + 1,
      parts,
      mode,
    ) {
    return true
  }
  let minimum = if self.compound_min <= 0 { 3 } else { self.compound_min }
  let mut end = position + minimum
  while end <= chars.length() {
    let part = chars_to_string(chars, position, end)
    if self.compound_part_has_flag(part, atom.flag, mode) {
      // `F*` stays on the same atom so it can consume further parts; `F` and
      // `F?` move on.
      let next_atom = match atom.repeat {
        Star => atom_index
        Once | Question => atom_index + 1
      }
      if self.matches_compound_pattern(
          chars,
          end,
          pattern,
          next_atom,
          parts + 1,
          mode,
        ) {
        return true
      }
    }
    end = end + 1
  }
  false
}

///|
/// May `part` stand as one constituent of a `COMPOUNDRULE` compound, and does it
/// carry the compound flag `flag`? A `KEEPCASE` part only matches in an
/// exact-case lookup.
fn Dictionary::compound_part_has_flag(
  self : Dictionary,
  part : String,
  flag : String,
  mode : MatchCase,
) -> Bool {
  if self.is_forbidden_word(part) {
    return false
  }
  for flags in self.homonyms(part) {
    if flags.contains(flag) &&
      !has_flag(self.needaffix, flags) &&
      !keepcase_blocks(mode, part, self.keepcase, flags) {
      return true
    }
  }
  false
}
