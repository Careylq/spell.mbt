// The public dictionary type: parse, index once, then answer `check` queries.
//
// This is an independent, clean-room implementation of the judgement rules
// documented in the Hunspell manual. No Hunspell (LGPL-2.1) source code was
// consulted or copied; this project is Apache-2.0.

///|
/// The error raised when a dictionary cannot be built.
///
/// It wraps whichever parser failed, so the caller keeps the original line
/// number and message.
pub(all) suberror SpellError {
  AffParse(@aff.AffParseError)
  DicParse(@dic.DicParseError)
}

///|
pub impl Show for SpellError with fn to_string(self) {
  match self {
    AffParse(error) => ".aff: \{error.to_string()}"
    DicParse(error) => ".dic: \{error.to_string()}"
  }
}

///|
/// A parsed, indexed dictionary that can judge words.
///
/// Build one with `Dictionary::from_text`. Parsing and indexing happen once, so
/// `check` is cheap enough to call for every word of a document.
///
/// The type is opaque: the index representation is an implementation detail and
/// may change. Use the accessors below to inspect the loaded file.
pub struct Dictionary {
  /// Every `.dic` word mapped to its homonyms' flag vectors. A word that occurs
  /// several times keeps one flag vector per occurrence, because Hunspell treats
  /// them as alternatives: `foo`, `foo/X` and `foo/Y` make `foo` correct even
  /// though the `X` homonym alone would not be.
  entries : Map[String, Array[Array[String]]]
  prefix_rules : Array[SpellRule]
  suffix_rules : Array[SpellRule]
  forbiddenword : String?
  keepcase : String?
  needaffix : String?
  onlyincompound : String?
  /// `CIRCUMFIX`: an affix carrying this flag may only be applied together with
  /// an affix of the opposite kind that carries it too.
  circumfix : String?
  compound_flag : String?
  /// `COMPOUNDBEGIN` / `COMPOUNDEND`: the flags that licence a word as the
  /// first or the last part of a compound (`check_compound`). `COMPOUNDMIDDLE`
  /// is parsed but unused until compounds of three or more parts are handled.
  compound_begin : String?
  compound_end : String?
  compound_middle : String?
  /// `COMPOUNDPERMITFLAG` / `COMPOUNDFORBIDFLAG`: the flags that let an affix sit
  /// inside a compound / forbid an affixed word from being a compound part.
  compound_permit : String?
  compound_forbid : String?
  /// `FORCEUCASE`: a compound whose last part carries this flag is only correct
  /// when the whole word is capitalised.
  forceucase : String?
  /// The `COMPOUNDRULE` patterns, verbatim. A compound is correct when its
  /// parts' flags match one of them (`check_compound_rule` parses them).
  compound_rules : Array[String]
  /// The `CHECKCOMPOUNDPATTERN` lines, verbatim; parsed at match time.
  check_compound_pattern : Array[String]
  check_compound_dup : Bool
  check_compound_triple : Bool
  check_compound_simplified_triple : Bool
  check_compound_case : Bool
  /// `0` means unlimited.
  compound_word_max : Int
  /// `COMPOUNDSYLLABLE max vowels`; `0` means the directive was absent.
  compound_syllable_max : Int
  compound_syllable_vowels : String
  /// `REP`-driven `CHECKCOMPOUNDREP`.
  check_compound_rep : Bool
  /// The space-free spellings of `.dic` word pairs (`compound word`). A
  /// compound must not be recognised for one of these: the word pair is the
  /// only correct spelling (`wordpair`, `ph2`).
  blocked_compounds : Map[String, Bool]
  /// `0` means the `.aff` had no `COMPOUNDMIN`; Hunspell's default of `3` is
  /// applied at match time.
  compound_min : Int
  /// `WORDCHARS`: characters that may appear inside a word. Only the trailing
  /// `.` (abbreviations such as `etc.`) is acted on today.
  word_chars : String
  /// `TRY`: the characters the suggestion engine may substitute or insert.
  /// Empty when the `.aff` had no `TRY` line.
  try_chars : String
  /// `KEY`: the keyboard layout, one row per `|`-separated group. Empty when the
  /// `.aff` had no `KEY` line. Used only to rank suggestions.
  keyboard : String
  /// `REP`: the replacement pairs, in source order. `_` still stands for a space
  /// (the parser keeps it verbatim); the suggestion engine interprets it.
  replacements : Array[@aff.Replacement]
  /// `REP` plus the rules derived from the `.dic` `ph:` fields, in source order.
  /// The `ph:` fields are the manual's "inner REP table": a `ph:` value names a
  /// transliteration of the word, so `which ph:wich` suggests `which` for
  /// `wich`. Built once at load time.
  suggestion_replacements : Array[@aff.Replacement]
  /// `MAP` groups, verbatim, in source order. The suggestion engine expands each
  /// group into "replace any member by any other member".
  map_groups : Array[String]
  /// `PHONE` phonetic-transcription rules, in source order. Empty when the
  /// `.aff` file has none, in which case the phonetic pass is skipped entirely.
  phone_rules : Array[@aff.PhoneRule]
  /// The parsed `PHONE` table and the phonetic key -> words index, built once at
  /// load time. Empty when there are no `PHONE` rules (so a dictionary that does
  /// not use them pays nothing). A word whose `.dic` entry carries a `ph:` field
  /// is indexed under that field instead of a computed key.
  phonet : PhonetTable
  /// `ICONV`: the input-conversion table, already in matching order. Applied to
  /// the word being checked (`check`) and never to dictionary entries.
  iconv : Array[@aff.Conversion]
  /// `OCONV`: the output-conversion table, already in matching order. Applied to
  /// suggestion output only (`Dictionary::apply_oconv`).
  oconv : Array[@aff.Conversion]
  /// `NOSUGGEST`: a word carrying this flag is never offered as a suggestion.
  nosuggest : String?
  /// The characters listed by the `IGNORE` directive, as code points. They are
  /// removed from dictionary entries, affix `strip`/`add` text and checked
  /// words before any comparison (`remove_ignored`).
  ignore_chars : Array[Char]
  /// `CHECKSHARPS`: an uppercase word may spell a dictionary `ß` as `SS`, and a
  /// `KEEPCASE` entry containing `ß` may be capitalised or uppercased.
  check_sharps : Bool
  /// `COMPLEXPREFIXES`: when set, `affix_hit` allows a second prefix whose flag
  /// the inner prefix's continuation flags supply, and refuses twofold suffix
  /// stacking (the manual's "twofold prefix matching, but only one suffix level
  /// instead of the default two").
  complex_prefixes : Bool
  /// The `BREAK` patterns: where a word may be split into two separately
  /// correct parts (`check_breaks`). When the `.aff` has no `BREAK` line this
  /// holds Hunspell's default (`-`, `^-`, `-$`); `BREAK 0` leaves it empty.
  break_patterns : Array[String]
  encoding : String
  flag_type : @aff.FlagType
  /// `LANG tr` / `az` / `crh`: use the Turkic dotted/dotless `I` casing rules.
  turkic : Bool
  rule_count : Int
}

