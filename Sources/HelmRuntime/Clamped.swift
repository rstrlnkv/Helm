/// Keeping a value inside a range, in one place: hand-written `min(max(…))`
/// comes in several spellings a reader has to prove equal each time, and a
/// value from a plist (`<integer>9223372036854775807</integer>`,
/// `<real>1e300</real>`) reaching arithmetic that traps is a family of crashes.
/// Architecture/StoredSettings.md § A number that came from a file. Look in
/// `HelmRuntime` before writing a helper (Architecture/TestsAndMeasurement.md § Tests and measurement).
///
/// **The range does the arguing about bounds.** `ClosedRange` traps on its own
/// initialiser when the upper bound is below the lower one, so a call site whose
/// bounds are computed raises the upper to the lower before the range is formed
/// rather than relying on which of `min` and `max` happens to win.
extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension FloatingPoint {
    /// The same clamp for a number that came from somewhere untrusted — a
    /// `plist`, a JSON payload, a file — where the answer for a value that is
    /// not a number has to be the reader's and not this helper's.
    ///
    /// `clamped(to:)` **cannot** contain a NaN: `Swift.max(.nan, low)` is NaN
    /// and `Swift.min(.nan, high)` is NaN, so a clamp built from them hands back
    /// a value inside no range at all, and `Int(thatValue)` traps. Infinity is
    /// refused with it: sending a non-finite value to *a* bound is safe under
    /// one comparison and catastrophic under the other (`RuleCondition`), so
    /// the choice belongs to whoever knows what the number means.
    public func clampedIfFinite(to range: ClosedRange<Self>) -> Self? {
        isFinite ? clamped(to: range) : nil
    }

    /// The same clamp for a caller who already knows what a value that is not
    /// a number means to them — a drawn fraction, an opacity, the height of a
    /// window.
    ///
    /// `min(hi, max(lo, x))` and `max(lo, min(x, hi))` **absorb** a NaN, at the
    /// low and the high bound respectively, by an accident of which argument
    /// `Swift.min` and `Swift.max` return; `clamped(to:)` does not, so a caller
    /// that relied on the accident names its answer here. Not
    /// `clampedIfFinite`, which refuses infinity too, and infinity is precisely
    /// the value a bound knows what to do with.
    public func clamped(to range: ClosedRange<Self>, whenNotANumber fallback: Self) -> Self {
        isNaN ? fallback : clamped(to: range)
    }
}

extension Int {
    /// The sum, held at `Int.max` or `Int.min` instead of trapping.
    ///
    /// For figures that came out of a file or a scan, where one bound on
    /// each figure does not bound a sum of thousands of them: an integer add traps
    /// in release as well as debug, and a figure that is only large is a better
    /// answer than a process that is gone. `RingLayout` calls this for both its sums.
    public func saturatingAdding(_ other: Int) -> Int {
        let (sum, overflowed) = addingReportingOverflow(other)
        return overflowed ? (other < 0 ? .min : .max) : sum
    }
}

extension Sequence where Element == Int {
    /// `reduce(0, +)` that saturates, see `Int.saturatingAdding(_:)`.
    public func saturatingSum() -> Int {
        reduce(0) { $0.saturatingAdding($1) }
    }
}
