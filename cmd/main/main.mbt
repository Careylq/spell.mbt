// `spell` — a command-line front end for the spell-checking library.
//
// Contract (see conformance/README.md):
//
//   moon run cmd/main -- check --aff <file.aff> --dic <file.dic> --words -
//
// Words are read one per line from stdin (`--words -`) or from a file, and one
// line `1` (correct) / `0` (incorrect) is printed per input word, in input
// order. Empty input lines produce no output at all, so the output lines line up
// one-to-one with the non-empty lines of the input. The dictionary is loaded
// once; a failure to read or parse either file exits non-zero with a message on
// stderr instead of printing verdicts.
//
// The `.aff` file's `SET` directive decides how the bytes of all three inputs
// are decoded. UTF-8 is decoded as UTF-8; anything else (ISO8859-*, KOI8-*, ...)
// is decoded byte-for-byte into the matching code point, which keeps the `.aff`,
// the `.dic` and the input words consistent with one another even for the
// legacy encodings that the Hunspell test corpus uses.

///|
/// How the bytes of the `.aff`, `.dic` and word input are decoded.
priv enum FileEncoding {
  Utf8
  /// One code point per byte (`ISO8859-1` and a safe fallback for the other
  /// single-byte encodings).
  Latin1
  /// `ISO8859-15`, which differs from Latin-1 in eight code points (notably the
  /// euro sign and `œ`/`Œ`).
  Latin15
}

///|
/// Run the command line and terminate with its status.
fn main {
  let status = run(@env.args())
  if status != 0 {
    @sys.exit(status)
  }
}

///|
/// Parse the arguments, run the `check` subcommand, and return the exit status.
fn run(args : Array[String]) -> Int {
  if args.length() < 2 {
    print_usage()
    return 2
  }
  if args[1] != "check" {
    eprintln("spell: unknown subcommand \"\{args[1]}\"")
    print_usage()
    return 2
  }
  let options = match parse_options(args) {
    Ok(options) => options
    Err(message) => {
      eprintln("spell: \{message}")
      print_usage()
      return 2
    }
  }
  let aff_path = match options.aff {
    Some(path) => path
    None => {
      eprintln("spell: --aff is required")
      print_usage()
      return 2
    }
  }
  let dic_path = match options.dic {
    Some(path) => path
    None => {
      eprintln("spell: --dic is required")
      print_usage()
      return 2
    }
  }
  let aff_bytes = match read_bytes(aff_path) {
    Ok(bytes) => bytes
    Err(message) => {
      eprintln("spell: \{message}")
      return 1
    }
  }
  // The `.aff` decides the encoding for all three inputs.
  let encoding = sniff_encoding(aff_bytes)
  let aff_text = strip_bom(decode_bytes(aff_bytes, encoding))
  let dic_bytes = match read_bytes(dic_path) {
    Ok(bytes) => bytes
    Err(message) => {
      eprintln("spell: \{message}")
      return 1
    }
  }
  let dic_text = strip_bom(decode_bytes(dic_bytes, encoding))
  let dictionary = match load_dictionary(aff_text, dic_text) {
    Ok(dictionary) => dictionary
    Err(message) => {
      eprintln("spell: \{message}")
      return 1
    }
  }
  let words_source = match options.words {
    Some(source) => source
    None => "-"
  }
  let words_path = if words_source == "-" { "/dev/stdin" } else { words_source }
  let words_bytes = match read_bytes(words_path) {
    Ok(bytes) => bytes
    Err(message) => {
      eprintln("spell: \{message}")
      return 1
    }
  }
  let words_text = strip_bom(decode_words(words_bytes, encoding))
  let verdicts : Array[String] = []
  for raw in words_text.split("\n") {
    let line = match raw.strip_suffix("\r") {
      Some(view) => view.to_owned()
      None => raw.to_owned()
    }
    // An input line that is empty produces no output, so the output lines line
    // up with the non-empty input lines. A line that has content but only
    // whitespace still produces a verdict, keeping that alignment exact.
    if !line.is_empty() {
      let word = line.trim()
      let correct = !word.is_empty() && dictionary.check(word.to_owned())
      verdicts.push(if correct { "1" } else { "0" })
    }
  }
  if !verdicts.is_empty() {
    println(verdicts.join("\n"))
  }
  0
}

