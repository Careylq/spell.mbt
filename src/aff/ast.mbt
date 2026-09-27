// Typed AST for a Hunspell `.aff` file.
//
// This is an independent, clean-room model of the file format as documented in
// the Hunspell manual. No Hunspell (LGPL-2.1) source code was consulted or
// copied; this project is Apache-2.0.
//
// The AST is intentionally lossless: everything that the format distinguishes
// is kept as a `String`/`Bool`/`Int`, and pattern languages (`condition`,
// `COMPOUNDRULE`, `CHECKCOMPOUNDPATTERN`) are stored verbatim because matching
// is out of scope for this slice.

///|
/// How flags are encoded in the `.aff` and `.dic` files.
///
/// Hunspell's default (no `FLAG` line) is one character per flag.
pub(all) enum FlagType {
  /// One character per flag; used when the file has no `FLAG` line.
  SingleChar
  /// `FLAG long`: two characters per flag.
  Long
  /// `FLAG num`: a decimal number per flag.
  Num
  /// `FLAG UTF-8`: one UTF-8 character per flag.
  Utf8
} derive(Eq, @debug.Debug)

///|
/// Whether an affix is attached before (`Prefix`) or after (`Suffix`) the stem.
pub(all) enum AffixKind {
  /// The affix is attached before the stem (`PFX`).
  Prefix
  /// The affix is attached after the stem (`SFX`).
  Suffix
} derive(Eq, @debug.Debug)

///|
/// The header line of a `PFX`/`SFX` block: `PFX flag cross_product count`.
pub(all) struct AffixHeader {
  /// Whether this header declared a `PFX` or an `SFX` block.
  kind : AffixKind
  /// The flag selecting this block. Numeric `AF` alias indices are resolved to
  /// the alias string while parsing.
  flag : String
  /// `Y` means rules of this block combine with rules of the opposite kind.
  cross_product : Bool
  /// Number of rule lines declared for this block.
  count : Int
} derive(Eq, @debug.Debug)

///|
/// One `PFX`/`SFX` rule line: `PFX flag strip add condition [morph...]`.
pub(all) struct AffixRule {
  /// Whether the rule adds before or after the stem; copied from the header.
  kind : AffixKind
  /// The flag selecting this rule. Numeric `AF` alias indices are resolved to
  /// the alias string while parsing.
  flag : String
  /// Copied from the block header; only headers carry cross-product.
  cross_product : Bool
  /// Text removed from the stem; `"0"` means "strip nothing".
  strip : String
  /// Text added to the stem; `"0"` means "add nothing".
  add : String
  /// The affix condition, stored verbatim. It is a mini-pattern applied to the
  /// start of the stem for prefixes and to the end for suffixes; matching is
  /// not implemented in this slice.
  condition : String
  /// Morphological fields (`po:`, `ds:`, `is:`, ...) in source order.
  morph : Array[String]
} derive(Eq, @debug.Debug)

///|
/// One `REP` replacement pair.
///
/// `from`/`to` are stored verbatim, so the Hunspell convention of `_` for a
/// space is preserved and must be interpreted by the consumer.
pub(all) struct Replacement {
  /// The text to look for.
  from : String
  /// The text to replace it with.
  to : String
} derive(Eq, @debug.Debug)

///|
/// One `PHONE` phonetic-transcription rule.
///
/// Both fields are stored verbatim. The pattern uses the Aspell/Hunspell
/// mini-language documented in the `hunspell(5)` manual (`(class)` character
/// classes, leading/trailing `-`, `<`, digit priorities, `^`, `$`); `_` as a
/// replacement means "output nothing".
pub(all) struct PhoneRule {
  /// The Aspell/Hunspell phonetic pattern, verbatim.
  pattern : String
  /// The replacement text; `_` means "output nothing".
  replacement : String
} derive(Eq, @debug.Debug)

