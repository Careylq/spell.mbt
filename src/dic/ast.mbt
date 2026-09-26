// Typed AST for a Hunspell `.dic` word list.
//
// This is an independent, clean-room model of the file format as documented in
// the Hunspell manual. No Hunspell (LGPL-2.1) source code was consulted or
// copied; this project is Apache-2.0.

///|
/// One entry line of a `.dic` file: `word[/FLAGS] [morph...]`.
///
/// `flags` is already decoded according to the matching `.aff` file's
/// `FlagType`, so a `FLAG long` file yields two-character flags and a
/// `FLAG num` file yields one decimal-number string per flag.
pub(all) struct DicEntry {
  /// The word, with an escaped `\/` unescaped to `/`.
  word : String
  /// Decoded flags in source order; empty when the entry has no `/`.
  flags : Array[String]
  /// Morphological fields (`po:`, `ds:`, `is:`, ...) in source order.
  morph : Array[String]
  /// The whole word as written, before the first morphological field.
  ///
  /// A `.dic` entry may be a word pair (`a lot ph:alot`): the first
  /// colon-bearing token starts the morphological fields and everything before
  /// it — with the `/FLAGS` suffix stripped from the last token — is one word.
  /// `word` deliberately stays the first whitespace-separated field because the
  /// judgement engine relies on that; `full_word` is what the `ph:` suggestion
  /// rules point at.
  full_word : String
  /// The flags of the last word token (`black bird/S` is the word `black bird`
  /// with the flags `S`), which is where a word pair's flags are written. Equal
  /// to `flags` for an entry whose word is a single field.
  full_flags : Array[String]
} derive(Eq, @debug.Debug)

///|
/// A parsed Hunspell `.dic` file.
///
/// `declared_count` is the integer on the file's first non-empty line. It is
/// kept even when it disagrees with `entries.length()`: real dictionaries are
/// sometimes stale, and the manual's count is advisory, so a mismatch is not an
/// error.
pub(all) struct DicFile {
  declared_count : Int
  /// Every entry line after the count line, in source order.
  entries : Array[DicEntry]
} derive(Eq, @debug.Debug)
