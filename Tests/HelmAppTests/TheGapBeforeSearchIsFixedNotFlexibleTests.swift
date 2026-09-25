import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import HelmApp
@testable import HelmUI
@testable import Module_Uninstaller_UI

/// **The item immediately ahead of `helm.search` is `helm.actions`, and never
/// a flexible space, at every width tried.**
///
/// **Rewritten 2026-09-24, from the SwiftUI-`.searchable` bridge this file
/// used to read against.** Before `UninstallerSettingsPage` moved onto
/// `.helmWindowToolbar`, `.searchable(placement: .toolbar)` inserted a
/// flexible space of its own ahead of the bridged search item, and
/// `ToolbarSearchName.closeGapBeforeSearch(in:)` swapped it for a fixed one
/// after the fact on every `willAddItem` and every `nameWhatIsThere()` —
/// this file mounted that bridge by hand and read the correction. Uninstaller
/// was the last page still calling `.helmSearchable`
/// (`command grep -rn 'helmSearchable\|\.searchable(' Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift`
/// finds nothing now); `SettingsToolbar.identifiers` (`SettingsToolbar.swift`)
/// never puts a spacer of any kind next to `helm.search` in the first place —
/// there is no after-the-fact correction left to guard, only the ordering
/// itself, read off a real, attached `NSToolbar` through
/// `LivePageToolbarFixture` (its own header explains why only
/// `Tests/HelmAppTests` can build one).
@MainActor
final class TheGapBeforeSearchIsFixedNotFlexibleTests: XCTestCase {

    /// Answers `.listApps` so the page has something other than a wait state
    /// to draw — the toolbar's own identifier list does not depend on it, but
    /// a page stuck loading is not the ordinary case this file means to read.
    private final class Stub: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data {
            guard UninstallerCommand(rawValue: command.name) == .listApps else { return Data() }
            return (try? JSONEncoder().encode([InstalledApp]())) ?? Data()
        }
    }

    private var fixture: LivePageToolbarFixture?

    override func tearDown() {
        fixture?.drop()
        fixture = nil
        super.tearDown()
    }

    /// The identifier of the item right before `helm.search`, read straight
    /// off `toolbar.items` — the list `SettingsToolbar.identifiers` built,
    /// with no skip over a spacer: a spacer *is* the defect this file is
    /// about, so stepping past one the way a pixel-gap measurement has to
    /// skip an overflowed item would hide exactly what it exists to catch.
    private func identifierBeforeSearch(_ toolbar: NSToolbar) -> NSToolbarItem.Identifier? {
        let items = toolbar.items
        guard let searchIndex = items.firstIndex(where: { $0.itemIdentifier.rawValue == "helm.search" }),
              searchIndex > 0 else { return nil }
        return items[searchIndex - 1].itemIdentifier
    }

    /// **Never `.flexibleSpace`, at 860 (the window's own floor,
    /// `SettingsWindow.minSize`), 1060 (the default) and 1400 pt** — the three
    /// widths quoted in this file's own predecessor's readings. The switcher
    /// may fold to its compact capsule at some of these and not others; the
    /// bar's own identifier list, which this file reads, does not change
    /// shape for that (`SettingsToolbar.identifiers`'s own doc: "a tab change
    /// never renegotiates the bar's shape").
    func testTheItemAheadOfSearchIsHelmActionsAtEveryWidth() async throws {
        let vm = ModuleViewModel(transport: Stub())
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()

        for width: CGFloat in [860, 1060, 1400] {
            let fixture = LivePageToolbarFixture(UninstallerSettingsPage(vm: vm),
                                                 selection: .module(UninstallerDescriptor.id.rawValue),
                                                 width: width, height: 700)
            fixture.settle(30)
            self.fixture = fixture
            let toolbar = try XCTUnwrap(fixture.mount.window?.toolbar, "\(width) pt: no toolbar")
            let identifier = try XCTUnwrap(identifierBeforeSearch(toolbar),
                                           "\(width) pt: could not read the item ahead of search")
            XCTAssertEqual(identifier.rawValue, "helm.actions", """
                At \(width) pt the item immediately ahead of `helm.search` is \
                `\(identifier.rawValue)` — Uninstaller's own actions capsule must sit there, \
                never a flexible space
                """)
            fixture.drop()
        }
        fixture = nil
    }
}