///|
/// One `ICONV`/`OCONV` conversion pair.
///
/// `from`/`to` are stored verbatim. For `ICONV` a trailing `_` in `from` is the
/// Hunspell "end of word" marker (`ICONV <ZWJ>_ x` applies only when `<ZWJ>` is
/// the last character of the word, as the manual's `ICONV <200D>_ <FFF0>`
/// example describes); the consumer strips and interprets it.
pub(all) struct Conversion {
  /// The input sequence, verbatim (a trailing `_` for `ICONV` means end of word).
  from : String
  /// The output sequence.
  to : String
} derive(Eq, @debug.Debug)

///|
/// The flag-valued directives that mark a word (or affix) as special.
///
/// `None` means the directive was absent. Values are stored verbatim (see
/// `parse_aff` for how `AF` aliases are handled).
pub(all) struct SpecialFlags {
  /// `NOSUGGEST`: never offer the word as a suggestion.
  nosuggest : String?
  /// `KEEPCASE`: the word is only correct in the exact spelling given.
  keepcase : String?
  /// `FORBIDDENWORD`: the word is always wrong, even as an affixed form.
  forbiddenword : String?
  /// `NEEDAFFIX` (or its deprecated spelling `PSEUDOROOT`): the bare stem is not
  /// a word, only an affixed form of it is.
  needaffix : String?
  /// `CIRCUMFIX`: an affix carrying this flag must be paired with one of the
  /// opposite kind carrying it too.
  circumfix : String?
  /// `ONLYINCOMPOUND`: the word is only correct inside a compound.
  onlyincompound : String?
} derive(Eq, @debug.Debug)

///|
/// A directive this slice does not model, kept so that no input is rejected
/// merely for being unknown.
pub(all) struct UnknownDirective {
  /// The directive keyword, e.g. `ICONV`.
  name : String
  /// The remaining whitespace-separated arguments, verbatim.
  args : Array[String]
  /// 1-based line number the directive appeared on.
  line : Int
} derive(Eq, @debug.Debug)

