import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`.searchable(placement: .toolbar)` inserts a flexible space of its own
/// ahead of the search item, on top of anything a page declares.**
///
/// Measured against this bridge (2026-09-21): a `ToolbarSpacer(.fixed)` added
/// at the end of `HomebrewSettingsPage.pageToolbar` does not replace that
/// space, it sits beside it — the flexible item is not the page's to remove
/// through `ToolbarContent` at all, because `.searchable` is a view modifier
/// and never appears inside that `@ToolbarContentBuilder`. A flexible item
/// claims whatever the bar has left over once every other item has taken its
/// own width, so the room between Refresh and the search field grew and
/// shrank with the window rather than holding still, the way it would beside
/// an ordinary neighbour in the same `ToolbarItemGroup` — Finder's own
/// trailing items keep a small, fixed gap from each other, and this one held
/// none.
///
/// `ToolbarSearchName.closeGapBeforeSearch(in:)` swaps that flexible item for
/// AppKit's own standard fixed-width one (`.space`) each time it names or
/// sizes the bridged field — the same after-the-fact correction `size(_:)`
/// already makes on the field's width constraint, since there is no
/// `ToolbarContent` spelling that reaches this specific item either.
///
/// **What this harness needs beyond `ASearchCollapsesOnlyWhereTheWindowIsSmallTests`'s
/// own fixture.** `ToolbarSearchName.init`'s own one-shot hop can lose the
/// race against SwiftUI's own settling of a freshly built bar — measured
/// here, calling only that hop left the flexible item in place across every
/// width tried. The shipping window never relies on that hop alone:
/// `SettingsWindow.applyTitle` and `SettingsWindow.show` each dispatch their
/// own further call to `settleDisplayMode` -> `nameWhatIsThere()`, a second
/// hop this file's `mount(id:width:)` reproduces rather than reaching into
/// `ToolbarSearchName` for a test-only entry point `closeGapBeforeSearch`
/// does not need and should not gain.
@MainActor
final class TheGapBeforeSearchIsFixedNotFlexibleTests: XCTestCase {

    @MainActor private final class Turn { var finished = false }

    private struct Mounted {
        let window: NSWindow
        let keepAlive: [AnyObject]
    }

    /// `SettingsSplitViewController.sidebarDefault` — duplicated for the same
    /// reason `ASearchCollapsesOnlyWhereTheWindowIsSmallTests` duplicates it.
    private static let sidebarWidth: CGFloat = 214

    private func mount(id: String, width: CGFloat) -> Mounted? {
        guard let descriptor = ModuleRegistry.descriptor(id) else { return nil }
        let store = NamespacedStore(namespace: id, backing: InMemoryKeyValueStore())
        ModulePageRender.pastFirstRun(id, store)
        let engine = descriptor.makeEngine(store: store)
        let transport = FixtureTransport(ModulePageRender.answering(id))
        let viewModel = ModuleViewModel(transport: transport)
        let base = descriptor.settingsPage(viewModel)
            .environment(\.helmGrants, ModulePageRender.granted)
        let rootView = AnyView(
            base
                .helmPageHeader(symbol: descriptor.moduleMetadata.sfSymbol,
                                tint: descriptor.moduleTint.colour,
                                title: descriptor.moduleMetadata.name,
                                bleeds: descriptor.pageBleeds)
                .environment(\.helmPageBar, PageBarStyle.moduleName))
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
        // `SettingsWindow.applyTitle` and `.show` each take a second hop to
        // `settleDisplayMode` -> `nameWhatIsThere()`, separate from the one
        // `ToolbarSearchName.init` already schedules — see this file's own
        // header for why the first hop alone is not what the shipping window
        // relies on.
        DispatchQueue.main.async { name.nameWhatIsThere() }
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return Mounted(window: window, keepAlive: [engine, viewModel, name])
    }

    private func drop(_ mounted: Mounted) { mounted.window.contentViewController = nil }

