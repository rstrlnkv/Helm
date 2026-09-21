import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The two real pages that search, measured whole — leading item, switcher
/// or pop-up, buttons and all — rather than through a generic fixture.**
///
/// `TheSearchFieldRestsNarrowerAndWidensOnFocusTests` holds the mechanism —
/// `ToolbarSearchName.size(_:)` pins nothing, so AppKit's own leftover-room
/// layout decides the resting width — against a fixture built for that one
/// question. It cannot say whether collapse is actually *reachable* within
/// `SettingsWindow`'s own resizable range (860 pt at the floor,
/// `SettingsWindow.minSize`; 1060 pt at the default), because that is a fact
/// about how much a real page's toolbar holds ahead of the search item, and
/// only Homebrew and Uninstaller declare `helmSearchable` at all
/// (`command grep -rln helmSearchable Sources/Modules`). This file mounts
/// both, wired and primed the way `ModulePageRender` mounts every page for its
/// own ratchets, with a real toolbar bridge and `ToolbarSearchName` attached.
///
/// # This harness was wrong by ninety points, and here is why
///
/// This file used to mount the page directly as the window's whole content
/// view controller. `SettingsWindow` never does that: the real window is an
/// `NSSplitViewController` with a 214 pt sidebar (`SettingsSplitViewController`,
/// its own `sidebarDefault`) and the page sits in the *detail* item beside it.
/// The toolbar is the window's, drawn full width — but two things a page reads
/// about its own room are not: `HomebrewSettingsPage.paneWidth`, which decides
/// `switcherFits` and comes from `.onGeometryChange` on the page's own view,
/// and `HomebrewSplit`'s own threshold, both read the *detail pane's* width,
/// 214 pt narrower than the window. Mounting the page as the whole window's
/// content, as this file did, handed both of those readings 214 pt of room
/// neither page has in the app — which is why every threshold this file found
/// disagreed with a designer's reading of the rendered window (2026-09-21,
/// real app, AX frames plus pixels, key window verified every frame, each
/// reading taken twice and agreeing): Homebrew showed the *magnifier* at the
/// 1060 pt shipping default, threshold between 1112 (collapsed) and 1120 pt
/// (open, 162 pt field), and Uninstaller never collapsed at any width down to
/// the 860 pt floor (163.0 pt field there) — where this file's old sweep read
/// Homebrew open at 1024, a 198 pt field at 1060, and Uninstaller collapsing
/// at 884–888.
///
/// # Adding the sidebar back does not close the gap, and that is the finding
///
/// The obvious suspect was geometric: `SettingsWindow` never mounts a page as
/// the whole content view controller the way this file's old fixture did. The
/// real window is an `NSSplitViewController` with a 214 pt sidebar
/// (`SettingsSplitViewController`, its own `sidebarDefault`), and the page
/// sits in the *detail* item beside it — narrower than the window by that
/// much. `HomebrewSettingsPage.paneWidth`, which decides `switcherFits`, and
/// `HomebrewSplit`'s own threshold both read that narrower pane's width
/// through `.onGeometryChange`, so a fixture with no sidebar hands both of
/// those readings 214 pt of room neither page has in the app.
///
/// `mount(id:width:leadingItem:)` below now wraps the page in that shape —
/// a sidebar item pinned to 214 pt, a detail item bridging the page's toolbar
/// — rather than reproducing `ModuleHost`/`SettingsModel` and their real
/// `UserDefaults` reads, which this file has no business touching. **It moved
/// both pages' thresholds further from the rendered window, not closer**
/// (`bash Scripts/test.sh --filter
/// 'ASearchCollapsesOnlyWhereTheWindowIsSmallTests'`, this Mac, 2026-09-21):
/// with the sidebar and the module-name leading item both mounted, Homebrew's
/// field read collapsed (36 pt) at every width from 860 up through 1140 pt —
/// the rendered window opens by 1120 — and Uninstaller's field read collapsed
/// at 860 and 1000 pt and open only from 1060 pt up — the rendered window
/// never collapses down to 860. A missing sidebar cannot be the *whole*
/// mechanism: fixing it should have moved both pages' crossings toward the
/// photographed ones, and instead it moved both away, in the same direction,
/// regardless of which page's toolbar is lighter or heavier. What this file's
/// window shares with the one it replaced and the rendered window does not is
/// that it is built with `orderBack(nil)` and never made key — and Liquid
/// Glass's own adaptive collapse is a compositing decision; an offscreen,
/// non-key window is not shown anywhere in this tree to composite glass at
/// all. So **no structural fix to this harness is asserted to reach the
/// shipping crossing**, and nothing below claims one does.
///
/// # What this file can still prove off-screen, and what it cannot
///
/// `TheSearchFieldRestsNarrowerAndWidensOnFocusTests` already proves the part
/// that does not depend on glass compositing: a field forced directly to
/// 159 pt reads collapsed and one forced to 160 reads open, which is a
/// constraint on the view's own width and not a layout decision. What this
/// file can add on top of that, honestly, is a same-run, same-window
/// comparison — the module-name leading item measurably narrows the room left
/// for the search field, at a width and in a direction this harness itself
/// reproduces, regardless of whether its absolute crossing matches the
/// shipping one. What it cannot do any more is assert that a width read here
/// is the width a person's window collapses at; that is the designer's own
/// reading above, and confirming *these* two pages at *these* two widths
/// (1112/1120 for Homebrew, 860 for Uninstaller) needs the same kind of
/// reading taken again — a screen recording of the real, key, composited
/// window, the way `CLAUDE.md`'s own motion rules already require for
/// anything Liquid Glass draws.
@MainActor
final class ASearchCollapsesOnlyWhereTheWindowIsSmallTests: XCTestCase {

