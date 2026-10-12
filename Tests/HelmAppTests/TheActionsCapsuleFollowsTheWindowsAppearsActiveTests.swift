import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`SettingsToolbar.setWindowAppearsActive(_:)` is the one channel the
/// toolbar's `HelmToolbarActionsModel.appearsActive` gets its value from** (the
/// page bar's capsule has its own, `ShellBarActions`) — fed, on the
/// real window, by `SettingsWindow`'s own `windowDid…` delegate methods
/// (a direct `isKeyWindow || isMainWindow` read, not any SwiftUI content's
/// `controlActiveState` — that type's own header has the reading that ruled
/// the latter out). This file does not repeat that measurement, and does not
/// build a `SettingsWindow` at all — it holds `SettingsToolbar`'s own half of
/// the wiring to account over a bare `NSWindow` that both rows order front.
@MainActor
final class TheActionsCapsuleFollowsTheWindowsAppearsActiveTests: XCTestCase {

    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    /// The toolbar on a window, built under Liquid Glass: the look is read when the bar is built
    /// (`SettingsToolbar`'s `ShapeSignature`), and only a glass capsule is corrected on its first attach, so a
    /// family that reads whether the host was replaced has to say which look it reads. The settings are
    /// pinned through `PinnedBarSettings` and put back when the test ends.
    private func makeToolbar() -> Fixture {
        PinnedBarSettings.pin(in: self)
        AppSettings.barAppearance = .liquidGlass
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Fixture(toolbar: toolbar, model: model, channel: channel, window: window)
    }

    /// The view of the window's `helm.actions` item, read through `ActionsCapsuleReading`: the item's view
    /// hosts the capsule under the look's environment writes, so it is no `NSHostingView<HelmToolbarActionsCapsule>`
    /// and a cast to that type answers nil whatever the bar holds. A window with no toolbar, a toolbar with no
    /// such item, an item with no view and a view holding no capsule each fail with their own sentence, led by
    /// `context`, before the error is thrown.
    private func actionsHost(_ window: NSWindow, context: String,
                             file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        guard let toolbar = window.toolbar else {
            let sentence = "\(context): the window wears no toolbar"
            XCTFail(sentence, file: file, line: line)
            throw ActionsCapsuleReading.Unread(description: sentence)
        }
        return try ActionsCapsuleReading.read(toolbar, context: context, file: file, line: line).host
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
    /// `rebuildActionsHost(_:)` call, which is armed under Liquid Glass only:
    /// a flat capsule has no glass to follow, and its host is never replaced
    /// (`TheToolbarsItemsFollowTheLookTests`' flat row holds that on an unshown
    /// window). `makeToolbar()` stores Liquid Glass before the row declares its
    /// page, so the bar that declaration builds is a glass one. Put the
    /// method's body back to nothing and this goes red under that look: the
    /// host `makeActionsItem` first built is still the one on screen a turn
    /// later.
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
        let builtHost = try actionsHost(fixture.window, context: "on the bar")

        spinOneMainQueueTurn()
        fixture.window.layoutIfNeeded()
        let afterHost = try actionsHost(fixture.window, context: "a turn after attach")
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
    /// hosting-view replacement on every ordinary page switch instead.
    func testABarBuiltWhileActiveIsNeverRebuiltAgain() throws {
        let fixture = makeToolbar()
        fixture.window.appearance = NSAppearance(named: .aqua)
        fixture.window.orderFront(nil)
        fixture.model.selection = .module("test.ordinaryOpenNotRebuilt")
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "plus", title: "Add", symbol: "plus") {}
        ]), token: "test.ordinaryOpenNotRebuilt", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()
        let builtHost = try actionsHost(fixture.window, context: "on the bar")

        spinOneMainQueueTurn()
        fixture.window.layoutIfNeeded()
        let afterHost = try actionsHost(fixture.window, context: "a turn after attach")
        XCTAssertTrue(afterHost === builtHost, """
            an ordinary build's capsule host was replaced with no signal change and no reason to — \
            `correctActionsGlassOnFirstAttach` should not have run
            """)
    }
}
