import XCTest
import HelmContract
import HelmUI
import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// `loadIfNeeded` loads the status and the installed list and deliberately not
/// `brew outdated` — and the status line then said «Updates: 0» about a
/// question that had never been asked. The comment beside the line described
/// this defect as fixed; it was fixed for the installed count only.
///
/// The safe direction is silence: until the outdated list has actually come
/// back, the line says nothing about updates rather than naming a zero — the
/// same reasoning `UnStr.appsCount(nil)` records for the apps list.
@MainActor
final class AStatusLineDoesNotInventZeroUpdatesTests: XCTestCase {

    private final class SilentTransport: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    func testTheLineIsSilentAboutUpdatesUntilTheyHaveLoaded() async {
        let vm = ModuleViewModel(transport: SilentTransport())
        let page = HomebrewSettingsPage(vm: vm)
        let model = HomebrewViewModel.shared(vm: vm)

        // The state the page really opens in: the installed list has answered,
        // `brew outdated` has never been asked. Assert the subject happened —
        // a guard tested against a state that never occurred proves nothing.
        await model.refreshInstalled()
        XCTAssertTrue(model.loadedInstalled)
        XCTAssertFalse(model.loadedOutdated, "precondition: outdated was never asked")

        XCTAssertNotEqual(page.statusLine, HbStr.packagesStatus(0, 0, 0), """
            The status line names a count of updates before `brew outdated` has \
            answered — a zero about a question that was never asked.
            """)

        // And once the answer is in, the full line — the guard must not
        // silence updates for ever.
        await model.refreshOutdated()
        XCTAssertEqual(page.statusLine, HbStr.packagesStatus(0, 0, 0))
    }
}
