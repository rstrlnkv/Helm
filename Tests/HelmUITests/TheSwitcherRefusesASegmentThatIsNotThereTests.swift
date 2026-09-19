import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **A selected index naming no segment is refused, and one naming a segment is
/// still applied.**
///
/// # The defect
///
/// `HelmToolbarSwitcher.width(of:in:symbol:)` builds a control, fills it and
/// reads its fitting size; it passes the literal `0` as the selected segment
/// whatever it was handed. Given an empty list of labels it therefore reached
/// `setSelected(true, forSegment: 0)` on a control with no segments, and AppKit
/// traps on that rather than refusing. Closed by the commit
/// "fix(HelmUI): refuse an out-of-range selected segment in fill", which bounds
/// `selected` against `segments.indices` inside `fill`, where both callers pass
/// through. Named by its subject and not by a hash: the hash this file first
/// carried stopped being an ancestor of the branch when the chain was rebased.
///
/// # What AppKit actually does, measured
///
/// Probed 2026-09-19 in a standalone binary — outside XCTest, which installs an
/// Objective-C exception handler of its own around every case — with
/// `NSSegmentedControl.setSelected(true, forSegment:)`, and re-run against the
/// same binary after the chain was rebased — all four rows reproduced, the
/// three exception messages byte for byte:
///
/// | segments | index | outcome |
/// | --- | --- | --- |
/// | 3 | 2 | returns, `selectedSegment == 2` |
/// | 0 | 0 | `NSRangeException`, «index (0) beyond bounds (-1)», SIGABRT, exit 134 |
/// | 3 | 3 | `NSRangeException`, «index (3) beyond bounds (2)», SIGABRT, exit 134 |
/// | 3 | -1 | `NSRangeException`, «index (-1) beyond bounds (2)», SIGABRT, exit 134 |
///
/// All three out-of-range directions are the same trap in
/// `-[NSSegmentedCell _setSelected:forSegment:]`, and the empty list is the
/// past-the-end case with the bound at `-1`. There is no Swift frame between
/// `fill` and that raise, so in the app it is `abort()` and not a catchable
/// error — which is why the bound has to be ahead of the call and cannot be a
/// `do`/`catch` around it. Inside this file the same raise is caught by XCTest
/// and reported as a failed case; that is a property of the harness and not of
/// the code under test.
///
/// # Which directions a test can reach, and how the rest are covered
///
/// `fill` is `private`, so no test calls it directly, and both of its callers
/// constrain their own index: `updateNSView` passes
/// `segments.firstIndex { … }`, which is in range or nil, and `width` passes
/// `0`. **The only out-of-range index reachable through the public API is `0`
/// against an empty list** — which is why engineer's own repro exercised that
/// and nothing else.
///
/// So the directions are covered in three ways, and each says which it is:
///
/// 1. the reachable one, behaviourally, through `width(of:in:)` — the case that
///    aborted;
/// 2. the in-range side, behaviourally, off a live control SwiftUI filled — a
///    bound that refused *everything* would pass (1) and is caught here;
/// 3. the two directions no caller can reach — a negative index, and an index
///    past the end of a non-empty list — by reading the guard, because a bound
///    written as a range containment covers them by construction while an
///    emptiness special-case does not. That check is a source reading and says
///    so where it fails.
@MainActor
final class TheSwitcherRefusesASegmentThatIsNotThereTests: XCTestCase {

    private static let file = "Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift"

    // MARK: - 1. The reachable direction: an index past the end of an empty list

    /// Every style, because `fill` writes labels, images, tooltips and widths
    /// per segment before it selects, and only the selection traps — a style
    /// that happened to leave the list empty for another reason would still
    /// reach the same line.
    ///
    /// **What a total failure prints.** With the bound removed this does not
    /// fail, it raises `NSRangeException` out of
    /// `-[NSSegmentedCell _setSelected:forSegment:]`; inside XCTest that is
    /// reported as a failed case naming the exception, and in the app it is the
    /// process ending. Either way it cannot print what a pass prints, which is
    /// nothing.
    func testAnEmptySegmentListAnswersAWidthRatherThanRaising() {
        for style in ToolbarSwitcherStyle.allCases {
            let width = HelmToolbarSwitcher<Int>.width(of: [], in: style)
            XCTAssertTrue(width.isFinite, """
                the width of an empty switcher in \(style.rawValue) is \(width), which is not a \
                number a layout can use.
                """)
            XCTAssertGreaterThanOrEqual(width, 0, """
                the width of an empty switcher in \(style.rawValue) is \(width) pt.
                """)
        }
    }

    /// The answer is a measurement of the empty control and not a constant a
    /// repair returned early — without this, a `width` that answered `0` for
    /// everything would pass the case above and silently collapse every
    /// switcher on the page.
    func testAnEmptySwitcherIsNarrowerThanOneCarryingAWord() {
        for style in ToolbarSwitcherStyle.allCases {
            let empty = HelmToolbarSwitcher<Int>.width(of: [], in: style)
            let one = HelmToolbarSwitcher<Int>.width(of: ["Installed"], in: style)
            XCTAssertLessThan(empty, one, """
                an empty switcher measures \(empty) pt in \(style.rawValue) and one carrying a word \
                measures \(one) pt. The empty list is not being measured — width is answering a \
                constant, so the other cases here are reading that constant and not the control.
                """)
        }
    }

    // MARK: - 2. The in-range side: the bound must not refuse a real segment

