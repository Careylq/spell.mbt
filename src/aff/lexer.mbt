// Line-level lexer for Hunspell `.aff` files.
//
// The lexer is deliberately dumb and lossless: it normalizes line endings,
// drops blank and full-line-comment lines, and splits what is left on
// whitespace. It never interprets directives; that is the parser's job.

///|
/// A logical line of an `.aff` file after lexical processing.
///
/// Blank lines and full-line comments are already removed, so `number` values
/// are not contiguous; it is the 1-based line number in the source text.
priv struct AffLine {
  /// 1-based line number in the original text.
  number : Int
  /// The line with surrounding whitespace removed.
  text : String
  /// Whitespace-separated tokens of `text`; `tokens[0]` is the directive name.
  tokens : Array[String]
}

///|
/// Split `text` into logical lines and drop blank / full-line comment lines.
///
/// Comment policy is intentionally conservative: `#` starts a comment only when
/// it is the first non-whitespace character of a line. A mid-line `#` is kept
/// verbatim because it may be part of `AF`/`AM`/`REP` data or a morphological
/// field (e.g. a `ds:` value). As a consequence a trailing `SET UTF-8 # note`
/// keeps `#` and `note` as extra tokens; every modelled directive reads only the
/// arguments it expects, so that is harmless.
///
/// `\r\n`, `\n` and lone `\r` all end a line, so CRLF files get correct line
/// numbers.
fn lex_aff(text : String) -> Array[AffLine] {
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let lines : Array[AffLine] = []
  let mut number = 1
  for raw in normalized.split("\n") {
    let stripped = strip_line(raw)
    if !stripped.is_empty() {
      lines.push({ number, text: stripped, tokens: tokenize(stripped), })
    }
    number = number + 1
  }
  lines
}

///|
/// Remove surrounding whitespace and return `""` for blank or comment-only
/// lines. See `lex_aff` for the comment policy.
fn strip_line(raw : StringView) -> String {
  let trimmed = raw.trim()
  if trimmed.is_empty() || trimmed.has_prefix("#") {
    ""
  } else {
    trimmed.to_owned()
  }
}

///|
/// Split a trimmed line on runs of Unicode whitespace.
fn tokenize(text : String) -> Array[String] {
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