///|
/// The accepted `check` options; each is `None` until its flag is seen.
struct Options {
  aff : String?
  dic : String?
  words : String?
}

///|
/// Read the `--aff` / `--dic` / `--words` flags, rejecting anything else.
fn parse_options(args : Array[String]) -> Result[Options, String] {
  let mut aff : String? = None
  let mut dic : String? = None
  let mut words : String? = None
  let mut index = 2
  while index < args.length() {
    let option = args[index]
    if index + 1 >= args.length() {
      return Err("\{option} needs a value")
    }
    let value = args[index + 1]
    if option == "--aff" {
      aff = Some(value)
    } else if option == "--dic" {
      dic = Some(value)
    } else if option == "--words" {
      words = Some(value)
    } else {
      return Err("unknown option \"\{option}\"")
    }
    index = index + 2
  }
  Ok({ aff, dic, words, })
}

///|
/// Read a whole file (or the `/dev/stdin` pseudo-file for `--words -`) raw.
fn read_bytes(path : String) -> Result[Bytes, String] {
  Ok(@fs.read_file_to_bytes(path)) catch {
    @fs.IOError(message) => Err("cannot read \"\{path}\": \{message}")
  }
}

///|
/// Read the `SET` directive without needing to know the encoding yet: the
/// directive itself is ASCII, so a byte-preserving decode is enough to find it.
/// A leading UTF-8 byte-order mark is skipped so it cannot hide the directive.
///
/// `FLAG UTF-8` is treated as declaring the file encoding when there is no
/// `SET` line: one flag is one Unicode character, so the flag text can only be
/// meant as UTF-8. (The corpus' `flagutf8` suite is exactly this shape, and
/// without this rule a multi-byte flag character is read as two Latin-1
/// characters in the `.aff` but as two one-character flags in the `.dic`, so
/// the two never compare equal.)
fn sniff_encoding(bytes : Bytes) -> FileEncoding {
  let text = decode_bytes(bytes, Latin1)
  let text = match text.strip_prefix("\u{00EF}\u{00BB}\u{00BF}") {
    Some(rest) => rest.to_owned()
    None => text
  }
  let mut flag_utf8 = false
  for line in text.split("\n") {
    let trimmed = line.trim()
    if trimmed.is_empty() {
      continue
    }
    match trimmed.strip_prefix("SET") {
      Some(rest) =>
        if !rest.is_empty() && first_char_is_space(rest) {
          let name = rest.trim()
          if name.contains("UTF") || name.contains("utf") {
            return Utf8
          } else if name.contains("8859-15") {
            return Latin15
          } else {
            return Latin1
          }
        }
      None => ()
    }
    match trimmed.strip_prefix("FLAG") {
      Some(rest) =>
        if !rest.is_empty() && first_char_is_space(rest) {
          let name = rest.trim()
          if name == "UTF-8" || name == "utf-8" {
            flag_utf8 = true
          }
        }
      None => ()
    }
  }
  if flag_utf8 {
    return Utf8
  }
  // No `SET` line: Hunspell's documented default is ISO8859-1.
  Latin1
}

///|
/// Does `text` begin with a whitespace character?
fn first_char_is_space(text : StringView) -> Bool {
  for c in text {
    return c.is_whitespace()
  }
  false
}

///|
/// Decode raw bytes with the file's encoding.
fn decode_bytes(bytes : Bytes, encoding : FileEncoding) -> String {
  match encoding {
    Utf8 => @unicode.to_utf8_string(bytes)
    Latin1 => decode_single_byte(bytes, false)
    Latin15 => decode_single_byte(bytes, true)
  }
}

