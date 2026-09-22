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
/// `IGNORE` characters are removed from `word` before anything else, exactly as
/// they were removed from the dictionary's entries when it was built.
///
/// The word is then classified by capitalisation. Exact-case forms are looked up
/// directly, then through the affix rules, then through the compounds; `Capitalised`
/// and `ALL CAPS` words additionally accept their folded forms, except that
/// `KEEPCASE` entries only ever match their exact case.
///
/// When `.` is declared in `WORDCHARS`, a failed word that ends in `.` is
/// retried with its trailing dots removed, which is how abbreviations such as
/// `etc.` are accepted.
///
/// A line holding several whitespace-separated words is correct when every word
/// on it is correct on its own (`check_word_group`).
///
/// An empty word is never correct (the CLI skips empty input lines entirely).
pub fn Dictionary::check(self : Dictionary, word : String) -> Bool {
  let cleaned = remove_ignored(word, self.ignore_chars)
  if cleaned.is_empty() {
    return false
  }
  self.check_word_group(cleaned) || self.check_single(cleaned)
}

///|
/// Hunspell also accepts a line of whitespace-separated words when every one of
/// them is correct on its own (`drink eat` is correct because `drink` and `eat`
/// are). A line with fewer than two words is not this path, so `check` falls
/// through to the normal single-word judgement.
fn Dictionary::check_word_group(self : Dictionary, word : String) -> Bool {
  let parts : Array[String] = []
  let buffer = StringBuilder()
  let mut pending = false
  for c in word {
    if c.is_whitespace() {
      if pending {
        parts.push(buffer.to_string())
        buffer.reset()
        pending = false
      }
    } else {
      buffer.write_char(c)
      pending = true
    }
  }
  if pending {
    parts.push(buffer.to_string())
  }
  if parts.length() < 2 {
    return false
  }
  for part in parts {
    if !self.check_single(part) {
      return false
    }
  }
  true
}

///|
/// The single-word judgement: the capitalisation, affix and compound rules, plus
/// the trailing-`.` retry that `WORDCHARS` enables.
fn Dictionary::check_single(self : Dictionary, cleaned : String) -> Bool {
  if self.check_word(cleaned) {
    return true
  }
  if self.check_breaks(cleaned) {
    return true
  }
  if self.word_chars.contains(".") {
    let trimmed = strip_trailing_dots(cleaned)
    if !trimmed.is_empty() && trimmed != cleaned {
      return self.check_word(trimmed)
    }
  }
  false
}

///|
/// Can `word` be split at a `BREAK` pattern into two separately correct parts?
///
/// Hunspell's default patterns are `-` (split at every hyphen), `^-` (drop a
/// leading hyphen) and `-$` (drop a trailing one); `BREAK 0` switches them off.
/// Breaking is recursive (`foo-bar-foo-bar`), and a `FORBIDDENWORD` entry for
/// the whole word still wins (`foo-baz` stays wrong even though `foo` and `baz`
/// are words).
fn Dictionary::check_breaks(self : Dictionary, word : String) -> Bool {
  if self.break_patterns.length() == 0 {
    return false
  }
  if self.is_forbidden_word(word) {
    return false
  }
  for pattern in self.break_patterns {
    if self.breaks_at(word, pattern) {
      return true
    }
  }
  false
}

///|
/// Does the single `BREAK` pattern `pattern` split `word` into two correct
/// parts? A pattern may instead carry a leading `^` or trailing `$`, in which
/// case it names text to drop from that end.
fn Dictionary::breaks_at(
  self : Dictionary,
  word : String,
  pattern : String,
) -> Bool {
  let (body, at_start, at_end) = split_break_pattern(pattern)
  if body.is_empty() {
    return false
  }
  if at_start {
    match word.strip_prefix(body) {
      Some(rest) => return self.break_part_ok(rest.to_owned())
      None => return false
    }
  }
  if at_end {
    match word.strip_suffix(body) {
      Some(rest) => return self.break_part_ok(rest.to_owned())
      None => return false
    }
  }
  let chars = word.to_array()
  let pattern_chars = body.to_array()
  let mut index = 0
  while index + pattern_chars.length() <= chars.length() {
    if matches_chars_at(chars, pattern_chars, index) {
      let left = chars_to_string(chars, 0, index)
      let right = chars_to_string(
        chars,
        index + pattern_chars.length(),
        chars.length(),
      )
      if !left.is_empty() &&
        !right.is_empty() &&
        self.break_part_ok(left) &&
        self.break_part_ok(right) {
        return true
      }
    }
    index = index + 1
  }
  false
}

