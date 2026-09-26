// Phonetic transcription (`PHONE`) and the phonetic suggestion index.
//
// `PHONE n` / `PHONE pattern replacement` declares a table-driven phonetic
// transcription, borrowed by Hunspell from Aspell. The rule mini-language is
// documented in the `hunspell(5)` manual (which points at Aspell's "Phonetic
// Code" chapter). This file is an independent implementation of that documented
// behaviour; no Hunspell (LGPL-2.1) source code was consulted or copied. This
// project is Apache-2.0.
//
// The documented semantics, and how each is implemented here:
//
// * Rules are tried in table order and the first match at the current position
//   wins ("the higher the rule the higher the priority ... the first rule that
//   matches is applied").
// * A pattern is `letters` + an optional `(class)` (exactly one of those
//   characters) + optional control characters, which must occur in the order
//   `<` `-`* digit `^` `$`.
// * Leading dashes: the match is the whole pattern but only the part before the
//   dashes is replaced; the retained tail is scanned again (`TCH--` -> `_`
//   deletes only the `T`, then `CH` is transformed on its own).
// * `<`: after the replacement the search continues *with the replacement text*
//   rather than with the next character of the word.
// * A digit sets the rule priority (default 5); it matters when a `<` rule's
//   replacement is re-scanned.
// * `^` anchors the match to the start of the word; `$` to its end; `^^`
//   processes the rest of the word separately (this implementation re-scans
//   from the end of the match, the same as for a plain `^`).
// * A character no rule matches is dropped from the key.
// * `_` as the replacement means "output nothing".
//
// The transcription is applied to the upper-cased word, exactly as the manual's
// example table (all upper-case patterns) requires.

///|
/// One parsed `PHONE` rule. This is an implementation detail of the index
/// (`Dictionary` is opaque), so a caller never constructs one.
pub struct PhonetRule {
  base : Array[Char]
  class_chars : Array[Char]
  has_class : Bool
  dashes : Int
  follow : Bool
  start_anchor : Bool
  end_anchor : Bool
  priority : Int
  replacement : String
}

///|
/// The phonetic table of a dictionary: the rules grouped by their first
/// character (so a lookup at one position only tests plausible rules) and the
/// key -> words index built once at load time.
pub struct PhonetTable {
  by_initial : Map[Char, Array[PhonetRule]]
  index : Map[String, Array[String]]
}

///|
/// An empty table, used when the `.aff` file has no `PHONE` rules.
fn empty_phonet_table() -> PhonetTable {
  { by_initial: Map([]), index: Map([]), }
}

///|
/// Is `c` one of the characters that ends the literal part of a `PHONE`
/// pattern?
fn is_phonet_control(c : Char) -> Bool {
  c == '(' ||
  c == ')' ||
  c == '<' ||
  c == '-' ||
  c == '^' ||
  c == '$' ||
  (c >= '0' && c <= '9')
}

///|
/// Parse one `PHONE` pattern line. Returns `None` for a pattern this
/// implementation does not understand, so one odd line cannot break the table.
fn parse_phonet_rule(raw : @aff.PhoneRule) -> PhonetRule? {
  let chars = raw.pattern.to_array()
  let base : Array[Char] = []
  let mut index = 0
  while index < chars.length() && !is_phonet_control(chars[index]) {
    base.push(chars[index])
    index = index + 1
  }
  if base.is_empty() {
    return None
  }
  let class_chars : Array[Char] = []
  let mut has_class = false
  if index < chars.length() && chars[index] == '(' {
    has_class = true
    index = index + 1
    while index < chars.length() && chars[index] != ')' {
      class_chars.push(chars[index])
      index = index + 1
    }
    if index >= chars.length() || class_chars.is_empty() {
      return None
    }
    index = index + 1
  }
  let mut follow = false
  let mut dashes = 0
  let mut priority = 5
  let mut start_anchor = false
  let mut end_anchor = false
  if index < chars.length() && chars[index] == '<' {
    follow = true
    index = index + 1
  }
  while index < chars.length() && chars[index] == '-' {
    dashes = dashes + 1
    index = index + 1
  }
  if index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
    priority = chars[index].to_int() - '0'.to_int()
    index = index + 1
  }
  if index < chars.length() && chars[index] == '^' {
    start_anchor = true
    index = index + 1
    if index < chars.length() && chars[index] == '^' {
      index = index + 1
    }
  }
  if index < chars.length() && chars[index] == '$' {
    end_anchor = true
    index = index + 1
  }
  if index != chars.length() {
    return None
  }
  let replacement = if raw.replacement == "_" { "" } else { raw.replacement }
  Some({
    base,
    class_chars,
    has_class,
    dashes,
    follow,
    start_anchor,
    end_anchor,
    priority,
    replacement,
  })
}

///|
/// How many characters of the buffer a rule consumes when it matches (the
/// literal part plus one for a `(class)`).
fn PhonetRule::full_length(self : PhonetRule) -> Int {
  self.base.length() + (if self.has_class { 1 } else { 0 })
}

