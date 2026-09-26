// Suggestion generation for a `@spell.Dictionary`.
//
// The algorithms follow the "Suggestion" section of the Hunspell manual
// (`hunspell(5)`): `REP` replacements, edit distance 1, case variations, word
// splitting, and a bounded edit distance 2. No Hunspell (LGPL-2.1) source code
// was consulted or copied; this project is Apache-2.0.
//
// Every generated candidate is judged by the same `Dictionary::check` the
// `check` subcommand uses, so a suggestion is only ever a word this library
// itself accepts. Nothing is re-parsed per call: the replacement table, `TRY`
// and `KEY` all come from the dictionary that was indexed once.

///|
/// The alphabet used when the `.aff` file declares no `TRY` line.
fn default_alphabet() -> String {
  "abcdefghijklmnopqrstuvwxyz"
}

///|
/// A word longer than this skips single-edit generation. The candidate space
/// grows with the length, and the corpus contains deliberately pathological
/// words (the `timelimit` suite) that must not stall the engine.
const MAX_EDIT_LEN : Int = 32

///|
/// A word longer than this skips the bounded distance-2 pass.
const MAX_EDIT2_LEN : Int = 20

///|
/// The rank given to a character that is not in `TRY` (or when `TRY` is absent).
const RANK_NONE : Int = 1000000

///|
/// A candidate correction together with the keys used to rank it.
priv struct Candidate {
  word : String
  /// Came from a `REP` pair: the strongest signal, ranked first.
  rep : Bool
  /// The differing character is adjacent on the `KEY` layout.
  adjacent : Bool
  /// Lowest `TRY` position among the differing characters; `RANK_NONE` when
  /// neither character is listed.
  try_rank : Int
  /// Edit distance; `0` for a pure case change.
  distance : Int
}

///|
/// The `TRY`/`KEY` tables of one dictionary, prepared once per `suggest` call.
priv struct Ranker {
  try_array : Array[Char]
  key_rows : Array[Array[Char]]
}

///|
/// Look up the `REP` table, `TRY` and `KEY` of `dict` and prepare the ranking
/// helper. This is O(`TRY` + `KEY`) and does no dictionary work.
fn Ranker::new(dict : @spell.Dictionary) -> Ranker {
  {
    try_array: dedupe_chars(dict.try_chars()),
    key_rows: parse_key_rows(dict.keyboard()),
  }
}

///|
/// The distinct characters of `text`, in first-seen order.
fn dedupe_chars(text : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in text {
    if !out.contains(c) {
      out.push(c)
    }
  }
  out
}

///|
/// Split `KEY` into rows on `|` (`qwerty|asdf|zxcv`).
fn parse_key_rows(keyboard : String) -> Array[Array[Char]] {
  let rows : Array[Array[Char]] = []
  let mut current : Array[Char] = []
  for c in keyboard {
    if c == '|' {
      rows.push(current)
      current = []
    } else {
      current.push(c)
    }
  }
  rows.push(current)
  rows
}

///|
/// The `TRY` position of `c`, or `RANK_NONE` when it is not listed.
fn Ranker::try_rank(self : Ranker, c : Char) -> Int {
  let mut index = 0
  while index < self.try_array.length() {
    if self.try_array[index] == c {
      return index
    }
    index = index + 1
  }
  RANK_NONE
}

///|
/// Are `a` and `b` neighbouring keys? Two keys are neighbours when they sit
/// next to each other in a row, or in adjacent rows with at most one column of
/// offset (the staggered row layout of a real keyboard).
fn Ranker::adjacent(self : Ranker, a : Char, b : Char) -> Bool {
  if a == b {
    return false
  }
  let mut row_index = 0
  while row_index < self.key_rows.length() {
    let row = self.key_rows[row_index]
    let mut column = 0
    while column < row.length() {
      if row[column] == a {
        if column > 0 && row[column - 1] == b {
          return true
        }
        if column + 1 < row.length() && row[column + 1] == b {
          return true
        }
        let mut delta_row = -1
        while delta_row <= 1 {
          if delta_row != 0 {
            let neighbour_row = row_index + delta_row
            if neighbour_row >= 0 && neighbour_row < self.key_rows.length() {
              let other = self.key_rows[neighbour_row]
              let mut delta_column = -1
              while delta_column <= 1 {
                let other_column = column + delta_column
                if other_column >= 0 &&
                  other_column < other.length() &&
                  other[other_column] == b {
                  return true
                }
                delta_column = delta_column + 1
              }
            }
          }
          delta_row = delta_row + 1
        }
      }
      column = column + 1
    }
    row_index = row_index + 1
  }
  false
}