///|
/// Parse `.aff` and `.dic` text and build an indexed dictionary.
///
/// Raises `SpellError` when either file is malformed. A leading UTF-8 BOM
/// (`U+FEFF`) on either text is ignored, because real dictionaries sometimes
/// carry one.
///
/// The `.dic` flags are decoded with the `.aff` file's `FLAG` mode; when the
/// `.aff` declares an `AF` alias table the `.dic` holds alias numbers, so the
/// numbers are resolved to the same strings that `PFX`/`SFX` rule flags were
/// resolved to.
pub fn Dictionary::from_text(
  aff_text : String,
  dic_text : String,
) -> Dictionary raise SpellError {
  let aff = @aff.parse_aff(strip_bom(aff_text)) catch {
    error => raise AffParse(error)
  }
  // With an `AF` table the word list stores alias indices, not flags, so it has
  // to be decoded as numbers even when the file's own `FLAG` mode differs.
  let dic_flag_type = if aff.flag_aliases.is_empty() {
    aff.flag_type
  } else {
    @aff.Num
  }
  let dic = @dic.parse_dic(strip_bom(dic_text), dic_flag_type) catch {
    error => raise DicParse(error)
  }
  let entries : Map[String, Array[Array[String]]] = Map([])
  let blocked_compounds : Map[String, Bool] = Map([])
  let ignore_chars = aff.ignore_chars.to_array()
  for entry in dic.entries {
    let flags : Array[String] = []
    for flag in entry.flags {
      // An `AF` alias stands for a whole flag vector (`AF AB` is the flags `A`
      // and `B`), so resolving one alias can add several flags.
      for resolved in resolve_alias(aff.flag_aliases, flag, aff.flag_type) {
        flags.push(resolved)
      }
    }
    // `IGNORE` characters are dropped from dictionary words as well as from the
    // word being checked, so `مُدَرِّس` and `مدرس` become the same entry.
    let word = remove_ignored(entry.word, ignore_chars)
    match entries.get(word) {
      Some(existing) => existing.push(flags)
      None => {
        let homonyms : Array[Array[String]] = [flags]
        entries[word] = homonyms
      }
    }
    // A word pair such as `a lot ph:alot` or `forbidden root/A ph:...` is one
    // dictionary word spelled with a space. `word` above stays the first field
    // (the judgement index leans on it), but the whole spelling is registered
    // too, with the flags written on its last token, so that a `ph:` suggestion
    // can pass `check`.
    let full = remove_ignored(entry.full_word, ignore_chars)
    if full != word {
      let full_flags : Array[String] = []
      for flag in entry.full_flags {
        for resolved in resolve_alias(aff.flag_aliases, flag, aff.flag_type) {
          full_flags.push(resolved)
        }
      }
      match entries.get(full) {
        Some(existing) => existing.push(full_flags)
        None => {
          let homonyms : Array[Array[String]] = [full_flags]
          entries[full] = homonyms
        }
      }
      // The same word without its space must never be recognised as a compound:
      // the word pair is the only accepted spelling.
      let joined = remove_whitespace(full)
      if !joined.is_empty() {
        blocked_compounds[joined] = true
      }
    }
  }
  let prefix_rules : Array[SpellRule] = []
  let suffix_rules : Array[SpellRule] = []
  for rule in aff.affix_rules {
    let cont_flags = decode_continuation(
      rule.add,
      aff.flag_aliases,
      aff.flag_type,
    )
    let cleaned = rule_without_continuation_flags(rule)
    // The strip and add text are cleaned too: for `IGNORE aeiou` the rule
    // `PFX A 0 re .` adds `r`, so `reexpression` and `rxprssn` both normalise to
    // the same accepted form.
    let cleaned = {
      ..cleaned,
      strip: remove_ignored(cleaned.strip, ignore_chars),
      add: remove_ignored(cleaned.add, ignore_chars),
    }
    let spell_rule : SpellRule = { rule: cleaned, cont_flags, }
    match cleaned.kind {
      @aff.Prefix => prefix_rules.push(spell_rule)
      @aff.Suffix => suffix_rules.push(spell_rule)
    }
  }
  let special = aff.special_flags
  {
    entries,
    prefix_rules,
    suffix_rules,
    forbiddenword: special.forbiddenword,
    keepcase: special.keepcase,
    needaffix: special.needaffix,
    onlyincompound: special.onlyincompound,
    circumfix: special.circumfix,
    compound_flag: aff.compound_flag,
    compound_begin: aff.compound_begin,
    compound_end: aff.compound_end,
    compound_middle: aff.compound_middle,
    compound_permit: aff.compound_permit,
    compound_forbid: aff.compound_forbid,
    forceucase: aff.forceucase,
    compound_rules: aff.compound_rules,
    check_compound_pattern: aff.check_compound_pattern,
    check_compound_dup: aff.check_compound_dup,
    check_compound_triple: aff.check_compound_triple,
    check_compound_simplified_triple: aff.check_compound_simplified_triple,
    check_compound_case: aff.check_compound_case,
    compound_word_max: aff.compound_word_max,
    compound_syllable_max: aff.compound_syllable_max,
    compound_syllable_vowels: aff.compound_syllable_vowels,
    check_compound_rep: aff.check_compound_repeat,
    blocked_compounds,
    compound_min: aff.compound_min,
    word_chars: aff.word_chars,
    try_chars: aff.try_chars,
    keyboard: aff.keyboard,
    replacements: aff.replacements,
    suggestion_replacements: suggest_replacements(
      aff.replacements,
      dic.entries,
      ignore_chars,
    ),
    map_groups: aff.map_groups,
    phone_rules: aff.phone_rules,
    phonet: build_phonetic_table(dic.entries, ignore_chars, aff.phone_rules),
    iconv: prepare_conversions(aff.iconv),
    oconv: prepare_conversions(aff.oconv),
    nosuggest: special.nosuggest,
    ignore_chars,
    check_sharps: aff.check_sharps,
    complex_prefixes: aff.complex_prefixes,
    break_patterns: if aff.breaks_declared {
      aff.break_patterns
    } else {
      ["-", "^-", "-$"]
    },
    encoding: aff.encoding,
    flag_type: aff.flag_type,
    turkic: aff.lang == "tr" || aff.lang == "az" || aff.lang == "crh",
    rule_count: aff.affix_rules.length(),
  }
}

