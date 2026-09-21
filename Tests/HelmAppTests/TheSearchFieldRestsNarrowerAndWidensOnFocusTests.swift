import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The owner's third order on this control (2026-09-21): a field again,
/// collapsing only where the window is small.**
///
/// The field used to carry no width of its own at all — AppKit gave it
/// whatever the toolbar had left over, which is why the same control drew at
/// 266 pt in the Uninstaller and 169 in Homebrew at the shipping default
/// width. The pass that followed pinned it to `max(160, naturalWidth(prompt))`
/// with a `.defaultHigh` constraint, which the designer's own screen sweep
/// (1100→860 pt, 4 pt steps, two passes agreeing) found held the field open at
/// 162.0 pt on every one of 61 steps and never once collapsed. The next pass
/// pinned it under the floor instead (`restingWidth = 40`), which collapsed it
/// everywhere rather than nowhere — the same defect from the other side. Both
/// pinned a *constant*, and measured against real pages (`ToolbarSearchName`'s
/// own doc) a pinned constant, at any priority AppKit will actually hold,
/// either always fits or never does: this toolbar sends an item it cannot
/// shrink into overflow rather than compress it.
///
/// **So `ToolbarSearchName.size(_:)` pins nothing at rest any more.** It
/// clears any stray width constraint and leaves the field to AppKit's own
/// leftover-room layout, which is what makes the resting width track the
/// window rather than sit at one number — and, given enough real content ahead
/// of it in the toolbar, is what makes the 160 pt floor below reachable at a
/// realistic width at all. This file's fixture stands a fixed-width filler
/// item in the toolbar's leading zone to reach scarcity without depending on
/// any one module's page (`ASearchFieldSaysWhatItIsTests`'s reason for
/// mounting "Search apps" rather than importing `UnStr`) — the collapse
/// thresholds of the real pages are measured and guarded separately
/// (`ASearchCollapsesOnlyWhereTheWindowIsSmallTests`).
///
/// **The Mount below is `ASearchFieldSaysWhatItIsTests`'s, with a filler
/// added** — same bridge, same two channels, same reason a fresh
/// `NSSearchField` object shows up on the next page change.
@MainActor
final class TheSearchFieldRestsNarrowerAndWidensOnFocusTests: XCTestCase {

    private final class Page: ObservableObject {
        @Published var text = ""
        let prompt: String
        init(prompt: String) { self.prompt = prompt }
    }

    /// A fixed-width view, standing in for whatever real content — a leading
    /// module-name item, a switcher, a button group — sits ahead of the search
    /// item in a real page's toolbar and leaves it less room than an empty
    /// toolbar would. `intrinsicContentSize` rather than a SwiftUI `.frame`,
    /// because AppKit's toolbar layout reads the represented `NSView`'s own
    /// size and a SwiftUI frame is not one.
    private final class Filler: NSView {
        let fixedWidth: CGFloat
        init(width: CGFloat) { fixedWidth = width; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("not supported") }
        override var intrinsicContentSize: NSSize { NSSize(width: fixedWidth, height: 24) }
    }

    private struct FillerView: NSViewRepresentable {
        let width: CGFloat
        func makeNSView(context: Context) -> Filler { Filler(width: width) }
        func updateNSView(_ nsView: Filler, context: Context) {}
    }

    private struct Pane: View {
        @ObservedObject var page: Page
        /// 0 draws the plain `ToolbarSpacer` every settings pane carries when
        /// it has nothing of its own for the leading zone; a positive value
        /// draws `FillerView` there instead.
        let filler: CGFloat
        var body: some View {
            VStack(spacing: 0) {
                Color.clear.frame(height: 0)
                    .helmSearchable(text: Binding(get: { page.text }, set: { page.text = $0 }),
                                    prompt: page.prompt)
                Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                if filler > 0 {
                    ToolbarItem(placement: .navigation) { FillerView(width: filler) }
                } else {
                    ToolbarSpacer(.fixed, placement: .navigation)
                }
            }
        }
    }

    @MainActor
    private final class Mount {
        let window: NSWindow
        let page: Page
        let name: ToolbarSearchName
        private let controller: NSHostingController<Pane>

