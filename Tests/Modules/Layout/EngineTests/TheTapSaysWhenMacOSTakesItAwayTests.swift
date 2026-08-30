import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **The lie arrives after the person fixes the permission, not while it is
/// withheld.**
///
/// While the grant is missing the page is honest: `start` refuses, `tapped`
/// stays false and the module says it is not watching. What was broken is the
/// recovery. macOS revokes a tap mid-session and says so once, down the tap
/// being switched off; `TapDisabled` rules that a revoked grant means stand
/// down, and standing down stopped the tap **without clearing `tapped`** — so
/// `startTap`'s `guard running, !tapped` refused to build another one for the
/// rest of the process. The person restores Accessibility, switches back to
/// Helm, `didBecomeActive` fires, the page goes green — and nobody is listening
/// to the keyboard until they relaunch.
///
/// A local flag standing in for a live external fact, with no channel back from
/// the port that knows (CLAUDE.md § Anything that can stop being true on its
/// own). The channel is `died`.
///
/// **What is not covered here, and cannot be.** No test process can make macOS
/// revoke a real `CGEvent` tap, so `CGKeyTap.theSystemDisabledUs` calling this
/// channel is checked by reading it. What is covered is everything after the
/// call: the state the page draws, and the rebuild on the next activation.
@MainActor
final class TheTapSaysWhenMacOSTakesItAwayTests: XCTestCase {

    private func engine(_ tap: FakeTap) -> LayoutEngine {
        LayoutEngine(tap: tap, typing: FakeTyping(), sources: FakeSources(),
                     translation: FakeTranslation(table: [:]), spell: FakeSpell(valid: []),
                     secure: FakeSecure(),
                     settings: NamespacedStore(namespace: LayoutEngine.moduleID,
                                               backing: InMemoryKeyValueStore()))
    }

    /// The last state the engine published, which is what the settings page
    /// reads. `LocalTransport` replays it, so a reader arriving after the fact
    /// is handed it rather than waiting for the next one.
    private func published(by engine: LayoutEngine) async -> LayoutState? {
        for await event in engine.transport.events
        where event.name == LayoutEvent.layoutState.rawValue {
            return try? JSONDecoder().decode(LayoutState.self, from: event.payload)
        }
        return nil
    }

    func testTheTapIsBuiltAgainAfterMacOSTookTheLastOneAway() async {
        let tap = FakeTap()
        let engine = engine(tap)
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
        let restarted = expectation(description: "the tap was built again")
        tap.onStart = { restarted.fulfill() }
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification,
                                        object: nil)
        await fulfillment(of: [restarted], timeout: 5)

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

    /// The other half, and it is the state `FakeTap` could not be in until now:
    /// `start` returned true unconditionally, so «macOS refused the tap» was
    /// unrepresentable and no test of the honest path could exist.
    func testWithoutTheGrantThePageSaysNobodyIsWatchingAndOneComesBackWithIt() async {
        let tap = FakeTap()
        tap.grant = false
        let engine = engine(tap)
        engine.activate()
        XCTAssertEqual(tap.starts, 1, "the engine never asked for a tap")
        var watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, false,
                       "the tap was refused and the page says the module is watching")

        tap.grant = true
        let started = expectation(description: "the tap started once the grant was given")
        tap.onStart = { started.fulfill() }
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification,
                                        object: nil)
        await fulfillment(of: [started], timeout: 5)
        watching = await published(by: engine)?.enabled
        XCTAssertEqual(watching, true,
                       "the grant came back and the module did not")
        engine.deactivate()
    }
}
