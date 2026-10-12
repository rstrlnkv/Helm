import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_UI
import Module_Layout_UI
import Module_VPN_UI
@testable import HelmApp
@testable import HelmUI

/// **The owner, 2026-09-28: «Давай вернем его в правую часть».** The
/// Active/Inactive status badge stands at the window's trailing edge, right of
/// the module's name — `SettingsToolbar`'s own `helm.status` item, always
/// present on the shared name-only bar and only under `PageBarStyle.moduleName`.
///
/// **The bar read here** is the `SettingsToolbar` of `LivePageInTheToolbarFixture`, built with the
/// `.sidebarSeparator` lead. The status item is made by `makeStatusItem` and patched by `patchName` whichever
/// lead the toolbar wears; the lead enters the list only before the status (`identifiers(content:style:lead:)`
/// puts the tracking separator or the name ahead of it), and the tail `[.flexibleSpace, helm.status]` the
/// name-only bar ends on is the same under both.
///
/// **Real modules, not a recorder** — unlike `TheHostPutsAModulesOwnItemIn-
/// TheMenuBarTests`'s own `Recorder`, which exists precisely because a real
/// `LanguageIndicator` would decorate this Mac's menu bar. Keyboard's own
/// indicator only builds a status item when its own `indicator` store key
/// reads `true` (`LanguageIndicator.refresh`'s own guard, default `false`),
/// and nothing here writes that key — `ModuleHost.shared.setEnabled` seeds no
/// store beyond the "enabled" flag — so enabling `LayoutDescriptor` for real
/// here builds no status item on this Mac, the same care `ModulePageFixtures
/// .swift`'s own header takes with *seeding* that module's store.
@MainActor
final class TheStatusBadgeMovesToTheWindowsTrailingEdgeTests: XCTestCase {

    /// `SettingsWindow.minSize.width` (860) minus the widest of `ShellGeometry.sidebarRange` (320): narrower than the window reaches, where the sidebar is 200 or the rail.
    /// `LivePageInTheToolbarFixture`'s own `width:` sets the window's content width directly, which is what
    /// `offeredRoom()` reads back when there is no split view to ask — the same convention
    /// `TheLastItemsGlassSitsAsFarFromTheEdgeTests` uses.
    private static let minPaneWidth: CGFloat = 860 - 320

    private var fixtures: [LivePageInTheToolbarFixture] = []

    /// **Forced, not assumed** — `pageBarStyle` is a real, persisted setting several other files in this
    /// target also drive, so a bare `swift test` process finds whatever the last one left; on
    /// `.windowTitle` the bar carries no `helm.status` at all. The pin puts every setting back after the test.
    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in Self.moduleIDs {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        super.tearDown()
    }

    private static let moduleIDs = [
        KeepAwakeDescriptor.id.rawValue, VPNDescriptor.id.rawValue, LayoutDescriptor.id.rawValue,
    ]

    private static let modules: [(name: String, selection: SettingsSelection)] = [
        ("Keep Awake", .module(KeepAwakeDescriptor.id.rawValue)),
        ("VPN", .module(VPNDescriptor.id.rawValue)),
        ("Keyboard", .module(LayoutDescriptor.id.rawValue)),
    ]

    private func enableTheThreeStatusModules() {
        ModuleHost.shared.shutdown()
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        ModuleHost.shared.setEnabled(VPNDescriptor(), true)
        ModuleHost.shared.setEnabled(LayoutDescriptor(), true)
    }

    private func mount(_ selection: SettingsSelection, width: CGFloat) -> LivePageInTheToolbarFixture {
        let fx = LivePageInTheToolbarFixture(EmptyView(), selection: selection, width: width, height: 700)
        fx.settle(30)
        fixtures.append(fx)
        return fx
    }

