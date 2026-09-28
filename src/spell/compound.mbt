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

// ---------------------------------------------------------------------------
// General compounding: `COMPOUNDFLAG` / `COMPOUNDBEGIN` / `COMPOUNDMIDDLE` /
// `COMPOUNDEND` with affixed parts, `COMPOUNDPERMITFLAG`,
// `COMPOUNDFORBIDFLAG`, `CHECKCOMPOUNDPATTERN`, `CHECKCOMPOUNDDUP`,
// `CHECKCOMPOUNDTRIPLE`, `SIMPLIFIEDTRIPLE`, `CHECKCOMPOUNDCASE`,
// `COMPOUNDWORDMAX`, `FORCEUCASE` and `COMPOUNDSYLLABLE`.
//
// Clean-room implementation of the behaviour documented in the Hunspell
// manual; no Hunspell source code was consulted or copied.

///|
/// The position a compound part occupies, which decides the flag it needs.
priv enum CpdRole {
  First
  Middle
  Last
} derive(Eq)

///|
/// One parsed `CHECKCOMPOUNDPATTERN` line.
///
/// `end_chars`/`begin_chars` are the literal boundary text (`""` matches
/// anything); `zero_end` is the manual's special `0` pattern, which limits the
/// rule to unmodified stems. `replacement` is the optional simplified form.
priv struct CpdPattern {
  end_chars : String
  end_flag : String?
  begin_chars : String
  begin_flag : String?
  replacement : String?
  zero_end : Bool
}

///|
/// How a `CHECKCOMPOUNDPATTERN` rule reacts to one boundary.
priv enum CpdBoundary {
  /// The rule does not apply.
  NoMatch
  /// The rule forbids the plain join.
  Forbid
  /// The rule forbids the plain join but allows the replacement form.
  Replace
}

///|
/// Split one `endchars[/flag]` field of a `CHECKCOMPOUNDPATTERN` line.
fn split_pattern_field(token : String) -> (String, String?) {
  let body = StringBuilder()
  let flag = StringBuilder()
  let mut in_flag = false
  for c in token {
    if in_flag {
      flag.write_char(c)
    } else if c == '/' {
      in_flag = true
    } else {
      body.write_char(c)
    }
  }
  (body.to_string(), if in_flag { Some(flag.to_string()) } else { None })
}

///|
/// Parse a `CHECKCOMPOUNDPATTERN` line (the three fields joined by spaces).
fn parse_compound_pattern(text : String) -> CpdPattern {
  let fields : Array[String] = []
  let buffer = StringBuilder()
  let mut pending = false
  for c in text {
    if c.is_whitespace() {
      if pending {
        fields.push(buffer.to_string())
        buffer.reset()
        pending = false
      }
    } else {
      buffer.write_char(c)
      pending = true
    }
  }
  if pending {
    fields.push(buffer.to_string())
  }
  let end_field = if fields.length() > 0 { fields[0] } else { "" }
  let begin_field = if fields.length() > 1 { fields[1] } else { "" }
  let (end_raw, end_flag) = split_pattern_field(end_field)
  let (begin_chars, begin_flag) = split_pattern_field(begin_field)
  let replacement = if fields.length() > 2 {
    Some(apply_compound_underscore(fields[2]))
  } else {
    None
  }
  // The manual reserves the `0` endchars pattern for "unmodified stems".
  let zero_end = end_raw == "0"
  {
    end_chars: if zero_end {
      ""
    } else {
      end_raw
    },
    end_flag,
    begin_chars,
    begin_flag,
    replacement,
    zero_end,
  }
}

///|
/// `_` in a `CHECKCOMPOUNDPATTERN` replacement stands for a space (as in `REP`).
fn apply_compound_underscore(text : String) -> String {
  let buffer = StringBuilder()
  for c in text {
    if c == '_' {
      buffer.write_char(' ')
    } else {
      buffer.write_char(c)
    }
  }
  buffer.to_string()
}

///|
/// The compound flags that licence a part in `role`: `COMPOUNDFLAG` always, plus
/// the position-specific flag.
fn Dictionary::role_flags(self : Dictionary, role : CpdRole) -> Array[String?] {
  let flags : Array[String?] = match role {
    First => [self.compound_flag, self.compound_begin]
    Middle => [self.compound_flag, self.compound_middle]
    Last => [self.compound_flag, self.compound_end]
  }
  flags
}

///|
/// Does `flags` carry a flag that licences `role`?
fn Dictionary::flags_have_role(
  self : Dictionary,
  flags : Array[String],
  role : CpdRole,
) -> Bool {
  for flag in self.role_flags(role) {
    if has_flag(flag, flags) {
      return true
    }
  }
  false
}