    /// The gap between the last `.primaryAction` item and the search item —
    /// the field's own `minX` where it is open, the collapsed magnifier's
    /// `minX` where it is not, since both are the same `NSSearchToolbarItem`'s
    /// view. nil where either edge cannot be read.
    private func gapBeforeSearch(_ mounted: Mounted) -> (gap: CGFloat, precededByFlexibleSpace: Bool)? {
        guard let toolbar = mounted.window.toolbar else { return nil }
        let items = toolbar.items
        guard let searchIndex = items.firstIndex(where: { $0 is NSSearchToolbarItem }),
              searchIndex > 0 else { return nil }
        let search = items[searchIndex]
        guard let searchView = search.view ?? (search as? NSSearchToolbarItem)?.searchField else { return nil }
        let searchMinX = searchView.convert(searchView.bounds, to: nil).minX
        // Walk backwards over any zero-width (overflowed) items to the last
        // one that actually drew something — skipping past the fixed/flexible
        // space items themselves, which carry no `.view` at all, and past any
        // overflowed item, whose view is present but zero-width.
        var priorIndex = searchIndex - 1
        while priorIndex >= 0 {
            if let view = items[priorIndex].view, view.convert(view.bounds, to: nil).width > 0 { break }
            priorIndex -= 1
        }
        guard priorIndex >= 0, let priorView = items[priorIndex].view else { return nil }
        let priorMaxX = priorView.convert(priorView.bounds, to: nil).maxX
        let flexible = items[searchIndex - 1].itemIdentifier == .flexibleSpace
        return (searchMinX - priorMaxX, flexible)
    }

    /// **The item immediately ahead of search is never the flexible one AppKit
    /// bridged in, at any width tried.** Not asserting a bound on the gap's own
    /// size here — `.space`'s width is AppKit's own standard and not this
    /// file's to pin — only that it is the fixed identifier and not the
    /// flexible one, which is the whole of the defect: a flexible item is what
    /// grows and shrinks with the window, and a fixed one cannot.
    func testTheItemAheadOfSearchIsNeverFlexible() throws {
        for width: CGFloat in [1100, 1300, 1500] {
            guard let mounted = mount(id: "homebrew", width: width) else {
                XCTFail("no homebrew descriptor")
                return
            }
            defer { drop(mounted) }
            let result = try XCTUnwrap(gapBeforeSearch(mounted), "\(width) pt: could not read the gap")
            XCTAssertFalse(result.precededByFlexibleSpace, """
                At \(width) pt the item immediately ahead of the search item is still \
                `.flexibleSpace` — the gap between Refresh and search grows and shrinks with the \
                window instead of holding the small, fixed gap Finder's own trailing items keep
                """)
        }
    }

    /// **The gap holds the same width across widths where it used to grow.**
    /// 1100, 1300 and 1500 pt bracket the field's own open/collapsed states
    /// (`ASearchCollapsesOnlyWhereTheWindowIsSmallTests`'s own numbers), which
    /// is exactly where a flexible item's width would have tracked the
    /// window — this reads a fixed item instead, so the reading should not
    /// move by more than a point of layout noise between them.
    func testTheGapDoesNotGrowWithTheWindow() throws {
        var gaps: [CGFloat: CGFloat] = [:]
        for width: CGFloat in [1100, 1300, 1500] {
            guard let mounted = mount(id: "homebrew", width: width) else {
                XCTFail("no homebrew descriptor")
                return
            }
            defer { drop(mounted) }
            let result = try XCTUnwrap(gapBeforeSearch(mounted), "\(width) pt: could not read the gap")
            gaps[width] = result.gap
        }
        let values = Array(gaps.values)
        guard let first = values.first else {
            XCTFail("no gaps read")
            return
        }
        for (width, gap) in gaps {
            XCTAssertEqual(gap, first, accuracy: 1, """
                Gap at \(width) pt read \(gap) pt against \(first) pt at another width — \
                \(gaps) — a gap that still varies by width is a flexible item under another name
                """)
        }
    }
}