    @MainActor private final class Turn { var finished = false }

    private struct Mounted {
        let window: NSWindow
        let keepAlive: [AnyObject]
    }

    /// `SettingsSplitViewController.sidebarDefault` — not read off that type
    /// because it is `private`, and duplicated rather than made internal for
    /// one test file to reach, the way `SettingsWindow.defaultSize` already is
    /// public for the same reason a test needs it.
    private static let sidebarWidth: CGFloat = 214

    /// Wired, seeded and primed the way `ModulePageRender.page(for:)` mounts
    /// every module page for its own ratchets — the same fixtures, so a page
    /// that shows nothing without them (Homebrew's `installScreen` in place of
    /// its manager, Uninstaller's own empty list) is not what this file reads
    /// by accident. The one thing borrowed rather than reused wholesale is the
    /// window: `ModulePageRender` draws into a bare, off-screen
    /// `NSHostingView` with no toolbar bridge at all, because its ratchets are
    /// about the page's own content; this file needs the real
    /// `NSToolbar` the settings window builds, so it mounts its own resizable,
    /// `sceneBridgingOptions`-bridged window instead — with the page in the
    /// *detail* item of a split view carrying a 214 pt sidebar, the shape
    /// `SettingsSplitViewController.viewDidLoad` builds and this file used not
    /// to, which is the whole of why its numbers used to be wrong (see this
    /// file's own header). `ModuleHost` and `SettingsModel` stay out of it —
    /// they read real `UserDefaults` and build every enabled module's engine,
    /// which is not this file's business — so the sidebar item here is an
    /// empty view pinned to the same width and nothing else about it is real.
    private func mount(id: String, width: CGFloat, leadingItem: Bool) -> Mounted? {
        guard let descriptor = ModuleRegistry.descriptor(id) else { return nil }
        let store = NamespacedStore(namespace: id, backing: InMemoryKeyValueStore())
        ModulePageRender.pastFirstRun(id, store)
        let engine = descriptor.makeEngine(store: store)
        let transport = FixtureTransport(ModulePageRender.answering(id))
        let viewModel = ModuleViewModel(transport: transport)
        let base = descriptor.settingsPage(viewModel)
            .environment(\.helmGrants, ModulePageRender.granted)
        let rootView: AnyView
        if leadingItem {
            rootView = AnyView(
                base
                    .helmPageHeader(symbol: descriptor.moduleMetadata.sfSymbol,
                                    tint: descriptor.moduleTint.colour,
                                    title: descriptor.moduleMetadata.name,
                                    bleeds: descriptor.pageBleeds)
                    .environment(\.helmPageBar, PageBarStyle.moduleName))
        } else {
            rootView = AnyView(base.toolbar { ToolbarSpacer(.fixed, placement: .navigation) })
        }
        let detail = NSHostingController(rootView: rootView)
        detail.sceneBridgingOptions = [.toolbars]
        detail.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420

        let sidebar = NSViewController()
        sidebar.view = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: 700))
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: width, height: 700))
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        window.layoutIfNeeded()
        // The real window's own placement, done directly rather than through
        // `SettingsSplitViewController`'s deferred, first-run-only logic —
        // this window is never shown to a person, so there is no first launch
        // to distinguish from a hundredth.
        split.splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
        window.layoutIfNeeded()
        let name = ToolbarSearchName(namingIn: window)

        if let work = ModulePageRender.opened(id, viewModel) {
            let turn = Turn()
            Task { @MainActor in await work(); turn.finished = true }
            var turns = 0
            while !turn.finished, turns < 300 {
                turns += 1
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return Mounted(window: window, keepAlive: [engine, viewModel, name])
    }

    private func field(_ mounted: Mounted) -> NSSearchField? {
        (mounted.window.toolbar?.items ?? [])
            .compactMap { $0 as? NSSearchToolbarItem }.first?.searchField
    }

    private func drop(_ mounted: Mounted) { mounted.window.contentViewController = nil }

    // MARK: - The leading item measurably narrows the room left for the field
    //
    // Neither case below claims the width it reads is where the *shipping*
    // window collapses — this file's own header says why that claim cannot be
    // made off-screen any more. What each proves is a same-window,
    // same-everything-else comparison: mounting `PageBarStyle.moduleName`'s
    // plate measurably costs the search field room, in the direction the
    // mechanism predicts, at a width this harness itself reproduces
    // (`bash Scripts/test.sh --filter 'ASearchCollapsesOnlyWhereTheWindowIsSmallTests'`,
    // this Mac, 2026-09-21 — the widths quoted in each failure message are
    // that run's own readings).

    /// Homebrew, 1120 pt: open with an empty leading zone, collapsed with the
    /// module-name plate mounted — the same width, the same switcher, the
    /// same two buttons, the only difference being the plate.
    func testTheLeadingItemNarrowsHomebrewsRoomAt1120() throws {
        guard let noLeading = mount(id: "homebrew", width: 1120, leadingItem: false) else {
            XCTFail("no homebrew descriptor")
            return
        }
        defer { drop(noLeading) }
        let noLeadingField = try XCTUnwrap(field(noLeading), "1120 pt, no leading item: no search item")
        XCTAssertFalse(noLeadingField.isHidden, """
            Homebrew's search field is collapsed at 1120 pt even with an empty leading zone \
            (\(noLeadingField.frame.width) pt) — this harness's own crossing for the bare toolbar \
            has moved, and the comparison below may now be reading two states that agree
            """)

        guard let withLeading = mount(id: "homebrew", width: 1120, leadingItem: true) else { return }
        defer { drop(withLeading) }
        let withLeadingField = try XCTUnwrap(field(withLeading), "1120 pt, with leading item: no search item")
        XCTAssertTrue(withLeadingField.isHidden, """
            Homebrew's search field is still open at 1120 pt with the module-name plate mounted \
            (\(withLeadingField.frame.width) pt) — the plate stopped costing this page room, which \
            is worth knowing on its own: the rendered window's own threshold sits between 1112 and \
            1120 pt with the plate mounted (a designer's reading, 2026-09-21), so a plate that no \
            longer narrows the field's room here is a mechanism this file can no longer show working
            """)
    }

    /// Uninstaller, 1000 pt: the same comparison, at the width this page's
    /// own lighter toolbar reads it at.
    func testTheLeadingItemNarrowsUninstallersRoomAt1000() throws {
        guard let noLeading = mount(id: "uninstaller", width: 1000, leadingItem: false) else {
            XCTFail("no uninstaller descriptor")
            return
        }
        defer { drop(noLeading) }
        let noLeadingField = try XCTUnwrap(field(noLeading), "1000 pt, no leading item: no search item")
        XCTAssertFalse(noLeadingField.isHidden, """
            Uninstaller's search field is collapsed at 1000 pt even with an empty leading zone \
            (\(noLeadingField.frame.width) pt) — this harness's own crossing for the bare toolbar \
            has moved
            """)

        guard let withLeading = mount(id: "uninstaller", width: 1000, leadingItem: true) else { return }
        defer { drop(withLeading) }
        let withLeadingField = try XCTUnwrap(field(withLeading), "1000 pt, with leading item: no search item")
        XCTAssertTrue(withLeadingField.isHidden, """
            Uninstaller's search field is still open at 1000 pt with the module-name plate mounted \
            (\(withLeadingField.frame.width) pt) — the plate stopped costing this page room, which \
            this file exists to catch even though it cannot say where the shipping window's own \
            crossing sits (a designer's reading says it never collapses down to the 860 pt floor)
            """)
    }

    // MARK: - The leading item is load-bearing for Uninstaller specifically

    /// **Without the leading item, Uninstaller's field reads open at the
    /// window's own floor; with it, this harness reads it collapsed.** The
    /// direct reading behind `PageBarStyle`'s own claim that the shipping
    /// shape is not merely a preference — but read what this case can and
    /// cannot say against the header above: a designer's reading of the
    /// rendered window found Uninstaller's field open (163.0 pt) at 860 pt
    /// *with* the plate mounted, where this harness reads it collapsed. Both
    /// facts can be true at once — the plate narrows this page's room either
    /// way, which is what this case is for, and how far it narrows it is not
    /// something an offscreen, non-key window is shown to answer.
    func testTheCollapseIsReachableOnlyWithTheLeadingItem() throws {
        guard let noLeading = mount(id: "uninstaller", width: 860, leadingItem: false) else {
            XCTFail("no uninstaller descriptor")
            return
        }
        defer { drop(noLeading) }
        let noLeadingField = try XCTUnwrap(field(noLeading), "860 pt, no leading item: no search item")
        XCTAssertFalse(noLeadingField.isHidden, """
            Uninstaller's search field collapsed at the window's own floor (860 pt) even with an \
            empty leading zone (\(noLeadingField.frame.width) pt) — the coupling this file records \
            no longer holds, which is worth knowing but is not itself a defect
            """)

        guard let withLeading = mount(id: "uninstaller", width: 860, leadingItem: true) else { return }
        defer { drop(withLeading) }
        let withLeadingField = try XCTUnwrap(field(withLeading), "860 pt, with leading item: no search item")
        XCTAssertTrue(withLeadingField.isHidden, """
            Uninstaller's search field is still open at 860 pt even with the module-name header \
            mounted (\(withLeadingField.frame.width) pt) — the collapse this file's other two \
            cases rely on being reachable at all has stopped happening
            """)
    }
}
