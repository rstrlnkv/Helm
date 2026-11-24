import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// The recovery after the person fixes the permission.
///
/// macOS revokes a tap mid-session and says so once, down the tap being
/// switched off; `TapDisabled` rules that a revoked grant means stand down.
/// Standing down clears `tapped`, so when the person restores Accessibility and
/// switches back to Helm, `startTap`'s `guard running, !tapped` builds a new
/// tap rather than leaving the page green over nobody listening.
///
/// A local flag must not stand in for a live external fact: the channel back
/// from the port that knows is `died`.
/// Architecture/ModulePattern.md § Ports and logic.
///
/// What is not covered here, and cannot be. No test process can make macOS
/// revoke a real `CGEvent` tap, so `CGKeyTap.theSystemDisabledUs` calling this
/// channel is checked by reading it. What is covered is everything after the
/// call: the state the page draws, and the rebuild on the next activation.
@MainActor
final class TheTapSaysWhenMacOSTakesItAwayTests: XCTestCase {

    private func engine(_ tap: FakeTap, _ activation: FakeActivation) -> LayoutEngine {
        LayoutEngine(tap: tap, typing: FakeTyping(), sources: FakeSources(),
                     translation: FakeTranslation(table: [:]), spell: FakeSpell(valid: []),
                     secure: FakeSecure(), activation: activation,
                     settings: layoutStore())
    }

    /// The last state the engine published, which is what the settings page
    /// reads. `EngineNews<LayoutState>` replays it, so a reader arriving after the fact
    /// is handed it rather than waiting for the next one.
    private func published(by engine: LayoutEngine) async -> LayoutState? {
        for await state in engine.stream() { return state }
        return nil
    }

    func testTheTapIsBuiltAgainAfterMacOSTookTheLastOneAway() async {
        let tap = FakeTap()
        let activation = FakeActivation()
        let engine = engine(tap, activation)
        engine.activate()
        XCTAssertEqual(tap.starts, 1, "the tap never started, so nothing below is about a rebuild")
        var watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, true,
                       "the module is not watching to begin with, so «it stopped» is vacuous")

        // macOS revokes the grant mid-session: the tap is stopped from inside
        // the port, which is the one route the engine cannot see for itself.
        tap.macOSTakesItAway()
        watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, false, """
            the page still says the keyboard is being watched after macOS took the tap away, \
            which is the one thing this module must never claim.
            """)

        // The person grants Accessibility again and switches back to Helm.
        tap.grant = true
        activation.helmComesToTheFront()

        XCTAssertEqual(tap.starts, 2, """
            coming back to Helm did not rebuild the tap: `tapped` is still true from the tap \
            macOS destroyed, so `startTap` refuses for the rest of the process and the page \
            reports a module that nobody is listening through.
            """)
        watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, true,
                       "the rebuilt tap is not reflected in what the page draws")
        engine.deactivate()
    }

    /// The other half: «macOS refused the tap», which `FakeTap` can represent.
    func testWithoutTheGrantThePageSaysNobodyIsWatchingAndOneComesBackWithIt() async {
        let tap = FakeTap()
        tap.grant = false
        let activation = FakeActivation()
        let engine = engine(tap, activation)
        engine.activate()
        XCTAssertEqual(tap.starts, 1, "the engine never asked for a tap")
        var watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, false,
                       "the tap was refused and the page says the module is watching")

        tap.grant = true
        activation.helmComesToTheFront()
        watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, true,
                       "the grant came back and the module did not")
        engine.deactivate()
    }
}