///|
/// May `part` stand as one part of an ordinary compound in `role`? Either it is
/// a plain dictionary entry, or an affixed form of one.
fn Dictionary::compound_part_ok(
  self : Dictionary,
  part : String,
  role : CpdRole,
  mode : MatchCase,
) -> Bool {
  if self.is_forbidden_word(part) {
    return false
  }
  // `COMPOUNDFORBIDFLAG` on a dictionary word removes that *spelling* from the
  // first and middle positions, even when another homonym could also be derived
  // by an affix.
  if role != Last && has_flag(self.compound_forbid, self.flags_of_word(part)) {
    return false
  }
  if self.plain_compound_part_ok(part, role, mode) {
    return true
  }
  self.affixed_compound_part_ok(part, role, mode)
}

///|
/// A plain dictionary entry used as a compound part.
fn Dictionary::plain_compound_part_ok(
  self : Dictionary,
  part : String,
  role : CpdRole,
  mode : MatchCase,
) -> Bool {
  for flags in self.homonyms(part) {
    if has_flag(self.needaffix, flags) {
      continue
    }
    if keepcase_blocks(mode, part, self.keepcase, flags) {
      continue
    }
    // A plain word carrying COMPOUNDFORBIDFLAG is removed from the first and
    // middle positions (it may still be the last part).
    if role != Last && has_flag(self.compound_forbid, flags) {
      continue
    }
    if self.flags_have_role(flags, role) {
      return true
    }
  }
  false
}

///|
/// Is `stem` a dictionary entry carrying `flag` that may take an affix inside a
/// compound? `ONLYINCOMPOUND` and `NEEDAFFIX` are allowed here: this *is* the
/// inside of a compound, and a virtual stem is completed by the affix.
fn Dictionary::compound_stem_ok(
  self : Dictionary,
  stem : String,
  flag : String,
  mode : MatchCase,
) -> Bool {
  for flags in self.homonyms(stem) {
    if flags.contains(flag) &&
      !keepcase_blocks(mode, stem, self.keepcase, flags) {
      return true
    }
  }
  false
}

///|
/// May an affix with these continuation flags appear on a compound part in
/// `role`?
///
/// `COMPOUNDFORBIDFLAG` forbids it outright. An affix at its natural edge
/// (prefix on the first part, suffix on the last) needs nothing else, but an
/// affix "inside" the compound needs `COMPOUNDPERMITFLAG`. A suffix whose
/// continuation class carries `ONLYINCOMPOUND` is a Fuge-element: it must be
/// followed by another part, so it can never sit on the last part.
fn Dictionary::compound_affix_allowed(
  self : Dictionary,
  cont_flags : Array[String],
  role : CpdRole,
  is_suffix : Bool,
  check_fuge : Bool,
) -> Bool {
  if has_flag(self.compound_forbid, cont_flags) {
    return false
  }
  if check_fuge &&
    is_suffix &&
    role == Last &&
    has_flag(self.onlyincompound, cont_flags) {
    return false
  }
  let at_edge = if is_suffix { role == Last } else { role == First }
  if !at_edge && !has_flag(self.compound_permit, cont_flags) {
    return false
  }
  true
}

///|
/// Does a form built from `stem` plus these affix continuation classes carry a
/// flag that licences `role`? Either the stem itself carries it, or one of the
/// affixes hands it out (`compoundaffix2`'s permit flag is separate).
fn Dictionary::compound_role_from(
  self : Dictionary,
  stem : String,
  cont_flags : Array[Array[String]],
  role : CpdRole,
) -> Bool {
  for flags in self.homonyms(stem) {
    if self.flags_have_role(flags, role) {
      return true
    }
  }
  for cont in cont_flags {
    if self.flags_have_role(cont, role) {
      return true
    }
  }
  false
}

///|
/// Is a chain of affix continuation classes a complete surface form? The last
/// affix applied must not hand out `NEEDAFFIX`; `ONLYINCOMPOUND` is fine because
/// the form is used inside a compound.
fn Dictionary::compound_chain_ok(
  self : Dictionary,
  cont_flags : Array[Array[String]],
) -> Bool {
  let mut pending = false
  for cont in cont_flags {
    if pending {
      pending = false
    }
    if has_flag(self.needaffix, cont) {
      pending = true
    }
  }
  !pending
}

