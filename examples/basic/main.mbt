// A runnable, self-contained example of the `spell.mbt` library.
//
// The `.aff` and `.dic` text is written from scratch right here — nothing is
// read from disk and nothing comes from the Hunspell test corpus (Hunspell is
// LGPL-2.1, this project is Apache-2.0).
//
// Run it with:
//
//   moon run examples/basic

///|
fn main {
  // Two suffix blocks, one prefix block, and a KEEPCASE flag. `S` builds regular
  // plurals, `D` shows a strip (`y` -> `ied`), and `U` prefixes `un-`.
  let aff =
    #|SET UTF-8
    #|TRY abcdefghijklmnopqrstuvwxyz
    #|KEEPCASE K
    #|SFX S Y 2
    #|SFX S 0 s [^sx]
    #|SFX S 0 es [sx]
    #|SFX D Y 1
    #|SFX D y ied [^aeiou]y
    #|PFX U Y 1
    #|PFX U 0 un .
  let dic =
    #|7
    #|cat/S
    #|box/S
    #|do/US
    #|happy/UD
    #|unhappy
    #|ebook/K
    #|word
  let dictionary = @spell.load(aff, dic) catch {
    error => {
      eprintln("example: could not load the dictionary: \{error.to_string()}")
      return
    }
  }
  println("spell.mbt — tiny dictionary written for this example")
  println("")
  println("encoding           : \{@spell.encoding(dictionary)}")
  println("flag type          : \{@spell.flag_type_name(dictionary)}")
  println("affix rules        : \{@spell.rule_count(dictionary)}")
  println("dictionary entries : \{@spell.entry_count(dictionary)}")
  println("")
  // `cats` and `boxes` come from `SFX S`, `happied` from the stripping `SFX D`,
  // `undos` needs `PFX U` + `SFX S` on the same stem, and `EBOOK` must be
  // rejected because `ebook` carries KEEPCASE.
  let words : Array[String] = [
    "cat", "cats", "box", "boxes", "happy", "happied", "unhappy", "undos", "ebook",
    "EBOOK", "Cat", "catss", "nope",
  ]
  println("word         correct?")
  for word in words {
    let verdict = if @spell.check(dictionary, word) { "yes" } else { "no" }
    println("  \{pad(word, 8)}\{verdict}")
  }
}

///|
/// Left-align `word` in a field of `width` characters (code points).
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
