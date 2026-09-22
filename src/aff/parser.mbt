// Directive-level parser for Hunspell `.aff` files.
//
// `parse_aff` walks the logical lines produced by `lex_aff`, fills an
// `AffBuilder`, and converts it to an immutable `AffFile`. Directives without a
// typed field are recorded in `unrecognized`; a modelled directive with
// malformed arguments raises `AffParseError` carrying the source line number.

///|
/// The error raised when a modelled directive cannot be parsed.
///
/// `line` is the 1-based line number in the original `.aff` text.
pub(all) suberror AffParseError {
  AffParseError(line~ : Int, message~ : String)
} derive(Eq, @debug.Debug)

///|
pub impl Show for AffParseError with fn to_string(self) {
  match self {
    AffParseError(line~, message~) => "line \{line}: \{message}"
  }
}

///|
/// Parse the text of a Hunspell `.aff` file into a typed AST.
///
/// The first malformed modelled directive stops the parse and raises
/// `AffParseError`. Unknown directives are collected in
/// `AffFile::unrecognized` instead of being rejected.
///
/// `AF` aliases are resolved for `PFX`/`SFX` flag arguments (Hunspell replaces
/// affix flags with alias indices when an `AF` table is present). Flag values in
/// other directives are stored verbatim so that no information is lost.
///
/// Parsing is single-pass, so an `AF` table must appear before the affix rules
/// that reference it. Real `.aff` files place `AF`/`AM` near the top, so this
/// matches the format in practice.
pub fn parse_aff(text : String) -> AffFile raise AffParseError {
  let lines = lex_aff(text)
  let builder = new_builder()
  let mut index = 0
  while index < lines.length() {
    let line = lines[index]
    let tokens = line.tokens
    let name = tokens[0]
    index = index + 1
    match name {
      "SET" => builder.encoding = arg_at(line, 1, name)
      "FLAG" => builder.flag_type = parse_flag_type(line, name)
      "AF" => {
        let count = parse_count(arg_at(line, 1, name), line.number, name)
        let (body, next) = take_body(lines, index, name, count, line.number)
        index = next
        for entry in body {
          builder.flag_aliases.push(arg_at(entry, 1, name))
        }
      }
      "AM" => {
        let count = parse_count(arg_at(line, 1, name), line.number, name)
        let (body, next) = take_body(lines, index, name, count, line.number)
        index = next
        for entry in body {
          builder.morph_aliases.push(arg_at(entry, 1, name))
        }
      }
      "PFX" => index = parse_affix_block(builder, lines, index, Prefix, line)
      "SFX" => index = parse_affix_block(builder, lines, index, Suffix, line)
      "REP" => {
        let count = parse_count(arg_at(line, 1, name), line.number, name)
        let (body, next) = take_body(lines, index, name, count, line.number)
        index = next
        for entry in body {
          let from = arg_at(entry, 1, name)
          let to = arg_at(entry, 2, name)
          builder.replacements.push({ from, to, })
        }
      }
      "TRY" => builder.try_chars = arg_at(line, 1, name)
      "KEY" => builder.keyboard = arg_at(line, 1, name)
      "IGNORE" => builder.ignore_chars = arg_at(line, 1, name)
      "WORDCHARS" => builder.word_chars = arg_at(line, 1, name)
      "COMPOUNDMIN" =>
        builder.compound_min = parse_count(
          arg_at(line, 1, name),
          line.number,
          name,
        )
      "COMPOUNDFLAG" => builder.compound_flag = Some(arg_at(line, 1, name))
      "COMPOUNDBEGIN" => builder.compound_begin = Some(arg_at(line, 1, name))
      "COMPOUNDEND" => builder.compound_end = Some(arg_at(line, 1, name))
      "COMPOUNDMIDDLE" => builder.compound_middle = Some(arg_at(line, 1, name))
      "COMPOUNDRULE" => {
        let count = parse_count(arg_at(line, 1, name), line.number, name)
        let (body, next) = take_body(lines, index, name, count, line.number)
        index = next
        for entry in body {
          builder.compound_rules.push(join_tail(entry, 1))
        }
      }
      "CHECKCOMPOUNDDUP" => builder.check_compound_dup = true
      "CHECKCOMPOUNDTRIPLE" => builder.check_compound_triple = true
      "CHECKCOMPOUNDREPEAT" => builder.check_compound_repeat = true
      "CHECKCOMPOUNDSIMPLIFIEDTRIPLE" =>
        builder.check_compound_simplified_triple = true
      "CHECKCOMPOUNDPATTERN" => {
        let count = parse_count(arg_at(line, 1, name), line.number, name)
        let (body, next) = take_body(lines, index, name, count, line.number)
        index = next
        for entry in body {
          builder.check_compound_pattern.push(join_tail(entry, 1))
        }
      }
      "NOSUGGEST" => builder.special_nosuggest = Some(arg_at(line, 1, name))
      "KEEPCASE" => builder.special_keepcase = Some(arg_at(line, 1, name))
      "FORBIDDENWORD" =>
        builder.special_forbiddenword = Some(arg_at(line, 1, name))
      "NEEDAFFIX" => builder.special_needaffix = Some(arg_at(line, 1, name))
      "CIRCUMFIX" => builder.special_circumfix = Some(arg_at(line, 1, name))
      "ONLYINCOMPOUND" =>
        builder.special_onlyincompound = Some(arg_at(line, 1, name))
      _ =>
        builder.unrecognized.push({
          name,
          args: tail_from(tokens, 1),
          line: line.number,
        })
    }
  }
  finish(builder)
}

