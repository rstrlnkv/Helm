import HelmContract
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// A rule applies and the Mac sleeps anyway.
///
/// Stopping a session while a rule still holds silences that rule until it
/// fires again, and a timer that ends automation does the same when it runs
/// out. Both are correct, and neither used to be visible anywhere: the switch
/// reads off, the rule reads on, and the app that should be holding the Mac
/// awake is still on screen. There is a line for it on the settings page and
/// now one in the panel, which is where somebody looks when the Mac slept and
/// they did not expect it to.
///
/// Both lines are drawn from `vm.suppressed`, and both are invisible until it
/// is true. So what has to be guarded is not the row — it is the hop the row
/// depends on: the engine sets the flag, JSON carries it, the view model
/// publishes it. Break any link and both rows are dead code that looks right in
/// a screenshot taken by hand and never appears in anybody's life.
@MainActor
final class TheSilencedRuleReachesTheScreenTests: XCTestCase {

    /// Feeds the view model exactly what the engine emits: the engine's own
    /// `StatePayload`, encoded, under the engine's own event name. A hand-built
    /// dictionary here would be a second declaration of the wire and would go
    /// on passing after the real one changed.
    private func deliver(_ payload: KeepAwakeEngine.StatePayload,
                         to transport: LocalTransport) async {
        guard let data = try? JSONEncoder().encode(payload) else {
            return XCTFail("the engine's own payload did not encode")
        }
        transport.emit(EngineEvent(name: KeepAwakeEvent.state.rawValue, payload: data))
        // The view model reads events in a task of its own; give it the turn.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func state(suppressed: Bool) -> KeepAwakeEngine.StatePayload {
        KeepAwakeEngine.StatePayload(isActive: false, conditions: [], clamshellActive: false,
                                     endDate: nil, startDate: nil, suppressed: suppressed)
    }

    func testTheFlagTravelsFromTheEngineToTheScreen() async {
        let transport = LocalTransport()
        let vm = KeepAwakeViewModel.shared(vm: ModuleViewModel(transport: transport))

        XCTAssertFalse(vm.suppressed, "precondition: nothing is silenced yet")
        await deliver(state(suppressed: true), to: transport)

        XCTAssertTrue(vm.suppressed,
                      "the engine says a rule is silenced and no screen can find out — "
                      + "the line on the page and the row in the panel are both dead")
    }

    /// And it clears. The row goes away by itself when the condition drops —
    /// there is nothing to dismiss — so a flag that only ever turns on would
    /// leave «Resume» offered for a rule that is already running.
    func testItClearsAgain() async {
        let transport = LocalTransport()
        let vm = KeepAwakeViewModel.shared(vm: ModuleViewModel(transport: transport))

        await deliver(state(suppressed: true), to: transport)
        XCTAssertTrue(vm.suppressed, "precondition: it was set")

        await deliver(state(suppressed: false), to: transport)
        XCTAssertFalse(vm.suppressed,
                       "the rule is holding the Mac again and both screens still offer "
                       + "to resume it")
    }

    // The command itself — that `resumeAutomation` really lifts suppression and
    // hands the Mac back to the rule — is guarded next door, in
    // `ATimerCanEndTheAutomationItSatOnTests`, where the engine's fakes live.
    // Repeating it here would be a second copy of a check, not a second check.
}