///|
/// Can one affix have produced `part` from a stem that is itself a valid
/// compound-part stem?
fn Dictionary::affixed_compound_part_ok(
  self : Dictionary,
  part : String,
  role : CpdRole,
  mode : MatchCase,
) -> Bool {
  // A single suffix.
  for rule in self.suffix_rules {
    if has_flag(self.circumfix, rule.cont_flags) {
      continue
    }
    let rest = match part.strip_suffix(normalise_affix(rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = rest + normalise_affix(rule.rule.strip)
    if !self.compound_stem_ok(stem, rule.rule.flag, mode) {
      continue
    }
    if !self.compound_affix_allowed(rule.cont_flags, role, true, true) {
      continue
    }
    let conts : Array[Array[String]] = [rule.cont_flags]
    if !self.compound_role_from(stem, conts, role) {
      continue
    }
    if !self.compound_chain_ok(conts) {
      continue
    }
    match @affix.apply_rule(rule.rule, stem) {
      Some(produced) => if produced == part { return true }
      None => ()
    }
  }
  // A single prefix.
  for rule in self.prefix_rules {
    if has_flag(self.circumfix, rule.cont_flags) {
      continue
    }
    let rest = match part.strip_prefix(normalise_affix(rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = normalise_affix(rule.rule.strip) + rest
    if !self.compound_stem_ok(stem, rule.rule.flag, mode) {
      continue
    }
    if !self.compound_affix_allowed(rule.cont_flags, role, false, true) {
      continue
    }
    let conts : Array[Array[String]] = [rule.cont_flags]
    if !self.compound_role_from(stem, conts, role) {
      continue
    }
    if !self.compound_chain_ok(conts) {
      continue
    }
    match @affix.apply_rule(rule.rule, stem) {
      Some(produced) => if produced == part { return true }
      None => ()
    }
  }
  // A prefix and a suffix on the same stem.
  for prefix_rule in self.prefix_rules {
    if !prefix_rule.rule.cross_product {
      continue
    }
    let after_prefix = match
      part.strip_prefix(normalise_affix(prefix_rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    for suffix_rule in self.suffix_rules {
      if !suffix_rule.rule.cross_product {
        continue
      }
      let core = match
        after_prefix.strip_suffix(normalise_affix(suffix_rule.rule.add)) {
        Some(view) => view.to_owned()
        None => continue
      }
      let stem = normalise_affix(prefix_rule.rule.strip) +
        core +
        normalise_affix(suffix_rule.rule.strip)
      if self.is_forbidden_word(stem) {
        continue
      }
      if !@affix.matches_condition(
          prefix_rule.rule.condition,
          stem,
          @aff.Prefix,
        ) {
        continue
      }
      if !@affix.matches_condition(
          suffix_rule.rule.condition,
          stem,
          @aff.Suffix,
        ) {
        continue
      }
      if reconstruct_cross(prefix_rule.rule, suffix_rule.rule, stem) !=
        Some(part) {
        continue
      }
      if !self.circumfix_ok(
          has_flag(self.circumfix, prefix_rule.cont_flags),
          has_flag(self.circumfix, suffix_rule.cont_flags),
        ) {
        continue
      }
      // Mirror `derives_cross`: each rule's flag may come from the stem or from
      // the other rule's continuation class. The German decapitalising prefix
      // gets its flag from the zero suffix's continuation class this way.
      let stem_has_prefix = self.compound_stem_ok(
        stem,
        prefix_rule.rule.flag,
        mode,
      )
      let stem_has_suffix = self.compound_stem_ok(
        stem,
        suffix_rule.rule.flag,
        mode,
      )
      let prefix_first = stem_has_prefix &&
        (
          stem_has_suffix ||
          prefix_rule.cont_flags.contains(suffix_rule.rule.flag)
        )
      let suffix_first = stem_has_suffix &&
        (
          stem_has_prefix ||
          suffix_rule.cont_flags.contains(prefix_rule.rule.flag)
        )
      if !(prefix_first || suffix_first) {
        continue
      }
      if !self.compound_affix_allowed(prefix_rule.cont_flags, role, false, true) {
        continue
      }
      // When a prefix is applied as well, it can be the outermost affix, so the
      // suffix's `ONLYINCOMPOUND` does not force another part to follow.
      if !self.compound_affix_allowed(suffix_rule.cont_flags, role, true, false) {
        continue
      }
      let conts : Array[Array[String]] = [
        prefix_rule.cont_flags,
        suffix_rule.cont_flags,
      ]
      if !self.compound_role_from(stem, conts, role) {
        continue
      }
      if !self.compound_chain_ok(conts) {
        continue
      }
      return true
    }
  }
  false
}

///|
/// Does `part` carry `flag` after being used as a compound part in `role`?
///
/// This is the flag set `CHECKCOMPOUNDPATTERN` tests: the stem's own flags, the
/// affix rules' flags, and their continuation classes (the master corpus has
/// dedicated suites for a pattern flag arriving through an affix continuation
/// class).
fn Dictionary::part_has_pattern_flag(
  self : Dictionary,
  part : String,
  flag : String,
  role : CpdRole,
  mode : MatchCase,
) -> Bool {
  for flags in self.homonyms(part) {
    let usable = !has_flag(self.needaffix, flags) &&
      !keepcase_blocks(mode, part, self.keepcase, flags) &&
      !(role != Last && has_flag(self.compound_forbid, flags))
    if usable && flags.contains(flag) {
      return true
    }
  }
  if self.affixed_pattern_flag(part, flag, mode) {
    return true
  }
  false
}

///|
/// Could an affixed form of `part` carry `flag` for a `CHECKCOMPOUNDPATTERN`
/// test?
fn Dictionary::affixed_pattern_flag(
  self : Dictionary,
  part : String,
  flag : String,
  mode : MatchCase,
) -> Bool {
  for rule in self.suffix_rules {
    let rest = match part.strip_suffix(normalise_affix(rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = rest + normalise_affix(rule.rule.strip)
    if !self.compound_stem_ok(stem, rule.rule.flag, mode) {
      continue
    }
    if rule.rule.flag == flag ||
      rule.cont_flags.contains(flag) ||
      self.entry_has_flag(stem, flag) {
      match @affix.apply_rule(rule.rule, stem) {
        Some(produced) => if produced == part { return true }
        None => ()
      }
    }
  }
  for rule in self.prefix_rules {
    let rest = match part.strip_prefix(normalise_affix(rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = normalise_affix(rule.rule.strip) + rest
    if !self.compound_stem_ok(stem, rule.rule.flag, mode) {
      continue
    }
    if rule.rule.flag == flag ||
      rule.cont_flags.contains(flag) ||
      self.entry_has_flag(stem, flag) {
      match @affix.apply_rule(rule.rule, stem) {
        Some(produced) => if produced == part { return true }
        None => ()
      }
    }
  }
  for prefix_rule in self.prefix_rules {
    if !prefix_rule.rule.cross_product {
      continue
    }
    let after_prefix = match
      part.strip_prefix(normalise_affix(prefix_rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    for suffix_rule in self.suffix_rules {
      if !suffix_rule.rule.cross_product {
        continue
      }
      let core = match
        after_prefix.strip_suffix(normalise_affix(suffix_rule.rule.add)) {
        Some(view) => view.to_owned()
        None => continue
      }
      let stem = normalise_affix(prefix_rule.rule.strip) +
        core +
        normalise_affix(suffix_rule.rule.strip)
      if reconstruct_cross(prefix_rule.rule, suffix_rule.rule, stem) !=
        Some(part) {
        continue
      }
      if prefix_rule.rule.flag == flag ||
        suffix_rule.rule.flag == flag ||
        prefix_rule.cont_flags.contains(flag) ||
        suffix_rule.cont_flags.contains(flag) ||
        self.entry_has_flag(stem, flag) {
        return true
      }
    }
  }
  false
}

///|
/// Apply one `CHECKCOMPOUNDPATTERN` line to the boundary between `left` and
/// `right`.
fn Dictionary::match_compound_pattern(
  self : Dictionary,
  pattern : CpdPattern,
  left : String,
  left_role : CpdRole,
  right : String,
  right_role : CpdRole,
  mode : MatchCase,
) -> CpdBoundary {
  // The optional flags must be present on the parts.
  match pattern.end_flag {
    Some(flag) =>
      if !self.part_has_pattern_flag(left, flag, left_role, mode) {
        return NoMatch
      }
    None => ()
  }
  match pattern.begin_flag {
    Some(flag) =>
      if !self.part_has_pattern_flag(right, flag, right_role, mode) {
        return NoMatch
      }
    None => ()
  }
  if pattern.zero_end {
    // The special `0` pattern only matches unmodified stems.
    if !self.is_unmodified_stem(left, pattern.end_flag) {
      return NoMatch
    }
  } else if !pattern.end_chars.is_empty() {
    if !ends_with_text(left, pattern.end_chars) {
      return NoMatch
    }
  }
  if !pattern.begin_chars.is_empty() {
    if !starts_with_text(right, pattern.begin_chars) {
      return NoMatch
    }
  }
  match pattern.replacement {
    None => Forbid
    Some(_) => Replace
  }
}

///|
/// Is `part` an unmodified dictionary stem (possibly through a zero affix)?
/// This is what the manual's special `CHECKCOMPOUNDPATTERN 0` endchars pattern
/// restricts a rule to.
fn Dictionary::is_unmodified_stem(
  self : Dictionary,
  part : String,
  flag : String?,
) -> Bool {
  if self.homonyms(part).length() == 0 {
    return false
  }
  match flag {
    None => true
    Some(flag) => self.entry_has_flag(part, flag)
  }
}

///|
/// Does `text` end with `suffix`? (`String::strip_suffix` returns `None` for the
/// empty suffix, which is why the callers test emptiness first.)
fn ends_with_text(text : String, suffix : String) -> Bool {
  match text.strip_suffix(suffix) {
    Some(_) => true
    None => false
  }
}

///|
/// Does `text` start with `prefix`?
fn starts_with_text(text : String, prefix : String) -> Bool {
  match text.strip_prefix(prefix) {
    Some(_) => true
    None => false
  }
}

///|
/// Does a `CHECKCOMPOUNDPATTERN` rule forbid this boundary?
fn Dictionary::boundary_forbidden(
  self : Dictionary,
  left : String,
  left_role : CpdRole,
  right : String,
  right_role : CpdRole,
  mode : MatchCase,
) -> Bool {
  for text in self.check_compound_pattern {
    let pattern = parse_compound_pattern(text)
    match
      self.match_compound_pattern(
        pattern, left, left_role, right, right_role, mode,
      ) {
      Forbid | Replace => return true
      NoMatch => ()
    }
  }
  false
}

///|
/// `CHECKCOMPOUNDCASE`: an upper-case character adjacent to the boundary forbids
/// the compound.
fn compound_case_forbidden(left : String, right : String) -> Bool {
  if left.is_empty() || right.is_empty() {
    return false
  }
  is_upper_char(last_char(left)) || is_upper_char(first_char(right))
}

///|
/// The last code point of `text` (the caller guarantees a non-empty string).
fn last_char(text : String) -> Char {
  let chars = text.to_array()
  chars[chars.length() - 1]
}

///|
/// The first code point of `text`.
fn first_char(text : String) -> Char {
  let chars = text.to_array()
  chars[0]
}

///|
/// `CHECKCOMPOUNDTRIPLE`: does the boundary between `left` and `right` join a
/// run of three or more identical characters?
///
/// **ASCII only, deliberately.** `hunspell(5)` documents this as a limitation of the
/// reference implementation — "Bug: missing multi-byte character support in UTF-8
/// encoding (works only for 7-bit ASCII characters)" — so Hunspell accepts a non-ASCII
/// triple such as `abééécd`. This library reproduces that: compatibility with the
/// reference is the project's goal, and the conformance corpus is what measures it.
/// The code used to test every character while this comment already claimed ASCII-only.
fn compound_triple_forbidden(left : String, right : String) -> Bool {
  if left.is_empty() || right.is_empty() {
    return false
  }
  let lc = last_char(left)
  let rc = first_char(right)
  if lc != rc {
    return false
  }
  if !lc.is_ascii() {
    return false
  }
  trailing_run(left) + leading_run(right) >= 3
}

///|
/// How many identical characters `text` ends with.
fn trailing_run(text : String) -> Int {
  let chars = text.to_array()
  let last = chars[chars.length() - 1]
  let mut count = 0
  let mut index = chars.length() - 1
  while index >= 0 && chars[index] == last {
    count = count + 1
    index = index - 1
  }
  count
}

///|
/// How many identical characters `text` starts with.
fn leading_run(text : String) -> Int {
  let chars = text.to_array()
  let first = chars[0]
  let mut count = 0
  while count < chars.length() && chars[count] == first {
    count = count + 1
  }
  count
}

///|
/// May the two adjacent parts `left` (already chosen) and `right` be joined?
fn Dictionary::boundary_ok(
  self : Dictionary,
  left : String,
  left_role : CpdRole,
  right : String,
  right_role : CpdRole,
  mode : MatchCase,
) -> Bool {
  if self.check_compound_case && compound_case_forbidden(left, right) {
    return false
  }
  if self.check_compound_triple && compound_triple_forbidden(left, right) {
    return false
  }
  if self.boundary_forbidden(left, left_role, right, right_role, mode) {
    return false
  }
  if self.blocked_compounds.contains(left + right) {
    return false
  }
  if self.compound_rep_blocks(left, right, mode) {
    return false
  }
  true
}

///|
/// `CHECKCOMPOUNDREP`: forbid the boundary when a `REP` replacement turns the
/// joined pair into a plain dictionary word.
///
/// This is the manual's "the compound word may be a non-compound word with a
/// REP fault": `szer|víz` is rejected because `szerviz` is in the dictionary.
fn Dictionary::compound_rep_blocks(
  self : Dictionary,
  left : String,
  right : String,
  mode : MatchCase,
) -> Bool {
  if !self.check_compound_rep {
    return false
  }
  let joined = left + right
  for replacement in self.suggestion_replacements {
    let from = rep_text(replacement.from)
    if from.is_empty() {
      continue
    }
    let to = rep_text(replacement.to)
    let replaced = replace_text(joined, from, to)
    if replaced != joined &&
      (self.direct_hit(replaced, mode) || self.check_word_group(replaced)) {
      return true
    }
  }
  false
}

///|
/// Interpret one side of a `REP` pair for `CHECKCOMPOUNDREP`: `_` stands for a
/// space, and the `^`/`$` anchors are dropped (the plain substring case is what
/// the check needs).
fn rep_text(text : String) -> String {
  let buffer = StringBuilder()
  let chars = text.to_array()
  let mut index = 0
  while index < chars.length() {
    let c = chars[index]
    if c == '^' && index == 0 {
      index = index + 1
      continue
    }
    if c == '$' && index == chars.length() - 1 {
      index = index + 1
      continue
    }
    if c == '_' {
      buffer.write_char(' ')
    } else {
      buffer.write_char(c)
    }
    index = index + 1
  }
  buffer.to_string()
}

///|
/// Replace every occurrence of `from` in `text` with `to`.
fn replace_text(text : String, from : String, to : String) -> String {
  let chars = text.to_array()
  let needle = from.to_array()
  if needle.length() == 0 {
    return text
  }
  let buffer = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if index + needle.length() <= chars.length() &&
      matches_chars_at(chars, needle, index) {
      buffer.write_string(to)
      index = index + needle.length()
    } else {
      buffer.write_char(chars[index])
      index = index + 1
    }
  }
  buffer.to_string()
}

///|
/// Does the last compound part force capitalisation of the whole compound?
fn Dictionary::forceucase_part(
  self : Dictionary,
  part : String,
  mode : MatchCase,
) -> Bool {
  if self.forceucase is None {
    return false
  }
  if has_flag(self.forceucase, self.flags_of_word(part)) {
    return true
  }
  self.affixed_forceucase(part, mode)
}

///|
/// The union of all homonyms' flags for a word.
fn Dictionary::flags_of_word(self : Dictionary, word : String) -> Array[String] {
  let out : Array[String] = []
  for flags in self.homonyms(word) {
    for flag in flags {
      out.push(flag)
    }
  }
  out
}

///|
/// Does an affixed form of `part` carry the `FORCEUCASE` flag (on its stem or in
/// an affix's continuation class)?
fn Dictionary::affixed_forceucase(
  self : Dictionary,
  part : String,
  mode : MatchCase,
) -> Bool {
  let flag = match self.forceucase {
    None => return false
    Some(flag) => flag
  }
  for rule in self.suffix_rules {
    let rest = match part.strip_suffix(normalise_affix(rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = rest + normalise_affix(rule.rule.strip)
    if !self.compound_stem_ok(stem, rule.rule.flag, mode) {
      continue
    }
    if rule.cont_flags.contains(flag) || self.entry_has_flag(stem, flag) {
      match @affix.apply_rule(rule.rule, stem) {
        Some(produced) => if produced == part { return true }
        None => ()
      }
    }
  }
  for rule in self.prefix_rules {
    let rest = match part.strip_prefix(normalise_affix(rule.rule.add)) {
      Some(view) => view.to_owned()
      None => continue
    }
    let stem = normalise_affix(rule.rule.strip) + rest
    if !self.compound_stem_ok(stem, rule.rule.flag, mode) {
      continue
    }
    if rule.cont_flags.contains(flag) || self.entry_has_flag(stem, flag) {
      match @affix.apply_rule(rule.rule, stem) {
        Some(produced) => if produced == part { return true }
        None => ()
      }
    }
  }
  false
}

///|
/// The most parts this library will consider in one compound.
///
/// `hunspell(5)` documents no such limit (`COMPOUNDWORDMAX` defaults to unlimited); see
/// `Dictionary::compound_part_limit` for why a deterministic ceiling is used anyway, what
/// it costs, and the measurement that shows why simply raising it does not work.
fn compound_part_ceiling() -> Int {
  8
}

///|
/// `COMPOUNDWORDMAX` / `COMPOUNDSYLLABLE`: how many parts a compound of this
/// spelling may have.
///
/// The manual's Hungarian rule: the syllable-count limit is the exception that
/// allows *more* words than `COMPOUNDWORDMAX` ("allow more words in a compound,
/// than COMPOUNDWORDMAX, if syllable count of the compound is 6 or less").
/// The syllable count is the number of vowels in the whole word.
///
/// # Why the ceiling is 8 and not "unlimited"
///
/// `hunspell(5)` says of `COMPOUNDWORDMAX`: "Default is unlimited." This library caps a
/// compound at `compound_part_ceiling()` parts anyway, which is a **known and disclosed
/// deviation** (README *Not implemented yet*; `ACCEPTANCE.md` 7.2) — and it is deliberate.
///
/// The compound search backtracks over every way of splitting the word, so an unbounded
/// part count makes it exponential. The reference implementation has the same problem and
/// answers it with a hard-coded wall-clock `TIMELIMIT_MS` in `affixmgr.cxx` — a mechanism
/// `hunspell(5)` does not document, and one that would make results depend on the machine.
/// The upstream corpus has a suite for exactly this: `tests/timelimit.{aff,dic,good}` is
/// one 22-character word over `WORDCHARS 01`, `COMPOUNDMIN 1` and `COMPOUNDFLAG Y`.
///
/// **Measured on 2026-09-28**: raising this ceiling to the word's own length makes that
/// one word take longer than 20 s here, where `hunspell 1.7.3` answers it in 7 ms — the
/// corpus caught an attempt to "fix" this deviation by making the number bigger. Closing
/// it properly needs a search budget or memoisation, not a larger ceiling.
fn Dictionary::compound_part_limit(self : Dictionary, word : String) -> Int {
  let ceiling = compound_part_ceiling()
  let word_max = if self.compound_word_max > 0 {
    self.compound_word_max
  } else {
    ceiling
  }
  if self.compound_syllable_max <= 0 || self.compound_syllable_vowels.is_empty() {
    return word_max
  }
  let vowels = self.compound_syllable_vowels.to_array()
  let mut count = 0
  for c in word {
    if vowels.contains(c) {
      count = count + 1
    }
  }
  if count <= self.compound_syllable_max {
    ceiling
  } else {
    word_max
  }
}

///|
/// Recursively split `chars` from `position` into compound parts.
///
/// `part_index` is the number of parts already accepted, `prev` the part that
/// ends at `position` (for the boundary rules), and `orig_cap` whether the word
/// as typed had a capital letter (`FORCEUCASE`).
fn Dictionary::compound_search(
  self : Dictionary,
  chars : Array[Char],
  position : Int,
  part_index : Int,
  max_parts : Int,
  mode : MatchCase,
  orig_cap : Bool,
  prev : String?,
) -> Bool {
  let minimum = if self.compound_min <= 0 { 3 } else { self.compound_min }
  let total = chars.length()
  // More parts (each at least `minimum` long) must remain possible.
  let mut end = position + minimum
  while end <= total - minimum && part_index + 1 < max_parts {
    let part = chars_to_string(chars, position, end)
    let role = if part_index == 0 { First } else { Middle }
    let left_role = if part_index == 0 { First } else { Middle }
    if self.compound_part_ok(part, role, mode) &&
      self.prev_boundary_ok(prev, left_role, part, role, mode) &&
      self.compound_search(
        chars,
        end,
        part_index + 1,
        max_parts,
        mode,
        orig_cap,
        Some(part),
      ) {
      return true
    }
    end = end + 1
  }
  if part_index >= 1 &&
    total - position >= minimum &&
    part_index + 1 <= max_parts {
    let part = chars_to_string(chars, position, total)
    let left_role = if part_index == 0 { First } else { Middle }
    if self.compound_part_ok(part, Last, mode) &&
      self.prev_boundary_ok(prev, left_role, part, Last, mode) &&
      self.dup_ok(prev, part) &&
      self.forceucase_ok(part, mode, orig_cap) {
      return true
    }
  }
  false
}

///|
/// Check the boundary before the part being added; `prev` is the part on the
/// left (absent for the first part).
fn Dictionary::prev_boundary_ok(
  self : Dictionary,
  prev : String?,
  left_role : CpdRole,
  right : String,
  right_role : CpdRole,
  mode : MatchCase,
) -> Bool {
  match prev {
    None => true
    Some(left) => self.boundary_ok(left, left_role, right, right_role, mode)
  }
}

///|
/// `CHECKCOMPOUNDDUP`: the last two parts must not be identical.
fn Dictionary::dup_ok(self : Dictionary, prev : String?, part : String) -> Bool {
  if !self.check_compound_dup {
    return true
  }
  match prev {
    None => true
    Some(left) => left != part
  }
}

///|
/// `FORCEUCASE`: a compound whose last part carries the flag is only correct
/// when the word as typed was capitalised.
fn Dictionary::forceucase_ok(
  self : Dictionary,
  part : String,
  mode : MatchCase,
  orig_cap : Bool,
) -> Bool {
  if orig_cap {
    return true
  }
  !self.forceucase_part(part, mode)
}

///|
/// Accept a word that splits into two dictionary words, each at least
/// `COMPOUNDMIN` characters long, with the roles `COMPOUNDFLAG` /
/// `COMPOUNDBEGIN` / `COMPOUNDMIDDLE` / `COMPOUNDEND` describe.
fn Dictionary::check_compound(
  self : Dictionary,
  word : String,
  mode : MatchCase,
  orig_cap : Bool,
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
  // A `.dic` word pair (`compound word`) forbids the space-free compound.
  if self.blocked_compounds.contains(word) {
    return false
  }
  if self.compound_search(
      chars,
      0,
      0,
      self.compound_part_limit(word),
      mode,
      orig_cap,
      None,
    ) {
    return true
  }
  self.compound_simplified(chars, mode, orig_cap)
}

///|
/// The `CHECKCOMPOUNDPATTERN` replacement forms and `SIMPLIFIEDTRIPLE`: a word
/// whose boundary is a forbidden pattern (or a triple letter) may still be
/// correct as the *simplified* spelling of a valid two-part compound.
fn Dictionary::compound_simplified(
  self : Dictionary,
  chars : Array[Char],
  mode : MatchCase,
  orig_cap : Bool,
) -> Bool {
  let total = chars.length()
  let minimum = if self.compound_min <= 0 { 3 } else { self.compound_min }
  let mut pos = 1
  while pos < total {
    let left = chars_to_string(chars, 0, pos)
    let right = chars_to_string(chars, pos, total)
    // CHECKCOMPOUNDPATTERN replacement.
    for text in self.check_compound_pattern {
      let pattern = parse_compound_pattern(text)
      match pattern.replacement {
        None => ()
        Some(replacement) =>
          if !replacement.is_empty() && ends_with_text(left, replacement) {
            let base_left = chars_to_string(
                chars,
                0,
                pos - replacement.to_array().length(),
              ) +
              pattern.end_chars
            let base_right = pattern.begin_chars + right
            if self.simplified_pair_ok(
                base_left, base_right, pattern, minimum, mode, orig_cap,
              ) {
              return true
            }
          }
      }
    }
    // SIMPLIFIEDTRIPLE: re-insert one letter at the boundary. The directive is
    // useful on its own (`gh151`), because it also relaxes `COMPOUNDMIN` for a
    // second part that is one letter shorter on the surface.
    if self.check_compound_simplified_triple && !left.is_empty() {
      let c = last_char(left)
      let restored = c.to_string() + right
      if compound_triple_forbidden(left, restored) {
        let base_right = restored
        if self.simplified_pair_ok(
            left,
            base_right,
            no_pattern(),
            minimum,
            mode,
            orig_cap,
          ) {
          return true
        }
      }
    }
    pos = pos + 1
  }
  false
}

///|
/// A neutral pattern used by the `SIMPLIFIEDTRIPLE` path (no flags, no
/// replacement).
fn no_pattern() -> CpdPattern {
  {
    end_chars: "",
    end_flag: None,
    begin_chars: "",
    begin_flag: None,
    replacement: None,
    zero_end: false,
  }
}

///|
/// Validate the two original parts of a simplified compound.
fn Dictionary::simplified_pair_ok(
  self : Dictionary,
  left : String,
  right : String,
  pattern : CpdPattern,
  minimum : Int,
  mode : MatchCase,
  orig_cap : Bool,
) -> Bool {
  if left.to_array().length() < minimum || right.to_array().length() < minimum {
    return false
  }
  if !self.compound_part_ok(left, First, mode) {
    return false
  }
  if !self.compound_part_ok(right, Last, mode) {
    return false
  }
  let left_role = First
  match
    self.match_compound_pattern(pattern, left, left_role, right, Last, mode) {
    Forbid | Replace => ()
    NoMatch => return false
  }
  if self.check_compound_case && compound_case_forbidden(left, right) {
    return false
  }
  self.forceucase_ok(right, mode, orig_cap)
}
