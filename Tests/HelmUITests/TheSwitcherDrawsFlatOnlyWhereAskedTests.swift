import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The switcher wears its own flat cell only where it is asked to, and the capsule asks for it by the
/// environment's look.** A switcher built with no appearance keeps the system's own cell; a control that
/// is flipped to flat and back keeps its identity, its segments and its action.
///
/// No window is ordered: the hosting view is laid out windowless, and the capsule rows mount through
/// `MountedRender`, whose window is never ordered in. What is read back is the cell's class, the
/// control's fitting height, its segments and its action, and for the flat cell the alpha of one row of its own drawing through `cacheDisplay`. **Not seen on a screen:** this cell. Measured on 27.2
/// in a standalone bench app's window, key and then not key, in the dark appearance, was only that a cell
/// overriding `drawSegment` alone has its paint on screen, with the system's selection capsule still under the
/// selected segment; whether that capsule shows under this cell's pick, and this cell's exact widths, were not.
@MainActor
final class TheSwitcherDrawsFlatOnlyWhereAskedTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// Fixed English strings: the rows read a segment's own label, not a visible localized one.
    struct Mounted: View {
        static let words = ["Installed", "Updates", "Search"]
        let selected: Int
        let compact: Bool
        let appearance: HelmBarAppearance?
        var enabled = true
        /// The segment that carries the attention dot, if any.
        var dot: Int? = nil

        var body: some View {
            let segments = Self.words.enumerated().map { index, word in
                HelmSwitcherSegment(index, word, symbol: "circle", needsAttention: dot == index)
            }
            Group {
                if let appearance {
                    HelmToolbarSwitcher("Probe", selection: .constant(selected), segments: segments,
                                        compact: compact, appearance: appearance)
                } else {
                    HelmToolbarSwitcher("Probe", selection: .constant(selected), segments: segments,
                                        compact: compact)
                }
            }
            .environment(\.helmSwitcherStyle, .text)
            .disabled(!enabled)
        }
    }

    private func host(_ view: Mounted) -> NSHostingView<Mounted> {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func control(in host: NSView, _ what: String = "the switcher") throws -> NSSegmentedControl {
        try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                      "no NSSegmentedControl in the tree (\(what))")
    }

    private func isFlat(_ control: NSSegmentedControl) -> Bool { control.cell is HelmFlatSegmentedCell }

    private func isExactlyTheSystemsCell(_ control: NSSegmentedControl) -> Bool {
        guard let cell = control.cell else { return false }
        return type(of: cell) == NSSegmentedCell.self
    }

    func testAFlatSwitcherWearsTheFlatCellAndTheBarsHeight() throws {
        let host = host(Mounted(selected: 1, compact: false, appearance: .flat))
        let control = try control(in: host)
        XCTAssertGreaterThan(control.segmentCount, 0, "precondition — no segments filled")
        XCTAssertTrue(isFlat(control), "the flat switcher wears \(String(describing: control.cell.map { type(of: $0) }))")
        XCTAssertEqual(control.fittingSize.height, HelmFlatSegmentedCell.height, accuracy: 0.5,
                       "the flat control is not the bar's height")
        XCTAssertEqual(HelmFlatSegmentedCell.height,
                       HelmFlatSegmentedCell.pill + 2 * HelmFlatSegmentedCell.inset, accuracy: 0.001)
    }

    func testASwitcherToldNothingKeepsTheSystemsOwnCell() throws {
        // 36 is the stock control's height at `.extraLarge` as measured for three words; the flat cell
        // is built to match it, so both looks fit to one height.
        let host = host(Mounted(selected: 1, compact: false, appearance: nil))
        let control = try control(in: host)
        XCTAssertGreaterThan(control.segmentCount, 0, "precondition — no segments filled")
        XCTAssertTrue(isExactlyTheSystemsCell(control), """
            a switcher given no appearance wears \(String(describing: control.cell.map { type(of: $0) })), \
            not exactly NSSegmentedCell
            """)
        XCTAssertEqual(control.fittingSize.height, 36, accuracy: 0.5, "the stock control's height moved")
    }

    func testAFlipKeepsTheControlItsSegmentsAndItsAction() throws {
        let host = host(Mounted(selected: 1, compact: false, appearance: .liquidGlass))
        let control = try control(in: host)
        XCTAssertEqual(control.segmentCount, Mounted.words.count, "precondition — the glass form is not filled")

        func check(_ step: String, flat: Bool) throws {
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first,
                          "\(step): the flip rebuilt the control")
            XCTAssertEqual(control.segmentCount, Mounted.words.count, """
                segmentCount is \(control.segmentCount) after the flip (\(step)): the swap emptied the \
                control and nothing refilled it
                """)
            for (index, word) in Mounted.words.enumerated() {
                XCTAssertEqual(control.label(forSegment: index), word, "\(step): label of segment \(index)")
            }
            XCTAssertEqual(control.selectedSegment, 1, "\(step): selected segment")
            XCTAssertNotNil(control.target, "\(step): the control lost its target")
            XCTAssertNotNil(control.action, "\(step): the control lost its action")
            XCTAssertEqual(control.controlSize, .extraLarge, "\(step): control size")
            XCTAssertEqual(isFlat(control), flat, "\(step): cell class \(String(describing: control.cell.map { type(of: $0) }))")
            if !flat {
                XCTAssertTrue(isExactlyTheSystemsCell(control), "\(step): not exactly NSSegmentedCell")
            }
        }

        try check("glass first", flat: false)
        host.rootView = Mounted(selected: 1, compact: false, appearance: .flat)
        try check("flat", flat: true)
        host.rootView = Mounted(selected: 1, compact: false, appearance: .liquidGlass)
        try check("glass again", flat: false)
    }

    func testAFlatSwitcherFoldsAsTheGlassOneDoes() throws {
        let host = host(Mounted(selected: 1, compact: false, appearance: .flat))
        let control = try control(in: host)
        XCTAssertTrue(isFlat(control), "precondition — the switcher is not flat")
        XCTAssertEqual(control.segmentCount, Mounted.words.count, "the full flat form drew \(control.segmentCount) segments")
        let fullWidth = control.fittingSize.width

        host.rootView = Mounted(selected: 1, compact: true, appearance: .flat)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first,
                      "folding rebuilt the control")
        XCTAssertTrue(isFlat(control), "folding dropped the flat cell")
        XCTAssertEqual(control.segmentCount, 1, "compact drew \(control.segmentCount) segments")
        XCTAssertEqual(control.label(forSegment: 0), "Updates", "the folded segment's label")
        XCTAssertTrue(control.showsMenuIndicator(forSegment: 0), "the folded segment has no menu indicator")
        XCTAssertLessThan(control.fittingSize.width, fullWidth, """
            the folded flat control (\(control.fittingSize.width) pt) is not narrower than the full one \
            (\(fullWidth) pt)
            """)

        host.rootView = Mounted(selected: 1, compact: false, appearance: .flat)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first, "unfolding rebuilt the control")
        XCTAssertEqual(control.segmentCount, Mounted.words.count, "unfolding drew \(control.segmentCount) segments")
        for index in 0..<control.segmentCount {
            XCTAssertFalse(control.showsMenuIndicator(forSegment: index),
                           "segment \(index) keeps a menu indicator after unfolding")
        }
    }

    // MARK: - the capsule

    private func segmentedEntry() -> HelmToolbarActionsModel.Entry {
        HelmToolbarActionsModel.Entry(
            id: "viewMode", title: "View", symbol: "", isEnabled: true,
            kind: .segmented([
                .init(id: "table", title: "Table", symbol: "tablecells"),
                .init(id: "text", title: "Plain text", symbol: "text.alignleft"),
            ], selectedID: "table", reserveWidth: 0))
    }

    private func mountCapsule(appearance: HelmBarAppearance?) -> MountedRender {
        let model = HelmToolbarActionsModel()
        model.setDeclared([segmentedEntry()])
        model.setVisibleIDs(["viewMode"])
        let render: MountedRender
        if let appearance {
            render = MountedRender(HelmToolbarActionsCapsule(model).environment(\.helmBarAppearance, appearance),
                                   width: 400, height: 60, appearance: .aqua)
        } else {
            render = MountedRender(HelmToolbarActionsCapsule(model), width: 400, height: 60, appearance: .aqua)
        }
        renders.append(render)
        return render
    }

    func testACapsuleHandsItsAppearanceToTheSwitcherInside() throws {
        let flat = mountCapsule(appearance: .flat)
        let flatControl = try XCTUnwrap(flat.host.everyView(ofType: NSSegmentedControl.self).first,
                                        "no segmented control mounted (flat environment)")
        XCTAssertGreaterThan(flatControl.segmentCount, 0, "precondition — no segments filled (flat)")
        XCTAssertTrue(isFlat(flatControl), """
            the capsule under a flat environment mounts \(String(describing: flatControl.cell.map { type(of: $0) }))
            """)

        let bare = mountCapsule(appearance: nil)
        let bareControl = try XCTUnwrap(bare.host.everyView(ofType: NSSegmentedControl.self).first,
                                        "no segmented control mounted (no environment)")
        XCTAssertGreaterThan(bareControl.segmentCount, 0, "precondition — no segments filled (no environment)")
        XCTAssertTrue(isExactlyTheSystemsCell(bareControl), """
            the capsule with no environment mounts \(String(describing: bareControl.cell.map { type(of: $0) })), \
            not exactly NSSegmentedCell
            """)

        let glass = mountCapsule(appearance: .liquidGlass)
        let glassControl = try XCTUnwrap(glass.host.everyView(ofType: NSSegmentedControl.self).first,
                                         "no segmented control mounted (glass environment)")
        XCTAssertTrue(isExactlyTheSystemsCell(glassControl), "a glass environment does not mount the system's cell")
    }

    func testFlatActionsCarryNoPlateAndASegmentedOneDoes() throws {
        let kinds: [(String, HelmToolbarActionsModel.EntryKind)] = [
            ("button", .button),
            ("toggle", .toggle(isOn: true)),
            ("menu", .menu([.init(id: "a", title: "A", isOn: false, isEnabled: true)])),
        ]
        for (name, kind) in kinds {
            XCTAssertNil(HelmToolbarActionsCapsule.flatFill(for: kind), "a \(name) action carries a plate")
        }
        let kind = segmentedEntry().kind
        let fill = HelmToolbarActionsCapsule.flatFill(for: kind)
        XCTAssertNotNil(fill, "a segmented action carries no plate, so its pick has nothing to sit on")
        XCTAssertEqual(fill, HelmSurface.barPlate, "the segmented plate is not barPlate")
    }

    // MARK: - what the flat cell draws

    /// The columns the selected segment's pick covers in the control's own drawing, taken at the pick's
    /// middle row (the word sits inside the pick, so the first and last column that differ from the same drawing
    /// with nothing selected are the pick's edges).
    private func pickExtent(of control: NSSegmentedControl, selecting segment: Int) throws -> ClosedRange<Int> {
        func row(_ selected: Int) throws -> [CGFloat] {
            control.selectedSegment = selected
            let rep = try XCTUnwrap(control.bitmapImageRepForCachingDisplay(in: control.bounds))
            control.cacheDisplay(in: control.bounds, to: rep)
            let y = rep.pixelsHigh / 2
            return (0..<rep.pixelsWide).map { rep.colorAt(x: $0, y: y)?.alphaComponent ?? -1 }
        }
        // The unselected words are inked too, so ink alone would span the whole control: the pick is
        // what differs from the same control with nothing selected.
        let bare = try row(-1)
        let with = try row(segment)
        XCTAssertEqual(bare.count, with.count, "two drawings of one control differ in width")
        let changed = bare.indices.filter { abs(bare[$0] - with[$0]) > 0.005 }
        return try XCTUnwrap(changed.first.flatMap { first in changed.last.map { first...$0 } },
                             "segment \(segment) drew no pick")
    }

    /// **Measured, windowless, through `cacheDisplay`:** the flat cell draws its picks left to right, the first
    /// one inset from the leading edge, one inset between two, the last one inset from the trailing edge of the
    /// control's fitting width. The control reports no set width for any segment (every `width(forSegment:)` is
    /// 0). **Not measured:** where a press lands. The cell overrides no hit-testing, and whether the system's own
    /// follows the widths drawn here needs a real press in a window.
    func testTheFlatCellsDrawnSegmentsAreWhatItsSizeSays() throws {
        let flat = try control(in: host(Mounted(selected: 0, compact: false, appearance: .flat)))
        XCTAssertTrue(isFlat(flat), "precondition — not flat")
        XCTAssertEqual(flat.segmentCount, Mounted.words.count, "precondition — the flat control is not filled")
        let size = flat.fittingSize
        flat.frame = NSRect(origin: .zero, size: size)
        flat.layoutSubtreeIfNeeded()

        var extents: [ClosedRange<Int>] = []
        for index in 0..<flat.segmentCount {
            XCTAssertEqual(flat.width(forSegment: index), 0, "segment \(index) has a set width")
            extents.append(try pickExtent(of: flat, selecting: index))
        }
        let scale = Int((flat.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1).rounded())
        let drawn = extents.map { ($0.lowerBound / scale, ($0.upperBound + 1) / scale) }

        let inset = Int(HelmFlatSegmentedCell.inset)
        XCTAssertEqual(drawn.first?.0 ?? -1, inset, "the first pick does not start at the inset")
        for (left, right) in zip(drawn, drawn.dropFirst()) {
            XCTAssertEqual(right.0 - left.1, inset, "two picks are not one inset apart: \(drawn)")
        }
        XCTAssertEqual((drawn.last?.1 ?? -1) + inset, Int(size.width.rounded()), "the last pick does not end at the inset")
    }

    /// **A disabled flat strip draws the pick and the dot at the strength its words are drawn at.** The words
    /// and the template glyphs are inked in `tertiaryLabelColor`; the pick is `barPick`'s fill and the dot is a
    /// non-template image, and neither takes that ink. Read through `cacheDisplay` at the middle row, in each
    /// appearance named on the host: the pick left of the word of segment 0, and the strongest alpha in the six
    /// points after the side padding of segment 2, where the dot is (the text style draws the dot alone as that
    /// segment's image). The strength expected is the alpha of `tertiaryLabelColor` over the alpha of
    /// `labelColor`, each resolved here in the appearance under test.
    func testADisabledFlatControlDrawsItsPickAndItsDotAtTheDisabledInksStrength() throws {
        func alpha(of color: NSColor, in name: NSAppearance.Name) throws -> CGFloat {
            var resolved: NSColor?
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
            }
            return try XCTUnwrap(resolved, "the colour did not resolve in \(name.rawValue)").alphaComponent
        }

        func mount(enabled: Bool, in name: NSAppearance.Name) throws -> NSSegmentedControl {
            let host = host(Mounted(selected: 0, compact: false, appearance: .flat, enabled: enabled, dot: 2))
            host.appearance = NSAppearance(named: name)
            host.layoutSubtreeIfNeeded()
            let control = try control(in: host)
            XCTAssertTrue(isFlat(control), "precondition: not flat (\(name.rawValue), enabled \(enabled))")
            XCTAssertEqual(control.isEnabled, enabled, "the control's enabled state is not what the row set")
            XCTAssertEqual(control.segmentCount, Mounted.words.count, "precondition: the control is not filled")
            control.frame = NSRect(origin: .zero, size: control.fittingSize)
            control.layoutSubtreeIfNeeded()
            return control
        }

        /// One row of alpha values across the control, and how many pixels one point is.
        func middleRow(_ control: NSSegmentedControl, selected: Int) throws -> (row: [CGFloat], scale: CGFloat) {
            control.selectedSegment = selected
            let rep = try XCTUnwrap(control.bitmapImageRepForCachingDisplay(in: control.bounds))
            control.cacheDisplay(in: control.bounds, to: rep)
            let y = rep.pixelsHigh / 2
            let row = (0..<rep.pixelsWide).map { rep.colorAt(x: $0, y: y)?.alphaComponent ?? -1 }
            return (row, CGFloat(rep.pixelsWide) / control.bounds.width)
        }

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let label = try alpha(of: .labelColor, in: name)
            let tertiary = try alpha(of: .tertiaryLabelColor, in: name)
            let strength = tertiary / label
            XCTAssertGreaterThan(strength, 0.1, "\(name.rawValue): the strength read back as no dimming at all")
            XCTAssertLessThan(strength, 0.6, "\(name.rawValue): the strength read back as hardly dimming")

            let on = try mount(enabled: true, in: name)
            let off = try mount(enabled: false, in: name)

            // Where segment 2 starts: the pick's left edge when it is selected, which is the same enabled or not.
            let bare = try middleRow(on, selected: -1)
            let picked = try middleRow(on, selected: 2)
            let moved = bare.row.indices.filter { abs(bare.row[$0] - picked.row[$0]) > 0.005 }
            let segment2 = try XCTUnwrap(moved.first, "\(name.rawValue): segment 2 drew no pick, so its place is unknown")
            let scale = bare.scale

            // The pick, left of segment 0's word.
            let pickX = Int((HelmFlatSegmentedCell.inset + 4) * scale)
            let pickOn = try middleRow(on, selected: 0).row[pickX]
            let pickOff = try middleRow(off, selected: 0).row[pickX]
            XCTAssertGreaterThan(pickOn, 0.05, """
                \(name.rawValue): the enabled pick drew nothing at x \(pickX) (alpha \(pickOn)): the ratio below \
                would be read off an empty pixel
                """)
            XCTAssertEqual(pickOff / pickOn, strength, accuracy: 0.05, """
                \(name.rawValue): the disabled pick is drawn at \(pickOff / pickOn) of the enabled one, not at the \
                disabled ink's strength \(strength)
                """)

            // The dot: six points after the side padding of segment 2.
            let from = segment2 + Int(HelmFlatSegmentedCell.sidePadding * scale)
            let to = from + Int(6 * scale)
            func strongest(_ control: NSSegmentedControl) throws -> CGFloat {
                let row = try middleRow(control, selected: 0).row
                return row[from..<min(to, row.count)].max() ?? -1
            }
            let dotOn = try strongest(on)
            let dotOff = try strongest(off)
            XCTAssertGreaterThan(dotOn, 0.9, """
                \(name.rawValue): the enabled dot is not where the row looks (strongest alpha \(dotOn) in \
                columns \(from)..<\(to)): the disabled reading below would be read off nothing
                """)
            XCTAssertGreaterThan(dotOff, 0.2, "\(name.rawValue): the disabled dot vanished (alpha \(dotOff))")
            XCTAssertLessThan(dotOff, 0.4, """
                \(name.rawValue): the disabled dot is drawn at alpha \(dotOff), not at the disabled ink's strength \
                (about \(strength))
                """)
            // The two appearances' strengths differ by about 0.014, which the 0.05 above cannot tell apart; the dot is
            // drawn at full alpha enabled, so its disabled alpha reads the strength to within one 8-bit step.
            XCTAssertEqual(dotOff / dotOn, strength, accuracy: 0.006, """
                \(name.rawValue): the disabled dot is drawn at \(dotOff / dotOn) of the enabled one, not at this \
                appearance's strength \(strength)
                """)
        }
    }
}