///|
/// The first position where `from` and `to` differ, plus the two characters at
/// that position (`None` on the shorter side, which is how an insertion or a
/// deletion shows up).
fn first_difference(from : String, to : String) -> (Int, Char?, Char?) {
  let left = from.to_array()
  let right = to.to_array()
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  let mut index = 0
  while index < shared {
    if left[index] != right[index] {
      return (index, Some(left[index]), Some(right[index]))
    }
    index = index + 1
  }
  if left.length() < right.length() {
    (shared, None, Some(right[shared]))
  } else if left.length() > right.length() {
    (shared, Some(left[shared]), None)
  } else {
    (shared, None, None)
  }
}

///|
/// The rank key for one candidate. `from` is the misspelled word, `to` the
/// candidate; `rep` and `distance` come from the generator.
fn Ranker::candidate(
  self : Ranker,
  from : String,
  to : String,
  rep : Bool,
  distance : Int,
) -> Candidate {
  let (index, old_char, new_char) = first_difference(from, to)
  let adjacent = match (old_char, new_char) {
    (Some(a), Some(b)) => self.adjacent(a, b)
    (None, Some(b)) => self.adjacent_to_neighbour(from, index, b)
    _ => false
  }
  let mut try_rank = RANK_NONE
  match old_char {
    Some(c) => {
      let rank = self.try_rank(c)
      if rank < try_rank {
        try_rank = rank
      }
    }
    None => ()
  }
  match new_char {
    Some(c) => {
      let rank = self.try_rank(c)
      if rank < try_rank {
        try_rank = rank
      }
    }
    None => ()
  }
  { word: to, rep, adjacent, try_rank, distance, }
}

///|
/// Is the character inserted at `index` adjacent to either of its neighbours in
/// `from`?
fn Ranker::adjacent_to_neighbour(
  self : Ranker,
  from : String,
  index : Int,
  inserted : Char,
) -> Bool {
  let chars = from.to_array()
  if index > 0 && self.adjacent(chars[index - 1], inserted) {
    return true
  }
  if index < chars.length() && self.adjacent(chars[index], inserted) {
    return true
  }
  false
}

///|
/// Rank two candidates. `REP` hits first, then keyboard-neighbour typos, then
/// the `TRY` order, then the edit distance, and finally the word itself so the
/// order is total and deterministic.
fn compare_candidates(left : Candidate, right : Candidate) -> Int {
  if left.rep != right.rep {
    return if left.rep { -1 } else { 1 }
  }
  if left.adjacent != right.adjacent {
    return if left.adjacent { -1 } else { 1 }
  }
  if left.try_rank != right.try_rank {
    return left.try_rank - right.try_rank
  }
  if left.distance != right.distance {
    return left.distance - right.distance
  }
  left.word.compare(right.word)
}

///|
/// Add `candidate` to `out` when it is a real correction: not the input word,
/// accepted by `check`, and not a `NOSUGGEST` entry.
fn push_candidate(
  dict : @spell.Dictionary,
  ranker : Ranker,
  from : String,
  candidate : String,
  rep : Bool,
  distance : Int,
  out : Array[Candidate],
) -> Unit {
  if candidate == from || candidate.is_empty() {
    return
  }
  if !dict.check(candidate) {
    return
  }
  if dict.is_no_suggest(candidate) {
    return
  }
  out.push(ranker.candidate(from, candidate, rep, distance))
}

///|
/// A slice of code points as a string (indices are code-point offsets).
fn slice_string(chars : Array[Char], start : Int, end : Int) -> String {
  let buffer = StringBuilder()
  let mut index = start
  while index < end {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}

///|
/// `chars` without the character at `skip`.
fn remove_one(chars : Array[Char], skip : Int) -> String {
  let buffer = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if index != skip {
      buffer.write_char(chars[index])
    }
    index = index + 1
  }
  buffer.to_string()
}

///|
/// `chars` without the characters at `first` and `second`.
fn remove_two(chars : Array[Char], first : Int, second : Int) -> String {
  let buffer = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if index != first && index != second {
      buffer.write_char(chars[index])
    }
    index = index + 1
  }
  buffer.to_string()
}

