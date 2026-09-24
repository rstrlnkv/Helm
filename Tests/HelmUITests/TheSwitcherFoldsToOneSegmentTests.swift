import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **Owner item (2): the tabs fold to one segment — the current tab — with a
/// menu naming the rest, rather than overflowing whole into AppKit's own
/// «»» menu.** `HelmToolbarSwitcher`'s `compact` flag is what
/// `SettingsToolbar`'s fold mechanism (M1/M2/M3, `setTabsFolded`) writes; this
/// file tests the flag's own effect on the control, in isolation from the
/// three mechanisms that decide *when* to set it.
///
/// **The same `NSSegmentedControl` instance throughout** is why the compact
/// form reuses this control rather than swapping in a different view — see
/// `compact`'s own doc on `HelmToolbarSwitcher`'s initialiser: a torn-down
/// and rebuilt view would re-pin its own toolbar metric and lose the item
/// AppKit had already inserted, which the plan measured this reuse avoids.
@MainActor
final class TheSwitcherFoldsToOneSegmentTests: XCTestCase {

    /// Fixed English strings, not localized ones — this file asserts on the
    /// segment's own label, and `AppLanguage.each` exists for a test that
    /// reads a *visible* string, which this one is not (`Mounted`'s own
    /// header in `TheSwitcherRefusesASegmentThatIsNotThereTests` states the
    /// same rule for the same reason).
    struct Mounted: View {
        static let words = ["Installed", "Updates", "Search"]
        let selected: Int
        let compact: Bool

        var body: some View {
            HelmToolbarSwitcher("Probe", selection: .constant(selected),
                                segments: Self.words.enumerated().map { index, word in
                                    HelmSwitcherSegment(index, word, symbol: "circle")
                                }, compact: compact)
                .environment(\.helmSwitcherStyle, .text)
        }
    }

    func testCompactDrawsOneSegmentAndFullDrawsAllWithNoIndicator() throws {
        let host = NSHostingView(rootView: Mounted(selected: 1, compact: false))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()

        // Assert the subject happened before asserting anything about it.
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        XCTAssertEqual(control.segmentCount, Mounted.words.count, """
            the full form drew \(control.segmentCount) segments, not \(Mounted.words.count)
            """)
        for index in 0..<control.segmentCount {
            XCTAssertFalse(control.showsMenuIndicator(forSegment: index), """
                segment \(index) shows a menu indicator while full — only the compact form's one \
                segment should carry one
                """)
        }
        let fullWidth = control.fittingSize.width

        // Fold.
        host.rootView = Mounted(selected: 1, compact: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first, """
            folding rebuilt the view rather than updating the same control — the identity this \
            mechanism depends on (`compact`'s own doc) was not kept
            """)
        XCTAssertEqual(control.segmentCount, 1,
                       "compact must draw exactly one segment, not \(control.segmentCount)")
        XCTAssertEqual(control.label(forSegment: 0), "Updates", """
            the compact segment reads «\(control.label(forSegment: 0))» — it must carry the \
            currently selected tab's own label, not the first one
            """)
        XCTAssertTrue(control.showsMenuIndicator(forSegment: 0),
                      "the one compact segment must show the menu indicator")
        // The intrinsic width changes in the same update the fold does —
        // guards `control.invalidateIntrinsicContentSize()`, without which
        // the width SwiftUI reads lags by one update in both directions.
        XCTAssertLessThan(control.fittingSize.width, fullWidth, """
            the compact control (\(control.fittingSize.width) pt) is not narrower than the full \
            one (\(fullWidth) pt) in the same update — the width did not follow the fold
            """)

        // Unfold — no indicator may survive it.
        host.rootView = Mounted(selected: 1, compact: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first,
                      "unfolding rebuilt the view rather than updating the same control")
        XCTAssertEqual(control.segmentCount, Mounted.words.count, """
            unfolding drew \(control.segmentCount) segments, not \(Mounted.words.count)
            """)
        for index in 0..<control.segmentCount {
            XCTAssertFalse(control.showsMenuIndicator(forSegment: index), """
                segment \(index) still shows a menu indicator after unfolding — no indicator may \
                survive a return to the full form
                """)
        }
    }

    /// Compact selects the tab it is drawing — `displaySelectedIndex`'s own
    /// rule — whichever tab that is, not only the middle one the test above
    /// exercises.
    func testCompactAlwaysSelectsTheOneSegmentItDraws() throws {
        for selected in Mounted.words.indices {
            let host = NSHostingView(rootView: Mounted(selected: selected, compact: true))
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
            host.layoutSubtreeIfNeeded()
            let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first)
            XCTAssertEqual(control.segmentCount, 1,
                           "compact drew \(control.segmentCount) segments for selection \(selected)")
            XCTAssertEqual(control.label(forSegment: 0), Mounted.words[selected], """
                compact on selection \(selected) drew «\(control.label(forSegment: 0))», not \
                «\(Mounted.words[selected])»
                """)
            XCTAssertEqual(control.selectedSegment, 0, """
                the one compact segment must itself read selected, so AppKit draws the emphasis a \
                real tab carries
                """)
        }
    }
}
