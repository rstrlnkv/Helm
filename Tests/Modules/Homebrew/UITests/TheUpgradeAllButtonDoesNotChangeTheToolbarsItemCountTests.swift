import AppKit
import HelmTestSupport
import XCTest
import Foundation
import HelmContract
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The owner's fourth order on this toolbar (2026-09-21): fix the 37 pt
/// jump, and do it by keeping the item count constant — the mechanism
/// already fixed once for the search field going into `helmSearchable`.**
///
/// «Обновить всё» entered and left `pageToolbar`'s `ToolbarItemGroup(placement:
/// .primaryAction)` on `hb.segment == .updates && !hb.outdated.isEmpty`. The
/// designer measured what that did: the unselected segment label «Состояние»
/// moved 37.00 pt inside a single frame (f84 → f85, 16.7 ms), twice measured,
/// while `.animation(HelmMotion.interface, value: hb.segment)` already sat on
/// the segment change and still snapped, because that transaction is
/// SwiftUI's and the toolbar's own relayout is AppKit's — the same reading
/// `managerBody`'s own comment gives for the search field, and no curve
/// written in this file reaches either. The remedy already shipped for the
/// search field was to stop the toolbar's item count from changing at all;
/// this file holds the same remedy for this button, and reads the count
/// rather than the frame jump, because AppKit's own relayout is not
/// something a headless test can watch move.
@MainActor
final class TheUpgradeAllButtonDoesNotChangeTheToolbarsItemCountTests: XCTestCase {

    private final class Cellar: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let lock = NSLock()
        private var _outdated: [OutdatedPackage] = []
        var outdated: [OutdatedPackage] {
            get { lock.lock(); defer { lock.unlock() }; return _outdated }
            set { lock.lock(); _outdated = newValue; lock.unlock() }
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .outdated: return try JSONEncoder().encode(outdated)
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    private var mount: MountedRender?

    override func tearDown() {
        mount?.drop()
        mount = nil
        super.tearDown()
    }

    private let node = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                       isCask: false)

    /// The window's toolbar's own item count — every kind, so an item that
    /// left for the overflow menu is still missed the way it would be by a
    /// person looking at the bar. `.items` and not `.visibleItems`: an item
    /// count that changes because AppKit folded one into the «»» menu is the
    /// same relayout hazard this file is about, not a different question.
    private func toolbarItemCount(_ mount: MountedRender) -> Int? {
        // `MountedRender` carries no accessor of its own for the raw toolbar
        // — only for the search field it already had a reason to reach —
        // so the count is read the same way `ASearchFieldSaysWhatItIsTests`
        // reads the field itself: off the mounted window's own toolbar.
        guard let field = mount.searchField, let window = field.window else { return nil }
        return window.toolbar?.items.count
    }

    func testTheItemCountIsTheSameOnEveryReasonTheButtonWouldOtherwiseHaveLeft() async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()

        // Installed: the button never applied here even before this change.
        hb.segment = .installed
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm), width: 1060, height: 700,
                                  appearance: .aqua)
        mount.settle(25)
        self.mount = mount
        let installedCount = try XCTUnwrap(toolbarItemCount(mount),
                                           "no toolbar to read a count off")

        // Updates, nothing outdated: the button's old condition was false here
        // too — the case that used to be indistinguishable from Installed.
        transport.outdated = []
        hb.segment = .updates
        await hb.refreshOutdated()
        mount.settle(25)
        let updatesEmptyCount = try XCTUnwrap(toolbarItemCount(mount))

        // Updates, something outdated: the button's old condition was true —
        // the one case that used to add an item.
        transport.outdated = [node]
        await hb.refreshOutdated()
        mount.settle(25)
        let updatesWithOutdatedCount = try XCTUnwrap(toolbarItemCount(mount))

        XCTAssertEqual(updatesEmptyCount, installedCount, """
            the toolbar holds \(updatesEmptyCount) items on Обновления with nothing outdated \
            against \(installedCount) on Установленные — the button is still leaving the bar \
            for a reason that has nothing to do with whether it can act
            """)
        XCTAssertEqual(updatesWithOutdatedCount, installedCount, """
            the toolbar holds \(updatesWithOutdatedCount) items with something outdated against \
            \(installedCount) with nothing to upgrade — the item count still changes with \
            `hb.segment` and `hb.outdated`, which is the relayout the designer measured moving \
            «Состояние» 37 pt in one frame. «Обновить всё» has to stay mounted and merely \
            disabled where it cannot act, the way Refresh already is while an operation runs
            """)
    }
}