///|
/// Remove every character listed in the `.aff` `IGNORE` directive from `text`.
///
/// Hunspell treats those characters as invisible: they are dropped from
/// dictionary entries and from the word being checked before the two are
/// compared. `ignored` holds the characters as code points, so an entry may
/// list multi-byte characters (Arabic diacritics, the right-to-left mark).
fn remove_ignored(text : String, ignored : Array[Char]) -> String {
  if ignored.is_empty() {
    return text
  }
  let buffer = StringBuilder()
  for c in text {
    if !ignored.contains(c) {
      buffer.write_char(c)
    }
  }
  buffer.to_string()
}

///|
/// Remove every whitespace character from `text` (`"a lot"` -> `"alot"`).
fn remove_whitespace(text : String) -> String {
  let buffer = StringBuilder()
  for c in text {
    if !c.is_whitespace() {
      buffer.write_char(c)
    }
  }
  buffer.to_string()
}

///|
/// A `PFX`/`SFX` rule as the judgement engine needs it: the rule with the
/// continuation-flag list cut off its `add` text, plus that list as flags.
///
/// `SFX A 0 s/123 .` adds `s` and gives the derived form the flags `1`, `2`
/// and `3`; chaining a second affix through those flags is what
/// `cont_flags` enables.
///
/// The type is an implementation detail of the index (`Dictionary` is opaque),
/// so it is never constructed by a caller.
pub struct SpellRule {
  rule : @aff.AffixRule
  cont_flags : Array[String]
}

