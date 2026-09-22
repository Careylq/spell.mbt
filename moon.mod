// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "YOURNAME/spell"

version = "0.1.0"

readme = "README.mbt.md"

// TODO(day 2): fill in the real GitHub URL, e.g.
// repository = "https://github.com/<你的GitHub用户名>/spell.mbt"
repository = ""

license = "Apache-2.0"

keywords = [
  "spellcheck",
  "hunspell",
  "dictionary",
  "affix",
  "text",
  "nlp",
]

preferred_target = "wasm"

description = "Pure-MoonBit spell checker compatible with the Hunspell .aff/.dic dictionary format."
