// Whitebox tests for the CLI's encoding sniffing and for the incremental stdin
// reader behind `--words -`.
//
// `sniff_encoding` decides how the bytes of the `.aff`, `.dic` and word list are
// decoded, so it has to agree with the `SET` and `FLAG` directives real
// dictionaries carry.
//
// The stdin tests drive `read_all_chunks` with a fake source, so the "read until
// EOF" loop is covered without a real pipe. (A pipe cannot be created inside
// `moon test`; `conformance/pipe.sh` checks the real thing end to end.)

///|
/// Run `sniff_encoding` and name the result, so a test can compare labels
/// without the private enum needing `Eq`/`Debug`.
fn encoding_label(bytes : Bytes) -> String {
  match sniff_encoding(bytes) {
    Utf8 => "utf8"
    Latin1 => "latin1"
    Latin15 => "latin15"
  }
}

///|
test "sniff_encoding reads SET" {
  assert_eq(encoding_label(@unicode.to_utf8_bytes("SET UTF-8\n")), "utf8")
  assert_eq(encoding_label(@unicode.to_utf8_bytes("SET ISO8859-1\n")), "latin1")
  assert_eq(
    encoding_label(@unicode.to_utf8_bytes("SET ISO8859-15\n")),
    "latin15",
  )
  // no SET line at all: Hunspell's documented default
  assert_eq(
    encoding_label(@unicode.to_utf8_bytes("# nothing here\n")),
    "latin1",
  )
}

///|
test "FLAG UTF-8 implies a UTF-8 encoding when SET is absent" {
  // A multi-byte flag character is one Unicode character, so a file that
  // declares `FLAG UTF-8` cannot be single-byte encoded.
  assert_eq(
    encoding_label(
      @unicode.to_utf8_bytes("FLAG UTF-8\nSFX A 0 s/\u{00F6}\u{00FC} .\n"),
    ),
    "utf8",
  )
  assert_eq(encoding_label(@unicode.to_utf8_bytes("FLAG UTF-8\n")), "utf8")
  // A single-byte flag mode keeps the default.
  assert_eq(encoding_label(@unicode.to_utf8_bytes("FLAG long\n")), "latin1")
  assert_eq(encoding_label(@unicode.to_utf8_bytes("FLAG num\n")), "latin1")
  // An explicit SET always wins, whichever order the lines appear in.
  assert_eq(
    encoding_label(@unicode.to_utf8_bytes("FLAG UTF-8\nSET ISO8859-1\n")),
    "latin1",
  )
  assert_eq(
    encoding_label(@unicode.to_utf8_bytes("SET ISO8859-1\nFLAG UTF-8\n")),
    "latin1",
  )
}

///|
/// A `read_all_chunks` source that serves `chunks` in order and then reports end
/// of input with an empty view. It lets the read loop be tested without a real
/// stream, which a pipe cannot be inside `moon test`.
#cfg(any(target="native", target="llvm"))
fn chunk_source(chunks : Array[Bytes]) -> () -> Result[BytesView, String] {
  let mut index = 0
  fn() {
    if index >= chunks.length() {
      return Ok(Bytes::make(0, 0).exact_view())
    }
    let chunk = chunks[index]
    index = index + 1
    Ok(chunk.exact_view())
  }
}

///|
/// Read `chunks` through `read_all_chunks`, aborting the test on an unexpected
/// error so each test can assert on the bytes alone.
#cfg(any(target="native", target="llvm"))
fn read_chunks(chunks : Array[Bytes]) -> Bytes {
  match read_all_chunks(chunk_source(chunks)) {
    Ok(bytes) => bytes
    Err(message) => abort("unexpected read error: \{message}")
  }
}

///|
/// The chunk loop is what replaced the seek-based whole-file read for
/// `--words -` on native (docs/MOONBIT_GOTCHAS.md #33), so it is tested with an
/// empty stream, a stream that ends inside a chunk, and a stream whose last
/// chunk has no trailing newline.
#cfg(any(target="native", target="llvm"))
test "read_all_chunks joins every chunk in order" {
  assert_eq(
    @unicode.to_utf8_string(
      read_chunks([
        @unicode.to_utf8_bytes("hel"),
        @unicode.to_utf8_bytes("lo\n"),
        @unicode.to_utf8_bytes("wor"),
        @unicode.to_utf8_bytes("ld\n"),
      ]),
    ),
    "hello\nworld\n",
  )
}

///|
#cfg(any(target="native", target="llvm"))
test "read_all_chunks reads an empty stream as no bytes" {
  assert_eq(read_chunks([]).length(), 0)
  assert_eq(read_chunks([@unicode.to_utf8_bytes("")]).length(), 0)
}

///|
#cfg(any(target="native", target="llvm"))
test "read_all_chunks keeps a final chunk with no trailing newline" {
  // `printf 'hello'` (no newline) must still yield one word.
  assert_eq(
    @unicode.to_utf8_string(read_chunks([@unicode.to_utf8_bytes("hello")])),
    "hello",
  )
}

///|
#cfg(any(target="native", target="llvm"))
test "read_all_chunks propagates a read error" {
  let failing = fn() { Err("boom") }
  match read_all_chunks(failing) {
    Ok(_) => abort("expected the read error to be propagated")
    Err(message) => assert_eq(message, "boom")
  }
}

