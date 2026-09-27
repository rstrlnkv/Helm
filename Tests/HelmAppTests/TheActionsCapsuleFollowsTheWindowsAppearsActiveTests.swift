import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`SettingsToolbar.setWindowAppearsActive(_:)` is the one channel
/// `HelmToolbarActionsModel.appearsActive` gets its value from** — fed, on the
/// real window, by `SettingsWindow`'s own `windowDid…` delegate methods
/// (a direct `isKeyWindow || isMainWindow` read, not any SwiftUI content's
/// `controlActiveState` — that type's own header has the reading that ruled
/// the latter out). This file does not repeat that measurement, and does not
/// build a `SettingsWindow` at all — it holds `SettingsToolbar`'s own half of
/// the wiring to account with a fixture cheap enough to run on every change,
/// the way `CLAUDE.md` asks a guard to be.
@MainActor
final class TheActionsCapsuleFollowsTheWindowsAppearsActiveTests: XCTestCase {

    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func makeToolbar() -> Fixture {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Fixture(toolbar: toolbar, model: model, channel: channel, window: window)
    }

    private func actionsHost(_ window: NSWindow) -> NSHostingView<HelmToolbarActionsCapsule>? {
        let item = window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" }
        return item?.view as? NSHostingView<HelmToolbarActionsCapsule>
    }

    // MARK: - First open: the capsule host is replaced once

    /// Lets one `DispatchQueue.main.async` turn run to completion — the same
    /// hop `correctActionsGlassOnFirstAttach(_:)` defers its rebuild through,
    /// so the two tests below can observe it having fired.
    private func spinOneMainQueueTurn() {
        let done = expectation(description: "one DispatchQueue.main.async turn")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    /// **A bar built while the window already reads inactive gets its capsule
    /// host replaced once, a turn after it is shown** —
    /// `correctActionsGlassOnFirstAttach(_:)`'s own deferred
    /// `rebuildActionsHost(_:)` call, the one lever this fix has since the
    /// look itself cannot be read here. Put the method's body back to nothing
    /// and this goes red: the host `makeActionsItem` first built is still the
    /// one on screen a turn later.
    func testABarBuiltWhileInactiveGetsItsCapsuleHostReplacedOnceAfterAttach() throws {
        let fixture = makeToolbar()
        fixture.window.appearance = NSAppearance(named: .aqua)
        fixture.toolbar.setWindowAppearsActive(false)
        fixture.model.selection = .module("test.firstOpenReplaced")
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "plus", title: "Add", symbol: "plus") {}
        ]), token: "test.firstOpenReplaced", generation: fixture.channel.nextGeneration())
        // Only now does the window ever appear — matching `SettingsWindow.show`'s
        // own order, where the toolbar is built long before this call.
        fixture.window.orderFront(nil)
        fixture.window.layoutIfNeeded()
        let builtHost = try XCTUnwrap(actionsHost(fixture.window), "no capsule host on the bar")

        spinOneMainQueueTurn()
        fixture.window.layoutIfNeeded()
        let afterHost = try XCTUnwrap(actionsHost(fixture.window), "no capsule host a turn after attach")
        XCTAssertFalse(afterHost === builtHost, """
            the window's first-ever capsule host is still the one `makeActionsItem` built — \
            `correctActionsGlassOnFirstAttach` did not replace it
            """)
    }

    /// **The counterweight: a bar built while the window already reads active
    /// pays nothing extra.** Same fixture, no `setWindowAppearsActive(false)`
    /// beforehand — `windowAppearsActive` starts `true`
    /// (`SettingsToolbar.windowAppearsActive`'s own header), so
    /// `makeActionsItem` never sets the correction flag and this bar's host
    /// is never replaced. Without this, a mutation that rebuilds on every
    /// attach regardless of the flag would pass the test above and cost a
    /// hosting-view replacement on every ordinary S1 page switch instead.
    func testABarBuiltWhileActiveIsNeverRebuiltAgain() throws {
        let fixture = makeToolbar()
        fixture.window.appearance = NSAppearance(named: .aqua)
        fixture.window.orderFront(nil)
        fixture.model.selection = .module("test.ordinaryOpenNotRebuilt")
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "plus", title: "Add", symbol: "plus") {}
        ]), token: "test.ordinaryOpenNotRebuilt", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()
        let builtHost = try XCTUnwrap(actionsHost(fixture.window), "no capsule host on the bar")

        spinOneMainQueueTurn()
        fixture.window.layoutIfNeeded()
        let afterHost = try XCTUnwrap(actionsHost(fixture.window), "no capsule host a turn after attach")
        XCTAssertTrue(afterHost === builtHost, """
            an ordinary S1 build's capsule host was replaced with no signal change and no reason to — \
            `correctActionsGlassOnFirstAttach` should not have run
            """)
    }
}
