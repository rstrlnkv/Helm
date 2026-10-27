import XCTest
@testable import HelmRuntime

/// The idiom that was written fifteen times.
///
/// `min(max(value, low), high)` — and `max(low, min(value, high))`, and
/// `min(high, max(low, value))` — stood in five modules and three shared
/// targets, three spellings of one rule. Four crashes of one family were then
/// fixed by adding a sixteenth by hand, which is the argument ARCHITECTURE.md § Tests
/// and measurement makes for reading `HelmRuntime` first.
///
/// The floating-point half is the reason this has tests of its own rather than
/// being a one-liner nobody argues with: a clamp built from `min`/`max`
/// **passes NaN straight through** — `Swift.max(.nan, 0)` is NaN and
/// `Swift.min(.nan, 1)` is NaN — so the helper written to keep an untrusted
/// number inside a range hands back a number that is inside no range at all.
final class ClampedTests: XCTestCase {

    // MARK: - Numbers that are not numbers

    /// Infinity needs no special case: it has a position on the number line and
    /// the bound is exactly the answer for a value past every bound.
    func testInfinityClampsToTheBoundItIsPast() {
        XCTAssertEqual(Double.infinity.clamped(to: 0...1), 1)
        XCTAssertEqual((-Double.infinity).clamped(to: 0...1), 0)
    }

    /// **The hole, recorded rather than hidden.** NaN is not past a bound, it is
    /// nowhere, and `min`/`max` return it untouched. A `Double` that came off
    /// disk therefore takes `clampedIfFinite` below; this one is for numbers
    /// the layout system produced.
    func testNaNPassesThroughTheComparableClamp() {
        XCTAssertTrue(Double.nan.clamped(to: 0...1).isNaN)
    }

    func testClampedIfFiniteRefusesEveryNonFiniteValue() {
        XCTAssertNil(Double.nan.clampedIfFinite(to: 0...1))
        XCTAssertNil(Double.infinity.clampedIfFinite(to: 0...1))
        XCTAssertNil((-Double.infinity).clampedIfFinite(to: 0...1))
        XCTAssertNil(Double.signalingNaN.clampedIfFinite(to: 0...1))
    }

    // MARK: - The caller who has an answer for NaN

    /// Four call sites were written as `min(1, max(0, x))` or `max(0, min(1,
    /// x))` — spellings that **absorb** a NaN, at 0 and at 1 respectively —
    /// and moving them to `clamped(to:)` turned every one of them into a NaN
    /// sink that leaks. `clampedIfFinite` is the wrong repair for them: they
    /// have an answer for a number that is not a number, and they do not want
    /// one for infinity, which has a place on the number line and is exactly
    /// what a bound is for.
    func testTheFallbackIsUsedForNaNOnly() {
        XCTAssertEqual(Double.nan.clamped(to: 0...1, whenNotANumber: 0.25), 0.25)
        XCTAssertEqual(Double.signalingNaN.clamped(to: 0...1, whenNotANumber: 0.25), 0.25)
    }

    func testInfinityStillClampsToTheBoundItIsPast() {
        XCTAssertEqual(Double.infinity.clamped(to: 0...1, whenNotANumber: 0.25), 1)
        XCTAssertEqual((-Double.infinity).clamped(to: 0...1, whenNotANumber: 0.25), 0)
    }

    /// The size of the numbers this exists for. `Int(1e300 / 60)` **traps** —
    /// "Double value cannot be converted to Int because the result would be
    /// greater than Int.max" — and a plist holding `<real>1e300</real>` is a
    /// legal plist. Clamped first, the same conversion is arithmetic.
    func testAClampedRealIsSafeToConvertToAnInteger() {
        let seconds = 1e300.clampedIfFinite(to: 0...86_400)
        XCTAssertEqual(seconds.map { Int($0 / 60) }, 1440)
    }
}