///|
/// `chars` with the characters at `first` and `second` exchanged.
fn swap_two(chars : Array[Char], first : Int, second : Int) -> String {
  let buffer = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if index == first {
      buffer.write_char(chars[second])
    } else if index == second {
      buffer.write_char(chars[first])
    } else {
      buffer.write_char(chars[index])
    }
    index = index + 1
  }
  buffer.to_string()
}

///|
/// `chars` with the character at `index` replaced by `replacement`.
fn replace_one(chars : Array[Char], index : Int, replacement : Char) -> String {
  let buffer = StringBuilder()
  let mut cursor = 0
  while cursor < chars.length() {
    if cursor == index {
      buffer.write_char(replacement)
    } else {
      buffer.write_char(chars[cursor])
    }
    cursor = cursor + 1
  }
  buffer.to_string()
}

///|
/// `chars` with `inserted` added before position `index` (`index` may be the
/// length, which appends).
fn insert_one(chars : Array[Char], index : Int, inserted : Char) -> String {
  let buffer = StringBuilder()
  let mut cursor = 0
  while cursor < chars.length() {
    if cursor == index {
      buffer.write_char(inserted)
    }
    buffer.write_char(chars[cursor])
    cursor = cursor + 1
  }
  if index >= chars.length() {
    buffer.write_char(inserted)
  }
  buffer.to_string()
}

///|
/// `chars` with the character at `from` taken out and put back before position
/// `to`. Positions are interpreted on the original word; a move that changes
/// nothing is rejected by the caller.
fn move_one(chars : Array[Char], from : Int, to : Int) -> String {
  let without = remove_one(chars, from)
  let remaining = without.to_array()
  let target = if from < to && to > 0 { to - 1 } else { to }
  insert_one(remaining, target, chars[from])
}

