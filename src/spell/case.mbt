// Capitalisation helpers for the `spell()` judgement engine.
//
// Hunspell applies the dictionary's capitalisation rules whenever a word is not
// found verbatim: a word that only differs from a dictionary entry by case may
// still be correct (`hello` accepts `Hello` and `HELLO`), while a genuinely
// mixed-case word such as `iPhone` must match exactly.
//
// Only the *shape* of the word is classified here; the lookup itself lives in
// `lookup.mbt`. Case folding uses `moonbitlang/x/unicode` for lowering, which
// covers the Latin-1 range; upper-casing is ASCII-only, so a non-ASCII first
// letter is not capitalised (documented in the README's limitations).

///|
/// The capitalisation shape of a word.
priv enum CaseKind {
  /// No cased letters at all (`123`, `--`): match exactly.
  NoLetters
  /// No upper-case letters (`hello`, `café`): match exactly.
  Lower
  /// First letter upper-case, all later letters lower-case (`Hello`).
  Capitalized
  /// No lower-case letters (`HELLO`, `A1`).
  AllCaps
  /// Any other mixture (`iPhone`, `ABc`): match exactly.
  Mixed
}

///|
/// Is `c` an upper-case letter for the purpose of the case rules?
///
/// ASCII upper-case letters and any character that Unicode lower-casing changes
/// count as upper-case. This is a deliberately cheap test: it never has to know
/// the full Unicode case table (see the README limitations).
fn is_upper_char(c : Char) -> Bool {
  c.is_ascii_uppercase() || @unicode.to_lowercase(c) != c
}

///|
/// Is `c` a lower-case letter for the purpose of the case rules?
///
/// Only ASCII lower-case letters are recognised, which is enough for the two
/// classifications that matter: a word with no upper-case letters behaves as
/// `Lower`, so a non-ASCII lower-case letter does not need to be identified.
fn is_lower_char(c : Char) -> Bool {
  c.is_ascii_lowercase()
}

///|
/// Classify the capitalisation shape of `word`.
fn classify_case(word : String) -> CaseKind {
  let chars = word.to_array()
  let mut upper = 0
  let mut lower = 0
  for c in chars {
    if is_upper_char(c) {
      upper = upper + 1
    } else if is_lower_char(c) {
      lower = lower + 1
    }
  }
  if upper == 0 && lower == 0 {
    NoLetters
  } else if upper == 0 {
    Lower
  } else if lower == 0 {
    AllCaps
  } else if upper == 1 && is_upper_char(chars[0]) {
    Capitalized
  } else {
    Mixed
  }
}

///|
/// Lower-case every character of `word`.
fn lower_word(word : String) -> String {
  let buffer = StringBuilder()
  for c in word {
    buffer.write_char(@unicode.to_lowercase(c))
  }
  buffer.to_string()
}

///|
/// The `Capitalised` form of `word`: lower-case it, then upper-case the first
/// character (ASCII only, see the module comment).
fn capitalise_word(word : String) -> String {
  let lowered = lower_word(word)
  let chars = lowered.to_array()
  if chars.length() == 0 {
    return lowered
  }
  let buffer = StringBuilder()
  buffer.write_char(chars[0].to_ascii_uppercase())
  let mut index = 1
  while index < chars.length() {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}
