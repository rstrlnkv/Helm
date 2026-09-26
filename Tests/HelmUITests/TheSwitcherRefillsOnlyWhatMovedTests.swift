import AppKit
import HelmTestSupport
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmUI

/// **`HelmToolbarSwitcher.updateNSView`'s cheap path rewrites the segments
/// when a drawn word, the selection, a name or a symbol moved — and on no
/// other update that reaches it.** The structural branch ahead of it
/// (`isInitial || countChanged || styleChanged || compactChanged`) refills on
/// every update it takes, and this file asks of it only that the updates
/// after it do not.
///
/// The cheap path in `updateNSView` decides whether to run `fill` again. Two
/// of its four reasons read the control's own drawn state (a word differs,
/// the selection moved); `Coordinator.lastNames` added a third: a segment's
/// *name* moved while a glyph style draws none. That reason has two ways to
/// go wrong, and this file holds both. `Coordinator.lastSymbols` added a
/// fourth, the same way — a segment's own glyph moved while nothing else
/// about it did — and is held to the point by
/// `AGlyphSwitcherRedrawsAChangedGlyphTests` instead.
///
/// - **Too often.** A `lastNames` that is never written, or written on one
///   path and not another, reads as "the names moved" on every update after
///   it, and every update then refills. A fill rewrites every segment's
///   image, width and tooltip and runs a layout pass, so a refill per update
///   is the per-update churn the gating exists to avoid — the first update
///   after `makeNSView` included (that branch's own comment names it) — and
///   it lands under whatever the control is doing at the time, a press or a
///   drag across the segments included. Counted here at the one place a fill
///   always passes through: `setToolTip(_:forSegment:)`, which `fill` calls
///   once per shown segment and nothing else in the target calls at all.
/// - **Not at all.** A folded switcher (`compact`) in a glyph style shows one
///   segment whose drawn word is always empty and whose selected index is
///   always 0, so neither older reason can see a tab picked from the fold's
///   own menu; only the name can. Before `lastNames` the folded glyph and its
///   tooltip stayed on the tab that had been left.
///
/// Fixed English words, not localized ones: nothing here is a visible string
/// the language decides (`TheSwitcherFoldsToOneSegmentTests.Mounted`'s own
/// header, same rule).
@MainActor
final class TheSwitcherRefillsOnlyWhatMovedTests: XCTestCase {

    struct Probe: View {
        static let symbols = ["circle", "square", "triangle"]
        let name: String
        let words: [String]
        let selected: Int
        let compact: Bool
        let style: ToolbarSwitcherStyle

        var body: some View {
            HelmToolbarSwitcher(name, selection: .constant(selected),
                                segments: words.enumerated().map { index, word in
                                    HelmSwitcherSegment(index, word, symbol: Self.symbols[index])
                                }, compact: compact)
                .environment(\.helmSwitcherStyle, style)
        }
    }

    static let english = ["Installed", "Updates", "Search"]
    static let renamed = ["Present", "Pending", "Lookup"]

    /// Tooltip writes per control, while installed.
    nonisolated(unsafe) static var writes: [ObjectIdentifier: Int] = [:]

    /// Counts every `setToolTip(_:forSegment:)` on any `NSSegmentedControl`
    /// until the test's teardown puts the original implementation back.
    private func countFills() throws {
        let selector = #selector(NSSegmentedControl.setToolTip(_:forSegment:))
        let method = try XCTUnwrap(class_getInstanceMethod(NSSegmentedControl.self, selector),
                                   "NSSegmentedControl has no setToolTip:forSegment: to count")
        let original = method_getImplementation(method)
        typealias Call = @convention(c) (NSSegmentedControl, Selector, NSString?, Int) -> Void
        let call = unsafeBitCast(original, to: Call.self)
        let counting: @convention(block) (NSSegmentedControl, NSString?, Int) -> Void = { control, tip, segment in
            TheSwitcherRefillsOnlyWhatMovedTests.writes[ObjectIdentifier(control), default: 0] += 1
            call(control, selector, tip, segment)
        }
        Self.writes = [:]
        method_setImplementation(method, imp_implementationWithBlock(counting))
        addTeardownBlock { method_setImplementation(method, original) }
    }

    private func fills(_ control: NSSegmentedControl, shown: Int) -> Double {
        Double(Self.writes[ObjectIdentifier(control)] ?? 0) / Double(shown)
    }

