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
/// A now-removed `HelmToolbarSwitcher.width(of:in:symbol:)` built a control,
/// filled it and read its fitting size; it passed the literal `0` as the
/// selected segment whatever it was handed. Given an empty list of labels it
/// therefore reached `setSelected(true, forSegment: 0)` on a control with no
/// segments, and AppKit traps on that rather than refusing. Closed by the
/// commit "fix(HelmUI): refuse an out-of-range selected segment in fill",
/// which bounds `selected` against `segments.indices` inside `fill`, where
/// every caller passes through. Named by its subject and not by a hash: the
/// hash this file first carried stopped being an ancestor of the branch when
/// the chain was rebased.
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
/// `fill` is `private`, so no test calls it directly. Both of its callers,
/// `makeNSView` and `updateNSView`, pass `displaySelectedIndex` —
/// `segments.firstIndex { … }`, which is in range or nil, or `0` for a folded
/// control that shows one segment and `nil` for one that shows none — so
/// nothing left in the public API can reach `fill` with an out-of-range index
/// at all; the
/// direction that once reached it, through the now-removed `width(of:in:)`
/// passing the literal `0` against an empty list, is covered below only by
/// reading the guard.
///
/// So the directions are covered in two ways, and each says which it is:
///
/// 1. the in-range side, behaviourally, off a live control SwiftUI filled — a
///    bound that refused *everything* would silently break every switcher on
///    the page and is caught here;
/// 2. every out-of-range direction — an index past the end of an empty list,
///    a negative index, and an index past the end of a non-empty list — by
///    reading the guard, because a bound written as a range containment
///    covers all three by construction while an emptiness special-case does
///    not. That check is a source reading and says so where it fails.
@MainActor
final class TheSwitcherRefusesASegmentThatIsNotThereTests: XCTestCase {

    private static let file = "Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift"

    // MARK: - 1. The in-range side: the bound must not refuse a real segment

    /// A bound proven from one side only is unproven from the other. Section 2
    /// reads the bound's shape and never asks for a selection to be *applied*,
    /// so a guard that kept that shape and refused every index would pass it.
    /// This is what sees it: a live control that SwiftUI filled, read for the
    /// segment it actually carries.
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

    // MARK: - 2. The directions no caller can reach

    /// The refusal is a *range* containment, and it is the only thing between
    /// `fill` and AppKit's trap.
    ///
    /// Two assertions, and they answer different questions. The first is about
    /// the family: `setSelected(forSegment:)` is the trapping call, and a second
    /// one anywhere in this file would be a second unguarded way to the same
    /// abort — the brother of the defect that was closed. The second is about
    /// the generality engineer chose: a bound written against `segments.indices`
    /// rejects a negative index, an index past the end of an empty list and one
    /// past the end of a non-empty list alike, none of which either caller can
    /// currently produce and none of which a test can therefore
    /// reach behaviourally; an emptiness special-case — `!segments.isEmpty` —
    /// passes every behavioural case in this file and leaves the other two open
    /// for the next caller that passes an index of its own.
    ///
    /// This is a source reading, and it is one because `fill` is `private` and
    /// both its callers, `makeNSView` and `updateNSView`, pass the constrained
    /// `displaySelectedIndex`. It says so where it fails.
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
