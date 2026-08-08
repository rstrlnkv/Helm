import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The two automation switches, drawn on two screens at once.
///
/// The settings page and the panel tile both draw "keep awake with an external
/// display" and "keep awake on power", and `NamespacedStore` is not observable —
/// each screen reads it into `@State` when it appears. With both open, flipping
/// one left the other showing what it had read on opening, and the next thing
/// that screen wrote put the stale value back. `keepAwakeAutomationMirror` is
/// the one place that listens now, and this is what it has to do.
///
/// Hosted in an `NSHostingView`, because the modifier *is* an `onReceive` and a
/// view that is never installed receives nothing. The window is offscreen and
/// needs no permission, the way `DisclosureProbe` already measures.
@MainActor
final class AutomationMirrorTests: XCTestCase {

    /// The other screen's `@State`, in a class so a test can read it back.
    private final class Switches: ObservableObject {
        @Published var externalDisplay = false
        @Published var power = false
    }

    private struct Harness: View {
        @ObservedObject var switches: Switches
        let store: NamespacedStore
        var body: some View {
            Color.clear
                .keepAwakeAutomationMirror(store,
                                           externalDisplay: $switches.externalDisplay,
                                           power: $switches.power)
        }
    }

    /// Installs the harness and holds the window for the test's lifetime — a
    /// hosting view whose window is released stops receiving.
    private func mounted(_ store: NamespacedStore) -> Switches {
        let switches = Switches()
        let host = NSHostingView(rootView: Harness(switches: switches, store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in window.contentView = nil }
        settle()
        return switches
    }

    /// `NamespacedStore` posts on the main thread; the run loop is where the
    /// notification is actually delivered.
    private func settle() {
        for _ in 0..<10 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func store() -> NamespacedStore {
        // In memory, never `UserDefaults.standard`: the runner's domain is
        // shared with every package tested on this machine.
        NamespacedStore(namespace: KeepAwakeDescriptor.id.rawValue,
                        backing: InMemoryKeyValueStore())
    }

    // MARK: -

    func testTheExternalDisplaySwitchFollowsAWriteFromTheOtherScreen() {
        let store = store()
        let switches = mounted(store)
        XCTAssertFalse(switches.externalDisplay, "precondition: off on both screens")

        KeepAwakeSettings(store: store).setAutoExternalDisplay(true)
        settle()

        XCTAssertTrue(switches.externalDisplay,
                      "the other screen still draws this switch off, and the next thing "
                      + "it writes will put the stored value back to off")
    }

    func testThePowerSwitchFollowsAWriteFromTheOtherScreen() {
        let store = store()
        let switches = mounted(store)

        KeepAwakeSettings(store: store).setAutoPower(true)
        settle()

        XCTAssertTrue(switches.power)
    }

    /// The half a mirror gets wrong by being too eager: it must copy the value
    /// that changed, not re-read both. Asserted because the modifier's two `if`s
    /// are the only thing keeping them apart, and a mirror that assigns both on
    /// every notification would satisfy the two tests above.
    func testAWriteToOneSwitchLeavesTheOtherAlone() {
        let store = store()
        let settings = KeepAwakeSettings(store: store)
        settings.setAutoPower(true)
        let switches = mounted(store)
        switches.power = false          // this screen's own, unsaved, edit

        settings.setAutoExternalDisplay(true)
        settle()

        XCTAssertTrue(switches.externalDisplay, "precondition: the write did arrive")
        XCTAssertFalse(switches.power,
                       "a change to the display switch re-read the power switch as well, "
                       + "throwing away an edit this screen had not stored yet")
    }

    /// Another module's write, naming the same bare key under its own
    /// namespace. `changed(_:is:)` compares the *namespaced* key, which is the
    /// only thing keeping `module.vpn.autoPower` out of this screen.
    ///
    /// **It ends by asserting that a real write does arrive**, in the same
    /// harness, after the foreign one did not. Without that the whole test is
    /// satisfied by a mirror that was never installed — which is exactly what
    /// happened when it was first written: it passed with the modifier's body
    /// replaced by `self`, and passed again with the two `if`s deleted.
    func testAWriteFromAnotherModulesStoreMovesNeitherSwitch() {
        let store = store()
        // Stored on, drawn off: this screen has an edit it has not saved, and a
        // mirror that re-reads on any notification would overwrite it.
        KeepAwakeSettings(store: store).setAutoPower(true)
        let switches = mounted(store)
        switches.power = false

        NotificationCenter.default.post(name: .helmStoreChanged,
                                        object: "module.vpn.\(KeepAwakeSettings.Key.autoPower)")
        settle()

        XCTAssertFalse(switches.power,
                       "another module's write to its own `autoPower` moved this screen's")
        XCTAssertFalse(switches.externalDisplay)

        KeepAwakeSettings(store: store).setAutoExternalDisplay(true)
        settle()
        XCTAssertTrue(switches.externalDisplay,
                      "the control: this harness was listening the whole time, so the "
                      + "two assertions above are about the foreign key and not about "
                      + "a mirror that was never installed")
    }
}