///|
/// Is one side of a break a correct word (and not a forbidden one)?
fn Dictionary::break_part_ok(self : Dictionary, part : String) -> Bool {
  !self.is_forbidden_word(part) && self.check_single(part)
}

///|
/// Split a `BREAK` pattern into its text and whether it anchors at the start
/// (`^`) or the end (`$`) of the word.
fn split_break_pattern(pattern : String) -> (String, Bool, Bool) {
  let at_start = match pattern.strip_prefix("^") {
    Some(rest) => rest.to_owned()
    None => pattern
  }
  let start_marked = at_start != pattern
  let (body, at_end) = match at_start.strip_suffix("$") {
    Some(rest) => (rest.to_owned(), true)
    None => (at_start, false)
  }
  (body, start_marked, at_end)
}

///|
/// Do `pattern` and `chars` agree at `offset`?
fn matches_chars_at(
  chars : Array[Char],
  pattern : Array[Char],
  offset : Int,
) -> Bool {
  let mut index = 0
  while index < pattern.length() {
    if chars[offset + index] != pattern[index] {
      return false
    }
    index = index + 1
  }
  true
}

///|
/// The capitalisation + affix + compound judgement for one exact string.
///
/// Affixes and compounds are both tried for every case variant the
/// capitalisation rules allow, so an all-caps compound such as `42ND` is found
/// through the folded form `42nd`.
fn Dictionary::check_word(self : Dictionary, word : String) -> Bool {
  match classify_case(word, self.check_sharps) {
    NoLetters | Lower => self.check_one(word, Exact)
    Capitalized =>
      self.check_one(word, Exact) ||
      self.check_one(lower_word(word), Folded) ||
      // `CHECKSHARPS`: a `KEEPCASE` word containing `ß` may be capitalised.
      (self.check_sharps && self.lookup_word(lower_word(word), SharpsFolded))
    AllCaps =>
      self.check_one(word, Exact) ||
      self.check_one(lower_word(word), Folded) ||
      self.check_one(capitalise_word(word), Folded) ||
      self.sharps_hit(word)
    Mixed => self.check_one(word, Exact)
  }
}

///|
/// Is `word` correct in one fixed casing: a dictionary entry (possibly affixed)
/// or a compound?
///
/// A `FORBIDDENWORD` entry subtracts its word from every accepted set, so a
/// compound is only tried when the word itself is not forbidden
/// (`foowordbar/F` must stay wrong even though `foo`, `word` and `bar` satisfy
/// a `COMPOUNDRULE`).
fn Dictionary::check_one(
  self : Dictionary,
  word : String,
  mode : MatchCase,
) -> Bool {
  self.lookup_word(word, mode) ||
  self.is_number_word(word) ||
  (
    !self.is_forbidden_word(word) &&
    (self.check_compound_rule(word, mode) || self.check_compound(word, mode))
  )
}

