import XCTest
@testable import HelmUI

/// **Owner item (1): the actions capsule morphs, unless Reduce Motion says
/// stillness.** `HelmToolbarActionsCapsule` reads `HelmMotion.morphs(reduceMotion:)`
/// to choose between `.matchedGeometry` and `.identity` for
/// `glassEffectTransition` — the same shape `swaps` and `spins` already take,
/// and for the same reason (`HelmMotion.swift`'s own header on `swaps`): a
/// decision made of an argument can be asserted here, and a decision that
/// reads `NSWorkspace` could only be asserted about whichever setting this
/// Mac happens to have right now.
final class TheActionsCapsuleMorphsOnlyWithMotionTests: XCTestCase {
    func testTheCapsuleMorphsWithMotionOn() {
        XCTAssertTrue(HelmMotion.morphs(reduceMotion: false),
                      "the capsule must be allowed to morph when Reduce Motion is off")
    }

    func testReduceMotionCutsInsteadOfMorphing() {
        XCTAssertFalse(HelmMotion.morphs(reduceMotion: true),
                       "Reduce Motion must stop the capsule morphing, the same as every other cut")
    }
}