    /// A bound proven from one side only is unproven from the other. Replacing
    /// the guard with `false` — refuse every index — passes everything above,
    /// because nothing above ever asks for a selection to be *applied*. This is
    /// what sees it: a live control that SwiftUI filled, read for the segment it
    /// actually carries.
    func testAnIndexNamingASegmentIsStillSelected() throws {
        for index in Mounted.words.indices {
            let host = NSHostingView(rootView: Mounted(index: index))
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
            host.layoutSubtreeIfNeeded()

            // Assert the subject happened before asserting anything about it:
            // an unfilled control reports -1 for the same reason a refused one
            // would.
            let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                        "the switcher put no NSSegmentedControl in the tree")
            XCTAssertEqual(control.segmentCount, Mounted.words.count, """
                the mounted control holds \(control.segmentCount) segments, not \
                \(Mounted.words.count): production never filled it, so the reading below is not a \
                reading of the selection.
                """)
            XCTAssertEqual(control.selectedSegment, index, """
                a switcher mounted on segment \(index) of \(Mounted.words.count) reports segment \
                \(control.selectedSegment) selected. The bound that refuses an index naming no \
                segment is refusing one that names a real segment, so the toolbar draws no \
                selection at all and the page it belongs to looks like it lost the user's tab.
                """)
        }
    }

    /// And a later fill still moves it — the first fill and every later one take
    /// different paths through `updateNSView`, so the bound sits on both and has
    /// to be proven on both.
    func testALaterFillStillMovesTheSelection() throws {
        let host = NSHostingView(rootView: Mounted(index: 0))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        XCTAssertEqual(control.selectedSegment, 0,
                       "the first fill did not select segment 0, so what follows is not a move")

        let last = Mounted.words.count - 1
        host.rootView = Mounted(index: last)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first, """
            the switcher was rebuilt rather than updated, so this is a second first fill and not \
            the later-fill path the animation group wraps.
            """)
        XCTAssertEqual(control.selectedSegment, last, """
            a switcher told to move to segment \(last) still reports segment \
            \(control.selectedSegment). A later fill is not applying an in-range selection, so \
            choosing a tab leaves the switcher showing the previous one.
            """)
    }

    // MARK: - 3. The directions no caller can reach

    /// The refusal is a *range* containment, and it is the only thing between
    /// `fill` and AppKit's trap.
    ///
    /// Two assertions, and they answer different questions. The first is about
    /// the family: `setSelected(forSegment:)` is the trapping call, and a second
    /// one anywhere in this file would be a second unguarded way to the same
    /// abort — the brother of the defect that was closed. The second is about
    /// the generality engineer chose: a bound written against `segments.indices`
    /// rejects a negative index and an index past the end of a *non-empty* list
    /// as well, neither of which any caller can currently produce and neither of
    /// which a test can therefore reach; an emptiness special-case —
    /// `!segments.isEmpty` — passes every behavioural case in this file and
    /// leaves both of those open for the next caller that passes an index of its
    /// own.
    ///
    /// This is a source reading, and it is one because `fill` is `private` and
    /// its two callers each constrain their index before it is passed. It says
    /// so where it fails.
    func testTheOnlySelectionCallIsBoundedAsARange() throws {
        let code = SwiftSource.code(try RepoSource.text(of: Self.file))
        let calls = Self.count(of: "setSelected(", in: code)
        XCTAssertEqual(calls, 1, """
            \(Self.file) calls setSelected( \(calls) time(s). AppKit traps on an index the control \
            does not have — measured: NSRangeException and SIGABRT for an empty control, for an \
            index past the end and for a negative one — so every such call has to sit behind the \
            one bound in fill. A second call site is a second way to abort the app.
            """)

        let fill = try XCTUnwrap(SwiftSource.body(of: "fill", in: code),
                                 "\(Self.file) no longer declares fill")
        XCTAssertEqual(Self.count(of: "setSelected(", in: fill), 1, """
            the file's one setSelected( is not inside fill's body, so the bound fill carries is not \
            what guards it.
            """)

        let range = fill.contains("segments.indices.contains(selected)")
        let bothEnds = fill.contains("selected >= 0") && fill.contains("selected < segments.count")
        XCTAssertTrue(range || bothEnds, """
            fill guards its setSelected( with neither segments.indices.contains(selected) nor an \
            explicit pair of bounds. The index has to be refused in *both* directions: AppKit \
            raises NSRangeException for a negative index and for one past the end exactly as it \
            does for an empty control, and an emptiness test passes every behavioural check in \
            this file while covering only the one direction a caller happens to reach today. \
            fill's body reads:
            \(fill)
            """)
    }

    // MARK: - The mounted switcher

    /// The switcher as a page mounts it, with its selection fixed by the caller.
    ///
    /// The index is a stored property rather than `@State`, so replacing the
    /// host's root view is a genuine later update against the same control.
    /// The binding is constant because nothing here presses a segment — the
    /// subject is what `fill` writes into the control, not what a press writes
    /// back.
    ///
    /// The words are never asserted, which is why they do not go through
    /// `AppLanguage`: nothing here reads a visible string.
    struct Mounted: View {
        static let words = ["Installed", "Updates", "Search"]
        let index: Int

        var body: some View {
            HelmToolbarSwitcher("Probe", selection: .constant(index),
                                segments: Self.words.enumerated().map { index, word in
                                    HelmSwitcherSegment(index, word, symbol: "circle")
                                })
                .environment(\.helmSwitcherStyle, .text)
        }
    }

    // MARK: - Reading the source

    private static func count(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var found = 0
        var cursor = text.startIndex
        while let range = text.range(of: needle, range: cursor..<text.endIndex) {
            found += 1
            cursor = range.upperBound
        }
        return found
    }
}
