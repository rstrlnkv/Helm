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
/// Active/Inactive status badge stands at the page bar's trailing edge, right of
/// the module's name: the bar's `.status` zone, present only under
/// `PageBarStyle.moduleName` and only on a page with no tabs, no actions and no
/// search (`ShellPageBar.Snapshot.statusWord`).
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
///
/// **The machine's settings the bar reads when it is built** — the page bar
/// style, the sidebar style, the search's collapse and the bar's appearance —
/// are pinned in `setUp` and put back in `tearDown`; with the page bar style on
/// the window title the bar draws no status at all. Every fixture is dropped in
/// `tearDown`: its search zone holds a process-wide event monitor until then.
@MainActor
final class TheStatusBadgeMovesToTheWindowsTrailingEdgeTests: XCTestCase {

    /// `SettingsWindow.minSize.width` (860) minus the widest of `ShellGeometry.sidebarRange` (320): narrower than the window reaches, where the sidebar is 200 or the rail.
    /// `LivePageToolbarFixture`'s own `width:` sets the window's content width, which is the bar's width.
    private static let minPaneWidth: CGFloat = 860 - 320

    private var fixtures: [LivePageToolbarFixture] = []
    private var savedStyle: PageBarStyle = .moduleName
    private var savedSidebarStyle: SidebarStyle = .colour
    private var savedCollapse = false
    private var savedBarAppearance: HelmBarAppearance = .flat

