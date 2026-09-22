// The reverse lookup that decides whether a word is correct.
//
// Direct lookup is a single map access. Affix-derived forms are found by
// *reconstructing* the stem from the word instead of generating every form of
// every dictionary entry: for a suffix rule the word is stripped of the rule's
// `add` and the rule's `strip` is put back, and the candidate stem is then
// verified by re-applying the rule. This keeps `check` proportional to the
// number of rules rather than to the size of the dictionary.

///|
/// Is `word` correct according to this dictionary?
///
/// The word is first classified by capitalisation. Exact-case forms are looked
/// up directly, then through the affix rules, then through the two-word compound
/// rule; `Capitalised` and `ALL CAPS` words additionally accept their folded
/// forms, except that `KEEPCASE` entries only ever match their exact case.
///
/// When `.` is declared in `WORDCHARS`, a failed word that ends in `.` is
/// retried with its trailing dots removed, which is how abbreviations such as
/// `etc.` are accepted.
///
/// An empty word is never correct (the CLI skips empty input lines entirely).
pub fn Dictionary::check(self : Dictionary, word : String) -> Bool {
  if word.is_empty() {
    return false
  }
  if self.check_word(word) {
    return true
  }
  if self.word_chars.contains(".") {
    let trimmed = strip_trailing_dots(word)
    if !trimmed.is_empty() && trimmed != word {
      return self.check_word(trimmed)
    }
  }
  false
}

///|
/// The capitalisation + affix + compound judgement for one exact string.
fn Dictionary::check_word(self : Dictionary, word : String) -> Bool {
  let matched = match classify_case(word) {
    NoLetters | Lower => self.lookup_word(word, true)
    Capitalized =>
      self.lookup_word(word, true) || self.lookup_word(lower_word(word), false)
    AllCaps =>
      self.lookup_word(word, true) ||
      self.lookup_word(lower_word(word), false) ||
      self.lookup_word(capitalise_word(word), false)
    Mixed => self.lookup_word(word, true)
  }
  matched || self.check_compound(word)
}

///|
/// Remove every trailing `.` from `word` (`"HUNSPELL..."` -> `"HUNSPELL"`).
fn strip_trailing_dots(word : String) -> String {
  let chars = word.to_array()
  let mut end = chars.length()
  while end > 0 && chars[end - 1] == '.' {
    end = end - 1
  }
  chars_to_string(chars, 0, end)
}

///|
/// Look one exact string up: direct entry first, then affix-derived forms.
///
/// `exact_case` is true only when `word` is the word the user actually asked
/// about. Folding a word to a different case must not make a `KEEPCASE` entry
/// match, so the folded lookups pass `false`.
fn Dictionary::lookup_word(
  self : Dictionary,
  word : String,
  exact_case : Bool,
) -> Bool {
  self.direct_hit(word, exact_case) || self.affix_hit(word, exact_case)
}

///|
/// Is `word` itself a dictionary entry that may be used on its own?
fn Dictionary::direct_hit(
  self : Dictionary,
  word : String,
  exact_case : Bool,
) -> Bool {
  match self.entries.get(word) {
    None => false
    Some(flags) =>
      !has_flag(self.forbiddenword, flags) &&
      !has_flag(self.needaffix, flags) &&
      !has_flag(self.onlyincompound, flags) &&
      (exact_case || !has_flag(self.keepcase, flags))
  }
}

///|
/// Could `word` be produced by applying exactly one affix rule, or by applying
/// one prefix and one suffix whose blocks allow cross products?
fn Dictionary::affix_hit(
  self : Dictionary,
  word : String,
  exact_case : Bool,
) -> Bool {
  for rule in self.suffix_rules {
    if self.derives_suffix(rule, word, exact_case) {
      return true
    }
  }
  for rule in self.prefix_rules {
    if self.derives_prefix(rule, word, exact_case) {
      return true
    }
  }
  for prefix_rule in self.prefix_rules {
    if prefix_rule.cross_product {
      for suffix_rule in self.suffix_rules {
        if suffix_rule.cross_product &&
          self.derives_cross(prefix_rule, suffix_rule, word, exact_case) {
          return true
        }
      }
    }
  }
  false
}

