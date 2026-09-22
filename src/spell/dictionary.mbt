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
  /// Every `(word, flags)` entry of the `.dic`, with duplicate words merged.
  entries : Map[String, Array[String]]
  prefix_rules : Array[@aff.AffixRule]
  suffix_rules : Array[@aff.AffixRule]
  forbiddenword : String?
  keepcase : String?
  needaffix : String?
  onlyincompound : String?
  compound_flag : String?
  /// `0` means the `.aff` had no `COMPOUNDMIN`; Hunspell's default of `3` is
  /// applied at match time.
  compound_min : Int
  /// `WORDCHARS`: characters that may appear inside a word. Only the trailing
  /// `.` (abbreviations such as `etc.`) is acted on today.
  word_chars : String
  encoding : String
  flag_type : @aff.FlagType
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
  let entries : Map[String, Array[String]] = Map([])
  for entry in dic.entries {
    let flags : Array[String] = []
    for flag in entry.flags {
      flags.push(resolve_alias(aff.flag_aliases, flag))
    }
    match entries.get(entry.word) {
      Some(existing) =>
        for flag in flags {
          if !existing.contains(flag) {
            existing.push(flag)
          }
        }
      None => entries[entry.word] = flags
    }
  }
  let prefix_rules : Array[@aff.AffixRule] = []
  let suffix_rules : Array[@aff.AffixRule] = []
  for rule in aff.affix_rules {
    let cleaned = rule_without_continuation_flags(rule)
    match cleaned.kind {
      @aff.Prefix => prefix_rules.push(cleaned)
      @aff.Suffix => suffix_rules.push(cleaned)
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
    compound_flag: aff.compound_flag,
    compound_min: aff.compound_min,
    word_chars: aff.word_chars,
    encoding: aff.encoding,
    flag_type: aff.flag_type,
    rule_count: aff.affix_rules.length(),
  }
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
/// Resolve one `.dic` flag through the `AF` alias table.
///
/// Outside the table's range (or when the flag is not a number) the flag is
/// returned unchanged, so a `.dic` that uses literal flags still works.
fn resolve_alias(aliases : Array[String], flag : String) -> String {
  if aliases.is_empty() {
    return flag
  }
  let parsed : Int? = Some(@string.parse_int(flag)) catch { _ => None }
  match parsed {
    Some(index) =>
      if index >= 1 && index <= aliases.length() {
        aliases[index - 1]
      } else {
        flag
      }
    None => flag
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
