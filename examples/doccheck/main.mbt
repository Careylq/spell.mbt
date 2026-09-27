// `doccheck` — use `spell.mbt` to spell-check a MoonBit project's own docs.
//
// This is the library's dogfooding example: it reads the Markdown and the
// `///` / `//` comments of a source tree, turns them into candidate English
// words, and asks the library whether each word is correct. Every spelling
// decision is made by `@spell.check`, so the example also demonstrates the
// public API described in the README.
//
// Extraction rules, and why:
//
//   * Files: `*.md` (including `*.mbt.md`) and `*.mbt`. `*_test.mbt` and
//     `*_wbtest.mbt` are skipped unless `--include-tests` is given, because
//     test comments deliberately contain misspelled fixture words.
//   * Markdown: fenced code blocks (``` / ~~~), inline code spans (`...`),
//     HTML comments, link targets, and whitespace-separated tokens that
//     contain `/` (paths and URLs) are removed before tokenising.
//   * MoonBit: only lines whose first non-space characters are `///` or `//`
//     are read; code fences inside a `///` block are skipped.
//   * A candidate is a run of letters (or `'`) with no non-ASCII character.
//     A run that touches a digit, `.` or `_` is dropped (code identifiers,
//     file names, versions, hex), and so is an ALL-CAPS run. A possessive
//     (`word's`) is reduced to its base; any other word with an apostrophe is
//     skipped. Words shorter than three letters are skipped (`e.g.`, `is`).
//
// Known false positives, by construction:
//
//   * a general English dictionary (en_US) rejects project vocabulary
//     (`Hunspell`, `mooncakes`, `PFX`, ...), British spellings and proper
//     nouns, so an allowlist is required for real prose;
//   * an unclosed backtick or code fence can hide or leak text;
//   * a `//` line inside a multi-line string literal would be read as a
//     comment;
//   * hyphenated words are checked as two separate words, and link text is
//     checked while the link target is not.

///|
/// The parsed command line.
struct Options {
  aff : String?
  dic : String?
  allowlist : String?
  include_tests : Bool
  quiet : Bool
  dir : String
}

///|
/// What one run found. `mut` is used because these are direct assignments,
/// not array pushes (see docs/MOONBIT_GOTCHAS.md #3).
struct Report {
  mut files : Int
  mut words : Int
  mut hits : Int
  quiet : Bool
  /// Distinct misspelled words as written, with how often each was seen.
  distinct : Map[String, Int]
  /// Content hash -> content of every file already scanned. `README.md` is a
  /// symlink to `README.mbt.md` in this repository, and scanning the same
  /// bytes twice would double every number.
  scanned : Map[Int, String]
}

///|
fn main {
  let status = run(command_args())
  if status != 0 {
    @sys.exit(status)
  }
}

///|
/// The command line with the program name first, as `run` expects.
///
/// Node's `process.argv` (the js backend) starts with the interpreter path
/// instead, so that entry is dropped and the script path takes the
/// program-name slot.
#cfg(target="js")
fn command_args() -> Array[String] {
  let args = @env.args()
  let tail : Array[String] = []
  let mut index = 1
  while index < args.length() {
    tail.push(args[index])
    index = index + 1
  }
  tail
}

///|
#cfg(not(target="js"))
fn command_args() -> Array[String] {
  @env.args()
}

///|
/// Parse, scan, and report; returns the process exit status.
fn run(args : Array[String]) -> Int {
  if wants_help(args) {
    print_usage()
    return 0
  }
  let options = match parse_options(args) {
    Ok(options) => options
    Err(message) => {
      eprintln("doccheck: \{message}")
      print_usage()
      return 2
    }
  }
  let aff_path = match options.aff {
    Some(path) => path
    None => {
      eprintln("doccheck: --aff is required")
      print_usage()
      return 2
    }
  }
  let dic_path = match options.dic {
    Some(path) => path
    None => {
      eprintln("doccheck: --dic is required")
      print_usage()
      return 2
    }
  }
  let aff_text = match read_text(aff_path) {
    Ok(text) => text
    Err(message) => {
      eprintln("doccheck: \{message}")
      return 1
    }
  }
  let dic_text = match read_text(dic_path) {
    Ok(text) => text
    Err(message) => {
      eprintln("doccheck: \{message}")
      return 1
    }
  }
  let allowlist = match options.allowlist {
    None => []
    Some(path) =>
      match read_allowlist(path) {
        Ok(words) => words
        Err(message) => {
          eprintln("doccheck: \{message}")
          return 1
        }
      }
  }
  if !allowlist.is_empty() {
    println(
      "doccheck: \{allowlist.length()} allowlist entries added to the dictionary",
    )
  }
  let dictionary = match
    load_dictionary(aff_text, with_allowlist(dic_text, allowlist)) {
    Ok(dictionary) => dictionary
    Err(message) => {
      eprintln("doccheck: \{message}")
      return 1
    }
  }
  let report : Report = {
    files: 0,
    words: 0,
    hits: 0,
    quiet: options.quiet,
    distinct: Map([]),
    scanned: Map([]),
  }
  let root = normalize_dir(options.dir)
  if !is_directory(root) {
    eprintln("doccheck: not a directory: \{root}")
    return 1
  }
  scan_directory(root, root, dictionary, report, options.include_tests)
  print_summary(report)
  0
}

