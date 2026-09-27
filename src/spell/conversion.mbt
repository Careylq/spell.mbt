// `ICONV` / `OCONV` character conversion.
//
// Clean-room implementation of the conversion tables documented in the
// Hunspell manual (`hunspell(5)`): "Define input conversion table" / "Define
// output conversion table". No Hunspell (LGPL-2.1) source code was consulted or
// copied; this project is Apache-2.0.
//
// The manual's example gives the semantics of the trailing `_`:
//
//   ICONV <200D>_ <FFF0>
//
// "change <200D> to <FFF0> only if it appears at the end of the word". So a
// trailing `_` in the *pattern* is an end-of-word anchor, not the `_`-for-space
// convention `REP` uses. The corpus pins the rest down:
//
//   * the longest pattern that matches at a position wins, regardless of the
//     order the pairs appeared in (`iconv2`: `Gagg` beats `Ga`);
//   * an anchored pattern wins over an unanchored one of the same length
//     (`nepali`: `<ZWNJ>_` must beat `<ZWNJ>`, otherwise a word ending in a
//     zero-width non-joiner would be wrongly accepted);
//   * matching is left to right and the replacements are *not* rescanned
//     (`ICONV a b`, `ICONV b c` does not turn `a` into `c`);
//   * a pattern that cannot match is skipped, so a shorter key still applies
//     (`iconv3`: `abc_` cannot match inside `abcd`, so `ab` applies).
//
// `ICONV` is applied to the word being checked, and — verified against
// hunspell 1.7.3 with a probe dictionary — never to the dictionary's entries:
// with `ICONV a b` and a word list holding only `a`, neither `a` nor `b` is
// accepted. `OCONV` is applied to suggestion output only.

///|
/// Split a conversion pattern into its body and whether it carries the
/// end-of-word marker `_`.
fn conversion_pattern(from : String) -> (String, Bool) {
  match from.strip_suffix("_") {
    Some(rest) => (rest.to_owned(), true)
    None => (from, false)
  }
}

///|
/// Order two conversion pairs the way the matcher needs them: longest pattern
/// first, then an end-anchored pattern before an unanchored one of the same
/// length, then a total tiebreak so the order is deterministic.
fn compare_conversions(left : @aff.Conversion, right : @aff.Conversion) -> Int {
  let (left_pattern, left_at_end) = conversion_pattern(left.from)
  let (right_pattern, right_at_end) = conversion_pattern(right.from)
  let left_length = left_pattern.char_length()
  let right_length = right_pattern.char_length()
  if left_length != right_length {
    return right_length - left_length
  }
  if left_at_end != right_at_end {
    return if left_at_end { -1 } else { 1 }
  }
  let by_pattern = left.from.compare(right.from)
  if by_pattern != 0 {
    return by_pattern
  }
  left.to.compare(right.to)
}

///|
/// A copy of `table` in matching order (`compare_conversions`).
///
/// The table is compiled once when the dictionary is built, so the per-word
/// cost is a linear scan without re-parsing the patterns.
fn prepare_conversions(
  table : Array[@aff.Conversion],
) -> Array[@aff.Conversion] {
  if table.length() < 2 {
    return table
  }
  let sorted : Array[@aff.Conversion] = []
  for entry in table {
    sorted.push(entry)
  }
  sorted.sort_by(compare_conversions)
  sorted
}

///|
/// Apply a prepared conversion table to `text`.
///
/// At each position the first (longest, then anchored) pattern that matches is
/// replaced and the scan continues *after* the matched input; the replacement
/// is never rescanned. A pair whose pattern is empty is skipped: a bare `_`
/// would be an anchor with nothing to match. An empty table (the common case)
/// returns `text` unchanged.
/// The patterns are split and turned into code points ONCE, before the scan, so
/// the inner loop only compares. Doing that per input position re-split every
/// pattern and allocated an array for every character of every word, which is
/// what `prepare_conversions` says the per-word cost must not do.
fn apply_conversion(table : Array[@aff.Conversion], text : String) -> String {
  if table.is_empty() || text.is_empty() {
    return text
  }
  let patterns : Array[(Array[Char], String, Bool)] = []
  let first_chars : Array[Char] = []
  for entry in table {
    let (pattern_text, at_end) = conversion_pattern(entry.from)
    if pattern_text.is_empty() {
      continue
    }
    let pattern = pattern_text.to_array()
    first_chars.push(pattern[0])
    patterns.push((pattern, entry.to, at_end))
  }
  if patterns.is_empty() {
    return text
  }
  // Most words in most languages contain none of the characters any conversion
  // pattern starts with (en_US converts a single typographic apostrophe). That
  // scan is allocation-free, so it is worth one pass to avoid building a code
  // point array and a string buffer for a text that cannot change.
  let mut may_match = false
  for c in text {
    if first_chars.contains(c) {
      may_match = true
      break
    }
  }
  if !may_match {
    return text
  }
  let chars = text.to_array()
  let buffer = StringBuilder()
  let mut position = 0
  while position < chars.length() {
    let mut matched = false
    for entry in patterns {
      let (pattern, replacement, at_end) = entry
      if position + pattern.length() > chars.length() {
        continue
      }
      if !matches_chars_at(chars, pattern, position) {
        continue
      }
      if at_end && position + pattern.length() != chars.length() {
        continue
      }
      buffer.write_string(replacement)
      position = position + pattern.length()
      matched = true
      break
    }
    if !matched {
      buffer.write_char(chars[position])
      position = position + 1
    }
  }
  buffer.to_string()
}