///|
/// The flags listed after the `/` of a rule's `add` field. An `add` without a
/// `/` has no continuation flags.
///
/// Without an `AF` table the list is a plain flag list in the file's `FLAG`
/// mode (`s/123` is the flags `1`, `2`, `3`). With an `AF` table the entries are
/// alias indices instead (`y/2` is whatever flag vector alias `2` names), and
/// each one expands to the flags it stands for.
fn decode_continuation(
  add : String,
  aliases : Array[String],
  flag_type : @aff.FlagType,
) -> Array[String] {
  let chars = add.to_array()
  let mut index = 0
  while index < chars.length() && chars[index] != '/' {
    index = index + 1
  }
  if index >= chars.length() {
    return []
  }
  let buffer = StringBuilder()
  let mut cursor = index + 1
  while cursor < chars.length() {
    buffer.write_char(chars[cursor])
    cursor = cursor + 1
  }
  let raw = buffer.to_string()
  if aliases.is_empty() {
    return @dic.decode_flags(raw, flag_type)
  }
  // Alias indices are stored as decimal numbers, exactly as in the `.dic`.
  let flags : Array[String] = []
  for entry in @dic.decode_flags(raw, Num) {
    for resolved in resolve_alias(aliases, entry, flag_type) {
      flags.push(resolved)
    }
  }
  flags
}

///|
/// Drop a leading UTF-8 byte-order mark, if the text starts with one.
fn strip_bom(text : String) -> String {
  match text.strip_prefix("\u{FEFF}") {
    Some(rest) => rest.to_owned()
    None => text
  }
}

///|
/// Copy `rule`, cutting the continuation-flag list off the `add` field.
///
/// Hunspell writes `SFX A 0 s/123 .` to mean "add `s` and give the result the
/// flags `123`", which is how a second affix can be chained onto the first.
/// Chaining is not implemented (see the README's limitations), but the *first*
/// affix is real and has to be applied with `add` = `s`, otherwise a word as
/// simple as `foos` would not be found. The flags after `/` are therefore
/// dropped rather than left glued to the addition.
fn rule_without_continuation_flags(rule : @aff.AffixRule) -> @aff.AffixRule {
  {
    kind: rule.kind,
    flag: rule.flag,
    cross_product: rule.cross_product,
    strip: rule.strip,
    add: add_without_flags(rule.add),
    condition: rule.condition,
    morph: rule.morph,
  }
}

///|
/// The part of an `add` field before the first `/` (the continuation-flag
/// separator); `0` and other values pass through unchanged.
fn add_without_flags(add : String) -> String {
  match add.find("/") {
    None => add
    Some(_) => {
      let buffer = StringBuilder()
      for c in add {
        if c == '/' {
          break
        }
        buffer.write_char(c)
      }
      buffer.to_string()
    }
  }
}