///|
/// How the program is meant to be called.
fn print_usage() -> Unit {
  let message =
    #|usage: doccheck --aff <file.aff> --dic <file.dic> [options] [<dir>]
    #|
    #|Spell-check the Markdown and MoonBit comments under <dir> (default ".").
    #|
    #|options:
    #|  --aff <path>        Hunspell .aff file (required)
    #|  --dic <path>        Hunspell .dic file (required)
    #|  --allowlist <path>  extra correct words, one per line (# comments allowed)
    #|  --include-tests     also scan *_test.mbt and *_wbtest.mbt
    #|  --quiet             print only the summary
    #|  -h, --help          show this message
    #|
    #|Run it with the wrapper, which fetches the dictionary at run time:
    #|  bash examples/doccheck/run.sh [--include-tests] [<dir>]
  eprintln(message)
}

///|
/// Was `-h` or `--help` asked for?
fn wants_help(args : Array[String]) -> Bool {
  for arg in args {
    if arg == "-h" || arg == "--help" {
      return true
    }
  }
  false
}

///|
/// Parse `args` (with the program name first).
fn parse_options(args : Array[String]) -> Result[Options, String] {
  let mut aff : String? = None
  let mut dic : String? = None
  let mut allowlist : String? = None
  let mut include_tests = false
  let mut quiet = false
  let mut dir : String? = None
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if arg == "--aff" {
      match next_arg(args, index, arg) {
        Ok(value) => {
          aff = Some(value)
          index = index + 2
        }
        Err(message) => return Err(message)
      }
    } else if arg == "--dic" {
      match next_arg(args, index, arg) {
        Ok(value) => {
          dic = Some(value)
          index = index + 2
        }
        Err(message) => return Err(message)
      }
    } else if arg == "--allowlist" {
      match next_arg(args, index, arg) {
        Ok(value) => {
          allowlist = Some(value)
          index = index + 2
        }
        Err(message) => return Err(message)
      }
    } else if arg == "--include-tests" {
      include_tests = true
      index = index + 1
    } else if arg == "--quiet" {
      quiet = true
      index = index + 1
    } else if arg.has_prefix("-") {
      return Err("unknown option \"\{arg}\"")
    } else {
      match dir {
        Some(_) => return Err("more than one directory given: \"\{arg}\"")
        None => {
          dir = Some(arg)
          index = index + 1
        }
      }
    }
  }
  Ok({
    aff,
    dic,
    allowlist,
    include_tests,
    quiet,
    dir: match dir {
      Some(path) => path
      None => "."
    },
  })
}

///|
/// The value that must follow `name` at `index + 1`.
fn next_arg(
  args : Array[String],
  index : Int,
  name : String,
) -> Result[String, String] {
  if index + 1 >= args.length() {
    Err("\{name} needs a value")
  } else {
    Ok(args[index + 1])
  }
}

///|
/// Read a UTF-8 text file, turning an IO failure into a message.
fn read_text(path : String) -> Result[String, String] {
  let text = @fs.read_file_to_string(path) catch {
    @fs.IOError(message) => return Err("cannot read \{path}: \{message}")
  }
  Ok(text)
}

///|
/// Read the allowlist: one word per line, `#` comments and blank lines ignored.
fn read_allowlist(path : String) -> Result[Array[String], String] {
  let text = match read_text(path) {
    Ok(text) => text
    Err(message) => return Err(message)
  }
  let words : Array[String] = []
  for raw in text.split("\n") {
    let line = raw.trim()
    if line.is_empty() || line.has_prefix("#") {
      continue
    }
    words.push(line.to_owned())
  }
  Ok(words)
}