        init(prompt: String, width: CGFloat, filler: CGFloat = 0) {
            page = Page(prompt: prompt)
            controller = NSHostingController(rootView: Pane(page: page, filler: filler))
            controller.sceneBridgingOptions = [.toolbars]
            controller.sizingOptions = []
            window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: width, height: 700))
            window.appearance = NSAppearance(named: .aqua)
            name = ToolbarSearchName(namingIn: window)
        }

        func settle(_ turns: Int = 20) {
            for _ in 0..<turns {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }

        var field: NSSearchField? {
            (window.toolbar?.items ?? []).compactMap { $0 as? NSSearchToolbarItem }.first?.searchField
        }
        var collapsed: Bool { field?.isHidden ?? false }
        func drop() { window.contentViewController = nil }
    }

    private var mounts: [Mount] = []

    override func tearDown() {
        mounts.forEach { $0.drop() }
        mounts = []
        super.tearDown()
    }

    private func mounted(prompt: String, width: CGFloat = 900, filler: CGFloat = 0) -> Mount {
        let mount = Mount(prompt: prompt, width: width, filler: filler)
        mounts.append(mount)
        mount.settle()
        return mount
    }

    /// What AppKit itself gives a bare, unmounted `NSSearchField` sized for
    /// typed content — never mounted, never drawn, the same reading
    /// `ToolbarSearchName.naturalWidth(typed:)` takes. The mounted control's
    /// focused width is checked against this rather than against a written
    /// number so the check is of the arithmetic and not of a copy of its
    /// answer.
    private func naturalWidth(typed: String) -> CGFloat {
        let probe = NSSearchField()
        probe.stringValue = typed
        probe.sizeToFit()
        return probe.frame.width
    }

    // MARK: - AppKit's own floor

    /// **Below 160 pt `NSSearchToolbarItem` draws its magnifier whatever room
    /// the toolbar has** — measured by forcing the field's width directly in a
    /// 900 pt window, far more room than the control could ever need: 159 pt
    /// drew collapsed and 160 pt drew open. This is not a claim about this
    /// app's toolbars, it is a claim about the control, and it is untouched by
    /// what `size(_:)` does or does not pin — the floor is AppKit's.
    func testAFieldForcedBelowOneSixtyDrawsCollapsedWhatever900PtOfRoomIsThere() throws {
        let mount = mounted(prompt: "Search apps", width: 900)
        guard let item = mount.window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first
        else {
            XCTFail("no search item in the toolbar to force a width on")
            return
        }
        item.searchField.constraints
            .filter { $0.firstItem === item.searchField && $0.firstAttribute == .width }
            .forEach { $0.isActive = false }
        item.searchField.widthAnchor.constraint(equalToConstant: 159).isActive = true
        mount.settle(15)
        XCTAssertTrue(item.searchField.isHidden, """
            a field pinned to 159 pt in a 900 pt window is not collapsed — the floor this file \
            measured has moved
            """)

        item.searchField.constraints
            .filter { $0.firstItem === item.searchField && $0.firstAttribute == .width }
            .forEach { $0.isActive = false }
        item.searchField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        mount.settle(15)
        XCTAssertFalse(item.searchField.isHidden, """
            a field pinned to 160 pt in a 900 pt window is collapsed — the floor moved upward
            """)
    }

    // MARK: - Resting state: AppKit's own leftover room, not a pinned constant

    /// **`size(_:)` leaves no width constraint of its own on the field.** This
    /// is the direct, mechanism-level check for the owner's third order: not
    /// "does it collapse here" — which depends on how much else is in the
    /// toolbar, and is measured against the real pages elsewhere — but "does
    /// anything here still pin a number", which is exactly what the first two
    /// orders did, in opposite directions, and both broke reachable collapse.
    func testTheRestingFieldCarriesNoWidthConstraintOfItsOwn() throws {
        for width: CGFloat in [900, 600, 300] {
            let mount = mounted(prompt: "Search apps", width: width)
            let field = try XCTUnwrap(mount.field, "\(width) pt: no search field to read")
            let ownWidthConstraints = field.constraints
                .filter { $0.firstItem === field && $0.firstAttribute == .width }
            XCTAssertTrue(ownWidthConstraints.isEmpty, """
                the field at \(width) pt carries \(ownWidthConstraints.count) width \
                constraint(s) of its own — `size(_:)` is pinning a resting width again, which \
                is what made collapse unreachable the first time it was tried
                """)
        }
    }

    /// **The resting width tracks the window rather than sitting at one
    /// number.** Not a claim about *where* it collapses — that depends on how
    /// crowded the rest of the toolbar is, which this generic fixture does not
    /// reproduce — only that it is not pinned: two widths with plenty of
    /// leftover room give two different field widths.
    func testTheRestingWidthMovesWithTheWindowWhenThereIsRoomToGive() throws {
        let wide = mounted(prompt: "Search apps", width: 900)
        let narrower = mounted(prompt: "Search apps", width: 700, filler: 150)
        XCTAssertFalse(wide.collapsed, "precondition: 900 pt with no filler is not open")
        XCTAssertFalse(narrower.collapsed, "precondition: 700 pt behind a 150 pt filler is not open")
        XCTAssertNotEqual(wide.field?.frame.width, narrower.field?.frame.width, """
            \(wide.field?.frame.width ?? -1) pt at 900 pt and \
            \(narrower.field?.frame.width ?? -1) pt at 700 pt behind a filler read the same — \
            the resting width is not moving with the room the toolbar has, which is what a \
            reintroduced constant would look like
            """)
    }

    /// **And the prompt does not decide the resting width** — the direct check
    /// that a longer prompt does not widen it, which was true under the old
    /// pinned design for the wrong reason (everything pinned to the same
    /// constant) and stays true under this one for the right reason: nothing
    /// here reads the prompt to size anything at all.
    func testARestingFieldForALongPromptIsNoWiderThanOneForAShortPrompt() throws {
        let short = mounted(prompt: "Search apps")
        let long = mounted(prompt: "Rechercher des paquets")
        XCTAssertEqual(short.field?.frame.width, long.field?.frame.width, """
            "Search apps" rests at \(short.field?.frame.width ?? -1) pt and "Rechercher des \
            paquets" at \(long.field?.frame.width ?? -1) pt in the same window — the prompt is \
            deciding the resting width, which only the placeholder should ever have read
            """)
    }

    /// **Scarce room still collapses it — the half of the mechanism this
    /// generic fixture can show without a real page.** 250 pt of filler ahead
    /// of the field in a 700 pt window is the calibration this file measured
    /// (`testCalibrateGenericFixture`, no longer in the tree) to cross AppKit's
    /// 160 pt floor; `ASearchCollapsesOnlyWhereTheWindowIsSmallTests` is where
    /// the real pages' own thresholds are guarded.
    func testScarceRoomCollapsesTheField() throws {
        let mount = mounted(prompt: "Search apps", width: 700, filler: 250)
        XCTAssertTrue(mount.collapsed, """
            a field behind a 250 pt filler in a 700 pt window rests open at \
            \(mount.field?.frame.width ?? -1) pt — this fixture's own calibration expected it \
            collapsed, which would mean AppKit's floor or this toolbar's layout has moved
            """)
    }

    // MARK: - Focus widens it

    func testClickingTheFieldWidensItPastTheResting() throws {
        // 150 pt of filler in a 600 pt window rests the field open but
        // narrower than the focused target (measured 174 pt against a
        // focused width well above it) — the scenario a click on a narrow
        // resting field is actually for. A wide-open fixture with nothing
        // else in the toolbar already rests wider than the focused target
        // and has nothing left for a click to widen into, which is what
        // made this case fail when it mounted with no filler at all.
        let mount = mounted(prompt: "Search apps", width: 600, filler: 150)
        let field = try XCTUnwrap(mount.field)
        let resting = field.frame.width
        guard let item = mount.window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first
        else {
            XCTFail("no search item in the toolbar")
            return
        }
        item.beginSearchInteraction()
        mount.settle(20)
        XCTAssertGreaterThan(field.frame.width, resting, """
            focusing the field left it at \(field.frame.width) pt, the same as its resting width \
            (\(resting) pt) — a click is supposed to widen it so a typed query can be read, and \
            nothing did
            """)
    }

    func testTheFocusedWidthShowsARealisticTypedQuery() throws {
        let mount = mounted(prompt: "Search apps")
        let field = try XCTUnwrap(mount.field)
        guard let item = mount.window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first
        else {
            XCTFail("no search item in the toolbar")
            return
        }
        item.beginSearchInteraction()
        mount.settle(20)
        // "Microsoft Remote Desktop": a real 24-character application name,
        // standing in for a query somebody actually types rather than for the
        // prompt it replaces. `naturalWidth(typed:)` and not `(placeholder:)`:
        // measured, a value carries a cancel button a placeholder never draws
        // — "Search apps" sizes to 108 pt as a placeholder against 132 pt typed
        // in, a 24 pt difference that is exactly that button.
        let query = "Microsoft Remote Desktop"
        let needed = naturalWidth(typed: query)
        XCTAssertGreaterThanOrEqual(field.frame.width, needed, """
            the field focused to \(field.frame.width) pt, short of the \(needed) pt a bare \
            `NSSearchField` needs to show «\(query)» typed in with its cancel button — a person \
            typing a query that long would not be able to read what they had typed
            """)
    }
}
