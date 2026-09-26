// Parser for Hunspell `.dic` word lists.
//
// This is an independent, clean-room implementation of the format documented in
// the Hunspell manual. No Hunspell (LGPL-2.1) source code was consulted or
// copied; this project is Apache-2.0.
//
// The format is line-oriented: the first non-empty line is the declared entry
// count and every following non-empty line is one `word[/FLAGS] [morph...]`
// entry. Parsing is single-pass; the declared count is stored but never
// enforced against the number of entries actually present.

///|
/// A non-empty source line, kept with its original 1-based line number.
priv struct DicLine {
  number : Int
  text : String
}

///|
/// The error raised when the `.dic` text cannot be parsed.
///
/// `line` is the 1-based line number in the original text.
pub(all) suberror DicParseError {
  DicParseError(line~ : Int, message~ : String)
} derive(Eq, @debug.Debug)

///|
pub impl Show for DicParseError with fn to_string(self) {
  match self {
    DicParseError(line~, message~) => "line \{line}: \{message}"
  }
}

///|
/// Parse the text of a Hunspell `.dic` file.
///
/// `flag_type` comes from the matching `.aff` file (`FLAG long` / `num` /
/// `UTF-8`, anything else being single-character flags) and decides how the text
/// after `/` is split into flags.
///
/// Blank lines are ignored and `\r\n`, `\n` and lone `\r` all end a line. The
/// first non-empty line must be the declared entry count: it is stored as-is
/// even when the file holds a different number of entries, because stale counts
/// are common and harmless. A malformed count line raises `DicParseError`;
/// malformed *entry* lines do not, since the format gives them no syntax to
/// violate.
///
/// On an entry line the first whitespace-separated field is the word (with any
/// `\/` unescaped) optionally followed by `/` and its flags; the remaining
/// fields are morphological fields. A literal `/` in a word may be escaped as
/// `\/`.
pub fn parse_dic(
  text : String,
  flag_type : @aff.FlagType,
) -> DicFile raise DicParseError {
  let lines = preprocess(text)
  if lines.length() == 0 {
    raise DicParseError(line=1, message="missing entry count line")
  }
  let header = lines[0]
  let declared_count = parse_count(header)
  let entries : Array[DicEntry] = []
  let mut index = 1
  while index < lines.length() {
    entries.push(parse_entry(lines[index], flag_type))
    index = index + 1
  }
  { declared_count, entries, }
}

///|
/// Parse the count line into a non-negative `Int`, or report why it is not one.
///
/// Hunspell reads the count with a numeric scan and ignores whatever follows it
/// on the same line, and real dictionaries use that for a trailing comment
/// (`4 # Old Persian numbers`). Only the first whitespace-separated field is
/// therefore parsed; the error message still quotes the whole line so a
/// malformed count reports exactly what was there.
fn parse_count(line : DicLine) -> Int raise DicParseError {
  let fields = split_whitespace(line.text)
  let number = if fields.length() > 0 { fields[0] } else { line.text }
  let parsed : Int? = Some(@string.parse_int(number)) catch { _ => None }
  match parsed {
    Some(count) =>
      if count < 0 {
        raise DicParseError(
          line=line.number,
          message="entry count must not be negative, found \"\{line.text}\"",
        )
      } else {
        count
      }
    None =>
      raise DicParseError(
        line=line.number,
        message="expected an entry count, found \"\{line.text}\"",
      )
  }
}

///|
/// Split `text` into trimmed non-empty lines, remembering source line numbers.
fn preprocess(text : String) -> Array[DicLine] {
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let lines : Array[DicLine] = []
  let mut number = 1
  for raw in normalized.split("\n") {
    let trimmed = raw.trim()
    if !trimmed.is_empty() {
      lines.push({ number, text: trimmed.to_owned(), })
    }
    number = number + 1
  }
  lines
}