///|
/// Load the dictionary, turning a parse failure into a message.
fn load_dictionary(
  aff_text : String,
  dic_text : String,
) -> Result[@spell.Dictionary, String] {
  let dictionary = @spell.load(aff_text, dic_text) catch {
    error => return Err("cannot load the dictionary: \{error.to_string()}")
  }
  Ok(dictionary)
}

///|
/// Strip a trailing `/` so that path joining stays simple.
fn normalize_dir(dir : String) -> String {
  let trimmed = dir.trim_end(chars="/").to_owned()
  if trimmed.is_empty() {
    "/"
  } else {
    trimmed
  }
}

///|
/// Is `path` an existing directory? Never raises.
fn is_directory(path : String) -> Bool {
  @fs.is_dir(path) catch {
    @fs.IOError(_) => false
  }
}

///|
/// Walk `dir`, scanning every candidate file below it.
fn scan_directory(
  dir : String,
  root : String,
  dictionary : @spell.Dictionary,
  report : Report,
  include_tests : Bool,
) -> Unit {
  let entries = @fs.read_dir(dir) catch {
    @fs.IOError(message) => {
      eprintln("doccheck: cannot list \{dir}: \{message}")
      return
    }
  }
  for name in entries {
    let path = dir + "/" + name
    if is_directory(path) {
      if should_descend(name) {
        scan_directory(path, root, dictionary, report, include_tests)
      }
    } else if is_candidate(name, include_tests) {
      scan_file(
        path,
        display_path(path, root),
        name.has_suffix(".md"),
        dictionary,
        report,
      )
    }
  }
}

///|
/// Should the walker enter a directory with this name?
///
/// Hidden directories (`.git`, `.mooncakes`, ...) and build output are never
/// part of the prose a contributor edits.
fn should_descend(name : String) -> Bool {
  !name.has_prefix(".") &&
  name != "_build" &&
  name != "node_modules" &&
  name != "target"
}

///|
/// Is this file worth scanning?
fn is_candidate(name : String, include_tests : Bool) -> Bool {
  let is_test = name.has_suffix("_test.mbt") || name.has_suffix("_wbtest.mbt")
  if is_test && !include_tests {
    return false
  }
  name.has_suffix(".md") || name.has_suffix(".mbt")
}

///|
/// The path as reported to the user: relative to the scanned root when it is
/// below it, absolute otherwise.
fn display_path(path : String, root : String) -> String {
  if path == root {
    return path
  }
  let prefix = root + "/"
  if path.has_prefix(prefix) {
    path[prefix.length():].to_owned()
  } else {
    path
  }
}

///|
/// Scan one file. IO failures are reported and skipped.
fn scan_file(
  path : String,
  display : String,
  is_markdown : Bool,
  dictionary : @spell.Dictionary,
  report : Report,
) -> Unit {
  let text = match read_text(path) {
    Ok(text) => text
    Err(message) => {
      eprintln("doccheck: \{message}")
      return
    }
  }
  let key = hash(text)
  match report.scanned.get(key) {
    Some(previous) =>
      if previous == text {
        // The same bytes were already scanned (a symlink or an identical copy).
        return
      }
    None => ()
  }
  report.scanned[key] = text
  report.files = report.files + 1
  let mut in_fence = false
  let mut number = 1
  for raw in text.split("\n") {
    let line = raw.to_owned()
    if is_markdown {
      if is_fence_line(line) {
        in_fence = !in_fence
      } else if !in_fence {
        check_line(line, display, number, dictionary, report)
      }
    } else {
      match comment_body(line) {
        Some(body) =>
          if is_fence_line(body) {
            in_fence = !in_fence
          } else if !in_fence {
            check_line(body, display, number, dictionary, report)
          }
        None => ()
      }
    }
    number = number + 1
  }
}

///|
/// The text after a leading `///` or `//`, or `None` when the line is not a
/// comment.
fn comment_body(line : String) -> String? {
  let trimmed = line.trim_start().to_owned()
  if trimmed.has_prefix("///") {
    Some(trimmed[3:].to_owned())
  } else if trimmed.has_prefix("//") {
    Some(trimmed[2:].to_owned())
  } else {
    None
  }
}

///|
/// Is this a Markdown code-fence line (``` or ~~~)?
fn is_fence_line(line : String) -> Bool {
  let trimmed = line.trim_start()
  trimmed.has_prefix("```") || trimmed.has_prefix("~~~")
}