///|
/// Mutable accumulator used while parsing. Converted to `AffFile` by `finish`.
priv struct AffBuilder {
  mut encoding : String
  mut flag_type : FlagType
  affix_headers : Array[AffixHeader]
  affix_rules : Array[AffixRule]
  flag_aliases : Array[String]
  morph_aliases : Array[String]
  replacements : Array[Replacement]
  mut try_chars : String
  mut keyboard : String
  mut ignore_chars : String
  mut word_chars : String
  mut compound_min : Int
  mut compound_flag : String?
  mut compound_begin : String?
  mut compound_end : String?
  mut compound_middle : String?
  compound_rules : Array[String]
  mut check_compound_dup : Bool
  mut check_compound_triple : Bool
  mut check_compound_repeat : Bool
  mut check_compound_simplified_triple : Bool
  check_compound_pattern : Array[String]
  mut special_nosuggest : String?
  mut special_keepcase : String?
  mut special_forbiddenword : String?
  mut special_needaffix : String?
  mut special_circumfix : String?
  mut special_onlyincompound : String?
  unrecognized : Array[UnknownDirective]
}

///|
/// An empty builder: no `SET` line (`encoding = ""`), single-character flags,
/// and every optional directive absent.
fn new_builder() -> AffBuilder {
  {
    encoding: "",
    flag_type: SingleChar,
    affix_headers: [],
    affix_rules: [],
    flag_aliases: [],
    morph_aliases: [],
    replacements: [],
    try_chars: "",
    keyboard: "",
    ignore_chars: "",
    word_chars: "",
    compound_min: 0,
    compound_flag: None,
    compound_begin: None,
    compound_end: None,
    compound_middle: None,
    compound_rules: [],
    check_compound_dup: false,
    check_compound_triple: false,
    check_compound_repeat: false,
    check_compound_simplified_triple: false,
    check_compound_pattern: [],
    special_nosuggest: None,
    special_keepcase: None,
    special_forbiddenword: None,
    special_needaffix: None,
    special_circumfix: None,
    special_onlyincompound: None,
    unrecognized: [],
  }
}

///|
/// Freeze the mutable accumulator into the public AST.
fn finish(builder : AffBuilder) -> AffFile {
  let special_flags : SpecialFlags = {
    nosuggest: builder.special_nosuggest,
    keepcase: builder.special_keepcase,
    forbiddenword: builder.special_forbiddenword,
    needaffix: builder.special_needaffix,
    circumfix: builder.special_circumfix,
    onlyincompound: builder.special_onlyincompound,
  }
  {
    encoding: builder.encoding,
    flag_type: builder.flag_type,
    affix_headers: builder.affix_headers,
    affix_rules: builder.affix_rules,
    flag_aliases: builder.flag_aliases,
    morph_aliases: builder.morph_aliases,
    replacements: builder.replacements,
    try_chars: builder.try_chars,
    keyboard: builder.keyboard,
    ignore_chars: builder.ignore_chars,
    word_chars: builder.word_chars,
    compound_min: builder.compound_min,
    compound_flag: builder.compound_flag,
    compound_begin: builder.compound_begin,
    compound_end: builder.compound_end,
    compound_middle: builder.compound_middle,
    compound_rules: builder.compound_rules,
    check_compound_dup: builder.check_compound_dup,
    check_compound_triple: builder.check_compound_triple,
    check_compound_repeat: builder.check_compound_repeat,
    check_compound_simplified_triple: builder.check_compound_simplified_triple,
    check_compound_pattern: builder.check_compound_pattern,
    special_flags,
    unrecognized: builder.unrecognized,
  }
}

///|
/// Parse one `PFX`/`SFX` block (header line plus its declared rule lines) and
/// return the index just past the block.
fn parse_affix_block(
  builder : AffBuilder,
  lines : Array[AffLine],
  start : Int,
  kind : AffixKind,
  line : AffLine,
) -> Int raise AffParseError {
  let name = match kind {
    Prefix => "PFX"
    Suffix => "SFX"
  }
  let raw_flag = arg_at(line, 1, name)
  let cross_product = parse_yes_no(arg_at(line, 2, name), line.number, name)
  let count = parse_count(arg_at(line, 3, name), line.number, name)
  let flag = resolve_flag(builder, raw_flag, line.number, name)
  builder.affix_headers.push({ kind, flag, cross_product, count, })
  let (body, next) = take_body(lines, start, name, count, line.number)
  for entry in body {
    let rule_flag = resolve_flag(
      builder,
      arg_at(entry, 1, name),
      entry.number,
      name,
    )
    let strip = arg_at(entry, 2, name)
    let add = arg_at(entry, 3, name)
    let condition = arg_at(entry, 4, name)
    builder.affix_rules.push({
      kind,
      flag: rule_flag,
      cross_product,
      strip,
      add,
      condition,
      morph: tail_from(entry.tokens, 5),
    })
  }
  next
}