///|
/// Decode one code point per byte, optionally applying the ISO8859-15
/// differences from Latin-1.
fn decode_single_byte(bytes : Bytes, latin15 : Bool) -> String {
  let buffer = StringBuilder()
  let mut index = 0
  while index < bytes.length() {
    let code = bytes[index].to_int()
    let mapped = if latin15 { latin15_code_point(code) } else { code }
    buffer.write_char(mapped.unsafe_to_char())
    index = index + 1
  }
  buffer.to_string()
}

///|
/// The eight code points where ISO8859-15 differs from ISO8859-1.
fn latin15_code_point(code : Int) -> Int {
  match code {
    0xA4 => 0x20AC // €
    0xA6 => 0x0160 // Š
    0xA8 => 0x0161 // š
    0xB4 => 0x017D // Ž
    0xB8 => 0x017E // ž
    0xBC => 0x0152 // Œ
    0xBD => 0x0153 // œ
    0xBE => 0x0178 // Ÿ
    _ => code
  }
}

///|
/// Decode the word list.
///
/// The `.aff`/`.dic` pair and the word list are not guaranteed to share an
/// encoding: the Hunspell test corpus keeps legacy-encoded dictionaries next to
/// UTF-8 word lists. So a word input that is valid UTF-8 is decoded as UTF-8,
/// and only genuinely non-UTF-8 input falls back to the dictionary's
/// single-byte encoding.
fn decode_words(bytes : Bytes, encoding : FileEncoding) -> String {
  match encoding {
    Utf8 => @unicode.to_utf8_string(bytes)
    _ =>
      if is_valid_utf8(bytes) {
        @unicode.to_utf8_string(bytes)
      } else {
        decode_bytes(bytes, encoding)
      }
  }
}

///|
/// Strictly validate UTF-8 (overlong forms, stray continuation bytes and
/// truncated sequences all count as invalid), so the fallback above only
/// triggers when the input really is not UTF-8.
fn is_valid_utf8(bytes : Bytes) -> Bool {
  let length = bytes.length()
  let mut index = 0
  while index < length {
    let first = bytes[index].to_int()
    if first < 0x80 {
      index = index + 1
    } else if first >= 0xC2 && first <= 0xDF {
      if index + 1 >= length || !is_continuation(bytes[index + 1]) {
        return false
      }
      index = index + 2
    } else if first >= 0xE0 && first <= 0xEF {
      if index + 2 >= length ||
        !is_continuation(bytes[index + 1]) ||
        !is_continuation(bytes[index + 2]) {
        return false
      }
      index = index + 3
    } else if first >= 0xF0 && first <= 0xF4 {
      if index + 3 >= length ||
        !is_continuation(bytes[index + 1]) ||
        !is_continuation(bytes[index + 2]) ||
        !is_continuation(bytes[index + 3]) {
        return false
      }
      index = index + 4
    } else {
      return false
    }
  }
  true
}

///|
/// Is this byte a UTF-8 continuation byte (`10xxxxxx`)?
fn is_continuation(byte : Byte) -> Bool {
  (byte.to_int() & 0xC0) == 0x80
}

///|
/// Drop a leading UTF-8 byte-order mark, which some dictionaries carry.
fn strip_bom(text : String) -> String {
  match text.strip_prefix("\u{FEFF}") {
    Some(rest) => rest.to_owned()
    None => text
  }
}

///|
/// Build the dictionary, turning a parse error into a printable message.
fn load_dictionary(
  aff_text : String,
  dic_text : String,
) -> Result[@api.Dictionary, String] {
  Ok(@api.load(aff_text, dic_text)) catch {
    error => Err("cannot load dictionary: \{error.to_string()}")
  }
}

///|
/// Print the accepted command shape to stderr.
fn print_usage() -> Unit {
  eprintln(
    "usage: spell check --aff <file.aff> --dic <file.dic> [--words <file>|-]",
  )
  eprintln("  --words -  read one word per line from stdin (the default)")
  eprintln("  prints one line per input word: 1 = correct, 0 = incorrect")
}
