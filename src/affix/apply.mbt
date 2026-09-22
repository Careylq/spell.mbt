// Application of a single Hunspell affix rule to a stem.
//
// This is an independent, clean-room implementation of the semantics documented
// in the Hunspell manual. No Hunspell (LGPL-2.1) source code was consulted or
// copied; this project is Apache-2.0.
//
// `cross_product` is intentionally ignored here: it only decides whether rules
// of opposite kinds may be chained, which is a later slice's concern. Applying
// one rule in isolation does not depend on it.

///|
/// Can this rule apply to `stem`, and what word does it produce?
///
/// For a `Suffix` rule the stem must satisfy `rule.condition` at its end and end
/// with `rule.strip`; the strip is removed and `rule.add` appended. Prefix rules
/// mirror this at the start of the stem.
///
/// `"0"` is the format's marker for "nothing": a `strip` of `"0"` removes
/// nothing and an `add` of `"0"` appends nothing. The condition is checked
/// against the stem as given, before any strip is removed.
///
/// Returns `None` when the condition or the strip does not match.
pub fn apply_rule(rule : @aff.AffixRule, stem : String) -> String? {
  if !matches_condition(rule.condition, stem, rule.kind) {
    return None
  }
  let base = match strip_from(stem, rule.strip, rule.kind) {
    Some(base) => base
    None => return None
  }
  if rule.add == "0" || rule.add.is_empty() {
    return Some(base)
  }
  match rule.kind {
    @aff.Prefix => Some(rule.add + base)
    @aff.Suffix => Some(base + rule.add)
  }
}

///|
/// Remove `strip` from the anchored end of `stem`.
///
/// `"0"` (and, defensively, the empty string) means "remove nothing". Returns
/// `None` when the stem does not actually carry the text to remove.
fn strip_from(stem : String, strip : String, kind : @aff.AffixKind) -> String? {
  if strip == "0" || strip.is_empty() {
    return Some(stem)
  }
  match kind {
    @aff.Prefix =>
      match stem.strip_prefix(strip) {
        Some(rest) => Some(rest.to_owned())
        None => None
      }
    @aff.Suffix =>
      match stem.strip_suffix(strip) {
        Some(rest) => Some(rest.to_owned())
        None => None
      }
  }
}