    private func item(_ toolbar: NSToolbar, _ rawID: String) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier.rawValue == rawID }
    }

    // MARK: - Visible, and nothing in the overflow menu

    /// **Puts the defect back to watch this go red**: reading it against the
    /// pre-fix `identifiers()` (no `helm.status` appended at all) leaves
    /// `item(toolbar, "helm.status")` `nil` for all three modules, in all
    /// eight languages — the `guard` below fails first ("no helm.status item
    /// in …"), before the `isVisible` assertion is ever reached.
    func testTheStatusItemIsVisibleAtTheMinimumPaneWidthInEveryLanguageOnAllThreeModules() {
        enableTheThreeStatusModules()
        AppLanguage.each { language in
            for module in Self.modules {
                let fx = mount(module.selection, width: Self.minPaneWidth)
                guard let toolbar = fx.mount.window?.toolbar else {
                    XCTFail("\(language) — \(module.name): no toolbar on the fixture's window at \(Self.minPaneWidth) pt")
                    continue
                }
                guard let status = item(toolbar, "helm.status") else {
                    XCTFail("""
                        \(language) — \(module.name): no helm.status item in \
                        \(toolbar.itemIdentifiers.map(\.rawValue)) — the badge never moved to the \
                        trailing edge
                        """)
                    continue
                }
                XCTAssertTrue(status.isVisible, """
                    \(language) — \(module.name): helm.status is not isVisible at \
                    \(Self.minPaneWidth) pt — AppKit folded it into the »» overflow menu, which \
                    the owner's 2026-09-23 "nothing into »" rule forbids
                    """)
                // Nothing this bar carries may sit in the overflow menu either
                // — the name-only bar's other watched item, same rule.
                guard let name = item(toolbar, "helm.name") else {
                    XCTFail("\(language) — \(module.name): no helm.name item in \(toolbar.itemIdentifiers.map(\.rawValue))")
                    continue
                }
                XCTAssertTrue(name.isVisible, "\(language) — \(module.name): helm.name evicted")
            }
        }
    }

    // MARK: - Order: right after the flexible space, at the trailing end

    /// **Puts the defect back**: the pre-fix `identifiers()` never appends
    /// `.flexibleSpace, statusID` on the no-content `.moduleName` shape, so
    /// `toolbar.itemIdentifiers` for these three modules ends on `helm.name`
    /// — `suffix(2)` below reads `[.sidebarTrackingSeparator, helm.name]`
    /// rather than `[.flexibleSpace, helm.status]`, and the first assertion
    /// fails.
    func testTheStatusItemFollowsTheFlexibleSpaceAtTheTrailingEndOfTheNameOnlyBar() {
        enableTheThreeStatusModules()
        for module in Self.modules {
            let fx = mount(module.selection, width: 1060)
            guard let toolbar = fx.mount.window?.toolbar else {
                XCTFail("\(module.name): no toolbar on the fixture's window"); continue
            }
            let ids = toolbar.itemIdentifiers.map(\.rawValue)
            XCTAssertEqual(ids.suffix(2), ["NSToolbarFlexibleSpaceItem", "helm.status"], """
                \(module.name): the bar's own tail is \(ids) — the status item must be the very \
                last identifier, right after a flexible space, on the shared name-only bar
                """)

            guard let nameView = item(toolbar, "helm.name")?.view,
                  let statusView = item(toolbar, "helm.status")?.view
            else { return XCTFail("\(module.name): missing name or status view") }
            let nameTrailing = nameView.convert(NSPoint(x: nameView.bounds.width, y: 0), to: nil).x
            let statusLeading = statusView.convert(.zero, to: nil).x
            XCTAssertGreaterThanOrEqual(statusLeading, nameTrailing, """
                \(module.name): helm.status's own leading edge (\(statusLeading)) sits ahead of \
                helm.name's trailing edge (\(nameTrailing)) — the badge is still beside the name \
                rather than pushed to the far end by the flexible space between them
                """)

            // The same 4 pt `isBordered = false` outer margin the capsule's
            // own last-item measurement pins (`HelmToolbarActionsCapsule.edgeMargin`) — proof this
            // item really is the bar's own last one, not merely last in the identifier list.
            let statusTrailing = statusView.convert(NSPoint(x: statusView.bounds.width, y: 0), to: nil).x
            let boxMargin = 1060 - statusTrailing
            XCTAssertEqual(boxMargin, 4, accuracy: 0.5, """
                \(module.name): helm.status's own box sits \(boxMargin) pt from the window's \
                trailing edge — AppKit's own unbordered, last-item margin is 4 pt; a different \
                reading means either another item follows it or it is bordered
                """)
        }
    }

    // MARK: - No status where there is no notion of running

    /// **General has no notion of running**, so `pageIdentity().status` is
    /// nil there (`moduleStatus` is never called for General; the `nil` is
    /// `settings`' own, which `pageIdentity`'s `.none, .general` case returns) — on this fixture the item is
    /// still in the bar. Reads only `rootView.status == nil`: what the item draws from it, and that the
    /// bar is not rebuilt across General → Keep Awake → General, are not read here — they are
    /// `TheStatusItemHoldsUnderTheInputsTheFirstGuardSkippedTests`'s own reach
    /// (`testTheSharedBarBuiltOnGeneralCarriesEachPagesOwnStatusUnclipped`: on an empty page the host is
    /// asserted 0 pt tall, which is what an empty status measures there, and photographed for ink only
    /// if it were to have a size; and its same-toolbar and same-identifiers checks). The name item is read as present first, so a bar that was
    /// never built or never listed its items cannot pass the absence.
    func testTheStatusItemCarriesNoStatusWhereThereIsNoNotionOfRunning() {
        let fx = mount(.general, width: 1060)
        guard let toolbar = fx.mount.window?.toolbar else {
            return XCTFail("General: no toolbar on the fixture's window")
        }
        XCTAssertNotNil(item(toolbar, "helm.name"), """
            General: the toolbar lists no helm.name (it lists \(toolbar.itemIdentifiers.map(\.rawValue))) — \
            the bar was not built under `.moduleName`, so an absent status proves nothing
            """)
        guard let hosting = item(toolbar, "helm.status")?.view as? NSHostingView<StatusZoneView>
        else { return XCTFail("no helm.status item on General") }
        XCTAssertNil(hosting.rootView.status, "General: helm.status carries a status where there is none")
    }

    // MARK: - Guard: the one combination that would silently lose the badge

    /// **The guard for the one combination `SettingsToolbar.identifiers(content:style:lead:)` cannot handle.**
    /// It only ever appends `helm.status` on the shared no-content
    /// `.moduleName` shape — a page that also declares `.helmWindowToolbar`
    /// content gets tabs, actions or search instead, and that bar has no
    /// trailing status item at all (the `.moduleName`-gated `.flexibleSpace, statusID` pair). No module
    /// does both today (`ModuleDescriptor.activity`'s default is nil, in the extension of `ModuleDescriptor.swift`,
    /// and only `KeepAwakeDescriptor`, `VPNDescriptor` and `LayoutDescriptor`
    /// override it; which modules call `.helmWindowToolbar` is what the scan
    /// below finds), so this reads the source rather than mounting a
    /// combination the app cannot produce.
    func testNoModuleBothReportsActivityAndDeclaresToolbarContent() throws {
        let files = try RepoSource.swiftFiles(under: "Sources/Modules")
        var reportsActivity: Set<String> = []
        var declaresToolbar: Set<String> = []
        for file in files {
            // "Sources/Modules/<Name>/…" — the module's own directory.
            let parts = file.split(separator: "/")
            guard parts.count > 2, parts[0] == "Sources", parts[1] == "Modules" else { continue }
            let module = String(parts[2])
            let source = SwiftSource.uncommented(try RepoSource.text(of: file))
            if source.contains("func activity(_ vm: ModuleViewModel) -> ModuleActivity?") {
                reportsActivity.insert(module)
            }
            if source.contains(".helmWindowToolbar(") {
                declaresToolbar.insert(module)
            }
        }
        // The scan found its subjects on both sides, or an empty intersection proves nothing.
        XCTAssertFalse(reportsActivity.isEmpty, "the scan found no module that reports activity")
        XCTAssertFalse(declaresToolbar.isEmpty, "the scan found no module that declares toolbar content")
        let both = reportsActivity.intersection(declaresToolbar)
        XCTAssertTrue(both.isEmpty, """
            \(both.sorted()) both override activity(_:) and call .helmWindowToolbar — \
            identifiers() never appends helm.status on a bar with tabs, actions or search, so \
            the status badge would silently vanish on that page
            """)
    }
}
