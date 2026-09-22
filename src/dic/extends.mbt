// Deliberate promotions and non-promotions for this package's public API.
//
// `derive(Eq, Debug)` on a public type would implicitly promote trait methods
// (`equal`, `not_equal`, `to_repr`) to regular methods, which the compiler
// reports as `implicit_impl_as_method` (warning 0079). Declaring the `extend`
// blocks below states the intent explicitly, exactly as in `src/aff`.

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend DicEntry with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend DicEntry with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend DicFile with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend DicFile with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend DicParseError with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend DicParseError with @debug.Debug::{to_repr}

///|
pub extend DicParseError with Show::{output, to_string}
