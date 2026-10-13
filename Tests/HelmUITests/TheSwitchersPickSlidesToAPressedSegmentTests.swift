import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The selected segment's pill slides to a pressed segment, under both bar looks, for a press and for
/// nothing else.** A press on another segment asks the cell for one slide of the token's length, from the
/// segment that was shown to the one pressed; Reduce Motion, the first draw, a selection the page wrote, a
/// press on the segment already selected, a disabled control and an index the strip lacks ask for none, and a
/// refill ends a slide in flight.
///
/// Motion is not proven by a clock here: every row reads what the cell was ASKED through `onSlide`, and every
/// row but the order one what it holds in `sliding`, at once, and none waits, sleeps or spins a run loop. That the pill looks right on a
/// screen is not asserted; the hosting view is in no window. Every row that expects nothing asked also sees a
/// press on the same cell begin a slide, before or after the silence (through `onSlide`; through `sliding`
/// in the shrink row), so a seam nobody calls cannot pass it.
@MainActor
final class TheSwitchersPickSlidesToAPressedSegmentTests: XCTestCase {

    typealias Slide = HelmFlatSegmentedCell.Slide

    private static let looks: [(String, HelmBarAppearance)] = [("flat", .flat), ("liquidGlass", .liquidGlass)]
    private static let words = ["Installed", "Updates", "Search"]

    /// The page's side of the binding: what the switcher reads and what a press writes.
    private final class Box {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    private struct Probe: View {
        let box: Box
        let appearance: HelmBarAppearance
        var words = TheSwitchersPickSlidesToAPressedSegmentTests.words
        /// Changed to make SwiftUI evaluate the representable again with everything else equal.
        var revision = 0

        var body: some View {
            let segments = words.enumerated().map { HelmSwitcherSegment($0.offset, $0.element, symbol: "circle") }
            HelmToolbarSwitcher("Probe", selection: Binding(get: { box.value }, set: { box.value = $0 }),
                                segments: segments, compact: false, appearance: appearance)
                .environment(\.helmSwitcherStyle, .text)
        }
    }

    private struct Rig {
        let host: NSHostingView<Probe>
        let box: Box
        let appearance: HelmBarAppearance
        let control: NSSegmentedControl
        let cell: HelmFlatSegmentedCell
    }

    /// The seams are set after mounting, on the cell the control wears, because the switcher swaps its cell in
    /// while it is made.
    private func mount(_ appearance: HelmBarAppearance, selected: Int) throws -> Rig {
        let box = Box(selected)
        let host = NSHostingView(rootView: Probe(box: box, appearance: appearance))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first, "no switcher in the tree")
        let cell = try XCTUnwrap(control.cell as? HelmFlatSegmentedCell, "the switcher does not wear the flat cell")
        XCTAssertEqual(control.segmentCount, Self.words.count, "precondition — the segments are not filled")
        XCTAssertEqual(control.selectedSegment, selected, "precondition — the first fill did not select \(selected)")
        return Rig(host: host, box: box, appearance: appearance, control: control, cell: cell)
    }

    /// The page evaluates the switcher again after it wrote the box or changed the words.
    private func redeclare(_ rig: Rig, words: [String] = TheSwitchersPickSlidesToAPressedSegmentTests.words) {
        rig.host.rootView = Probe(box: rig.box, appearance: rig.appearance, words: words,
                                  revision: Int.random(in: 1...Int.max))
        rig.host.layoutSubtreeIfNeeded()
    }

    private func press(_ rig: Rig, _ index: Int, _ what: String = "") {
        rig.control.selectedSegment = index
        XCTAssertTrue(rig.control.sendAction(rig.control.action, to: rig.control.target),
                      "the control's own action went nowhere \(what)")
    }

    /// Records what the cell is asked for from here on.
    private final class Heard {
        var slides: [Slide] = []
    }

    private func listen(_ rig: Rig, reduceMotion: Bool = false) -> Heard {
        let heard = Heard()
        rig.cell.reducesMotion = { reduceMotion }
        rig.cell.onSlide = { heard.slides.append($0) }
        return heard
    }

