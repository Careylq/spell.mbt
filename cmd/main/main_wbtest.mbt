// Whitebox tests for the CLI's encoding sniffing.
//
// `sniff_encoding` decides how the bytes of the `.aff`, `.dic` and word list are
// decoded, so it has to agree with the `SET` and `FLAG` directives real
// dictionaries carry.

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
