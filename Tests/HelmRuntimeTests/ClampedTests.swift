import XCTest
@testable import HelmRuntime

/// One clamp instead of `min(max(value, low), high)` in its several spellings
/// (Architecture/TestsAndMeasurement.md § Why the commands are run: read
/// `HelmRuntime` before writing a helper).
///
/// The floating-point half is why this has tests of its own: a clamp built
/// from `min`/`max` passes NaN straight through (`Swift.max(.nan, 0)` is NaN),
/// so a helper meant to keep an untrusted number inside a range hands back a
/// number inside no range at all.
final class ClampedTests: XCTestCase {

    // MARK: - Numbers that are not numbers

    /// Infinity needs no special case: it has a position on the number line and
    /// the bound is exactly the answer for a value past every bound.
    func testInfinityClampsToTheBoundItIsPast() {
        XCTAssertEqual(Double.infinity.clamped(to: 0...1), 1)
        XCTAssertEqual((-Double.infinity).clamped(to: 0...1), 0)
    }

    /// The hole, recorded rather than hidden: NaN is not past a bound, it is
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

    /// For a caller with its own answer for NaN, as `min(1, max(0, x))`
    /// absorbs one at 0. `clampedIfFinite` would be wrong there: infinity has a
    /// place on the number line, and a bound is exactly its answer.
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