///|
/// Parse one entry line into a `DicEntry`.
fn parse_entry(line : DicLine, flag_type : @aff.FlagType) -> DicEntry {
  let tokens = split_whitespace(line.text)
  let (word, raw_flags) = split_word_flags(tokens[0])
  let flags = match raw_flags {
    Some(raw) => decode_flags(raw, flag_type)
    None => ([] : Array[String])
  }
  // The morphological fields start at the first colon-bearing token (Hunspell
  // writes them as `po:`, `ph:`, `st:`, ...); everything before it belongs to
  // the word, so `a lot ph:alot` is the word `a lot` with one morph field.
  let mut field_start = tokens.length()
  let mut index = 1
  while index < tokens.length() {
    if field_start == tokens.length() && tokens[index].contains(":") {
      field_start = index
    }
    index = index + 1
  }
  let morph : Array[String] = []
  index = field_start
  while index < tokens.length() {
    morph.push(tokens[index])
    index = index + 1
  }
  let full_word = if field_start <= 1 {
    word
  } else {
    full_word_of(tokens, field_start)
  }
  // A word pair carries its flags on the last word token (`black bird/S`), so
  // the whole-spelling alias needs those, not the first field's flags.
  let full_flags = if field_start <= 1 {
    flags
  } else {
    match split_word_flags(tokens[field_start - 1]) {
      (_, Some(raw)) => decode_flags(raw, flag_type)
      (_, None) => ([] : Array[String])
    }
  }
  { word, flags, morph, full_word, full_flags, }
}

///|
/// The word part of an entry line: the `count` tokens before the first
/// morphological field, joined by single spaces, with the `/FLAGS` suffix cut
/// off the last one (`forbidden root/A` -> `forbidden root`).
fn full_word_of(tokens : Array[String], count : Int) -> String {
  let buffer = StringBuilder()
  let mut index = 0
  while index < count {
    if index > 0 {
      buffer.write_char(' ')
    }
    if index + 1 == count {
      let (word, _) = split_word_flags(tokens[index])
      buffer.write_string(word)
    } else {
      buffer.write_string(tokens[index])
    }
    index = index + 1
  }
  buffer.to_string()
}

///|
/// Split the first field of an entry into its word and its raw flag text.
///
/// The word ends at the first unescaped `/` that is not the very first
/// character; `\/` is emitted as a literal `/`. A leading `/` belongs to the
/// word (`/foo/AB` is the word `/foo` with the flags `AB`, and `/AB` is just the
/// word `/AB`). Returns `None` for the flag text when the field has no
/// separator.
fn split_word_flags(field : String) -> (String, String?) {
  let chars = field.to_array()
  let word = StringBuilder()
  let mut raw_flags : String? = None
  let mut index = 0
  while index < chars.length() {
    let c = chars[index]
    if c == '\\' && index + 1 < chars.length() && chars[index + 1] == '/' {
      word.write_char('/')
      index = index + 2
    } else if c == '/' && index > 0 {
      let flags = StringBuilder()
      let mut rest = index + 1
      while rest < chars.length() {
        flags.write_char(chars[rest])
        rest = rest + 1
      }
      raw_flags = Some(flags.to_string())
      index = chars.length()
    } else {
      word.write_char(c)
      index = index + 1
    }
  }
  (word.to_string(), raw_flags)
}

///|
/// Decode the flag text after `/` according to the file's flag mode.
///
/// * `SingleChar` and `Utf8`: one character (Unicode scalar value) per flag.
/// * `Long`: two characters per flag; a trailing odd character is ignored,
///   because it cannot form a flag.
/// * `Num`: comma-separated decimal numbers, kept verbatim as strings; empty
///   fields between commas are skipped.
///
/// This is also how the continuation flags after the `/` of an affix rule's
/// `add` field are decoded (`SFX A 0 s/123 .`), so it is part of the package
/// interface rather than a private helper.
pub fn decode_flags(raw : String, flag_type : @aff.FlagType) -> Array[String] {
  match flag_type {
    @aff.SingleChar | @aff.Utf8 => {
      let flags : Array[String] = []
      for c in raw {
        flags.push(c.to_string())
      }
      flags
    }
    @aff.Long => {
      let chars = raw.to_array()
      let flags : Array[String] = []
      let mut index = 0
      while index + 1 < chars.length() {
        flags.push(chars[index].to_string() + chars[index + 1].to_string())
        index = index + 2
      }
      flags
    }
    @aff.Num => {
      let flags : Array[String] = []
      for part in raw.split(",") {
        let trimmed = part.trim()
        if !trimmed.is_empty() {
          flags.push(trimmed.to_owned())
        }
      }
      flags
    }
  }
}

///|
/// Split a trimmed line on runs of Unicode whitespace.
fn split_whitespace(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let buffer = StringBuilder()
  let mut pending = false
  for c in text {
    if c.is_whitespace() {
      if pending {
        tokens.push(buffer.to_string())
        buffer.reset()
        pending = false
      }
    } else {
      buffer.write_char(c)
      pending = true
    }
  }
  if pending {
    tokens.push(buffer.to_string())
  }
  tokens
}
