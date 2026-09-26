// The suggestion replacement table of a dictionary.
//
// The `.aff` `REP` table is the base. On top of it the manual's `ph:` field
// ("Optional data fields") adds one rule per field: a `ph:` value is a
// transliteration of its dictionary word, so `which ph:wich` is equivalent to
// `REP wich which`. Hunspell calls this the "inner REP table" and gives it the
// same top priority as `REP`.
//
// This is an independent, clean-room implementation of the behaviour documented
// in `hunspell(5)`. No Hunspell (LGPL-2.1) source code was consulted or copied;
// this project is Apache-2.0.

///|
/// The replacement rules the suggestion engine uses: the `.aff` `REP` pairs
/// first, then one rule per `.dic` `ph:` field, in dictionary order.
///
/// The `ph:` forms the manual documents are handled:
///
/// * `ph:wich` — the plain transliteration: rule `wich` -> the word.
/// * `ph:prity*` — a trailing `*` strips the last character of the pattern and
///   of the word: rule `prit` -> `prett`.
/// * `ph:hepi->happi` — an ASCII arrow is an explicit rule `hepi` -> `happi`.
///
/// Every rule is also added in its capitalised and its uppercased spelling (the
/// manual's equivalent `REP` table lists `wendsay Wednesday` *and*
/// `Wendsay Wednesday`; the uppercase variant is what turns an ALL-CAPS
/// misspelling such as `OMG` into `OH, MY GOSH!`).
fn suggest_replacements(
  base : Array[@aff.Replacement],
  entries : Array[@dic.DicEntry],
  ignored : Array[Char],
) -> Array[@aff.Replacement] {
  let rules : Array[@aff.Replacement] = []
  for replacement in base {
    rules.push(replacement)
  }
  for entry in entries {
    let target = remove_ignored(entry.full_word, ignored)
    for field in entry.morph {
      match field.strip_prefix("ph:") {
        Some(value) => add_ph_rules(rules, value.to_owned(), target)
        None => ()
      }
    }
  }
  rules
}

///|
/// Add the replacement rules one `ph:` value implies for `target`.
fn add_ph_rules(
  rules : Array[@aff.Replacement],
  value : String,
  target : String,
) -> Unit {
  let pair : (String, String)? = match value.find("->") {
    Some(at) => {
      let chars = value.to_array()
      let pattern = chars_between(chars, 0, at)
      let replacement = chars_between(chars, at + 2, chars.length())
      if pattern.is_empty() || replacement.is_empty() {
        None
      } else {
        Some((pattern, replacement))
      }
    }
    None =>
      match value.strip_suffix("*") {
        Some(body) => {
          let pattern = drop_last_char(body.to_owned())
          match (pattern, drop_last_char(target)) {
            (Some(pattern), Some(stripped)) =>
              if pattern.is_empty() {
                None
              } else {
                Some((pattern, stripped))
              }
            _ => None
          }
        }
        None => if value.is_empty() { None } else { Some((value, target)) }
      }
  }
  match pair {
    Some((pattern, replacement)) => push_rule(rules, pattern, replacement)
    None => ()
  }
}

///|
/// Add the three case spellings of one rule, skipping duplicates.
fn push_rule(
  rules : Array[@aff.Replacement],
  pattern : String,
  replacement : String,
) -> Unit {
  if pattern.is_empty() || replacement.is_empty() || pattern == replacement {
    return
  }
  push_unique_rule(rules, pattern, replacement)
  let capitalised = capitalise_ascii(pattern)
  if capitalised != pattern {
    push_unique_rule(rules, capitalised, replacement)
  }
  let upper = uppercase_ascii(pattern)
  if upper != pattern {
    push_unique_rule(rules, upper, uppercase_ascii(replacement))
  }
}

///|
/// Append `{ from, to, }` unless the exact pair is already present.
fn push_unique_rule(
  rules : Array[@aff.Replacement],
  from : String,
  to : String,
) -> Unit {
  for existing in rules {
    if existing.from == from && existing.to == to {
      return
    }
  }
  rules.push({ from, to, })
}

///|
/// The characters `[start, end)` as a string.
fn chars_between(chars : Array[Char], start : Int, end : Int) -> String {
  let buffer = StringBuilder()
  let mut index = start
  while index < end {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}

///|
/// `text` without its last character, or `None` when it is empty.
fn drop_last_char(text : String) -> String? {
  let chars = text.to_array()
  if chars.length() == 0 {
    return None
  }
  Some(chars_between(chars, 0, chars.length() - 1))
}

///|
/// The ASCII-capitalised form of `text` (first character upper case, the rest
/// left alone).
fn capitalise_ascii(text : String) -> String {
  let chars = text.to_array()
  if chars.length() == 0 {
    return text
  }
  let buffer = StringBuilder()
  buffer.write_char(chars[0].to_ascii_uppercase())
  let mut index = 1
  while index < chars.length() {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}

///|
/// Every ASCII character of `text` upper-cased. Non-ASCII characters pass
/// through unchanged (`moonbitlang/x/unicode` only offers lower-casing).
fn uppercase_ascii(text : String) -> String {
  let buffer = StringBuilder()
  for c in text {
    buffer.write_char(c.to_ascii_uppercase())
  }
  buffer.to_string()
}