///|
/// `chars` with `[start, start + length)` replaced by `replacement`.
fn replace_range(
  chars : Array[Char],
  start : Int,
  length : Int,
  replacement : String,
) -> String {
  let buffer = StringBuilder()
  let mut index = 0
  while index < start {
    buffer.write_char(chars[index])
    index = index + 1
  }
  for c in replacement {
    buffer.write_char(c)
  }
  index = start + length
  while index < chars.length() {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}

///|
/// Do `pattern` and `chars` agree starting at `offset`?
fn matches_at(chars : Array[Char], pattern : Array[Char], offset : Int) -> Bool {
  let mut index = 0
  while index < pattern.length() {
    if chars[offset + index] != pattern[index] {
      return false
    }
    index = index + 1
  }
  true
}

///|
/// Lower-case every character of `word`.
fn lower_word(word : String) -> String {
  let buffer = StringBuilder()
  for c in word {
    buffer.write_char(@unicode.to_lowercase(c))
  }
  buffer.to_string()
}

///|
/// Upper-case every character of `word` (ASCII only, like the judgement
/// engine's capitalisation helper).
fn upper_word(word : String) -> String {
  let buffer = StringBuilder()
  for c in word {
    buffer.write_char(c.to_ascii_uppercase())
  }
  buffer.to_string()
}

///|
/// `word` upper-cased with every `ß` spelled `SS`, the `CHECKSHARPS` rule that
/// lets an uppercase word reach a dictionary entry containing a sharp s
/// (`MÜßIG` -> `MÜSSIG`).
fn sharp_s_upper(word : String) -> String {
  let buffer = StringBuilder()
  for c in word {
    if c == 'ß' {
      buffer.write_char('S')
      buffer.write_char('S')
    } else {
      buffer.write_char(c.to_ascii_uppercase())
    }
  }
  buffer.to_string()
}

///|
/// The `Capitalised` form of `word`.
fn capitalise_word(word : String) -> String {
  let lowered = lower_word(word)
  let chars = lowered.to_array()
  if chars.length() == 0 {
    return lowered
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
/// Split a `REP` field into its body plus whether it was anchored to the start
/// (`^`) or the end (`$`) of the word. `_` is turned into a space afterwards.
fn rep_field(text : String) -> (String, Bool, Bool) {
  let (body, at_start) = match text.strip_prefix("^") {
    Some(rest) => (rest.to_owned(), true)
    None => (text, false)
  }
  let (body, at_end) = match body.strip_suffix("$") {
    Some(rest) => (rest.to_owned(), true)
    None => (body, false)
  }
  (underscore_to_space(body), at_start, at_end)
}

///|
/// The Hunspell convention that `_` in a `REP` field stands for a space.
fn underscore_to_space(text : String) -> String {
  let buffer = StringBuilder()
  for c in text {
    if c == '_' {
      buffer.write_char(' ')
    } else {
      buffer.write_char(c)
    }
  }
  buffer.to_string()
}

///|
/// Apply every `REP` pair: each `from` is substituted at every occurrence (a
/// `^`/`$` in the pair anchors it), on the word as typed and on its lower-case
/// form, exactly as Hunspell does.
fn collect_replacements(
  dict : @spell.Dictionary,
  ranker : Ranker,
  word : String,
  out : Array[Candidate],
) -> Unit {
  let replacements = dict.replacements()
  let sources : Array[String] = [word, lower_word(word)]
  for replacement in replacements {
    let (pattern_text, anchored_start, anchored_end) = rep_field(
      replacement.from,
    )
    if pattern_text.is_empty() {
      continue
    }
    let pattern = pattern_text.to_array()
    let to = underscore_to_space(replacement.to)
    for source in sources {
      let chars = source.to_array()
      let mut start = 0
      while start + pattern.length() <= chars.length() {
        if matches_at(chars, pattern, start) {
          let at_start = start == 0
          let at_end = start + pattern.length() == chars.length()
          if (!anchored_start || at_start) && (!anchored_end || at_end) {
            let candidate = replace_range(chars, start, pattern.length(), to)
            push_candidate(dict, ranker, word, candidate, true, 1, out)
          }
        }
        start = start + 1
      }
    }
  }
}

///|
/// The case variations Hunspell tries: all lower-case, `Capitalised`, and
/// ALL CAPS. The last one is what turns `nasa` into `NASA`.
///
/// Two refinements keep common shapes reachable: for a possessive the stem is
/// cased and the `'s` kept (`Unicef's` -> `UNICEF's`), and a word containing `ß`
/// also gets its `SS` spelling (`CHECKSHARPS`).
fn collect_case(
  dict : @spell.Dictionary,
  ranker : Ranker,
  word : String,
  out : Array[Candidate],
) -> Unit {
  let variants : Array[String] = [
    lower_word(word),
    capitalise_word(word),
    upper_word(word),
  ]
  for ending in ["'s", "'S"] {
    match word.strip_suffix(ending) {
      Some(stem) => {
        let stem_word = stem.to_owned()
        variants.push(lower_word(stem_word) + "'s")
        variants.push(capitalise_word(stem_word) + "'s")
        variants.push(upper_word(stem_word) + "'s")
      }
      None => ()
    }
  }
  if word.contains("ß") {
    variants.push(sharp_s_upper(word))
  }
  for variant in variants {
    push_candidate(dict, ranker, word, variant, false, 0, out)
  }
}

///|
/// The characters substitutions and insertions may use: `TRY` when the `.aff`
/// declared it, a plain ASCII alphabet otherwise.
fn edit_alphabet(dict : @spell.Dictionary) -> Array[Char] {
  let listed = dict.try_chars()
  if listed.is_empty() {
    dedupe_chars(default_alphabet())
  } else {
    dedupe_chars(listed)
  }
}

///|
/// Edit distance 1: deletions, adjacent transpositions, replacements and
/// insertions. Replacements and insertions are restricted to the alphabet
/// above, which is the cost control Hunspell also relies on.
fn collect_edits(
  dict : @spell.Dictionary,
  ranker : Ranker,
  word : String,
  out : Array[Candidate],
) -> Unit {
  let chars = word.to_array()
  let length = chars.length()
  if length == 0 || length > MAX_EDIT_LEN {
    return
  }
  let alphabet = edit_alphabet(dict)
  let mut index = 0
  while index < length {
    push_candidate(dict, ranker, word, remove_one(chars, index), false, 1, out)
    index = index + 1
  }
  index = 0
  while index + 1 < length {
    if chars[index] != chars[index + 1] {
      push_candidate(
        dict,
        ranker,
        word,
        swap_two(chars, index, index + 1),
        false,
        1,
        out,
      )
    }
    index = index + 1
  }
  index = 0
  while index < length {
    for c in alphabet {
      if c != chars[index] {
        push_candidate(
          dict,
          ranker,
          word,
          replace_one(chars, index, c),
          false,
          1,
          out,
        )
      }
    }
    index = index + 1
  }
  index = 0
  while index <= length {
    for c in alphabet {
      push_candidate(
        dict,
        ranker,
        word,
        insert_one(chars, index, c),
        false,
        1,
        out,
      )
    }
    index = index + 1
  }
  if length <= MAX_EDIT2_LEN {
    collect_edits_two(dict, ranker, word, chars, out)
  }
}

///|
/// A bounded edit distance 2, matching the kinds the Hunspell manual names
/// ("double two characters", "long swap", "long mov"). It is O(n²) candidates,
/// not O(n²·|TRY|²), so it stays cheap; a full distance-2 search (any two
/// replacements, a replacement plus an insertion, ...) is deliberately not done.
fn collect_edits_two(
  dict : @spell.Dictionary,
  ranker : Ranker,
  word : String,
  chars : Array[Char],
  out : Array[Candidate],
) -> Unit {
  let length = chars.length()
  let mut first = 0
  while first < length {
    let mut second = first + 1
    while second < length {
      push_candidate(
        dict,
        ranker,
        word,
        remove_two(chars, first, second),
        false,
        2,
        out,
      )
      second = second + 1
    }
    first = first + 1
  }
  first = 0
  while first < length {
    let mut second = first + 2
    while second < length {
      if chars[first] != chars[second] {
        push_candidate(
          dict,
          ranker,
          word,
          swap_two(chars, first, second),
          false,
          2,
          out,
        )
      }
      second = second + 1
    }
    first = first + 1
  }
  first = 0
  while first < length {
    let mut target = 0
    while target <= length {
      if first != target && first + 1 != target {
        push_candidate(
          dict,
          ranker,
          word,
          move_one(chars, first, target),
          false,
          2,
          out,
        )
      }
      target = target + 1
    }
    first = first + 1
  }
  // two independent adjacent transpositions (`ahev` -> `have`)
  first = 0
  while first + 1 < length {
    let mut second = first + 2
    while second + 1 < length {
      let swapped = swap_two(chars, first, first + 1)
      let second_swapped = swap_two(swapped.to_array(), second, second + 1)
      push_candidate(dict, ranker, word, second_swapped, false, 2, out)
      second = second + 1
    }
    first = first + 1
  }
}

///|
/// Split the word into two separately correct parts. Hunspell writes the two
/// parts with a space; when `TRY` (or `WORDCHARS`) declares `-`, the hyphenated
/// form is offered as well.
fn collect_splits(
  dict : @spell.Dictionary,
  ranker : Ranker,
  word : String,
  out : Array[Candidate],
) -> Unit {
  let chars = word.to_array()
  let length = chars.length()
  let hyphen = dict.try_chars().contains("-") || dict.word_chars().contains("-")
  let mut split = 1
  while split < length {
    let left = slice_string(chars, 0, split)
    let right = slice_string(chars, split, length)
    if dict.check(left) && dict.check(right) {
      push_candidate(dict, ranker, word, left + " " + right, false, 1, out)
      if hyphen {
        push_candidate(dict, ranker, word, left + "-" + right, false, 1, out)
      }
    }
    split = split + 1
  }
}

///|
/// Suggestions for `word` according to `dict`, best first and at most `limit`.
///
/// A word that `check` accepts needs no correction, so the result is empty.
/// Otherwise candidates are generated by the `REP` table, edit distance 1, case
/// variations, word splitting and a bounded edit distance 2; every candidate is
/// kept only when `check` accepts it, then ranked (`REP` first, then keyboard
/// adjacency, `TRY` order, edit distance, and an alphabetical tiebreak) and
/// deduplicated. The input word itself is never returned.
///
/// The winning suggestions are then passed through the `.aff` `OCONV` output
/// conversion table, exactly as Hunspell converts suggestion output (the
/// `oconv` suite expects `bébé` to be offered as `BÉBÉ`). Deduplication happens
/// on the converted text, so two entries that convert to the same string are
/// offered once.
pub fn suggest(
  dict : @spell.Dictionary,
  word : String,
  limit : Int,
) -> Array[String] {
  if limit <= 0 || word.is_empty() {
    return []
  }
  if dict.check(word) {
    return []
  }
  let ranker = Ranker::new(dict)
  let candidates : Array[Candidate] = []
  collect_replacements(dict, ranker, word, candidates)
  collect_case(dict, ranker, word, candidates)
  collect_edits(dict, ranker, word, candidates)
  collect_splits(dict, ranker, word, candidates)
  candidates.sort_by(compare_candidates)
  let out : Array[String] = []
  for candidate in candidates {
    let converted = dict.apply_oconv(candidate.word)
    if !out.contains(converted) {
      out.push(converted)
      if out.length() >= limit {
        break
      }
    }
  }
  out
}