///|
/// Resolve one `.dic` flag through the `AF` alias table into the flags it
/// stands for.
///
/// With no `AF` table the flag is returned as-is. Otherwise a decimal flag is
/// an alias index (`1` is the first `AF` body line) and its value is a flag
/// *vector*, which is split with the file's `FLAG` mode: `AF AB` in
/// single-character mode is the two flags `A` and `B`. An out-of-range index or
/// a non-numeric flag is kept verbatim, so a `.dic` that mixes both still works.
fn resolve_alias(
  aliases : Array[String],
  flag : String,
  flag_type : @aff.FlagType,
) -> Array[String] {
  if aliases.is_empty() {
    return [flag]
  }
  let parsed : Int? = Some(@string.parse_int(flag)) catch { _ => None }
  match parsed {
    Some(index) =>
      if index >= 1 && index <= aliases.length() {
        @dic.decode_flags(aliases[index - 1], flag_type)
      } else {
        [flag]
      }
    None => [flag]
  }
}

///|
/// The `SET` encoding declared by the `.aff` file, or `""` when absent.
pub fn Dictionary::encoding(self : Dictionary) -> String {
  self.encoding
}

///|
/// The `FLAG` mode declared by the `.aff` file (SingleChar when absent).
pub fn Dictionary::flag_type(self : Dictionary) -> @aff.FlagType {
  self.flag_type
}

///|
/// How many `PFX`/`SFX` rule lines the `.aff` file declared.
pub fn Dictionary::rule_count(self : Dictionary) -> Int {
  self.rule_count
}

///|
/// How many distinct words the word list holds.
pub fn Dictionary::entry_count(self : Dictionary) -> Int {
  self.entries.length()
}

///|
/// The `TRY` characters the `.aff` file declared, or `""` when it had none.
///
/// The suggestion engine substitutes and inserts only these characters (falling
/// back to a plain ASCII alphabet when the list is empty).
pub fn Dictionary::try_chars(self : Dictionary) -> String {
  self.try_chars
}

///|
/// The `KEY` keyboard layout, or `""` when the `.aff` file had none.
///
/// Rows are separated by `|`; the suggestion engine uses adjacency on this
/// layout to rank candidates.
pub fn Dictionary::keyboard(self : Dictionary) -> String {
  self.keyboard
}

///|
/// The `WORDCHARS` characters the `.aff` file declared, or `""` when it had none.
pub fn Dictionary::word_chars(self : Dictionary) -> String {
  self.word_chars
}

///|
/// The `REP` replacement pairs, in source order.
///
/// `_` stands for a space, exactly as it does in the file; the suggestion engine
/// is what interprets it.
pub fn Dictionary::replacements(self : Dictionary) -> Array[@aff.Replacement] {
  self.replacements
}

///|
/// The full suggestion replacement table: `REP` followed by the rules derived
/// from the `.dic` `ph:` fields, in source order.
pub fn Dictionary::suggestion_replacements(
  self : Dictionary,
) -> Array[@aff.Replacement] {
  self.suggestion_replacements
}

///|
/// The `MAP` groups verbatim, in source order; empty when the `.aff` file has
/// none. Each entry is one `MAP` body line, e.g. `uü` or `ß(ss)`.
pub fn Dictionary::map_groups(self : Dictionary) -> Array[String] {
  self.map_groups
}

///|
/// The `PHONE` rules in source order; empty when the `.aff` file has none.
pub fn Dictionary::phone_rules(self : Dictionary) -> Array[@aff.PhoneRule] {
  self.phone_rules
}

///|
/// Is `word` itself marked `NOSUGGEST`, so that it must never be offered as a
/// suggestion? Only a direct `.dic` entry is considered.
pub fn Dictionary::is_no_suggest(self : Dictionary, word : String) -> Bool {
  for flags in self.homonyms(word) {
    if has_flag(self.nosuggest, flags) {
      return true
    }
  }
  false
}

///|
/// Apply the `.aff` `OCONV` output-conversion table to `text`.
///
/// Hunspell only ever converts *output* with this table — the spell-checking
/// judgement is unaffected — so the suggestion engine calls this on each
/// suggestion it is about to return.
pub fn Dictionary::apply_oconv(self : Dictionary, text : String) -> String {
  apply_conversion(self.oconv, text)
}
