import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
import Foundation
import HelmContract
@testable import HelmUI
@testable import HelmApp
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The owner's fourth order on this toolbar (2026-09-21): fix the 37 pt
/// jump, and do it by keeping the item count constant — the mechanism
/// already fixed once for the search field going into `helmSearchable`.**
///
/// «Обновить всё» used to enter and leave a SwiftUI-bridged
/// `ToolbarItemGroup(placement: .primaryAction)` on
/// `hb.segment == .updates && !hb.outdated.isEmpty`. The designer measured
/// what that did: the unselected segment label «Состояние» moved 37.00 pt
/// inside a single frame (f84 → f85, 16.7 ms), twice measured, while
/// `.animation(HelmMotion.interface, value: hb.segment)` already sat on the
/// segment change and still snapped, because that transaction is SwiftUI's
/// and the toolbar's own relayout is AppKit's. The owner's later, revised
/// order (2026-09-22) hid the button off Обновления rather than mounting it
/// disabled everywhere, through one `NSToolbarItem` per action and
/// `NSToolbarItem.isHidden` — which this file rewrote against 2026-09-23,
/// when the morph pass replaced every per-action item with a
/// single `helm.actions` item hosting `HelmToolbarActionsCapsule`
/// (`Sources/HelmUI/DesignSystem/HelmToolbarActions.swift`): there is no
/// longer an `NSToolbarItem` of upgrade all's own to read `isHidden` off, so
/// this file now reads the capsule's own model (`capsuleShows`' header says
/// why not its AX tree), and the overflow menu form that item answers for when
/// it does not fit — the
/// `SettingsToolbar`, live, is still the only place that can be built at all
/// (`CLAUDE.md`'s "app-layer checks in `Tests/HelmAppTests`").
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

    private var fixture: LivePageInTheToolbarFixture?

    override func tearDown() {
        fixture?.drop()
        fixture = nil
        super.tearDown()
    }

    private let node = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                       isCask: false)

    /// The window's toolbar's own item count — every kind, so an item that
    /// left for the overflow menu is still missed the way it would be by a
    /// person looking at the bar. All items and not `.visibleItems`: an item
    /// count that changes because AppKit folded one into the «»» menu is the
    /// same relayout hazard this file is about, not a different question.
    private func toolbarItemCount() -> Int? {
        fixture?.mount.window?.toolbar?.items.count
    }

    private func actionsItem() -> NSToolbarItem? {
        fixture?.mount.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" }
    }

    /// **Whether the capsule is currently showing a button titled `label`.**
    /// There is no longer one `NSToolbarItem` per action to read `isHidden`
    /// off — a hidden action is simply not among `HelmToolbarActionsModel
    /// .visibleIDs` — and SwiftUI's own AX tree for a `Label`-titled button
    /// is not reliably walkable off a window this harness never orders on
    /// screen (measured: `accessibilityChildren()` answered empty all the way
    /// down), so this reads the capsule's own model directly, through
    /// `@testable import HelmUI`.
    ///
    /// **The capsule is read from the view's root through `ActionsCapsuleReading`**, which walks the
    /// environment writes `SettingsToolbar.actionsHost(_:for:)` puts around it. A view with no capsule in
    /// it throws, so it is never read as a button that is not shown: `false` here means a capsule that was
    /// read and has no such entry visible.
    private func capsuleShows(_ label: String, in view: NSView,
                              file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let model = try ActionsCapsuleReading.capsule(inHost: view, context: "Upgrade All", file: file, line: line).model
        guard let entry = model.declared.first(where: { $0.title == label }) else { return false }
        return model.visibleIDs.contains(entry.id)
    }

    /// Whether a button that *is* showing can currently act — the button's
    /// own `isEnabled`, not its visibility: Homebrew shows Upgrade All on
    /// every visit to Обновления and dims it until something is outdated,
    /// rather than hiding it in between.
    ///
    /// A view with no capsule throws; `nil` means a capsule that was read and declares no entry of this
    /// title.
    private func capsuleEnabled(_ label: String, in view: NSView,
                                file: StaticString = #filePath, line: UInt = #line) throws -> Bool? {
        try ActionsCapsuleReading.capsule(inHost: view, context: "Upgrade All", file: file, line: line).model.declared
            .first(where: { $0.title == label })?.isEnabled
    }

    func testTheItemCountIsTheSameOnEveryReasonTheButtonWouldOtherwiseHaveLeft() async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()

        // Installed: the button never applied here even before this change.
        hb.segment = .installed
        let fixture = LivePageInTheToolbarFixture(HomebrewSettingsPage(vm: mvm),
                                             selection: .module(HomebrewDescriptor.id.rawValue),
                                             width: 1060, height: 700)
        fixture.settle(25)
        self.fixture = fixture
        let installedCount = try XCTUnwrap(toolbarItemCount(), "no toolbar to read a count off")
        let installedActions = try XCTUnwrap(actionsItem(), "no single actions item on the toolbar")
        let installedView = try XCTUnwrap(installedActions.view, "the actions item has no hosted view")
        let installedShows = try capsuleShows(HbStr.upgradeAll, in: installedView)
        XCTAssertFalse(installedShows,
                       "Установленные is not Обновления — Upgrade All must not be in the capsule here")
        XCTAssertNotEqual(installedActions.menuFormRepresentation?.title, HbStr.upgradeAll, """
            the overflow menu form still names Upgrade All on Установленные — \
            \(installedActions.menuFormRepresentation?.title ?? "nil")
            """)

        // Updates, nothing outdated: `isVisible` is `hb.segment == .updates`
        // alone — the button is shown and merely dimmed here, never hidden,
        // which is the owner's revised order (2026-09-22): `isEnabled`, not
        // `isVisible`, is what `!hb.outdated.isEmpty` decides.
        transport.outdated = []
        hb.segment = .updates
        await hb.refreshOutdated()
        fixture.settle(25)
        let updatesEmptyCount = try XCTUnwrap(toolbarItemCount())
        let emptyShows = try capsuleShows(HbStr.upgradeAll, in: installedView)
        let emptyEnabled = try capsuleEnabled(HbStr.upgradeAll, in: installedView)
        XCTAssertTrue(emptyShows,
                      "Обновления must show Upgrade All whether or not anything is outdated")
        XCTAssertEqual(emptyEnabled, false, """
            Upgrade All is enabled with nothing outdated to upgrade
            """)

        // Updates, something outdated: the button's old condition was true —
        // the one case that used to add an item.
        transport.outdated = [node]
        await hb.refreshOutdated()
        fixture.settle(25)
        let updatesWithOutdatedCount = try XCTUnwrap(toolbarItemCount())

        XCTAssertEqual(updatesEmptyCount, installedCount, """
            the toolbar holds \(updatesEmptyCount) items on Обновления with nothing outdated \
            against \(installedCount) on Установленные — the button is still leaving the bar \
            for a reason that has nothing to do with whether it can act
            """)
        XCTAssertEqual(updatesWithOutdatedCount, installedCount, """
            the toolbar holds \(updatesWithOutdatedCount) items with something outdated against \
            \(installedCount) with nothing to upgrade — the item count still changes with \
            `hb.segment` and `hb.outdated`, which is the relayout the designer measured moving \
            «Состояние» 37 pt in one frame. «Обновить всё» has to stay dimmed or shown through the \
            one capsule model rather than changing the bar's own identifier list, the way \
            `HelmToolbarAction.isVisible` and `isEnabled` declare it
            """)

        let updatesActions = try XCTUnwrap(actionsItem())
        let updatesView = try XCTUnwrap(updatesActions.view)
        let outdatedShows = try capsuleShows(HbStr.upgradeAll, in: updatesView)
        let outdatedEnabled = try capsuleEnabled(HbStr.upgradeAll, in: updatesView)
        XCTAssertTrue(outdatedShows,
                      "Обновления with something outdated is exactly where Upgrade All must show")
        XCTAssertEqual(outdatedEnabled, true,
                      "something is outdated and nothing is running — Upgrade All must be enabled")
        XCTAssertTrue(installedActions === updatesActions, """
            a different NSToolbarItem answers for the actions capsule after the segment moved — \
            the reserve depends on the declared set, which did not change here, so the same item \
            should have been reused
            """)
    }
}