    /// A press on another segment, so the instrument half is a real move whatever came before.
    private func assertTheCellHearsAPress(_ rig: Rig, _ heard: Heard, from: Int, to: Int,
                                          _ look: String, file: StaticString = #filePath, line: UInt = #line) {
        let before = heard.slides.count
        press(rig, to, "(\(look), instrument)")
        XCTAssertEqual(rig.box.value, to, "\(look): the instrument press did not reach the page", file: file, line: line)
        XCTAssertEqual(heard.slides.count, before + 1,
                       "\(look): the cell did not hear a press from \(from) to \(to), so a silence proves nothing",
                       file: file, line: line)
    }

    // MARK: - What a press asks for

    func testAPressAsksForOneSlideWithTheTokensLength() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig)
            press(rig, 2)
            XCTAssertEqual(rig.box.value, 2, "\(look): the press did not reach the page")
            XCTAssertEqual(heard.slides, [Slide(from: 0, to: 2, duration: HelmMotion.interfaceDuration)],
                           "\(look): a press from 0 to 2 asked for something else")
            XCTAssertEqual(rig.cell.sliding, Slide(from: 0, to: 2, duration: HelmMotion.interfaceDuration),
                           "\(look): the cell holds no slide right after the press")
        }
    }

    func testUnderReduceMotionAPressAsksForNone() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig, reduceMotion: false)
            assertTheCellHearsAPress(rig, heard, from: 0, to: 2, look)
            // End the slide the instrument press began, so what follows reads the next press alone.
            redeclare(rig, words: Self.words.map { $0 + " " })
            XCTAssertNil(rig.cell.sliding, "\(look): precondition — a refill left the instrument's slide running")

            rig.cell.reducesMotion = { true }
            let count = heard.slides.count
            press(rig, 1)
            XCTAssertEqual(rig.box.value, 1, "\(look): the press under Reduce Motion did not reach the page")
            XCTAssertEqual(rig.control.selectedSegment, 1, "\(look): the pressed segment is not the selected one")
            XCTAssertEqual(heard.slides.count, count, "\(look): a press under Reduce Motion asked for a slide")
            XCTAssertNil(rig.cell.sliding, "\(look): the cell slides under Reduce Motion")
        }
    }

    // MARK: - What asks for none

    func testTheFirstDrawAsksForNone() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 1)
            let heard = listen(rig)
            for _ in 0..<3 {
                rig.host.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(rig.host.bitmapImageRepForCachingDisplay(in: rig.host.bounds))
                rig.host.cacheDisplay(in: rig.host.bounds, to: rep)
            }
            XCTAssertEqual(rig.control.selectedSegment, 1, "\(look): precondition — the drawn selection moved")
            XCTAssertEqual(heard.slides, [], "\(look): drawing asked for a slide")
            XCTAssertNil(rig.cell.sliding, "\(look): the cell slides without a press")
            assertTheCellHearsAPress(rig, heard, from: 1, to: 2, look)
        }
    }

    func testASelectionSetByThePageAsksForNone() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig)
            rig.box.value = 2
            redeclare(rig)
            XCTAssertEqual(rig.control.selectedSegment, 2, "\(look): the page's selection did not reach the control")
            XCTAssertEqual(heard.slides, [], "\(look): a selection the page wrote asked for a slide")
            XCTAssertNil(rig.cell.sliding, "\(look): the cell slides to a selection the page wrote")
            assertTheCellHearsAPress(rig, heard, from: 2, to: 0, look)
        }
    }

    func testAPressOnTheSelectedSegmentAsksForNone() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 1)
            let heard = listen(rig)
            press(rig, 1)
            XCTAssertEqual(rig.control.selectedSegment, 1, "\(look): precondition — the press moved the selection")
            XCTAssertEqual(rig.box.value, 1, "\(look): precondition — the press changed the page's value")
            XCTAssertEqual(heard.slides, [], "\(look): a press on the selected segment asked for a slide")
            XCTAssertNil(rig.cell.sliding, "\(look): the cell slides to where it already is")
            press(rig, 2)
            XCTAssertEqual(rig.box.value, 2, "\(look): the press on another segment did not reach the page")
            XCTAssertEqual(heard.slides, [Slide(from: 1, to: 2, duration: HelmMotion.interfaceDuration)],
                           "\(look): a press on another segment did not ask for exactly one slide")
        }
    }

    // MARK: - What ends one

    func testAFillEndsASlideInFlight() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig)
            let subviews = rig.control.subviews.count
            press(rig, 2)
            XCTAssertEqual(heard.slides.count, 1, "\(look): precondition — the press asked for no slide")
            // Completion is the animation's, asynchronous: right after the press the slide is in flight.
            XCTAssertNotNil(rig.cell.sliding, "\(look): precondition — no slide is in flight after the press")

            redeclare(rig, words: Self.words.map { $0 + " " })
            XCTAssertEqual(rig.control.label(forSegment: 0), Self.words[0] + " ",
                           "\(look): precondition — the refill did not reach the control")
            XCTAssertNil(rig.cell.sliding, "\(look): a refill left the slide in flight")
            XCTAssertEqual(rig.control.subviews.count, subviews,
                           "\(look): the slide's temporary view outlived the refill")
        }
    }

    // MARK: - Order

    func testTheSlideIsAskedBeforeThePageHears() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            var pageSawWhenAsked: [Int] = []
            rig.cell.reducesMotion = { false }
            rig.cell.onSlide = { _ in pageSawWhenAsked.append(rig.box.value) }
            press(rig, 2)
            XCTAssertEqual(rig.box.value, 2, "\(look): the press did not reach the page")
            XCTAssertEqual(pageSawWhenAsked.count, 1, "\(look): precondition — the press asked for \(pageSawWhenAsked.count) slides")
            XCTAssertEqual(pageSawWhenAsked, [0], """
                \(look): the page already held the new value when the slide was asked for — \
                the page was written before the cell was asked to slide
                """)
        }
    }

    // MARK: - Inputs a press can meet in the middle of something

    func testASecondPressInFlightTakesTheSlideOverAndLeavesOneTemporaryView() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig)
            let subviews = rig.control.subviews.count
            press(rig, 2)
            press(rig, 1)
            XCTAssertEqual(heard.slides, [Slide(from: 0, to: 2, duration: HelmMotion.interfaceDuration),
                                          Slide(from: 2, to: 1, duration: HelmMotion.interfaceDuration)],
                           "\(look): the second press did not start from where the first one went")
            XCTAssertEqual(rig.cell.sliding, Slide(from: 2, to: 1, duration: HelmMotion.interfaceDuration),
                           "\(look): the cell holds the first slide after the second press")
            XCTAssertEqual(rig.control.subviews.count, subviews + 1,
                           "\(look): two presses in flight left \(rig.control.subviews.count - subviews) temporary views")
            redeclare(rig, words: Self.words.map { $0 + " " })
            XCTAssertEqual(rig.control.subviews.count, subviews, "\(look): a refill left a temporary view behind")
        }
    }

    func testADisabledControlAsksForNone() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig)
            assertTheCellHearsAPress(rig, heard, from: 0, to: 2, look)
            redeclare(rig, words: Self.words.map { $0 + " " })
            rig.control.isEnabled = false
            let count = heard.slides.count
            press(rig, 1)
            XCTAssertEqual(heard.slides.count, count, "\(look): a disabled control asked for a slide")
            XCTAssertNil(rig.cell.sliding, "\(look): a disabled control slides")
        }
    }

    func testFewerSegmentsEndTheSlideAndLeaveNoIndexTheControlLacks() throws {
        for (look, appearance) in Self.looks {
            let rig = try mount(appearance, selected: 0)
            let heard = listen(rig)
            let subviews = rig.control.subviews.count
            press(rig, 2)
            XCTAssertNotNil(rig.cell.sliding, "\(look): precondition — no slide is in flight")
            // The page keeps 2 as its value while the strip loses the segment that held it.
            redeclare(rig, words: Array(Self.words.prefix(2)))
            XCTAssertEqual(rig.control.segmentCount, 2, "\(look): precondition — the strip did not shrink")
            XCTAssertNil(rig.cell.sliding, "\(look): the slide outlived the segment it went to")
            XCTAssertEqual(rig.control.subviews.count, subviews, "\(look): the temporary view outlived the shrink")
            // A press now starts from an index the strip no longer has or from none: it must cut, not trap.
            let count = heard.slides.count
            press(rig, 0)
            XCTAssertEqual(rig.box.value, 0, "\(look): the press after the shrink did not reach the page")
            XCTAssertEqual(heard.slides.count, count, "\(look): a slide was asked from a segment the strip lacks")
            // The cell itself refuses an index the strip lacks, on either end.
            rig.cell.slide(from: 2, to: 0)
            rig.cell.slide(from: 0, to: 2)
            XCTAssertEqual(heard.slides.count, count, "\(look): the cell slid across an index it does not have")
        }
    }
}