///|
/// Is `word` a number written with separators (`1.5`, `4,2`, `42-42`)?
///
/// `WORDCHARS` declares the characters that may appear inside a word, and
/// Hunspell accepts a word built from digits and one of the separator
/// characters `.`, `,` or `-` when the separators are not adjacent and sit
/// between digits. So `1.12345` and `42-42` are correct while `1..2`, `1.,2`
/// and `1,.2` are not.
fn Dictionary::is_number_word(self : Dictionary, word : String) -> Bool {
  let chars = word.to_array()
  if chars.length() == 0 {
    return false
  }
  let allows_dot = self.word_chars.contains(".")
  let allows_comma = self.word_chars.contains(",")
  let allows_dash = self.word_chars.contains("-")
  let mut digits = 0
  let mut separators = 0
  let mut separator_at = -1
  let mut index = 0
  while index < chars.length() {
    let c = chars[index]
    if is_digit_char(c) {
      digits = digits + 1
    } else if (c == '.' && allows_dot) ||
      (c == ',' && allows_comma) ||
      (c == '-' && allows_dash) {
      separators = separators + 1
      separator_at = index
    } else {
      return false
    }
    index = index + 1
  }
  if digits == 0 || separators > 1 {
    return false
  }
  if separators == 1 &&
    (separator_at == 0 || separator_at == chars.length() - 1) {
    return false
  }
  true
}