///|
/// A parsed Hunspell `.aff` file.
///
/// `compound_min` is `0` when the file has no `COMPOUNDMIN` line (Hunspell's
/// own default of `3` is a matching-time concern for a later slice). `encoding`
/// is `""` when the file has no `SET` line.
pub(all) struct AffFile {
  /// `SET`: the declared encoding; `""` when the directive is absent.
  encoding : String
  /// `FLAG`: how flags are encoded in both files.
  flag_type : FlagType
  /// `LANG`: the language code, used for the Turkic `I`/`İ` casing rules
  /// (`LANG tr`, `az`, `crh`). `""` when the directive is absent.
  lang : String
  /// Headers of every `PFX`/`SFX` block, in source order.
  affix_headers : Array[AffixHeader]
  /// Every `PFX`/`SFX` rule line, in source order.
  affix_rules : Array[AffixRule]
  /// `AF` alias table; index `0` is alias `1`.
  flag_aliases : Array[String]
  /// `AM` alias table; index `0` is alias `1`.
  morph_aliases : Array[String]
  /// `REP` replacement pairs, in source order.
  replacements : Array[Replacement]
  /// `MAP` groups, in source order. Each entry is one `MAP` body line stored
  /// verbatim: a run of single characters (and/or parenthesized character
  /// sequences) that are considered interchangeable when suggesting.
  map_groups : Array[String]
  /// `PHONE` phonetic-transcription rules, in source order.
  phone_rules : Array[PhoneRule]
  /// `ICONV` input-conversion pairs, in source order. Applied to the word being
  /// checked before any lookup (never to dictionary entries).
  iconv : Array[Conversion]
  /// `OCONV` output-conversion pairs, in source order. Applied to suggestion
  /// output only.
  oconv : Array[Conversion]
  /// `TRY`: the characters the suggestion engine may substitute or insert.
  try_chars : String
  /// `KEY`: the keyboard layout, one row per `|`-separated group.
  keyboard : String
  /// `IGNORE`: characters to drop before comparing words.
  ignore_chars : String
  /// `WORDCHARS`: extra characters that may appear inside a word.
  word_chars : String
  /// `CHECKSHARPS`: German `ß` may be written `SS` in an uppercased word, and a
  /// `KEEPCASE` word containing `ß` may be capitalised or uppercased (but its
  /// uppercased form may only use `SS`, never a sharp s).
  check_sharps : Bool
  /// `COMPLEXPREFIXES`: twofold prefix matching is allowed, and only one suffix
  /// level instead of the default two (the manual's wording). Hunspell 1.7.3
  /// behaves exactly this way — a probe dictionary confirmed that twofold
  /// suffix stacking stops working and twofold prefix stacking starts.
  complex_prefixes : Bool
  /// Whether a `BREAK` directive appeared at all. `BREAK 0` declares "no break
  /// points", which is different from the directive being absent (Hunspell then
  /// breaks at `-`, `^-` and `-$`).
  breaks_declared : Bool
  /// The `BREAK` patterns, verbatim. A leading `^` or trailing `$` means "strip
  /// that text at the start" or "at the end" instead of splitting there.
  break_patterns : Array[String]
  /// `COMPOUNDMIN`: minimum length of a compound part; `0` when absent.
  compound_min : Int
  /// `COMPOUNDFLAG`: the flag a word needs to be any part of a compound.
  compound_flag : String?
  /// `COMPOUNDBEGIN`: the flag a word needs to start a compound.
  compound_begin : String?
  /// `COMPOUNDEND`: the flag a word needs to end a compound.
  compound_end : String?
  /// `COMPOUNDMIDDLE`: the flag a word needs to sit inside a compound.
  compound_middle : String?
  /// `COMPOUNDRULE` patterns, verbatim (e.g. `n*mp`).
  compound_rules : Array[String]
  /// `COMPOUNDPERMITFLAG`: an affix carrying this flag may sit *inside* a
  /// compound (a prefix that is not at the very front, or a suffix that is not
  /// at the very end). Affixes at those natural edges need no permit.
  compound_permit : String?
  /// `COMPOUNDFORBIDFLAG`: an affix carrying this flag forbids compounding of
  /// the word it builds; a plain entry carrying it is removed from the first and
  /// middle positions of a compound.
  compound_forbid : String?
  /// `FORCEUCASE`: a compound whose last part carries this flag is only correct
  /// in a capitalised (or all-caps) spelling.
  forceucase : String?
  /// `COMPOUNDWORDMAX`: maximum number of parts in a compound (`0` = unlimited).
  compound_word_max : Int
  /// `COMPOUNDSYLLABLE max_syllable vowels`: Hungarian syllable-count limit;
  /// `compound_syllable_max` is `0` when the directive is absent.
  compound_syllable_max : Int
  /// The `vowels` argument of `COMPOUNDSYLLABLE`.
  compound_syllable_vowels : String
  /// `CHECKCOMPOUNDDUP`: no compound part may be repeated.
  check_compound_dup : Bool
  /// `CHECKCOMPOUNDTRIPLE`: no three identical characters across a compound
  /// boundary.
  check_compound_triple : Bool
  /// `CHECKCOMPOUNDREP`: reject a compound that a `REP` rule can turn into a
  /// dictionary word.
  check_compound_repeat : Bool
  /// `SIMPLIFIEDTRIPLE`: allow a simplified letter at a compound boundary.
  check_compound_simplified_triple : Bool
  /// `CHECKCOMPOUNDCASE`: forbid upper-case characters at a compound boundary.
  check_compound_case : Bool
  /// `CHECKCOMPOUNDPATTERN` lines, verbatim; parsed at match time.
  check_compound_pattern : Array[String]
  /// The special-flag directives, collected.
  special_flags : SpecialFlags
  /// Directives with no typed field above, in source order.
  unrecognized : Array[UnknownDirective]
} derive(Eq, @debug.Debug)
