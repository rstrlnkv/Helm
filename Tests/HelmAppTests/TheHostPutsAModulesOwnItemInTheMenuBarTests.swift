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
/// harness included — and into `attachMenuBarPresence()`. The host calls
/// `attachMenuBarPresence(_:)` with the module's view model when a module starts
/// running, and that one's default calls the argument-less one. That leaves the
/// familiar hazard: the module now has a door nothing has to open. Delete the
/// host's call and no test of the module notices, no build fails, and the app
/// quietly loses a feature that is switched on in somebody's settings.
///
/// So this is the other half, asserted through descriptors that record rather
/// than through Keyboard's own — a real `LanguageIndicator` here would be the
/// status item this whole change exists to keep out of a test run.
///
/// Both directions, because either can rot on its own: switching a module off
/// used to leave Keyboard's flag in the menu bar until somebody switched it back
/// on, which was what rebuilt it.
///
/// And what the attach is handed: the view model the host keeps for the module,
/// built over the store the host handed `makeEngine`. A view model built from a
/// transport alone reads an empty in-memory store of its own, so a page or a
/// presence built from it sees none of the keys the engine writes.
@MainActor
final class TheHostPutsAModulesOwnItemInTheMenuBarTests: XCTestCase {

    private static let moduleID = "test-menu-bar-presence"
    private static let viewModelModuleID = "test-menu-bar-presence-with-view-model"

    /// A descriptor that counts the two calls and does nothing else.
    private final class Recorder: ModuleDescriptor {
        static let id = ModuleID(TheHostPutsAModulesOwnItemInTheMenuBarTests.moduleID)
        static let metadata = ModuleMetadata(id: id, name: "Recorder", summary: "",
                                             sfSymbol: "gear", permissions: [])
        static let category: ModuleCategory = .utilities
        static let tint: ModuleTint = .keyboard
        static let glyph: ShellGlyph = .disk

        var attached = 0
        var detached = 0

        func makeEngine(store: NamespacedStore) -> any ModuleEngine { Stub() }
        func attachMenuBarPresence() { attached += 1 }
        func detachMenuBarPresence() { detached += 1 }
        func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { nil }
        func settingsPage(_ vm: ModuleViewModel) -> AnyView { AnyView(EmptyView()) }
    }

    /// A descriptor that keeps what it was handed: the store `makeEngine` got and
    /// the view model the presence was attached with. It overrides the view-model
    /// spelling of the attach, so the argument-less one is never called for it.
    private final class ViewModelRecorder: ModuleDescriptor {
        static let id = ModuleID(TheHostPutsAModulesOwnItemInTheMenuBarTests.viewModelModuleID)
        static let metadata = ModuleMetadata(id: id, name: "ViewModelRecorder", summary: "",
                                             sfSymbol: "gear", permissions: [])
        static let category: ModuleCategory = .utilities
        static let tint: ModuleTint = .keyboard
        static let glyph: ShellGlyph = .disk

        var storeHandedToTheEngine: NamespacedStore?
        var viewModelsAttachedWith: [ModuleViewModel] = []

        func makeEngine(store: NamespacedStore) -> any ModuleEngine {
            storeHandedToTheEngine = store
            return Stub()
        }
        func attachMenuBarPresence(_ vm: ModuleViewModel) { viewModelsAttachedWith.append(vm) }
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
        UserDefaults.standard.removeObject(forKey: "module.\(Self.viewModelModuleID).enabled")
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

    // MARK: - The view model is built over the module's own store

    /// Switches the module on through the host and returns what the host holds
    /// for it, after checking that it came up: a missing module would make every
    /// comparison below a comparison of nothing.
    private func bringUp(_ descriptor: ViewModelRecorder) throws -> ModuleHost.Live {
        ModuleHost.shared.setEnabled(descriptor, true)
        return try XCTUnwrap(ModuleHost.shared.liveModule(Self.viewModelModuleID),
                             "the module never came up, so nothing below compares anything")
    }

    private func address(_ object: AnyObject?) -> String {
        object.map { "\(Unmanaged.passUnretained($0).toOpaque())" } ?? "nil"
    }

    func testTheViewModelTheHostBuildsCarriesTheStoreItHandedToTheEngine() throws {
        let descriptor = ViewModelRecorder()
        let live = try bringUp(descriptor)
        let handed = try XCTUnwrap(descriptor.storeHandedToTheEngine,
                                   "the host never called makeEngine(store:), so there is no store to compare")

        XCTAssertTrue(live.store === handed, """
            the host's own record of the module's store is not the one the engine was handed: \
            live.store \(address(live.store)), handed to makeEngine \(address(handed))
            """)
        XCTAssertTrue(live.vm.store === handed, """
            the view model the host holds for the module reads another store than the engine \
            writes: vm.store \(address(live.vm.store)), handed to makeEngine \(address(handed)) — \
            a page built from it sees keys the engine never wrote.
            """)
    }

    func testThePresenceIsAttachedWithTheViewModelTheHostKeeps() throws {
        let descriptor = ViewModelRecorder()
        let live = try bringUp(descriptor)

        XCTAssertEqual(descriptor.viewModelsAttachedWith.count, 1, """
            the descriptor's attachMenuBarPresence(_ vm:) was called \
            \(descriptor.viewModelsAttachedWith.count) times, not once: none is a host that \
            attaches without the view model, so a presence that needs the module's transport \
            or store is attached by nobody; more than one is the host attaching it more than \
            once for one switch-on.
            """)
        XCTAssertTrue(descriptor.viewModelsAttachedWith.first === live.vm, """
            the presence was attached with \(address(descriptor.viewModelsAttachedWith.first)) \
            while the host holds \(address(live.vm)) in live — a second view model, or none.
            """)
    }
}
