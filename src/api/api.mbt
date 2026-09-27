// The public facade: load a dictionary, then check words.
//
// Clean-room implementation; Apache-2.0. See the repository README for the
// Quick start snippet this module is written to support.

///|
/// The dictionary type: parse once, then answer `check` queries.
pub using @spell {type Dictionary}

///|
/// The error raised while loading a dictionary: either the `.aff` or the `.dic`
/// parser failed, and its original line number and message are preserved.
pub using @spell {type SpellError}

///|
/// Load a dictionary from the text of a `.aff` file and the text of its `.dic`
/// file.
///
/// Parsing and indexing happen once; keep the returned `Dictionary` and call
/// `check` for every word. Raises `SpellError` when either text is malformed.
///
/// ```mbt check
/// test {
///   let dictionary = @api.load("SET UTF-8", "1\nhello")
///   assert_true(@api.check(dictionary, "hello"))
///   assert_false(@api.check(dictionary, "hella"))
/// }
/// ```
pub fn load(
  aff_text : String,
  dic_text : String,
) -> Dictionary raise SpellError {
  @spell.Dictionary::from_text(aff_text, dic_text)
}

///|
/// Is `word` correct according to `dictionary`?
///
/// See `@spell.Dictionary::check` for the capitalisation, affix, special-flag
/// and compound rules that decide the answer.
pub fn check(dictionary : Dictionary, word : String) -> Bool {
  dictionary.check(word)
}

///|
/// The `SET` encoding the `.aff` file declared, or `""` when it had none.
pub fn encoding(dictionary : Dictionary) -> String {
  dictionary.encoding()
}

///|
/// The `.aff` file's flag mode as a human-readable label.
///
/// This keeps `@aff.FlagType` out of the facade: a caller that only wants to
/// show the detected mode does not have to import the parser package.
pub fn flag_type_name(dictionary : Dictionary) -> String {
  match dictionary.flag_type() {
    @aff.SingleChar => "single character"
    @aff.Long => "FLAG long"
    @aff.Num => "FLAG num"
    @aff.Utf8 => "FLAG UTF-8"
  }
}

///|
/// How many `PFX`/`SFX` rule lines the `.aff` file declared.
pub fn rule_count(dictionary : Dictionary) -> Int {
  dictionary.rule_count()
}

///|
/// How many distinct words the `.dic` file holds.
pub fn entry_count(dictionary : Dictionary) -> Int {
  dictionary.entry_count()
}

///|
/// Suggestions for a misspelled `word`, best first and at most `limit`.
///
/// A word that `check` accepts needs no correction, so the result is empty.
/// Every returned candidate is a word `check` accepts. See
/// `@suggest.suggest` for the candidate sources and the ranking.
///
/// ```mbt check
/// test {
///   let dictionary = @api.load(
///     "SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\nREP 1\nREP ph f", "2\nform\nphantom",
///   )
///   assert_eq(@api.suggest(dictionary, "phorm", 5), ["form"])
/// }
/// ```
pub fn suggest(
  dictionary : Dictionary,
  word : String,
  limit : Int,
) -> Array[String] {
  @suggest.suggest(dictionary, word, limit)
}
