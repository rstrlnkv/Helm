import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **The sidebar's rows are `Button`s with a name, the arrow keys go through the
/// list's own `neighbour`, the blocked mark says what it means in words, and the
/// owner's numbers are the numbers the row draws with.**
///
/// No window: the view is never mounted. Two halves, and each says what its total
/// failure prints.
///
/// - **Readings of `ShellSidebar.swift`**, through `SwiftSource.code` (comments
///   blanked, string insides blanked) so a doc comment that explains why there is
///   no tap gesture is not a tap gesture. Every reading first asserts that the
///   file has the two types it is about: an empty file and a file reduced to
///   comments fail on that assertion, with a sentence that says what is missing,
///   instead of passing every "none of" rule vacuously. That it has buttons is
///   asserted by `testEveryRowIsAButtonWithAName`, and
///   `testEveryRowAndTheChevronCarryAHelp` throws without the row's and the
///   chevron's; no other reading asks. The tap-gesture scan and the motion
///   scan are also run on a planted sample, so either one that has stopped
///   matching is a red test; the triangle, colour-literal and number-literal
///   rules are not.
/// - **The pure functions** the view calls (`direction`, `landing`,
///   `selection(choosing:from:)`), fed values: both ends, a section boundary, no
///   current row, no module rows at all.
///
/// Whose numbers: the row's height 36, the glyph's 16 × 1.3, the chevron's column
/// 20 and the selection's radius 8 are the owner's, from the concept he chose,
/// not Helm's ladders' (the nearest rungs are more than a point away). A change
/// to one is a change to the owner's design and starts with him. The dot's 8 is
/// the side `HelmStatusDot` draws its dot at.
///
/// The chevron's key, the key of the row that widens the rail again and the
/// sentence a blocked row carries as its value are asserted to be present in
/// all eight languages by `StringsCoverageTests`; this does not repeat that.
/// It asks what is in them: that outside English they are not the English key.
final class TheSidebarIsReachableWithoutAPointerTests: XCTestCase {

    // MARK: - reading the file

    private static let path = "Sources/HelmApp/ShellSidebar.swift"

    private struct Reading {
        let code: String
        let uncommented: String
        var lines: [String] { code.components(separatedBy: "\n") }
    }

    private func reading() throws -> Reading {
        let text = try RepoSource.text(of: Self.path)
        let code = SwiftSource.code(text)
        // What the rest of this class is about. A file without them has nothing
        // to say "no" to.
        XCTAssertTrue(code.contains("struct ShellSidebar: View"), "\(Self.path) no longer holds the column")
        XCTAssertTrue(code.contains("struct ShellSidebarRow: View"), "\(Self.path) no longer holds the row")
        return Reading(code: code, uncommented: SwiftSource.uncommented(text))
    }

    /// The index of every line that opens a `Button` (not a longer name).
    private func buttonLines(_ lines: [String]) -> [Int] {
        lines.indices.filter { index in
            var from = lines[index].startIndex
            while let found = lines[index].range(of: "Button(", range: from..<lines[index].endIndex) {
                if found.lowerBound == lines[index].startIndex
                    || !(lines[index][lines[index].index(before: found.lowerBound)].isLetter) { return true }
                from = found.upperBound
            }
            return false
        }
    }

