// Deliberate promotions and non-promotions for this package's public API.
//
// `derive(Eq, Debug)` on a public type would implicitly promote trait methods
// (`equal`, `not_equal`, `to_repr`) to regular methods, which the compiler
// reports as `implicit_impl_as_method` (warning 0079). Declaring the `extend`
// blocks below states the intent explicitly:
//
// * `Debug::to_repr` is never promoted, per the standard library convention of
//   using `@debug.debug_inspect` / `@debug.Debug` directly.
// * `Eq` promotion is not part of the intended API either; callers use `==`
//   and `!=`, which go through the trait and need no promotion.

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend FlagType with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend FlagType with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend AffixKind with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend AffixKind with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend AffixHeader with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend AffixHeader with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend AffixRule with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend AffixRule with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend Replacement with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend Replacement with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend Conversion with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend Conversion with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend SpecialFlags with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend SpecialFlags with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend UnknownDirective with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend UnknownDirective with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend AffFile with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend AffFile with @debug.Debug::{to_repr}

///|
#deprecated("Use the `==` operator instead", skip_current_package=true)
#doc(hidden)
pub extend AffParseError with Eq::{equal, not_equal}

///|
#deprecated("Use @debug.debug_inspect instead", skip_current_package=true)
#doc(hidden)
pub extend AffParseError with @debug.Debug::{to_repr}

///|
pub extend AffParseError with Show::{output, to_string}
