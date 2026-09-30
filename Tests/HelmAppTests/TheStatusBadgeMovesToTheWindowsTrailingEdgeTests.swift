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
/// Active/Inactive status badge moved from beside the module's name back to
/// the window's trailing edge — `SettingsToolbar`'s own `helm.status` item,
/// always present on the shared name-only bar and only under
/// `PageBarStyle.moduleName`, the shape this round's item 1 settled on after
/// its skeptic pass.
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

    /// `SettingsWindow.minSize.width` (860) minus `SettingsWindow
    /// .sidebarMaximum` (320) — the narrowest a page's own pane is ever asked
    /// to draw at: the window at its minimum width, with the sidebar pulled
    /// out to its own maximum thickness. `LivePageToolbarFixture`'s own
    /// `width:` sets the window's content width directly, which is what
    /// `offeredRoom()` reads back when there is no split view to ask (its own
    /// header) — the same convention `TheLastItemsGlassSitsAsFarFromTheEdge-
    /// Tests` uses.
    private static let minPaneWidth: CGFloat = 860 - 320

    private var fixtures: [LivePageToolbarFixture] = []

    /// **Forced, not assumed** — `AppSettings.pageBarStyle` is a real,
    /// persisted setting several other files in this target also drive
    /// (`TheBarMenuAnswersOnlyTheBarTests`, `AlwaysCollapseSearchFirstPress-
    /// Tests`, …), none of them restoring it afterwards, so a bare `swift
    /// test` process finds whatever the last one left. Read on this Mac: the
    /// xctest tool's own domain already carried `windowTitle`, which made
    /// every guard here read a bar with no `helm.name` and no `helm.status`
    /// at all — this file's own defect, not the fix's.
    override func setUp() {
        super.setUp()
        AppSettings.pageBarStyle = .moduleName
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

    private func mount(_ selection: SettingsSelection, width: CGFloat) -> LivePageToolbarFixture {
        let fx = LivePageToolbarFixture(EmptyView(), selection: selection, width: width, height: 700)
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
    /// eight languages — `XCTUnwrap` below fails first, before the
    /// `isVisible` assertion is ever reached.
    func testTheStatusItemIsVisibleAtTheMinimumPaneWidthInEveryLanguageOnAllThreeModules() {
        enableTheThreeStatusModules()
        AppLanguage.each { language in
            for module in Self.modules {
                let fx = mount(module.selection, width: Self.minPaneWidth)
                guard let toolbar = fx.mount.window?.toolbar else {
                    XCTFail("\(language) — \(module.name): no toolbar at \(Self.minPaneWidth) pt")
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
                if let name = item(toolbar, "helm.name") {
                    XCTAssertTrue(name.isVisible, "\(language) — \(module.name): helm.name evicted")
                }
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
                XCTFail("\(module.name): no toolbar"); continue
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
            // own last-item measurement pins (`BareToolbarEdgeIsolationTests`,
            // `HelmToolbarActionsCapsule.edgeMargin`'s own header) — proof
            // this item really is the bar's own last one, not merely last in
            // the identifier list.
            let statusTrailing = statusView.convert(NSPoint(x: statusView.bounds.width, y: 0), to: nil).x
            let boxMargin = 1060 - statusTrailing
            XCTAssertEqual(boxMargin, 4, accuracy: 0.5, """
                \(module.name): helm.status's own box sits \(boxMargin) pt from the window's \
                trailing edge — AppKit's own unbordered, last-item margin is 4 pt; a different \
                reading means either another item follows it or it is bordered
                """)
        }
    }

    // MARK: - Empty and out of VoiceOver where there is no status

    /// **General has no notion of running**, so `pageIdentity().status` is
    /// nil there (`moduleStatus` is never called for General; the `nil` sits in
    /// `pageIdentity`'s own `.none, .general` case) — the item is still in the bar
    /// (never a churn across General → Keep Awake → General). Reads only
    /// `rootView.status == nil`: `StatusZoneView.body` computes both "draws
    /// nothing" and `.accessibilityHidden(status == nil)` straight off that
    /// same value, and neither is read behaviourally here. The ink is
    /// `TheStatusItemHoldsUnderTheInputsTheFirstGuardSkippedTests`'s own reach
    /// (`testTheSharedBarBuiltOnGeneralCarriesEachPagesOwnStatusUnclipped`'s
    /// `ink(host)` check on an empty page). This item's VoiceOver gate has
    /// no behavioural reading — it sits in an `NSHostingView`, which answers
    /// nothing in a test process —
    /// `testTheEmptyStatusIsKeptOutOfVoiceOverInTheOnlyPlaceItCanBeRead`
    /// reads the modifier straight off the source instead, which is what its
    /// own doc comment says a behavioural reading cannot do.
    func testTheStatusItemCarriesNoStatusWhereThereIsNoNotionOfRunning() {
        let fx = mount(.general, width: 1060)
        guard let toolbar = fx.mount.window?.toolbar,
              let hosting = item(toolbar, "helm.status")?.view as? NSHostingView<StatusZoneView>
        else { return XCTFail("no helm.status item on General") }
        XCTAssertNil(hosting.rootView.status, "General: helm.status carries a status where there is none")
    }

    // MARK: - Guard: the one combination that would silently lose the badge

    /// **The guard for the one combination `identifiers()` cannot handle.**
    /// It only ever appends `helm.status` on the shared no-content
    /// `.moduleName` shape — a page that also declares `.helmWindowToolbar`
    /// content gets tabs, actions or search instead, and that bar has no
    /// trailing status item at all (`SettingsToolbar.identifiers()`, the
    /// `.moduleName`-gated `.flexibleSpace, statusID` pair). No module does both today
    /// (`ModuleDescriptor.activity`'s default is nil, `ModuleDescriptor.swift:100`,
    /// and only `KeepAwakeDescriptor`, `VPNDescriptor` and `LayoutDescriptor`
    /// override it; only Uninstaller, Homebrew, Hosts and Leftovers call
    /// `.helmWindowToolbar`), so this reads the source rather than mounting a
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
        let both = reportsActivity.intersection(declaresToolbar)
        XCTAssertTrue(both.isEmpty, """
            \(both.sorted()) both override activity(_:) and call .helmWindowToolbar — \
            identifiers() never appends helm.status on a bar with tabs, actions or search, so \
            the status badge would silently vanish on that page
            """)
    }
}