    private func body(ofType name: String, in code: String) throws -> String {
        let bodies = SwiftSource.typeBodies(in: code).filter { $0.name == name }
        let characters = Array(code)
        guard let one = bodies.first else {
            throw NSError(domain: "TheSidebarIsReachableWithoutAPointerTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no type \(name) in \(Self.path)"])
        }
        return String(characters[(one.open + 1)..<one.close])
    }

    /// Tap gestures of every spelling. Applied to a sample below so that a scan
    /// that has stopped matching is red.
    private static func tapGestures(in code: String) -> [String] {
        ["onTapGesture", "TapGesture", ".gesture(", "simultaneousGesture", "highPriorityGesture"]
            .filter { code.contains($0) }
    }

    /// Every spelling of motion the shell does not take from `HelmMotion`.
    private static func motion(in code: String) -> [String] {
        ["withAnimation", ".animation(", ".transition(", "Animation", ".snappy", ".spring", ".bouncy",
         ".smooth", ".easeInOut", ".easeIn", ".easeOut", ".linear(", "interactiveSpring"]
            .filter { code.contains($0) }
    }

    // MARK: - rows are buttons, and the arrows move the selection

    func testEveryRowIsAButtonWithAName() throws {
        let file = try reading()
        let lines = file.lines

        XCTAssertEqual(Self.tapGestures(in: file.code), [],
                       "the sidebar's rows are tap gestures: the keyboard and Full Keyboard Access reach none of them")

        let buttons = buttonLines(lines)
        XCTAssertGreaterThanOrEqual(buttons.count, 2,
            "the sidebar has \(buttons.count) Button: a row and the chevron are two, so something is a tap target of another kind")
        var labelled = 0
        for line in buttons {
            let chain = SwiftSource.modifierChain(from: line, in: lines)
            XCTAssertTrue(chain.contains(".accessibilityLabel("),
                          "\(Self.path):\(line + 1): a Button with no accessibility label: it is read as whatever it draws")
            labelled += chain.contains(".accessibilityLabel(") ? 1 : 0
        }
        XCTAssertEqual(labelled, buttons.count)

        // The row: selected trait, tied to `selected`; and the blocked sentence as its value.
        let row = try body(ofType: "ShellSidebarRow", in: file.code)
        let rowButton = try XCTUnwrap(buttonLines(row.components(separatedBy: "\n")).first,
                                      "ShellSidebarRow holds no Button")
        let rowLines = row.components(separatedBy: "\n")
        let rowChain = SwiftSource.modifierChain(from: rowButton, in: rowLines)
        XCTAssertTrue(rowChain.contains(".accessibilityAddTraits(selected ? .isSelected : [])"),
                      "the selected row does not say it is selected to VoiceOver")
        XCTAssertTrue(rowChain.contains(".accessibilityLabel(title)"), "the row is not named by its title")
        // After the name, so the sentence names no subject of its own; the dot's
        // own sentence (below) carries the module's subject and is not read here.
        XCTAssertTrue(rowChain.contains(".accessibilityValue(blocked ? AppStr.moduleRowBlockedByPermission"),
                      "a blocked row's value is not the sentence written to follow a name")
        XCTAssertFalse(rowChain.contains("AppStr.moduleBlockedByPermission"),
                       "the row carries the dot's sentence, which disagrees with a name read before it")
    }

    func testTheSelectionIsMovedByTheArrowKeysThroughTheListsOwnNeighbour() throws {
        let file = try reading()
        XCTAssertTrue(file.code.contains(".neighbour(of:"),
                      "the sidebar never asks the list for a neighbour: a column of Buttons does not move a selection by arrows")
        XCTAssertTrue(file.code.contains(".focusable()") && file.code.contains(".focused("),
                      "the column does not take focus, so no arrow key reaches it")
        let lines = file.lines
        let handler = try XCTUnwrap(lines.firstIndex { $0.contains(".onMoveCommand") }, "no .onMoveCommand")
        let chain = SwiftSource.modifierChain(from: handler, in: lines)
        XCTAssertTrue(chain.contains("Self.direction(") && chain.contains("Self.landing(") && chain.contains("choose("),
                      "the arrow handler does not go direction -> landing -> choose: \(chain)")
        // `landing` is the one place `neighbour` is asked.
        let landing = try XCTUnwrap(SwiftSource.body(of: "landing", in: file.code), "no landing function")
        XCTAssertTrue(landing.contains(".neighbour(of:"), "landing does not ask the list")
    }

    // MARK: - the blocked mark

    func testTheBlockedMarkIsADotThatSaysItInWords() throws {
        let file = try reading()
        XCTAssertFalse(file.uncommented.contains("exclamationmark.triangle"),
                       "the triangle is back: the owner asked for a small round dot")
        let lines = file.lines
        let circle = try XCTUnwrap(lines.firstIndex { $0.contains("Circle()") }, "the mark is no Circle")
        let chain = SwiftSource.modifierChain(from: circle, in: lines)
        XCTAssertTrue(chain.contains(".fill(ShellSidebar.blockedInk)"), "the dot is not filled with blockedInk: \(chain)")
        XCTAssertTrue(chain.contains(".help(AppStr.moduleBlockedByPermission)"), "the dot has no tooltip")
        XCTAssertTrue(chain.contains(".accessibilityLabel(AppStr.moduleBlockedByPermission)"), "the dot has no label")
        XCTAssertFalse(chain.contains("moduleRowBlockedByPermission"),
                       "the dot says the row's sentence, which names no subject and stands only after a name")
        XCTAssertTrue(chain.contains(".frame(width: ShellSidebar.dotSide, height: ShellSidebar.dotSide)"),
                      "the dot's width and height are not both dotSide")
        // Drawn in the rail on the glyph and beside the name when expanded: two places.
        // Beside the name `{ mark }`; on the rail's glyph `mark.offset(`.
        let drawn = file.code.components(separatedBy: "{ mark }").count - 1
            + file.code.components(separatedBy: "mark.offset(").count - 1
        XCTAssertGreaterThanOrEqual(drawn, 2,
                                    "the dot is drawn in fewer than the two places (beside the name, on the rail's glyph)")
    }

    /// The colour is named in one place, so choosing another changes one line.
    func testTheDotsColourIsNamedOnceAndEveryUseGoesThroughIt() throws {
        let file = try reading()
        let lines = file.lines
        XCTAssertEqual(file.code.components(separatedBy: "HelmSignal").count - 1, 1,
                       "the signal palette is named \(file.code.components(separatedBy: "HelmSignal").count - 1) times in the code of \(Self.path): a colour chosen later changes more than one line")
        let declaration = try XCTUnwrap(lines.firstIndex { $0.contains("var blockedInk") }, "no blockedInk")
        XCTAssertTrue(SwiftSource.modifierChain(from: declaration, in: lines).contains("HelmSignal.warning"),
                      "blockedInk is not the warning ink")
        for literal in [".yellow", ".orange", ".red", ".green", "Color(", "NSColor"] {
            XCTAssertFalse(file.code.contains(literal), "a colour spelled \(literal) beside blockedInk")
        }
        XCTAssertGreaterThanOrEqual(file.code.components(separatedBy: "ShellSidebar.blockedInk").count - 1, 1,
                                    "nobody reads blockedInk")
    }

    // MARK: - the owner's numbers

    func testTheOwnersNumbersAreTheOnesTheRowDrawsWith() throws {
        // The owner's, from the concept he chose; the dot's 8 is HelmStatusDot's.
        XCTAssertEqual(ShellSidebar.rowHeight, 36)
        XCTAssertEqual(ShellSidebar.glyphSide, 16 * 1.3, accuracy: 0.0001)
        XCTAssertEqual(ShellSidebar.chevronColumn, 20)
        XCTAssertEqual(ShellSidebar.selectionRadius, 8)
        XCTAssertEqual(ShellSidebar.dotSide, 8)
        // The rail's row is square: the rail's width less the column's padding on both sides.
        XCTAssertEqual(ShellGeometry.railWidth - 2 * ShellSidebar.columnPad, ShellSidebar.rowHeight,
                       "in the rail a row is not square: the rail is \(ShellGeometry.railWidth) wide")

        // A constant nobody reads is a comment: each is read where it is drawn.
        let file = try reading()
        let row = try body(ofType: "ShellSidebarRow", in: file.code)
        let column = try body(ofType: "ShellSidebar", in: file.code)
        func uses(_ name: String, _ prefix: String, in text: String) -> Int {
            text.components(separatedBy: prefix + "." + name).count - 1
        }
        XCTAssertGreaterThanOrEqual(uses("rowHeight", "ShellSidebar", in: row), 1, "the row is not rowHeight high")
        XCTAssertGreaterThanOrEqual(uses("glyphSide", "ShellSidebar", in: row), 1, "the glyph is not the owner's size")
        XCTAssertGreaterThanOrEqual(uses("selectionRadius", "ShellSidebar", in: row), 1, "the selection has no owner's radius")
        XCTAssertGreaterThanOrEqual(uses("rowHeight", "Self", in: column), 1, "the chevron is not rowHeight high")
        XCTAssertGreaterThanOrEqual(uses("chevronColumn", "Self", in: column), 1, "the chevron has no column")
        XCTAssertGreaterThanOrEqual(uses("columnPad", "Self", in: column), 2, "the column's padding is not columnPad")
        XCTAssertGreaterThanOrEqual(uses("headingTop", "Self", in: column), 1, "no heading has its top")
        // And no second spelling of one of these numbers beside the constant.
        for literal in ["height: 36", "cornerRadius: 8", "width: 8", "height: 8", "width: 20", "size: 20.8"] {
            XCTAssertFalse(file.code.contains(literal), "\(literal) is spelled beside the constant that holds it")
        }
    }

    // MARK: - where the dot sits, and what a long heading does

    /// In the rail the dot is centred on the glyph frame's corner, so it clears the
    /// glyph's strokes; an overlay with no offset sits inside the frame, where most glyphs draw.
    func testInTheRailTheDotIsCentredOnTheGlyphFramesCorner() throws {
        let file = try reading()
        let row = try body(ofType: "ShellSidebarRow", in: file.code)
        let overlays = row.components(separatedBy: "\n").filter { $0.contains(".overlay(alignment:") }
        XCTAssertEqual(overlays.count, 1, "the row has \(overlays.count) overlays, not the one that holds the rail's dot")
        let squeezed = (overlays.first ?? "").replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(squeezed.contains(".overlay(alignment:.topTrailing)"), "the dot is not at the glyph's top trailing corner")
        XCTAssertTrue(squeezed.contains("mark.offset(x:ShellSidebar.dotSide/2,y:-ShellSidebar.dotSide/2)"),
                      "the rail's dot has no offset by half its side: it sits inside the glyph's frame: \(overlays.first ?? "")")
    }

    /// A section's name is typed by a person, and it must not wrap the column.
    func testASectionHeadingIsOneLine() throws {
        let file = try reading()
        let lines = file.lines
        let heading = try XCTUnwrap(lines.firstIndex { $0.contains("Text(AppStr.sectionTitle(group.section))") },
                                    "the column draws no section heading")
        XCTAssertTrue(SwiftSource.modifierChain(from: heading, in: lines).contains(".lineLimit(1)"),
                      "a long section name wraps the heading onto a second line")
    }

    // MARK: - no motion

    func testTheColumnHasNoMotionOfItsOwn() throws {
        let file = try reading()
        XCTAssertEqual(Self.motion(in: file.code), [], "the sidebar animates; curves come from HelmMotion alone")
        // The scans can fail.
        XCTAssertFalse(Self.motion(in: "withAnimation(.snappy) { x }").isEmpty, "the motion scan finds nothing in a sample of motion")
        XCTAssertFalse(Self.tapGestures(in: "Text(a).onTapGesture { b() }").isEmpty, "the tap scan finds nothing in a sample of one")
    }

    // MARK: - the rail names what it shows

    func testEveryRowAndTheChevronCarryAHelp() throws {
        let file = try reading()
        let lines = file.lines
        // The row: a help that is its title in both forms. Expanded, a name can be
        // cut short by the column (`lineLimit(1)`), and the tooltip is where the
        // whole of it is read.
        let row = try body(ofType: "ShellSidebarRow", in: file.code)
        let rowLines = row.components(separatedBy: "\n")
        let rowButton = try XCTUnwrap(buttonLines(rowLines).first)
        let rowChain = SwiftSource.modifierChain(from: rowButton, in: rowLines)
        XCTAssertTrue(rowChain.contains(".help(title)"), "a row has no tooltip naming it")
        XCTAssertFalse(rowChain.contains(".help(collapsed"),
                       "the tooltip is withheld when expanded, where a name cut short has nowhere else to be read")

        // The chevron: both its help and its label are the hide sentence.
        let chevron = try XCTUnwrap(lines.firstIndex { $0.contains("Button(action: toggleCollapsed)") }, "no chevron Button")
        let chain = SwiftSource.modifierChain(from: chevron, in: lines)
        XCTAssertTrue(chain.contains(".help(AppStr.hideSidebar)"), "the chevron has no tooltip: \(chain)")
        XCTAssertTrue(chain.contains(".accessibilityLabel(AppStr.hideSidebar)"), "the chevron has no label")
        XCTAssertFalse(chain.contains("AppStr.showSidebar"), "the hiding chevron is labelled with the showing sentence")

        // The row that widens the rail again: collapsed, titled with the show sentence.
        let calls = SwiftSource.callSites(of: "ShellSidebarRow", in: file.code)
        let show = calls.filter { $0.arguments.contains { $0.contains("AppStr.showSidebar") } }
        XCTAssertEqual(show.count, 1, "the rail has \(show.count) rows titled Show Sidebar, not one")
        XCTAssertTrue(show.first?.arguments.contains { $0.contains("collapsed: true") } ?? false,
                      "the row titled Show Sidebar is not the rail's own")
        XCTAssertTrue(show.first?.arguments.contains { $0.contains("action: toggleCollapsed") } ?? false,
                      "the row titled Show Sidebar does not toggle")
        XCTAssertEqual(file.code.components(separatedBy: "AppStr.hideSidebar").count - 1, 2)
        XCTAssertEqual(file.code.components(separatedBy: "AppStr.showSidebar").count - 1, 1)
    }

    /// Presence in all eight is `StringsCoverageTests`'s; this is what is in them.
    func testTheTwoLabelsAreTranslatedOutsideEnglish() {
        var seen = 0
        AppLanguage.each { language in
            seen += 1
            let hide = AppStr.hideSidebar, show = AppStr.showSidebar
            XCTAssertFalse(hide.isEmpty || show.isEmpty, "\(language): a label is empty")
            XCTAssertNotEqual(hide, show, "\(language): the two labels are one sentence")
            if language == .en {
                XCTAssertEqual(hide, "Hide Sidebar")
                XCTAssertEqual(show, "Show Sidebar")
            } else {
                XCTAssertNotEqual(hide, "Hide Sidebar", "\(language): Hide Sidebar is left in English")
                XCTAssertNotEqual(show, "Show Sidebar", "\(language): Show Sidebar is left in English")
            }
        }
        XCTAssertEqual(seen, 8, "the loop ran in \(seen) languages")
    }

    func testTheBlockedRowsValueIsTranslatedOutsideEnglish() {
        var seen = 0
        AppLanguage.each { language in
            seen += 1
            let value = AppStr.moduleRowBlockedByPermission
            XCTAssertFalse(value.isEmpty, "\(language): the blocked row's value is empty")
            XCTAssertNotEqual(value, AppStr.moduleBlockedByPermission, "\(language): the value and the dot's sentence are one")
            if language == .en {
                XCTAssertEqual(value, "macOS is withholding a needed permission")
            } else {
                XCTAssertNotEqual(value, "macOS is withholding a needed permission", "\(language): the value is left in English")
            }
        }
        XCTAssertEqual(seen, 8, "the loop ran in \(seen) languages")
    }

    // MARK: - the arrows (values)

    private typealias Rows = ShellSidebarRows

    private static let layout = SidebarLayout(sections: [
        .init(id: "s1", seed: nil, name: "First", modules: ["alpha", "beta"]),
        .init(id: "s2", seed: nil, name: "Second", modules: ["gamma", "delta"]),
    ])

    private func rows(on enabled: Set<String>) -> Rows { Rows(layout: Self.layout, enabled: enabled) }

    func testOnlyUpAndDownAreArrowsTheColumnMoves() {
        XCTAssertEqual(ShellSidebar.direction(.up), .up)
        XCTAssertEqual(ShellSidebar.direction(.down), .down)
        XCTAssertNil(ShellSidebar.direction(.left), "left moves the selection")
        XCTAssertNil(ShellSidebar.direction(.right), "right moves the selection")
    }

    func testAnArrowLandsOnTheNeighbourAcrossASectionBoundaryAndStopsAtBothEnds() {
        let all = rows(on: ["alpha", "beta", "gamma", "delta"])
        XCTAssertEqual(ShellSidebar.landing(from: .module("alpha"), moving: .down, in: all), .module("beta"))
        XCTAssertEqual(ShellSidebar.landing(from: .module("beta"), moving: .up, in: all), .module("alpha"))
        // Across the boundary between the two sections.
        XCTAssertEqual(ShellSidebar.landing(from: .module("beta"), moving: .down, in: all), .module("gamma"))
        XCTAssertEqual(ShellSidebar.landing(from: .module("gamma"), moving: .up, in: all), .module("beta"))
        // Into and out of the foot row.
        XCTAssertEqual(ShellSidebar.landing(from: .module("delta"), moving: .down, in: all), .foot)
        XCTAssertEqual(ShellSidebar.landing(from: .foot, moving: .up, in: all), .module("delta"))
        // Both ends: nothing, not a wrap.
        XCTAssertNil(ShellSidebar.landing(from: .module("alpha"), moving: .up, in: all), "up from the first row wraps")
        XCTAssertNil(ShellSidebar.landing(from: .foot, moving: .down, in: all), "down from the foot row wraps")
        // Modules that are off are not rows to stop on: down from alpha passes beta and gamma.
        let skipped = rows(on: ["alpha", "delta"])
        XCTAssertEqual(ShellSidebar.landing(from: .module("alpha"), moving: .down, in: skipped), .module("delta"))
        XCTAssertEqual(ShellSidebar.landing(from: .module("delta"), moving: .up, in: skipped), .module("alpha"))
    }

    /// A section whose every module is off, between two that have rows, is passed
    /// over in both directions.
    func testASectionWithEveryModuleOffBetweenTwoLiveOnesIsNotStoppedOn() {
        let layout = SidebarLayout(sections: [
            .init(id: "s1", seed: nil, name: "First", modules: ["alpha"]),
            .init(id: "s2", seed: nil, name: "Second", modules: ["beta", "gamma"]),
            .init(id: "s3", seed: nil, name: "Third", modules: ["delta"]),
        ])
        let list = Rows(layout: layout, enabled: ["alpha", "delta"])
        XCTAssertEqual(list.rows, [.module("alpha"), .module("delta"), .foot])
        XCTAssertEqual(ShellSidebar.landing(from: .module("alpha"), moving: .down, in: list), .module("delta"))
        XCTAssertEqual(ShellSidebar.landing(from: .module("delta"), moving: .up, in: list), .module("alpha"))
    }

    func testWithNoCurrentRowDownLandsOnTheFirstRowAndUpOnTheFootRow() {
        let all = rows(on: ["alpha", "beta", "gamma", "delta"])
        XCTAssertEqual(ShellSidebar.landing(from: nil, moving: .down, in: all), .module("alpha"))
        XCTAssertEqual(ShellSidebar.landing(from: nil, moving: .up, in: all), .foot)
        // One module on: the first row is it.
        XCTAssertEqual(ShellSidebar.landing(from: nil, moving: .down, in: rows(on: ["gamma"])), .module("gamma"))
    }

    func testWithNoModuleRowsAtAllTheFootRowIsEveryEnd() {
        let none = rows(on: [])
        XCTAssertEqual(none.rows, [.foot], "a sidebar with no module on has more than the foot row")
        XCTAssertEqual(ShellSidebar.landing(from: nil, moving: .down, in: none), .foot)
        XCTAssertEqual(ShellSidebar.landing(from: nil, moving: .up, in: none), .foot)
        XCTAssertNil(ShellSidebar.landing(from: .foot, moving: .down, in: none))
        XCTAssertNil(ShellSidebar.landing(from: .foot, moving: .up, in: none), "the only row has a row above it")
        // No sections at all, either.
        let empty = Rows(layout: SidebarLayout(sections: []), enabled: ["alpha"])
        XCTAssertEqual(empty.rows, [.foot])
        XCTAssertEqual(ShellSidebar.landing(from: nil, moving: .down, in: empty), .foot)
    }

    /// The current row may be one the list does not hold (a
    /// module switched off while it was selected). The view derives `current`
    /// from the list, so it passes nil then; handed over directly, nothing moves.
    func testARowThatIsNotInTheListLandsNowhere() {
        let all = rows(on: ["alpha", "beta"])
        XCTAssertNil(ShellSidebar.landing(from: .module("ghost"), moving: .down, in: all))
        XCTAssertNil(ShellSidebar.landing(from: .module("ghost"), moving: .up, in: all))
        // beta is off here, so a selection still naming it is not a row.
        XCTAssertNil(rows(on: ["alpha"]).row(for: .module("beta")))
    }

    // MARK: - what choosing a row writes

    func testChoosingAModuleSelectsItAndChoosingTheSelectedOneWritesNothing() {
        XCTAssertEqual(ShellSidebar.selection(choosing: .module("alpha"), from: nil), .module("alpha"))
        XCTAssertEqual(ShellSidebar.selection(choosing: .module("alpha"), from: .general), .module("alpha"))
        XCTAssertEqual(ShellSidebar.selection(choosing: .module("alpha"), from: .about), .module("alpha"))
        XCTAssertEqual(ShellSidebar.selection(choosing: .module("alpha"), from: .log), .module("alpha"))
        XCTAssertEqual(ShellSidebar.selection(choosing: .module("alpha"), from: .module("beta")), .module("alpha"))
        XCTAssertNil(ShellSidebar.selection(choosing: .module("alpha"), from: .module("alpha")),
                     "choosing the selected module writes the selection again")
    }

    func testChoosingTheFootRowOpensGeneralAndNeverResetsAnOpenTab() {
        XCTAssertEqual(ShellSidebar.selection(choosing: .foot, from: nil), .general)
        XCTAssertEqual(ShellSidebar.selection(choosing: .foot, from: .module("alpha")), .general)
        XCTAssertNil(ShellSidebar.selection(choosing: .foot, from: .general))
        XCTAssertNil(ShellSidebar.selection(choosing: .foot, from: .log), "the foot row resets the Log tab to General")
        XCTAssertNil(ShellSidebar.selection(choosing: .foot, from: .about), "the foot row resets the About tab to General")
    }
}
