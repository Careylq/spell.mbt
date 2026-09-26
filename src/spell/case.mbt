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
  c.is_ascii_uppercase() || c == 'İ' || @unicode.to_lowercase(c) != c
}

///|
/// Is `c` a lower-case letter for the purpose of the case rules?
///
/// Only ASCII lower-case letters are recognised, which is enough for the two
/// classifications that matter: a word with no upper-case letters behaves as
/// `Lower`, so a non-ASCII lower-case letter does not need to be identified.
///
/// `sharps` counts `ß` as lower-case. Under `CHECKSHARPS` a word such as `MÜßIG`
/// must be treated as mixed case (so it only matches exactly), because an
/// uppercased form of a word with `ß` may only spell it `SS`.
fn is_lower_char(c : Char, sharps : Bool) -> Bool {
  c.is_ascii_lowercase() || c == 'ı' || (sharps && c == 'ß')
}

///|
/// Classify the capitalisation shape of `word`.
fn classify_case(word : String, sharps : Bool) -> CaseKind {
  let chars = word.to_array()
  let mut upper = 0
  let mut lower = 0
  for c in chars {
    if is_upper_char(c) {
      upper = upper + 1
    } else if is_lower_char(c, sharps) {
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
/// Lower-case every character of `word`, using the Turkic `I`/`İ` mapping when
/// the `.aff` declares `LANG tr` (or `az` / `crh`).
fn fold_lower(word : String, turkic : Bool) -> String {
  let buffer = StringBuilder()
  for c in word {
    if turkic && c == 'I' {
      buffer.write_char('ı')
    } else if turkic && c == 'İ' {
      buffer.write_char('i')
    } else {
      buffer.write_char(@unicode.to_lowercase(c))
    }
  }
  buffer.to_string()
}

///|
/// `word` with its first character lower-cased (`ULinda` -> `uLinda`). Hunspell
/// accepts the upper-cased first letter of a mixed-case word (`gh106`).
fn lower_first_word(word : String) -> String {
  let chars = word.to_array()
  if chars.length() == 0 {
    return word
  }
  let buffer = StringBuilder()
  buffer.write_char(chars[0].to_ascii_lowercase())
  let mut index = 1
  while index < chars.length() {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}

///|
/// The `Capitalised` form of `word`: lower-case every character but keep the
/// first one, upper-casing it when it is an ASCII lower-case letter.
///
/// Keeping the first character as it stands (instead of re-deriving it from the
/// lower-cased string) is what lets `İZMİR` find the dictionary word `İzmir`:
/// the Turkish capital dotted `İ` has no single-character ASCII upper form.
/// `LANG tr` additionally maps `i`/`ı` to `İ`/`I` in that position.
fn fold_capitalise(word : String, turkic : Bool) -> String {
  let chars = word.to_array()
  if chars.length() == 0 {
    return word
  }
  let buffer = StringBuilder()
  let first = chars[0]
  if turkic && first == 'i' {
    buffer.write_char('İ')
  } else if turkic && first == 'ı' {
    buffer.write_char('I')
  } else if first.is_ascii_lowercase() {
    buffer.write_char(first.to_ascii_uppercase())
  } else {
    buffer.write_char(first)
  }
  let mut index = 1
  while index < chars.length() {
    let c = chars[index]
    if turkic && c == 'I' {
      buffer.write_char('ı')
    } else if c == 'İ' {
      buffer.write_char('i')
    } else {
      buffer.write_char(@unicode.to_lowercase(c))
    }
    index = index + 1
  }
  buffer.to_string()
}

///|
/// `fold_lower` with the dictionary's `LANG`-selected casing rules.
fn Dictionary::fold_lower(self : Dictionary, word : String) -> String {
  fold_lower(word, self.turkic)
}

///|
/// `fold_capitalise` with the dictionary's `LANG`-selected casing rules.
fn Dictionary::fold_capitalise(self : Dictionary, word : String) -> String {
  fold_capitalise(word, self.turkic)
}