///|
/// Can `rule` (a suffix rule) have produced `word`?
fn Dictionary::derives_suffix(
  self : Dictionary,
  rule : @aff.AffixRule,
  word : String,
  exact_case : Bool,
) -> Bool {
  let rest = match word.strip_suffix(normalise_affix(rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let stem = rest + normalise_affix(rule.strip)
  if !self.stem_is_usable(stem, rule.flag, exact_case) {
    return false
  }
  match @affix.apply_rule(rule, stem) {
    Some(produced) => produced == word
    None => false
  }
}

///|
/// Can `rule` (a prefix rule) have produced `word`?
fn Dictionary::derives_prefix(
  self : Dictionary,
  rule : @aff.AffixRule,
  word : String,
  exact_case : Bool,
) -> Bool {
  let rest = match word.strip_prefix(normalise_affix(rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let stem = normalise_affix(rule.strip) + rest
  if !self.stem_is_usable(stem, rule.flag, exact_case) {
    return false
  }
  match @affix.apply_rule(rule, stem) {
    Some(produced) => produced == word
    None => false
  }
}

///|
/// Can the cross product of `prefix_rule` and `suffix_rule` have produced
/// `word`?
///
/// Hunspell applies both rules to the *same* stem and puts the additions on the
/// outside, so `word = prefix.add + core + suffix.add` where `core` is the stem
/// with both strips removed. The stem is reconstructed, checked for both flags
/// and both conditions, and then the combination is re-built as a guard against
/// a wrong reconstruction.
fn Dictionary::derives_cross(
  self : Dictionary,
  prefix_rule : @aff.AffixRule,
  suffix_rule : @aff.AffixRule,
  word : String,
  exact_case : Bool,
) -> Bool {
  let after_prefix = match word.strip_prefix(normalise_affix(prefix_rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let core = match after_prefix.strip_suffix(normalise_affix(suffix_rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let stem = normalise_affix(prefix_rule.strip) +
    core +
    normalise_affix(suffix_rule.strip)
  let flags = match self.entries.get(stem) {
    None => return false
    Some(flags) => flags
  }
  if !flags.contains(prefix_rule.flag) || !flags.contains(suffix_rule.flag) {
    return false
  }
  if has_flag(self.forbiddenword, flags) || has_flag(self.onlyincompound, flags) {
    return false
  }
  if !exact_case && has_flag(self.keepcase, flags) {
    return false
  }
  if !@affix.matches_condition(prefix_rule.condition, stem, @aff.Prefix) {
    return false
  }
  if !@affix.matches_condition(suffix_rule.condition, stem, @aff.Suffix) {
    return false
  }
  reconstruct_cross(prefix_rule, suffix_rule, stem) == Some(word)
}

///|
/// Rebuild the word that applying both rules to `stem` would produce.
fn reconstruct_cross(
  prefix_rule : @aff.AffixRule,
  suffix_rule : @aff.AffixRule,
  stem : String,
) -> String? {
  let after_prefix = match
    stem.strip_prefix(normalise_affix(prefix_rule.strip)) {
    Some(view) => view.to_owned()
    None => return None
  }
  let core = match
    after_prefix.strip_suffix(normalise_affix(suffix_rule.strip)) {
    Some(view) => view.to_owned()
    None => return None
  }
  Some(
    normalise_affix(prefix_rule.add) + core + normalise_affix(suffix_rule.add),
  )
}

///|
/// Is `stem` a dictionary entry that carries `flag` and may take an affix?
///
/// `NEEDAFFIX` is deliberately *not* rejected here: it marks a stem that is only
/// valid once an affix is attached, which is exactly this path. `FORBIDDENWORD`
/// and `ONLYINCOMPOUND` disqualify the stem, and a `KEEPCASE` stem survives only
/// in an exact-case lookup.
fn Dictionary::stem_is_usable(
  self : Dictionary,
  stem : String,
  flag : String,
  exact_case : Bool,
) -> Bool {
  match self.entries.get(stem) {
    None => false
    Some(flags) =>
      flags.contains(flag) &&
      !has_flag(self.forbiddenword, flags) &&
      !has_flag(self.onlyincompound, flags) &&
      (exact_case || !has_flag(self.keepcase, flags))
  }
}

///|
/// Does `flags` contain the flag named by `maybe_flag` (which may be absent)?
fn has_flag(maybe_flag : String?, flags : Array[String]) -> Bool {
  match maybe_flag {
    None => false
    Some(flag) => flags.contains(flag)
  }
}

///|
/// The format writes `0` for "nothing"; an empty string means the same thing.
fn normalise_affix(text : String) -> String {
  if text == "0" {
    ""
  } else {
    text
  }
}

///|
/// Accept a word that splits into two dictionary words, each carrying
/// `COMPOUNDFLAG` and each at least `COMPOUNDMIN` characters long.
///
/// This is the basic two-part case only. `COMPOUNDBEGIN` / `COMPOUNDEND` /
/// `COMPOUNDMIDDLE`, `COMPOUNDRULE` and `CHECKCOMPOUNDPATTERN` are not applied
/// (see the README's limitations), and parts must be plain dictionary entries,
/// not affixed forms.
fn Dictionary::check_compound(self : Dictionary, word : String) -> Bool {
  let flag = match self.compound_flag {
    None => return false
    Some(flag) => flag
  }
  let minimum = if self.compound_min <= 0 { 3 } else { self.compound_min }
  let chars = word.to_array()
  let total = chars.length()
  if total < minimum * 2 {
    return false
  }
  let mut split = minimum
  while split <= total - minimum {
    let left = chars_to_string(chars, 0, split)
    let right = chars_to_string(chars, split, total)
    if self.compound_part_is_usable(left, flag) &&
      self.compound_part_is_usable(right, flag) {
      return true
    }
    split = split + 1
  }
  false
}

///|
/// May `part` stand as one half of a compound word?
fn Dictionary::compound_part_is_usable(
  self : Dictionary,
  part : String,
  flag : String,
) -> Bool {
  match self.entries.get(part) {
    None => false
    Some(flags) =>
      flags.contains(flag) &&
      !has_flag(self.forbiddenword, flags) &&
      !has_flag(self.needaffix, flags)
  }
}

///|
/// Build a string from a slice of code points (indices are code-point offsets).
fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let buffer = StringBuilder()
  let mut index = start
  while index < end {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}