///|
/// Parse `FLAG long` / `FLAG num` / `FLAG UTF-8`; anything else is an error.
fn parse_flag_type(
  line : AffLine,
  name : String,
) -> FlagType raise AffParseError {
  let value = arg_at(line, 1, name)
  match value {
    "long" => Long
    "num" => Num
    "UTF-8" | "utf-8" => Utf8
    _ =>
      raise AffParseError(
        line=line.number,
        message="\{name}: unknown flag mode \"\{value}\" (expected long, num or UTF-8)",
      )
  }
}

///|
/// Parse `Y`/`N` (case-insensitive) into a `Bool`.
fn parse_yes_no(
  value : String,
  line : Int,
  name : String,
) -> Bool raise AffParseError {
  match value {
    "Y" | "y" => true
    "N" | "n" => false
    _ =>
      raise AffParseError(
        line~,
        message="\{name}: expected Y or N, found \"\{value}\"",
      )
  }
}

///|
/// Parse a non-negative decimal count.
fn parse_count(
  value : String,
  line : Int,
  name : String,
) -> Int raise AffParseError {
  let parsed : Int? = Some(@string.parse_int(value)) catch { _ => None }
  match parsed {
    Some(n) =>
      if n < 0 {
        raise AffParseError(
          line~,
          message="\{name}: count must not be negative, found \"\{value}\"",
        )
      } else {
        n
      }
    None =>
      raise AffParseError(
        line~,
        message="\{name}: expected a count, found \"\{value}\"",
      )
  }
}

///|
/// Return the token at `position` (0-based) or raise a missing-argument error.
fn arg_at(
  line : AffLine,
  position : Int,
  name : String,
) -> String raise AffParseError {
  if position >= line.tokens.length() {
    raise AffParseError(
      line=line.number,
      message="\{name}: missing argument in \"\{line.text}\"",
    )
  }
  line.tokens[position]
}

///|
/// Read exactly `count` rule lines starting at `start`. Every one of them must
/// begin with `keyword`; the declared count is trusted, so a truncated block or
/// a foreign line inside it is an error at the offending line.
fn take_body(
  lines : Array[AffLine],
  start : Int,
  keyword : String,
  count : Int,
  header_line : Int,
) -> (Array[AffLine], Int) raise AffParseError {
  // Compare against the remaining line count instead of `start + count` so a
  // huge declared count cannot overflow `Int`.
  let available = lines.length() - start
  if count > available {
    raise AffParseError(
      line=header_line,
      message="\{keyword}: declared \{count} entries but only \{available} line(s) follow",
    )
  }
  let body : Array[AffLine] = []
  let mut index = start
  let end = start + count
  while index < end {
    let entry = lines[index]
    let first = entry.tokens[0]
    if first != keyword {
      raise AffParseError(
        line=entry.number,
        message="\{keyword}: expected an entry line, found \"\{first}\"",
      )
    }
    body.push(entry)
    index = index + 1
  }
  (body, end)
}

///|
/// Resolve a `PFX`/`SFX` flag through the `AF` alias table.
///
/// When no `AF` table has been seen the token is the flag itself. Otherwise a
/// decimal token is an alias index into the table (alias `1` is the first `AF`
/// body line), and an out-of-range index is an error. Non-numeric tokens are
/// kept verbatim so that files without aliases still parse.
fn resolve_flag(
  builder : AffBuilder,
  raw : String,
  line : Int,
  name : String,
) -> String raise AffParseError {
  let parsed : Int? = if builder.flag_aliases.length() == 0 {
    None
  } else {
    Some(@string.parse_int(raw)) catch {
      _ => None
    }
  }
  match parsed {
    None => raw
    Some(alias_index) =>
      if alias_index >= 1 && alias_index <= builder.flag_aliases.length() {
        builder.flag_aliases[alias_index - 1]
      } else {
        raise AffParseError(
          line~,
          message="\{name}: flag alias \{alias_index} is out of range (1..\{builder.flag_aliases.length()})",
        )
      }
  }
}

///|
/// Copy tokens from `start` on. Used for morphological tails and for the raw
/// arguments of directives whose grammar this slice does not model.
fn tail_from(tokens : Array[String], start : Int) -> Array[String] {
  let tail : Array[String] = []
  let mut index = start
  while index < tokens.length() {
    tail.push(tokens[index])
    index = index + 1
  }
  tail
}

///|
/// Join the tokens starting at `start` with single spaces.
fn join_tail(line : AffLine, start : Int) -> String {
  tail_from(line.tokens, start).join(" ")
}