    private func mount(_ probe: Probe) throws -> (NSHostingView<Probe>, NSSegmentedControl) {
        let host = NSHostingView(rootView: probe)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 60)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        return (host, control)
    }

    /// Hands the hosting view a new root that differs only in the control's
    /// own accessibility name — the one input `updateNSView` writes on every
    /// pass without a fill — and proves the update ran by reading it back.
    private func touch(_ host: NSHostingView<Probe>, _ control: NSSegmentedControl, _ pass: Int,
                       _ context: String) {
        let old = host.rootView
        host.rootView = Probe(name: "Probe \(pass)", words: old.words, selected: old.selected,
                              compact: old.compact, style: old.style)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(control.accessibilityLabel(), "Probe \(pass)",
                       "\(context): precondition — update \(pass) never reached the control")
    }

    func testAnUpdateThatMovesNothingRewritesNoSegmentInAnyStyleOrForm() throws {
        try countFills()
        for style in ToolbarSwitcherStyle.allCases {
            for compact in [false, true] {
                let context = "\(style)\(compact ? ", folded" : "")"
                let shown = compact ? 1 : Self.english.count
                let (host, control) = try mount(Probe(name: "Probe", words: Self.english, selected: 1,
                                                      compact: compact, style: style))
                XCTAssertEqual(control.segmentCount, shown, "\(context): precondition — wrong segment count")
                XCTAssertEqual(fills(control, shown: shown), 1, """
                    \(context): mounting filled the segments \(fills(control, shown: shown)) time(s) — \
                    makeNSView fills once and the first update after it must not fill again
                    """)
                for pass in 1...3 { touch(host, control, pass, context) }
                XCTAssertEqual(fills(control, shown: shown), 1, """
                    \(context): three updates that moved nothing refilled the segments — \
                    \(fills(control, shown: shown)) fills in all, where one is the mount's own
                    """)
            }
        }
    }

    /// A rename is a fill, once; the updates after it are not.
    func testARenameRefillsOnceAndTheUpdatesAfterItDoNot() throws {
        try countFills()
        for style in ToolbarSwitcherStyle.allCases {
            let (host, control) = try mount(Probe(name: "Probe", words: Self.english, selected: 1,
                                                  compact: false, style: style))
            let shown = Self.english.count
            host.rootView = Probe(name: "Probe", words: Self.renamed, selected: 1, compact: false, style: style)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual((0..<shown).map { control.toolTip(forSegment: $0) }, Self.renamed.map(Optional.some),
                           "\(style): precondition — the rename never reached the tooltips")
            XCTAssertEqual(fills(control, shown: shown), 2, "\(style): the rename was not exactly one fill")
            for pass in 1...3 { touch(host, control, pass, "\(style), renamed") }
            XCTAssertEqual(fills(control, shown: shown), 2, """
                \(style): after a rename, every later update refilled the segments — \
                \(fills(control, shown: shown)) fills in all, where two are the mount and the rename
                """)
        }
    }

    /// A style change that arrives together with a rename takes the
    /// structural branch; the updates after it are not fills either.
    func testAStyleChangeCarryingARenameRefillsOnceAndTheUpdatesAfterItDoNot() throws {
        try countFills()
        let (host, control) = try mount(Probe(name: "Probe", words: Self.english, selected: 1,
                                              compact: false, style: .text))
        let shown = Self.english.count
        host.rootView = Probe(name: "Probe", words: Self.renamed, selected: 1, compact: false, style: .icons)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(control.label(forSegment: 0), "", "precondition — the style change never reached the control")
        XCTAssertEqual(control.toolTip(forSegment: 0), Self.renamed[0],
                       "precondition — the rename never reached the tooltips")
        let afterChange = fills(control, shown: shown)
        for pass in 1...3 { touch(host, control, pass, "icons, renamed") }
        XCTAssertEqual(fills(control, shown: shown), afterChange, """
            after a style change carrying a rename, a later update refilled the segments \
            (\(afterChange) -> \(fills(control, shown: shown)) fills)
            """)
    }

    /// A tab picked from a folded glyph switcher's own menu: the one segment
    /// shown has to become that tab — its glyph and the name the glyph carries.
    func testAFoldedGlyphSwitcherShowsTheTabPickedFromItsMenu() throws {
        for style in [ToolbarSwitcherStyle.icons, .iconsAndText, .text] {
            let (host, control) = try mount(Probe(name: "Probe", words: Self.english, selected: 0,
                                                  compact: true, style: style))
            XCTAssertEqual(control.toolTip(forSegment: 0), Self.english[0], "\(style): precondition — first tab")
            for picked in [2, 1] {
                host.rootView = Probe(name: "Probe", words: Self.english, selected: picked,
                                      compact: true, style: style)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(control.segmentCount, 1, "\(style): the fold drew \(control.segmentCount) segments")
                XCTAssertEqual(control.toolTip(forSegment: 0), Self.english[picked], """
                    \(style): the folded switcher still names «\(control.toolTip(forSegment: 0) ?? "")» \
                    after «\(Self.english[picked])» was picked from its menu
                    """)
                XCTAssertEqual(control.image(forSegment: 0)?.accessibilityDescription, style == .text
                                   ? nil : Self.english[picked], """
                    \(style): the folded switcher still draws the glyph of the tab that was left
                    """)
            }
        }
    }
}
