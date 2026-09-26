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

name = "Careylq/spell"

version = "0.6.0"

readme = "README.mbt.md"

// NOTE: the namespace must match your mooncakes.io account for `moon publish`.
// Run `moon register` / `moon login` first; `moon whoami` shows the effective user.

repository = "https://github.com/Careylq/spell.mbt"

license = "Apache-2.0"

keywords = [ "spellcheck", "hunspell", "dictionary", "affix", "text", "nlp" ]

preferred_target = "wasm"

description = "Pure-MoonBit spell checker compatible with the Hunspell .aff/.dic dictionary format."

import {
  "moonbitlang/x@0.5.5",
}
