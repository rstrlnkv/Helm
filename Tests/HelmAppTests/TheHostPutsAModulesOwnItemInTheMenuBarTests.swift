import HelmContract
import HelmTestSupport
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **The seam has two sides, and only one of them is in the module.**
///
/// Keyboard's menu-bar indicator is built in `attachMenuBarPresence()`, which
/// the host calls when a module starts running, not at the engine's
/// construction, where it would decorate the Mac of every process that asks a
/// descriptor for an engine. That makes it a door nothing has to open: delete
/// the host's call and no test of the module notices, no build fails, and the
/// app quietly loses a feature switched on in somebody's settings.
///
/// So this is the other half, asserted through a descriptor that records: a
/// real `LanguageIndicator` would put a status item into the test run. Both
/// directions, because either can rot on its own: switching a module off must
/// take its item out of the menu bar.
@MainActor
final class TheHostPutsAModulesOwnItemInTheMenuBarTests: XCTestCase {

    private static let moduleID = "test-menu-bar-presence"

    /// A descriptor that counts the two calls and does nothing else.
    private final class Recorder: StandInDescriptor {
        static let id = ModuleID(TheHostPutsAModulesOwnItemInTheMenuBarTests.moduleID)

        var attached = 0
        var detached = 0

        func makeModule(store: NamespacedStore) -> ModuleParts<PageModel> {
            ModuleParts(engine: FakeEngine(), model: PageModel())
        }
        func attachMenuBarPresence() { attached += 1 }
        func detachMenuBarPresence() { detached += 1 }
    }

    private final class PageModel {}

    /// The host's store is `UserDefaults.standard`, so the enabled flag this
    /// writes is a key in the shared domain, taken back out here.
    override func tearDown() async throws {
        ModuleHost.shared.shutdown()
        UserDefaults.standard.removeObject(forKey: "module.\(Self.moduleID).enabled")
        try await super.tearDown()
    }

    func testEnablingAModuleAttachesItsMenuBarPresenceAndDisablingTakesItAway() {
        let descriptor = Recorder()
        let host = ModuleHost.shared

        host.setEnabled(descriptor, true)
        XCTAssertNotNil(host.liveModule(Self.moduleID),
                        "the module never came up, so neither call below proves anything")
        XCTAssertEqual(descriptor.attached, 1, """
            the host built the engine and never asked the module for its menu-bar presence, so \
            Keyboard's language indicator is drawn by nobody — the setting is on in the store and \
            nothing reads it.
            """)

        host.setEnabled(descriptor, false)
        XCTAssertEqual(descriptor.detached, 1, """
            switching the module off left its own menu-bar item where it was: the host dropped \
            the engine without telling the descriptor, which is the state Keyboard shipped in — \
            a flag that only went away when the module was switched back on.
            """)
    }

    /// Quitting is the other route out, and it is not `disable`: `shutdown()`
    /// deliberately skips `willDisable`, which is exactly the kind of asymmetry
    /// where a second teardown gets forgotten.
    func testShutdownTakesTheItemAwayToo() {
        let descriptor = Recorder()
        let host = ModuleHost.shared

        host.setEnabled(descriptor, true)
        XCTAssertEqual(descriptor.attached, 1,
                       "nothing was attached, so «shutdown detaches» would be vacuous")
        host.shutdown()
        XCTAssertEqual(descriptor.detached, 1, """
            the app quit with the module's own status item still in the menu bar and its \
            observers still registered.
            """)
    }
}