///|
/// Is `c` an ASCII decimal digit?
fn is_digit_char(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Is `word` itself an entry carrying `FORBIDDENWORD`?
fn Dictionary::is_forbidden_word(self : Dictionary, word : String) -> Bool {
  for flags in self.homonyms(word) {
    if has_flag(self.forbiddenword, flags) {
      return true
    }
  }
  false
}

///|
/// How a lookup treats case, which decides whether a `KEEPCASE` entry may match.
priv enum MatchCase {
  /// The word exactly as the user typed it: a `KEEPCASE` entry matches.
  Exact
  /// A case-folded form the user did not type: a `KEEPCASE` entry never matches.
  Folded
  /// A case-folded form of an all-caps word under `CHECKSHARPS`: a `KEEPCASE`
  /// entry whose word contains `ß` matches anyway, because its uppercased form
  /// is allowed to spell the sharp s as `SS`.
  SharpsFolded
}

///|
/// Does `KEEPCASE` on this entry forbid a match in `mode`?
///
/// `entry` is the dictionary word the flags belong to, so the `CHECKSHARPS`
/// exception in `SharpsFolded` mode can be limited to entries that really
/// contain a sharp s.
fn keepcase_blocks(
  mode : MatchCase,
  entry : String,
  keepcase : String?,
  flags : Array[String],
) -> Bool {
  if !has_flag(keepcase, flags) {
    return false
  }
  match mode {
    Exact => false
    Folded => true
    SharpsFolded => !contains_sharp_s(entry)
  }
}

///|
/// Does `text` contain a German sharp s (`ß`)?
fn contains_sharp_s(text : String) -> Bool {
  for c in text {
    if c == 'ß' {
      return true
    }
  }
  false
}

///|
/// Accept an all-caps word whose dictionary form contains `ß`.
///
/// Under `CHECKSHARPS` the uppercase spelling of `ß` is `SS`, so
/// `PROZESSIONSSTRASSE` must find `Prozessionsstraße` and `MÜSSIG` must find
/// `müßig`. Each non-empty subset of the non-overlapping `ss` pairs of the
/// folded word is rewritten to `ß` and looked up; the rewrite is what marks the
/// lookup as `SharpsFolded`, so only these candidates may bypass `KEEPCASE`.
/// A capital sharp s (`ẞ`, U+1E9E) needs no rewriting: it lower-cases to `ß`
/// through the ordinary folding above.
fn Dictionary::sharps_hit(self : Dictionary, word : String) -> Bool {
  if !self.check_sharps {
    return false
  }
  for base in [lower_word(word), capitalise_word(word)] {
    for candidate in sharp_s_variants(base) {
      if self.lookup_word(candidate, SharpsFolded) {
        return true
      }
    }
  }
  false
}

///|
/// Every string obtained from `base` by replacing a non-empty subset of its
/// non-overlapping `ss` pairs with `ß`.
///
/// `"strasse"` yields `["straße"]`; `"aussenmasse"` yields three candidates,
/// only one of which (`außenmaße`) is a real word. The search is therefore
/// exhaustive but bounded: a word with more than ten `ss` pairs is left alone.
fn sharp_s_variants(base : String) -> Array[String] {
  let chars = base.to_array()
  let positions : Array[Int] = []
  let mut index = 0
  while index + 1 < chars.length() {
    if chars[index] == 's' && chars[index + 1] == 's' {
      positions.push(index)
      index = index + 2
    } else {
      index = index + 1
    }
  }
  let variants : Array[String] = []
  if positions.length() == 0 || positions.length() > 10 {
    return variants
  }
  let mut total = 1
  let mut power = 0
  while power < positions.length() {
    total = total * 2
    power = power + 1
  }
  let mut mask = 1
  while mask < total {
    let buffer = StringBuilder()
    let mut cursor = 0
    let mut chosen = 0
    while cursor < chars.length() {
      if chosen < positions.length() && cursor == positions[chosen] {
        if ((mask >> chosen) & 1) == 1 {
          buffer.write_char('ß')
        } else {
          buffer.write_char('s')
          buffer.write_char('s')
        }
        cursor = cursor + 2
        chosen = chosen + 1
      } else {
        buffer.write_char(chars[cursor])
        cursor = cursor + 1
      }
    }
    variants.push(buffer.to_string())
    mask = mask + 1
  }
  variants
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
/// `mode` says how the word was cased. Folding a word to a different case must
/// not make a `KEEPCASE` entry match, so folded lookups pass `Folded` (or
/// `SharpsFolded`, which only relaxes `KEEPCASE` for `ß` entries).
fn Dictionary::lookup_word(
  self : Dictionary,
  word : String,
  mode : MatchCase,
) -> Bool {
  self.direct_hit(word, mode) || self.affix_hit(word, mode)
}

///|
/// Every flag vector stored for `word`, one per `.dic` occurrence.
fn Dictionary::homonyms(
  self : Dictionary,
  word : String,
) -> Array[Array[String]] {
  match self.entries.get(word) {
    None => []
    Some(homonyms) => homonyms
  }
}

///|
/// Is `word` itself a dictionary entry that may be used on its own?
///
/// A `FORBIDDENWORD` homonym forbids the whole word; otherwise any homonym that
/// is not `NEEDAFFIX`/`ONLYINCOMPOUND` and whose case is allowed accepts it.
fn Dictionary::direct_hit(
  self : Dictionary,
  word : String,
  mode : MatchCase,
) -> Bool {
  if self.is_forbidden_word(word) {
    return false
  }
  for flags in self.homonyms(word) {
    if !has_flag(self.needaffix, flags) &&
      !has_flag(self.onlyincompound, flags) &&
      !keepcase_blocks(mode, word, self.keepcase, flags) {
      return true
    }
  }
  false
}

///|
/// Could `word` be produced from a dictionary stem by applying affixes?
///
/// The paths tried are, in order: one suffix; one prefix; a prefix and a suffix
/// on the same stem; two suffixes; and a prefix plus two suffixes. Twofold
/// suffix stripping is what a rule's continuation flags (`SFX A 0 s/123 .`)
/// make possible: the inner suffix hands the derived form the flags the outer
/// one needs.
fn Dictionary::affix_hit(
  self : Dictionary,
  word : String,
  mode : MatchCase,
) -> Bool {
  for rule in self.suffix_rules {
    if self.derives_suffix(rule, word, mode) {
      return true
    }
  }
  for rule in self.prefix_rules {
    if self.derives_prefix(rule, word, mode) {
      return true
    }
  }
  for prefix_rule in self.prefix_rules {
    if prefix_rule.rule.cross_product {
      for suffix_rule in self.suffix_rules {
        if suffix_rule.rule.cross_product &&
          self.derives_cross(prefix_rule, suffix_rule, word, mode) {
          return true
        }
      }
    }
  }
  for outer in self.suffix_rules {
    if self.derives_two_suffixes(outer, word, mode) {
      return true
    }
  }
  for prefix_rule in self.prefix_rules {
    if prefix_rule.rule.cross_product {
      for outer in self.suffix_rules {
        if outer.rule.cross_product &&
          self.derives_prefix_two_suffixes(prefix_rule, outer, word, mode) {
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
  rule : SpellRule,
  word : String,
  mode : MatchCase,
) -> Bool {
  let rest = match word.strip_suffix(normalise_affix(rule.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let stem = rest + normalise_affix(rule.rule.strip)
  if !self.stem_is_usable(stem, rule.rule.flag, mode) {
    return false
  }
  let applied : Array[Array[String]] = [rule.cont_flags]
  if !self.derived_standalone(applied) {
    return false
  }
  match @affix.apply_rule(rule.rule, stem) {
    Some(produced) => produced == word
    None => false
  }
}

///|
/// Can `rule` (a prefix rule) have produced `word`?
fn Dictionary::derives_prefix(
  self : Dictionary,
  rule : SpellRule,
  word : String,
  mode : MatchCase,
) -> Bool {
  let rest = match word.strip_prefix(normalise_affix(rule.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let stem = normalise_affix(rule.rule.strip) + rest
  if !self.stem_is_usable(stem, rule.rule.flag, mode) {
    return false
  }
  let applied : Array[Array[String]] = [rule.cont_flags]
  if !self.derived_standalone(applied) {
    return false
  }
  match @affix.apply_rule(rule.rule, stem) {
    Some(produced) => produced == word
    None => false
  }
}

///|
/// Can `rule` (a suffix rule) have produced `mid` from a dictionary stem by
/// chaining a second suffix `outer` whose flag `rule` supplies?
///
/// `inner` has to carry `outer`'s flag in its continuation flags (or the stem
/// itself has to carry it), and the reconstructed form is verified by applying
/// both rules again.
fn Dictionary::derives_two_suffixes(
  self : Dictionary,
  outer : SpellRule,
  word : String,
  mode : MatchCase,
) -> Bool {
  let mid = match word.strip_suffix(normalise_affix(outer.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  for inner in self.suffix_rules {
    let rest = match mid.strip_suffix(normalise_affix(inner.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = rest + normalise_affix(inner.rule.strip)
    if !self.stem_is_usable(stem, inner.rule.flag, mode) {
      continue
    }
    if !self.flag_on_derived(stem, outer.rule.flag, inner.cont_flags) {
      continue
    }
    // `inner` is applied first, then `outer`.
    if !self.derived_standalone([inner.cont_flags, outer.cont_flags]) {
      continue
    }
    let produced_mid = match @affix.apply_rule(inner.rule, stem) {
      Some(produced) => produced
      None => continue
    }
    if produced_mid != mid {
      continue
    }
    match @affix.apply_rule(outer.rule, mid) {
      Some(produced) => if produced == word { return true }
      None => ()
    }
  }
  false
}

///|
/// Can `prefix_rule` have produced `word` from a form that two suffixes built
/// from a dictionary stem?
///
/// `word = prefix.add + stem + inner.add + outer.add`, and the prefix's flag
/// has to be available on the form it was attached to: on the stem itself or in
/// either suffix's continuation flags.
fn Dictionary::derives_prefix_two_suffixes(
  self : Dictionary,
  prefix_rule : SpellRule,
  outer : SpellRule,
  word : String,
  mode : MatchCase,
) -> Bool {
  let suffixed = match
    word.strip_prefix(normalise_affix(prefix_rule.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let mid = match suffixed.strip_suffix(normalise_affix(outer.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  for inner in self.suffix_rules {
    let rest = match mid.strip_suffix(normalise_affix(inner.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = rest + normalise_affix(inner.rule.strip)
    if !self.stem_is_usable(stem, inner.rule.flag, mode) {
      continue
    }
    if !self.flag_on_derived(stem, outer.rule.flag, inner.cont_flags) {
      continue
    }
    let prefix_ok = self.entry_has_flag(stem, prefix_rule.rule.flag) ||
      inner.cont_flags.contains(prefix_rule.rule.flag) ||
      outer.cont_flags.contains(prefix_rule.rule.flag)
    if !prefix_ok {
      continue
    }
    // The prefix may be applied first, between the two suffixes, or last; the
    // `NEEDAFFIX` state of the derived form depends on that order.
    let order_ok = self.derived_standalone([
        prefix_rule.cont_flags,
        inner.cont_flags,
        outer.cont_flags,
      ]) ||
      self.derived_standalone([
        inner.cont_flags,
        prefix_rule.cont_flags,
        outer.cont_flags,
      ]) ||
      self.derived_standalone([
        inner.cont_flags,
        outer.cont_flags,
        prefix_rule.cont_flags,
      ])
    if !order_ok {
      continue
    }
    let produced_mid = match @affix.apply_rule(inner.rule, stem) {
      Some(produced) => produced
      None => continue
    }
    if produced_mid != mid {
      continue
    }
    let produced_suffixed = match @affix.apply_rule(outer.rule, mid) {
      Some(produced) => produced
      None => continue
    }
    if produced_suffixed != suffixed {
      continue
    }
    match @affix.apply_rule(prefix_rule.rule, suffixed) {
      Some(produced) => if produced == word { return true }
      None => ()
    }
  }
  false
}

///|
/// Is `flag` available on the form built from dictionary entry `stem` plus the
/// rules whose continuation flags are `cont_flags`?
fn Dictionary::flag_on_derived(
  self : Dictionary,
  stem : String,
  flag : String,
  cont_flags : Array[String],
) -> Bool {
  self.entry_has_flag(stem, flag) || cont_flags.contains(flag)
}

///|
/// Does the dictionary entry `word` carry `flag`?
fn Dictionary::entry_has_flag(
  self : Dictionary,
  word : String,
  flag : String,
) -> Bool {
  for flags in self.homonyms(word) {
    if flags.contains(flag) {
      return true
    }
  }
  false
}

///|
/// Can the cross product of `prefix_rule` and `suffix_rule` have produced
/// `word`?
///
/// Hunspell applies both rules to the *same* stem and puts the additions on the
/// outside, so `word = prefix.add + core + suffix.add` where `core` is the stem
/// with both strips removed. The stem is reconstructed, checked for both flags
/// and both conditions, and then the combination is re-built as a guard against
/// a wrong reconstruction. The prefix's flag may also come from the suffix's
/// continuation flags, which is how `undrinkable` works when `un-` is licensed
/// by `-able`.
fn Dictionary::derives_cross(
  self : Dictionary,
  prefix_rule : SpellRule,
  suffix_rule : SpellRule,
  word : String,
  mode : MatchCase,
) -> Bool {
  let after_prefix = match
    word.strip_prefix(normalise_affix(prefix_rule.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let core = match
    after_prefix.strip_suffix(normalise_affix(suffix_rule.rule.add)) {
    Some(view) => view.to_owned()
    None => return false
  }
  let stem = normalise_affix(prefix_rule.rule.strip) +
    core +
    normalise_affix(suffix_rule.rule.strip)
  if self.is_forbidden_word(stem) {
    return false
  }
  if !@affix.matches_condition(prefix_rule.rule.condition, stem, @aff.Prefix) {
    return false
  }
  if !@affix.matches_condition(suffix_rule.rule.condition, stem, @aff.Suffix) {
    return false
  }
  if reconstruct_cross(prefix_rule.rule, suffix_rule.rule, stem) != Some(word) {
    return false
  }
  // Either rule may be applied first. Applying the suffix first needs the
  // suffix's flag on the stem and the prefix's flag on the stem or in the
  // suffix's continuation flags; applying the prefix first is the mirror image.
  for flags in self.homonyms(stem) {
    if has_flag(self.onlyincompound, flags) {
      continue
    }
    if keepcase_blocks(mode, stem, self.keepcase, flags) {
      continue
    }
    let suffix_first = flags.contains(suffix_rule.rule.flag) &&
      self.flag_on_derived(stem, prefix_rule.rule.flag, suffix_rule.cont_flags)
    let prefix_first = flags.contains(prefix_rule.rule.flag) &&
      self.flag_on_derived(stem, suffix_rule.rule.flag, prefix_rule.cont_flags)
    let suffix_first_ok = suffix_first &&
      self.derived_standalone([suffix_rule.cont_flags, prefix_rule.cont_flags])
    let prefix_first_ok = prefix_first &&
      self.derived_standalone([prefix_rule.cont_flags, suffix_rule.cont_flags])
    if suffix_first_ok || prefix_first_ok {
      return true
    }
  }
  false
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
/// Can a form built by applying rules whose continuation flags are `rules` (in
/// application order) stand alone as a word?
///
/// Two continuation flags change the answer:
///
/// * `ONLYINCOMPOUND` anywhere in the chain means the form only ever occurs
///   inside a compound, so it is never a standalone word.
/// * `NEEDAFFIX` makes the form a virtual stem: the next affix completes it
///   again, so the *last* rule applied must not hand out `NEEDAFFIX`.
fn Dictionary::derived_standalone(
  self : Dictionary,
  rules : Array[Array[String]],
) -> Bool {
  let mut pending = false
  for cont_flags in rules {
    if has_flag(self.onlyincompound, cont_flags) {
      return false
    }
    if pending {
      pending = false
    }
    if has_flag(self.needaffix, cont_flags) {
      pending = true
    }
  }
  !pending
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
  mode : MatchCase,
) -> Bool {
  if self.is_forbidden_word(stem) {
    return false
  }
  for flags in self.homonyms(stem) {
    if flags.contains(flag) &&
      !has_flag(self.onlyincompound, flags) &&
      !keepcase_blocks(mode, stem, self.keepcase, flags) {
      return true
    }
  }
  false
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
/// Accept a word that splits into two dictionary words, each at least
/// `COMPOUNDMIN` characters long.
///
/// The first part must carry `COMPOUNDFLAG` or `COMPOUNDBEGIN`, the last must
/// carry `COMPOUNDFLAG` or `COMPOUNDEND`. This is the two-part case only:
/// compounds of three or more parts, `COMPOUNDMIDDLE`, affixed parts and
/// `CHECKCOMPOUNDPATTERN` are not handled.
fn Dictionary::check_compound(
  self : Dictionary,
  word : String,
  mode : MatchCase,
) -> Bool {
  if self.compound_flag is None &&
    self.compound_begin is None &&
    self.compound_end is None {
    return false
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
    let left_ok = self.compound_part_is_usable(left, self.compound_flag, mode) ||
      self.compound_part_is_usable(left, self.compound_begin, mode)
    let right_ok = self.compound_part_is_usable(right, self.compound_flag, mode) ||
      self.compound_part_is_usable(right, self.compound_end, mode)
    if left_ok && right_ok {
      return true
    }
    split = split + 1
  }
  false
}

///|
/// May `part` stand as one half of a compound under `flag` (which may be
/// absent)?
///
/// A `KEEPCASE` part is only usable in an exact-case lookup: `TV-word` is wrong
/// even though `tv-` and `word` form a compound.
fn Dictionary::compound_part_is_usable(
  self : Dictionary,
  part : String,
  flag : String?,
  mode : MatchCase,
) -> Bool {
  let wanted = match flag {
    None => return false
    Some(flag) => flag
  }
  if self.is_forbidden_word(part) {
    return false
  }
  for flags in self.homonyms(part) {
    if flags.contains(wanted) &&
      !has_flag(self.needaffix, flags) &&
      !keepcase_blocks(mode, part, self.keepcase, flags) {
      return true
    }
  }
  false
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