    /// **Forced, not assumed** — these are real, persisted settings several other files in this target
    /// also drive, so a bare `swift test` process finds whatever the last one left. With
    /// `AppSettings.pageBarStyle` on `.windowTitle` the bar carries no status zone at all.
    override func setUp() {
        super.setUp()
        savedStyle = AppSettings.pageBarStyle
        savedSidebarStyle = AppSettings.sidebarStyle
        savedCollapse = AppSettings.alwaysCollapseSearch
        savedBarAppearance = AppSettings.barAppearance
        AppSettings.pageBarStyle = .moduleName
        AppSettings.sidebarStyle = .colour
        AppSettings.alwaysCollapseSearch = false
        AppSettings.barAppearance = .flat
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in Self.moduleIDs {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        AppSettings.pageBarStyle = savedStyle
        AppSettings.sidebarStyle = savedSidebarStyle
        AppSettings.alwaysCollapseSearch = savedCollapse
        AppSettings.barAppearance = savedBarAppearance
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

    // MARK: - Present, and with room for its word, at the narrowest pane

    /// With the status word left out of the snapshot the bar has no `.status` zone for any of the three
    /// modules, in any of the eight languages, and the `.status` half of the two `reachableZones`
    /// assertions fails first.
    func testTheStatusZoneIsReachableAndHasRoomForItsWordAtTheMinimumPaneWidthInEveryLanguageOnAllThreeModules() {
        enableTheThreeStatusModules()
        AppLanguage.each { language in
            for module in Self.modules {
                let label = "\(language) — \(module.name)"
                let fx = mount(module.selection, width: Self.minPaneWidth)
                let view = fx.bar.view
                XCTAssertTrue(view.reachableZones.contains(.name), "\(label): the name zone is not reachable")
                XCTAssertTrue(view.reachableZones.contains(.status), """
                    \(label): the bar has no reachable status zone at \(Self.minPaneWidth) pt — \
                    the badge never reached the trailing edge
                    """)
                guard let status = view.view(for: .status), let name = view.view(for: .name) else {
                    XCTFail("\(label): missing name or status view"); continue
                }
                XCTAssertGreaterThan(name.frame.width, 0, "\(label): the name was given no room")
                // The placed host's `fittingSize` is the content's own width: it read the same as a host
                // nobody had constrained in all 24 combinations of language and module, so this is not a
                // width compared with itself. The zone may be wider by up to a point, never narrower.
                XCTAssertGreaterThanOrEqual(status.frame.width, status.fittingSize.width, """
                    \(label): the status zone is \(status.frame.width) pt wide, its word needs \
                    \(status.fittingSize.width) pt
                    """)
                XCTAssertGreaterThanOrEqual(status.frame.minX, name.frame.maxX, """
                    \(label): the status (from \(status.frame.minX)) overlaps the name (to \
                    \(name.frame.maxX))
                    """)
            }
        }
    }

    // MARK: - Order: the status is the last zone, at the trailing edge

    /// A status zone laid out next to the name instead of at the end (its frame computed from the name's
    /// trailing edge) leaves `statusLeading` close to the name's trailing edge and `content - statusTrailing`
    /// at the window's width minus that, so the 100 pt assertion and the edge assertion both fail; a status
    /// that is absent fails the first assertion.
    func testTheStatusZoneIsTheLastOneAndEndsAtTheBarsTrailingEdgeRightOfTheName() {
        enableTheThreeStatusModules()
        for module in Self.modules {
            let fx = mount(module.selection, width: 1060)
            let view = fx.bar.view
            // `reachableZones` is filtered from `Zone.allCases`, where `.status` is the last case, so this
            // says the status is reachable; that it stands last is carried by the geometry below.
            XCTAssertTrue(view.reachableZones.contains(.status), """
                \(module.name): the bar's reachable zones are \(view.reachableZones) — the status \
                is not reachable
                """)
            guard let nameView = view.view(for: .name), let statusView = view.view(for: .status) else {
                XCTFail("\(module.name): missing name or status view"); continue
            }
            let nameTrailing = nameView.convert(NSPoint(x: nameView.bounds.width, y: 0), to: nil).x
            let statusLeading = statusView.convert(.zero, to: nil).x
            let statusTrailing = statusView.convert(NSPoint(x: statusView.bounds.width, y: 0), to: nil).x
            XCTAssertGreaterThan(statusLeading, nameTrailing, """
                \(module.name): the status's leading edge (\(statusLeading)) is not right of the \
                name's trailing edge (\(nameTrailing))
                """)
            // The room between the two is the bar's own: the badge is at the end, not beside the name.
            XCTAssertGreaterThan(statusLeading - nameTrailing, 100, """
                \(module.name): only \(statusLeading - nameTrailing) pt between the name and the \
                status in a 1060 pt bar — the badge is beside the name, not at the far end
                """)
            let content = fx.mount.window?.contentView?.frame.width ?? 0
            XCTAssertEqual(content, 1060, accuracy: 0.5, "\(module.name): the window is not 1060 pt wide")
            XCTAssertEqual(content - statusTrailing, ShellBarLayout.statusTrailing, accuracy: 0.5, """
                \(module.name): the status's box ends \(content - statusTrailing) pt from the window's \
                trailing edge, the layout gives it \(ShellBarLayout.statusTrailing)
                """)
        }
    }

    // MARK: - Absent where there is no status

    /// **General has no notion of running**, so `ShellPageBar.identity(for:host:)` answers a nil status
    /// there (General never reaches the module arm that asks for one) and the bar holds no status zone —
    /// it is not an empty one, which would still take its trailing padding. The absence is read in a mount whose name zone is there, so a
    /// bar that was never built or never laid out cannot pass it.
    func testTheBarCarriesNoStatusZoneWhereThereIsNoNotionOfRunning() {
        enableTheThreeStatusModules()
        let fx = mount(.general, width: 1060)
        let view = fx.bar.view
        XCTAssertTrue(view.reachableZones.contains(.name), "General: the name zone is not there — the bar is empty")
        XCTAssertGreaterThan(view.view(for: .name)?.frame.width ?? 0, 0, "General: the name has no room")
        XCTAssertNil(view.view(for: .status), "General: the bar holds a status zone where there is nothing to say")
    }

    // MARK: - Guard: the one combination that would silently lose the badge

    /// **The guard for the one combination the bar cannot show.** `ShellPageBar.Snapshot` gives a page a
    /// status word only when it declares no tabs, no actions and no search, so a page that also declares
    /// `.helmWindowToolbar` content has no trailing status zone at all. No module does both today
    /// (`ModuleDescriptor.activity`'s default is nil, in the extension of `ModuleDescriptor.swift`,
    /// and only `KeepAwakeDescriptor`, `VPNDescriptor` and `LayoutDescriptor`
    /// override it; the modules that call `.helmWindowToolbar` are what
    /// `command grep -rl '\.helmWindowToolbar(' Sources/Modules` lists), so this
    /// reads the source rather than mounting a combination the app cannot produce.
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
            the bar gives no status zone to a page with tabs, actions or search, so the status \
            badge would silently vanish on that page
            """)
    }
}