///|
/// Does this rule match `buffer` at `position`?
fn PhonetRule::matches(
  self : PhonetRule,
  buffer : Array[Char],
  position : Int,
) -> Bool {
  let full = self.full_length()
  if position + full > buffer.length() {
    return false
  }
  if self.start_anchor && position != 0 {
    return false
  }
  if self.end_anchor && position + full != buffer.length() {
    return false
  }
  let mut offset = 0
  while offset < self.base.length() {
    if buffer[position + offset] != self.base[offset] {
      return false
    }
    offset = offset + 1
  }
  if self.has_class && !self.class_chars.contains(buffer[position + offset]) {
    return false
  }
  true
}

///|
/// Parse every `PHONE` line, dropping the ones this implementation cannot read.
fn parse_phonet_rules(raws : Array[@aff.PhoneRule]) -> Array[PhonetRule] {
  let rules : Array[PhonetRule] = []
  for raw in raws {
    match parse_phonet_rule(raw) {
      Some(rule) => rules.push(rule)
      None => ()
    }
  }
  rules
}

///|
/// Group rules by their first character, keeping table order inside a group.
fn group_phonet_rules(
  rules : Array[PhonetRule],
) -> Map[Char, Array[PhonetRule]] {
  let by_initial : Map[Char, Array[PhonetRule]] = Map([])
  for rule in rules {
    let initial = rule.base[0]
    match by_initial.get(initial) {
      Some(group) => group.push(rule)
      None => by_initial[initial] = [rule]
    }
  }
  by_initial
}

///|
/// `buffer` with `[start, start + length)` replaced by `replacement`.
fn splice_chars(
  buffer : Array[Char],
  start : Int,
  length : Int,
  replacement : String,
) -> Array[Char] {
  let out : Array[Char] = []
  let mut index = 0
  while index < start && index < buffer.length() {
    out.push(buffer[index])
    index = index + 1
  }
  for c in replacement {
    out.push(c)
  }
  index = start + length
  if index < 0 {
    index = 0
  }
  while index < buffer.length() {
    out.push(buffer[index])
    index = index + 1
  }
  out
}

///|
/// The phonetic key of `word` under `by_initial`.
///
/// The word is upper-cased first; a character no rule matches is dropped. The
/// per-character work is bounded so that a self-reproducing `<` rule cannot loop
/// forever.
fn phonet_key_of(
  by_initial : Map[Char, Array[PhonetRule]],
  word : String,
) -> String {
  if by_initial.is_empty() || word.is_empty() {
    return ""
  }
  let mut buffer = uppercase_ascii(word).to_array()
  let out = StringBuilder()
  let mut position = 0
  let mut steps = 0
  let limit = buffer.length() * 8 + 64
  while position < buffer.length() && steps < limit {
    steps = steps + 1
    let candidates : Array[PhonetRule] = match
      by_initial.get(buffer[position]) {
      Some(group) => group
      None => []
    }
    let mut matched : PhonetRule? = None
    for rule in candidates {
      if rule.matches(buffer, position) {
        matched = Some(rule)
        break
      }
    }
    match matched {
      None => position = position + 1
      Some(rule) =>
        if rule.follow || rule.dashes > 0 {
          let keep = if rule.follow {
            rule.full_length()
          } else {
            rule.full_length() - rule.dashes
          }
          buffer = splice_chars(buffer, position, keep, rule.replacement)
        } else {
          out.write_string(rule.replacement)
          position = position + rule.full_length()
        }
    }
  }
  out.to_string()
}

///|
/// Build the phonetic index: every dictionary word keyed by its phonetic key.
///
/// A `.dic` entry with a `ph:` field is indexed under that field instead of the
/// computed transcription (`xxxxxxxxxx ph:Brasilia` is pronounced like
/// `Brasilia`), which is how the manual describes the field.
fn build_phonetic_table(
  entries : Array[@dic.DicEntry],
  ignored : Array[Char],
  raws : Array[@aff.PhoneRule],
) -> PhonetTable {
  let rules = parse_phonet_rules(raws)
  if rules.is_empty() {
    return empty_phonet_table()
  }
  let by_initial = group_phonet_rules(rules)
  let index : Map[String, Array[String]] = Map([])
  for entry in entries {
    let word = remove_ignored(entry.word, ignored)
    let keys : Array[String] = []
    for field in entry.morph {
      match field.strip_prefix("ph:") {
        Some(value) => if !value.is_empty() { keys.push(value.to_owned()) }
        None => ()
      }
    }
    if keys.is_empty() {
      keys.push(word)
    }
    for key in keys {
      let phonetic = phonet_key_of(by_initial, key)
      if phonetic.is_empty() {
        continue
      }
      match index.get(phonetic) {
        Some(words) => if !words.contains(word) { words.push(word) }
        None => index[phonetic] = [word]
      }
    }
  }
  { by_initial, index, }
}

///|
/// The phonetic key of `word` under the dictionary's `PHONE` table, or `""`
/// when the table is absent (no `PHONE` line in the `.aff` file).
pub fn Dictionary::phonetic_key(self : Dictionary, word : String) -> String {
  phonet_key_of(self.phonet.by_initial, word)
}

///|
/// The dictionary words whose phonetic key equals that of `word`, in dictionary
/// order. Empty when the `.aff` file has no `PHONE` table.
pub fn Dictionary::phonetic_words(
  self : Dictionary,
  word : String,
) -> Array[String] {
  let key = self.phonetic_key(word)
  if key.is_empty() {
    return []
  }
  match self.phonet.index.get(key) {
    Some(words) => words
    None => []
  }
}