///|
/// Check every candidate word on one prose line.
fn check_line(
  line : String,
  file : String,
  number : Int,
  dictionary : @spell.Dictionary,
  report : Report,
) -> Unit {
  for word in collect_words(clean_line(line)) {
    report.words = report.words + 1
    if !@spell.check(dictionary, word) {
      report.hits = report.hits + 1
      match report.distinct.get(word) {
        Some(count) => report.distinct[word] = count + 1
        None => report.distinct[word] = 1
      }
      if !report.quiet {
        println("\{file}:\{number}: \{word}")
      }
    }
  }
}

///|
/// Remove the parts of a prose line that are code, links or paths.
fn clean_line(line : String) -> String {
  drop_slash_tokens(
    strip_link_targets(strip_html_comments(strip_code_spans(line))),
  )
}

///|
/// Replace every `` `...` `` span with a space. An unmatched trailing backtick
/// is dropped on its own instead of swallowing the rest of the line.
fn strip_code_spans(line : String) -> String {
  let chars = line.to_array()
  let out = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '`' {
      let mut close = index + 1
      while close < chars.length() && chars[close] != '`' {
        close = close + 1
      }
      if close < chars.length() {
        out.write_char(' ')
        index = close + 1
      } else {
        index = index + 1
      }
    } else {
      out.write_char(chars[index])
      index = index + 1
    }
  }
  out.to_string()
}

///|
/// Drop `<!-- ... -->` comments that start and end on this line.
fn strip_html_comments(line : String) -> String {
  let chars = line.to_array()
  let out = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if starts_with_at(chars, index, "<!--") {
      let mut close = index + 4
      while close + 2 < chars.length() && !starts_with_at(chars, close, "-->") {
        close = close + 1
      }
      if close + 2 < chars.length() {
        index = close + 3
      } else {
        index = chars.length()
      }
      out.write_char(' ')
    } else {
      out.write_char(chars[index])
      index = index + 1
    }
  }
  out.to_string()
}

///|
/// Drop Markdown link targets (`](...)`), keeping the link text.
fn strip_link_targets(line : String) -> String {
  let chars = line.to_array()
  let out = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == ']' &&
      index + 1 < chars.length() &&
      chars[index + 1] == '(' {
      let mut close = index + 2
      while close < chars.length() && chars[close] != ')' {
        close = close + 1
      }
      index = if close < chars.length() { close + 1 } else { chars.length() }
      out.write_char(' ')
    } else {
      out.write_char(chars[index])
      index = index + 1
    }
  }
  out.to_string()
}

///|
/// Drop whitespace-separated tokens that contain `/`, i.e. paths and URLs.
fn drop_slash_tokens(line : String) -> String {
  let out = StringBuilder()
  let mut token = StringBuilder()
  let mut has_slash = false
  for c in line {
    if c == ' ' || c == '\t' {
      if !has_slash {
        out.write_string(token.to_string())
      }
      out.write_char(c)
      token = StringBuilder()
      has_slash = false
    } else {
      if c == '/' {
        has_slash = true
      }
      token.write_char(c)
    }
  }
  if !has_slash {
    out.write_string(token.to_string())
  }
  out.to_string()
}

///|
/// Does `chars` start with `prefix` at `index`?
fn starts_with_at(chars : Array[Char], index : Int, prefix : String) -> Bool {
  let wanted = prefix.to_array()
  if index + wanted.length() > chars.length() {
    return false
  }
  let mut offset = 0
  while offset < wanted.length() {
    if chars[index + offset] != wanted[offset] {
      return false
    }
    offset = offset + 1
  }
  true
}

///|
/// Extract the candidate words of one cleaned prose line.
fn collect_words(line : String) -> Array[String] {
  let chars = line.to_array()
  let words : Array[String] = []
  let mut index = 0
  while index < chars.length() {
    if is_word_char(chars[index]) {
      let start = index
      let mut non_ascii = false
      while index < chars.length() && is_word_char(chars[index]) {
        if !chars[index].is_ascii() {
          non_ascii = true
        }
        index = index + 1
      }
      if !non_ascii && !touches_code(chars, start, index) {
        match accept_word(chars_to_string(chars, start, index)) {
          Some(word) => words.push(word)
          None => ()
        }
      }
    } else {
      index = index + 1
    }
  }
  words
}

///|
/// A letter (any script) or an apostrophe.
fn is_word_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c == '\'' ||
  @unicode.non_ascii_id_start.contains(c) ||
  @unicode.non_ascii_id_continue.contains(c)
}