// --------------------------------------------------------------- option parsing
//
// `parse_options` decides which files a `check` run reads, and its `Err` strings are
// what a user sees on a mistake. The 69 lines of `main.mbt` that cover the option
// parser, `run` and the exit-code mapping were outside `moon test` — the exit codes
// were only exercised by `examples/ci-gate/run.sh`, which is a phase-2 (report-only)
// step, which is how a parser wart can survive. These pin the parser itself.

///|
/// Run `parse_options` and abort on an unexpected error, so a test can assert on the
/// parsed flags alone.
fn parse_ok(args : Array[String]) -> Options {
  match parse_options(args) {
    Ok(options) => options
    Err(message) => abort("unexpected parse error: \{message}")
  }
}

///|
/// Run `parse_options` and return the message, aborting if it unexpectedly succeeded.
fn parse_err(args : Array[String]) -> String {
  match parse_options(args) {
    Ok(_) => abort("expected a parse error")
    Err(message) => message
  }
}

///|
test "parse_options reads the three flags in any order" {
  let options = parse_ok([
    "spell", "check", "--dic", "d.dic", "--words", "w.txt", "--aff", "a.aff",
  ])
  assert_eq(options.aff, Some("a.aff"))
  assert_eq(options.dic, Some("d.dic"))
  assert_eq(options.words, Some("w.txt"))
}

///|
test "parse_options leaves a flag it never saw as None" {
  let options = parse_ok(["spell", "check", "--aff", "a.aff"])
  assert_eq(options.aff, Some("a.aff"))
  assert_eq(options.dic, (None : String?))
  assert_eq(options.words, (None : String?))
}

///|
test "a repeated flag keeps the last value" {
  let options = parse_ok([
    "spell", "check", "--aff", "one.aff", "--aff", "two.aff",
  ])
  assert_eq(options.aff, Some("two.aff"))
}

///|
test "parse_options names the unknown option it rejected" {
  assert_eq(
    parse_err(["spell", "check", "--aff", "a.aff", "--oops", "x"]),
    "unknown option \"--oops\"",
  )
}

///|
test "parse_options reports a flag that has no value after it" {
  assert_eq(parse_err(["spell", "check", "--aff"]), "--aff needs a value")
}

// ------------------------------------------------------------- --help handling
//
// `spell --help` used to answer "unknown subcommand \"--help\"" and `spell check
// --help` used to answer "--help needs a value" -- the first two things a new user
// types, and a bad first impression on a repository whose README tells you to run the
// CLI. The exit codes are asserted for real by `examples/ci-gate/run.sh`; what is
// pinned here is the predicate that decides, and the text both printers read.

///|
test "wants_help sees --help and -h in option position" {
  assert_true(wants_help(["spell", "check", "--help"]))
  assert_true(wants_help(["spell", "check", "-h"]))
  assert_true(wants_help(["spell", "suggest", "--help"]))
  // after real options, which is where people actually put it
  assert_true(wants_help(["spell", "check", "--aff", "a.aff", "--help"]))
  assert_true(
    wants_help(["spell", "check", "--aff", "a.aff", "--dic", "d.dic", "-h"]),
  )
}

///|
test "wants_help does not mistake a flag's value for a request for help" {
  // `--help` here is the *value* of `--aff`, not an option: the scan steps two at a
  // time precisely so a file called `--help` stays a file.
  assert_false(wants_help(["spell", "check", "--aff", "--help"]))
  assert_false(wants_help(["spell", "check", "--aff", "a.aff"]))
  assert_false(wants_help(["spell", "check"]))
  assert_false(wants_help(["spell", "suggest"]))
}

///|
test "the usage text documents --help and both subcommands" {
  let text = usage_lines().join("\n")
  assert_true(text.contains("--help"))
  assert_true(text.contains("spell check"))
  assert_true(text.contains("spell suggest"))
  assert_true(text.contains("--words"))
}

///|
/// `is_valid_utf8` chooses between decoding a word list as UTF-8 and decoding it as the
/// legacy encoding the `.aff` declares, so a byte sequence UTF-8 cannot represent must
/// not be accepted as UTF-8. The function claimed to reject overlong forms and had no
/// test; these are the cases that were wrong.
test "is_valid_utf8 rejects overlong forms, surrogates and out-of-range code points" {
  // 2-byte overlong for U+0049 (already rejected, kept as the control)
  assert_false(is_valid_utf8(Bytes::from_array([0xC1, 0xA9])))
  // 3-byte overlong for U+00E9
  assert_false(is_valid_utf8(Bytes::from_array([0xE0, 0x83, 0xA9])))
  // surrogate U+D800
  assert_false(is_valid_utf8(Bytes::from_array([0xED, 0xA0, 0x80])))
  // 4-byte overlong
  assert_false(is_valid_utf8(Bytes::from_array([0xF0, 0x80, 0x80, 0xAF])))
  // above U+10FFFF
  assert_false(is_valid_utf8(Bytes::from_array([0xF4, 0x90, 0x80, 0x80])))
  // truncated and stray continuation bytes
  assert_false(is_valid_utf8(Bytes::from_array([0xE0, 0xA0])))
  assert_false(is_valid_utf8(Bytes::from_array([0x80])))
  // and the legal neighbours of each rejected case must still be accepted, or the
  // function would have become useless rather than strict
  assert_true(is_valid_utf8(@unicode.to_utf8_bytes("é")))
  assert_true(is_valid_utf8(@unicode.to_utf8_bytes("€")))
  assert_true(is_valid_utf8(@unicode.to_utf8_bytes("😀")))
  assert_true(is_valid_utf8(@unicode.to_utf8_bytes("ascii")))
}
