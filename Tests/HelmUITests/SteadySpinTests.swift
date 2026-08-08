import XCTest
@testable import HelmUI

/// "Reduce motion" is a medical setting, and a symbol that turns forever is
/// exactly what it exists to stop.
///
/// The two refresh buttons that spin their own glyph — the uninstaller's and
/// Homebrew's — went straight to `.symbolEffect(.rotate, options: .repeating)`
/// and never asked. SwiftUI does not honour the setting for us.
///
/// The decision is a function of two facts rather than a reading of the system,
/// so it can be asserted at all: a test that consults `NSWorkspace` only proves
/// the machine it runs on is set the way the test assumed.
final class SteadySpinTests: XCTestCase {

    func testAGlyphSpinsWhenItIsAskedTo() {
        XCTAssertTrue(HelmMotion.spins(requested: true, reduceMotion: false))
    }

    func testAGlyphAtRestDoesNotSpin() {
        XCTAssertFalse(HelmMotion.spins(requested: false, reduceMotion: false))
    }

    /// The whole point.
    func testReduceMotionStopsASpinThatWasAskedFor() {
        XCTAssertFalse(HelmMotion.spins(requested: true, reduceMotion: true))
    }

    /// And it cannot start one either, which would be a strange way to fail but
    /// pins the rule as a conjunction rather than an override.
    func testReduceMotionNeverStartsASpin() {
        XCTAssertFalse(HelmMotion.spins(requested: false, reduceMotion: true))
    }
}
