import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A refusal has a way off the screen: its ✕. A thumbnail leaves by its lifetime or by the capsule's ✕.** The finding
/// the close control answered was "the toast has no way to dismiss" — picture
/// 6 s + 5 s, refusal 9 s, in the corner where the next click goes — and the
/// control went onto the picture only. A refusal without a missing grant draws
/// the close control and nothing else, so the corner is never only waited out.
///
/// Counted off the rendered tree, the way
/// `TheToastHoldsStillAndCanBeSentAwayTests` counts the picture's controls:
/// one focus-ring view per control SwiftUI draws.
@MainActor
final class TheRefusalToastCanBeSentAwayTests: XCTestCase {

    private func controls(_ content: ShotToastModel.Content) -> Int {
        ShotToastRig.controls(content, hovering: false)
    }

    func testARefusalToastHasAWayAway() {
        let withGrant = controls(ShotToast.refusalContent(.noPermission))
        let without = controls(ShotToast.refusalContent(.captureFailed))
        XCTAssertEqual(withGrant - without, 1, "the subject: the settings button is the one control the grant adds")
        XCTAssertEqual(without, 1, "a refusal toast with no settings button has exactly the close control")
    }

    /// The toast model's `dismiss()` takes a refusal down. **This does not prove
    /// the close control calls it** — it calls `dismiss()` itself, so it stays
    /// green with the control's action emptied. **The press is unproven
    /// headless, and there is no headless way to prove it**: a
    /// synthesised mouse down/up into the mounted window reached the hosting view
    /// and did nothing, and the accessibility tree of a hosting view that was
    /// never ordered in is empty (see
    /// `TheToastHoldsStillAndCanBeSentAwayTests`), so a press would need the
    /// window ordered in, which is a panel on a real screen and was not tried.
    /// The control's existence is counted above; its wiring is open.
    func testDismissingTheModelTakesTheRefusalDown() {
        let toast = ShotToast()
        toast.model.content = ShotToast.refusalContent(.captureFailed)
        toast.model.shown = true
        toast.model.dismiss()
        XCTAssertNil(toast.model.content, "dismiss() left the refusal up")
        XCTAssertFalse(toast.model.shown)
    }
}