///|
/// Does the run `chars[start..end)` touch a digit, `.` or `_`? Such a run is
/// part of an identifier, a file name or a number, not of prose.
///
/// A `.` *after* the run only counts when another letter or digit follows it
/// (`moon.pkg`), so a sentence-ending period (`the end.`) still leaves the
/// last word visible.
fn touches_code(chars : Array[Char], start : Int, end : Int) -> Bool {
  let before = if start > 0 { Some(chars[start - 1]) } else { None }
  let after = if end < chars.length() { Some(chars[end]) } else { None }
  let bad_before = match before {
    Some(c) => c.is_ascii_digit() || c == '.' || c == '_'
    None => false
  }
  let bad_after = match after {
    Some(c) =>
      c.is_ascii_digit() ||
      c == '_' ||
      (
        c == '.' &&
        end + 1 < chars.length() &&
        (
          chars[end + 1].is_ascii_alphabetic() ||
          chars[end + 1].is_ascii_digit() ||
          chars[end + 1] == '_'
        )
      )
    None => false
  }
  bad_before || bad_after
}

///|
/// Decide whether a raw run is a word worth checking. Returns `None` for
/// everything the extractor skips.
fn accept_word(raw : String) -> String? {
  let base = strip_possessive(raw)
  if base.contains("'") {
    // a contraction or an internal quote, not prose we can judge
    return None
  }
  if base.length() < 3 {
    return None
  }
  if is_all_caps(base) {
    return None
  }
  Some(base)
}

///|
/// Reduce a possessive to its base: `manual's` -> `manual`, `parts'` -> `parts`.
/// Surrounding apostrophes are removed so that `'quoted'` survives as a word.
fn strip_possessive(raw : String) -> String {
  let trimmed = raw.trim(chars="'").to_owned()
  if trimmed.has_suffix("'s") || trimmed.has_suffix("'S") {
    trimmed[:trimmed.length() - 2].to_owned()
  } else if trimmed.has_suffix("'") {
    trimmed[:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
}

///|
/// Is every ASCII letter in `word` upper case? `UTF`, `PFX` and the like are
/// identifiers, not prose.
fn is_all_caps(word : String) -> Bool {
  let mut has_upper = false
  for c in word {
    if c.is_ascii_lowercase() {
      return false
    }
    if c.is_ascii_uppercase() {
      has_upper = true
    }
  }
  has_upper
}

///|
fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let out = StringBuilder()
  let mut index = start
  while index < end {
    out.write_char(chars[index])
    index = index + 1
  }
  out.to_string()
}

///|
/// Lower-case every character of `word`.
fn lowercase_word(word : String) -> String {
  let out = StringBuilder()
  for c in word {
    out.write_char(@unicode.to_lowercase(c))
  }
  out.to_string()
}

///|
/// Insert the allowlist into a `.dic` text: each entry is added verbatim and
/// in lower case, so the library accepts it in any capitalisation it knows.
/// The declared entry count is updated, although the parser tolerates a stale
/// one.
fn with_allowlist(dic_text : String, allowlist : Array[String]) -> String {
  if allowlist.is_empty() {
    return dic_text
  }
  let entries : Array[String] = []
  for word in allowlist {
    entries.push(word)
    let lower = lowercase_word(word)
    if lower != word {
      entries.push(lower)
    }
  }
  let (header, body) = match dic_text.find("\n") {
    Some(index) =>
      (dic_text[:index].to_owned(), dic_text[index + 1:].to_owned())
    None => (dic_text, "")
  }
  let declared : Int = @string.parse_int(header) catch { _ => 0 }
  let out = StringBuilder()
  out.write_string((declared + entries.length()).to_string())
  out.write_char('\n')
  if !body.is_empty() {
    out.write_string(body)
    if !body.has_suffix("\n") {
      out.write_char('\n')
    }
  }
  for entry in entries {
    out.write_string(entry)
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// Print the run's totals and the distinct words it rejected.
fn print_summary(report : Report) -> Unit {
  println("")
  println("files scanned     : \{report.files}")
  println("words checked     : \{report.words}")
  println("misspelled tokens : \{report.hits}")
  println("distinct words    : \{report.distinct.length()}")
  if report.distinct.length() > 0 {
    println("")
    println("distinct misspelled words (count):")
    let rows = report.distinct.to_array()
    rows.sort_by(fn(a, b) { b.1 - a.1 })
    for row in rows {
      println("  \{pad(row.1.to_string(), 6)}\{row.0}")
    }
  }
}

///|
/// Left-align `word` in a field of `width` characters.
fn pad(word : String, width : Int) -> String {
  let buffer = StringBuilder()
  buffer.write_string(word)
  let mut missing = width - word.char_length()
  while missing > 0 {
    buffer.write_char(' ')
    missing = missing - 1
  }
  buffer.to_string()
}
