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
  Prefix
  Suffix
} derive(Eq, @debug.Debug)

///|
/// The header line of a `PFX`/`SFX` block: `PFX flag cross_product count`.
pub(all) struct AffixHeader {
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
  from : String
  to : String
} derive(Eq, @debug.Debug)

///|
/// The flag-valued directives that mark a word (or affix) as special.
///
/// `None` means the directive was absent. Values are stored verbatim (see
/// `parse_aff` for how `AF` aliases are handled).
pub(all) struct SpecialFlags {
  nosuggest : String?
  keepcase : String?
  forbiddenword : String?
  needaffix : String?
  circumfix : String?
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
  encoding : String
  flag_type : FlagType
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
  try_chars : String
  keyboard : String
  ignore_chars : String
  word_chars : String
  /// `CHECKSHARPS`: German `ß` may be written `SS` in an uppercased word, and a
  /// `KEEPCASE` word containing `ß` may be capitalised or uppercased (but its
  /// uppercased form may only use `SS`, never a sharp s).
  check_sharps : Bool
  /// Whether a `BREAK` directive appeared at all. `BREAK 0` declares "no break
  /// points", which is different from the directive being absent (Hunspell then
  /// breaks at `-`, `^-` and `-$`).
  breaks_declared : Bool
  /// The `BREAK` patterns, verbatim. A leading `^` or trailing `$` means "strip
  /// that text at the start" or "at the end" instead of splitting there.
  break_patterns : Array[String]
  compound_min : Int
  compound_flag : String?
  compound_begin : String?
  compound_end : String?
  compound_middle : String?
  compound_rules : Array[String]
  check_compound_dup : Bool
  check_compound_triple : Bool
  check_compound_repeat : Bool
  check_compound_simplified_triple : Bool
  check_compound_pattern : Array[String]
  special_flags : SpecialFlags
  /// Directives with no typed field above, in source order.
  unrecognized : Array[UnknownDirective]
} derive(Eq, @debug.Debug)
