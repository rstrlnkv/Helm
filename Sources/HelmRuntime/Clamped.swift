/// Keeping a value inside a range, in one place.
///
/// `min(max(value, low), high)` stood in most of the modules and in the shared
/// targets under them, in three spellings of the one rule — `max(low, min(value,
/// high))` and `min(high, max(low, value))` are the same sentence read from the
/// other end, and a reader has to prove that to themselves each time
/// (`grep -rn 'min(.*max(' Sources/` is what counts them). A family of crashes
/// — a plist holding `<integer>9223372036854775807</integer>`, then
/// `<real>1e300</real>`, reaching arithmetic that traps — was fixed each time by
/// writing one more by hand, which is the argument CLAUDE.md makes for
/// `HelmRuntime`.
///
/// **The range does the arguing about bounds.** `ClosedRange` traps on its own
/// initialiser when the upper bound is below the lower one, so a call site whose
/// bounds are computed raises the upper to the lower before the range is formed
/// rather than relying on which of `min` and `max` happens to win — that used to
/// be silent, and which one wins depends on the spelling.
public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public extension FloatingPoint {
    /// The same clamp for a number that came from somewhere untrusted — a
    /// `plist`, a JSON payload, a file — where the answer for a value that is
    /// not a number has to be the reader's and not this helper's.
    ///
    /// `clamped(to:)` **cannot** contain a NaN: `Swift.max(.nan, low)` is NaN
    /// and `Swift.min(.nan, high)` is NaN, so a clamp built from them hands back
    /// a value inside no range at all — and `Int(thatValue)` traps, which is the
    /// crash this family keeps producing. Infinity is refused with it: it does
    /// have a place on the number line, but `RuleCondition` is the standing
    /// proof that sending a non-finite value to *a* bound is safe under one
    /// comparison and catastrophic under the other, so the choice belongs to
    /// whoever knows what the number means.
    func clampedIfFinite(to range: ClosedRange<Self>) -> Self? {
        isFinite ? clamped(to: range) : nil
    }
}
