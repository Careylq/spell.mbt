// The module root is the shortest way in: it re-exports the public facade from
// `src/api`, so `import { "Careylq/spell" }` is enough for a user.
//
// Everything here is a re-export — the implementation lives in `src/`.

///|
/// Load a dictionary from `.aff` + `.dic` text, check words against it and
/// suggest corrections.
pub using @api {
  type Dictionary,
  type SpellError,
  load,
  check,
  suggest,
  encoding,
  flag_type_name,
  rule_count,
  entry_count,
}
