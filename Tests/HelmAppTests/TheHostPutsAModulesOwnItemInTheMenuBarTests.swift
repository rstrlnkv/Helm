import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **The seam has two sides, and only one of them is in the module.**
///
/// Keyboard's menu-bar indicator moved out of `makeEngine` — where it decorated
/// the Mac of every process that asked a descriptor for an engine, the render
/// harness included — and into `attachMenuBarPresence()`, which the host calls
/// when a module starts running. That leaves the familiar hazard: the module now
/// has a door nothing has to open. Delete the host's call and no test of the
/// module notices, no build fails, and the app quietly loses a feature that is
/// switched on in somebody's settings.
///
/// So this is the other half, asserted through a descriptor that records rather
/// than through Keyboard's own — a real `LanguageIndicator` here would be the
/// status item this whole change exists to keep out of a test run.
///
/// Both directions, because either can rot on its own: switching a module off
/// used to leave Keyboard's flag in the menu bar until somebody switched it back
/// on, which was what rebuilt it.
@MainActor
final class TheHostPutsAModulesOwnItemInTheMenuBarTests: XCTestCase {

    private static let moduleID = "test-menu-bar-presence"

    /// A descriptor that counts the two calls and does nothing else.
    private final class Recorder: ModuleDescriptor {
        static let id = ModuleID(TheHostPutsAModulesOwnItemInTheMenuBarTests.moduleID)
        static let metadata = ModuleMetadata(id: id, name: "Recorder", summary: "",
                                             sfSymbol: "gear", permissions: [])
        static let category: ModuleCategory = .utilities
        static let tint: ModuleTint = .keyboard

        var attached = 0
        var detached = 0

        func makeEngine(store: NamespacedStore) -> any ModuleEngine { Stub() }
        func attachMenuBarPresence() { attached += 1 }
        func detachMenuBarPresence() { detached += 1 }
        func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { nil }
        func settingsPage(_ vm: ModuleViewModel) -> AnyView { AnyView(EmptyView()) }
    }

    private final class Stub: ModuleEngine {
        let transport: EngineTransport = LocalTransport()
        func activate() {}
        func deactivate() {}
    }

    /// The host's store is `UserDefaults.standard`, so the enabled flag this
    /// writes is a key in the shared domain: taken back out here rather than
    /// left for the 3028 that had accumulated once already.
    override func tearDown() {
        ModuleHost.shared.shutdown()
        UserDefaults.standard.removeObject(forKey: "module.\(Self.moduleID).enabled")
        super.tearDown()
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
