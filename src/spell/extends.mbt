// Deliberate trait-method promotions for this package's public API.
//
// Declaring the `Show` promotion explicitly keeps `moon check` at zero warnings:
// without this block the compiler reports `implicit_impl_as_method` (0079)
// because `SpellError` is a public type with a `Show` implementation.

///|
pub extend SpellError with Show::{output, to_string}
