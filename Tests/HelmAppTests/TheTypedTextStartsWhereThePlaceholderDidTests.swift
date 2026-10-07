import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **In the page bar's search zone the typed text starts where the placeholder started, and never over the
/// magnifier.**
///
/// The field is borderless with no background. A bare borderless `NSSearchField` gives its field editor the
/// field's whole bounds, where the label (the placeholder, and the text of a field with no editor) sits 25 pt
/// in, after the glyph. So the line jumps left by about the glyph's width when editing starts, and the typed
/// letters are drawn over the glyph. Three claims, each read from the window's own bitmap (the theme frame's
/// `cacheDisplay` of a window that was never ordered, in a named appearance, taken twice):
///
/// - (a) with an editor and typed text, the left edge of the typed text's ink is where the placeholder's ink
///   began at rest, within 1 pt (the placeholder and the text start with the same letter, so their side
///   bearings are the same; 1 pt is two pixels at 2x, and the two reads of one state are required to agree
///   exactly);
/// - (b) with an editor and typed text, no pixel in the magnifier button's columns, less 3 pt at each side,
///   is further than the threshold from the same field with an editor holding one space, so nothing typed overlaps
///   the glyph;
/// - (c) beginning to edit moves nothing: text set through the page's binding with no editor, then the
///   editor taken, leaves the text's ink at the same left edge, within 1 pt.
///
/// The three reach the editor by `makeFirstResponder`, which goes through the cell's `select(withFrame:…)` and
/// never through `edit(withFrame:…)`. A fourth row repeats (a) and (b) with `edit(withFrame:…)` called on the
/// cell directly; no row shows that a press reaches that call.
///
/// **Typed ink is told from the glyph by a difference, not by a region.** A text drawn over the glyph cannot
/// be cut away from it by columns, so the typed text's ink is the pixels that differ from the same field,
/// with the same editor holding one space, which hides the placeholder and draws no ink. A row that finds the editor missing, no differing pixel or no
/// placeholder ink fails: nothing is claimed from a measurement that did not happen. The window is not key:
/// nothing here says how a key window draws.
@MainActor
final class TheTypedTextStartsWhereThePlaceholderDidTests: XCTestCase {

    private static let typed = "Se"           // the placeholder is "Search packages": the same first letter
    private static let blank = " "           // hides the placeholder and draws no ink: the baseline of a difference
    private static let threshold = 30
    private static let tolerance: CGFloat = 1

    private var saved: [String: Any?] = [:]
    private static let keys = ["module.app.\(PageBarStyle.storageKey)"]
    override func setUp() {
        super.setUp()
        for key in Self.keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.removeObject(forKey: Self.keys[0])
    }
    override func tearDown() {
        for key in Self.keys {
            if let found = saved[key] ?? nil { UserDefaults.standard.set(found, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        saved = [:]
        super.tearDown()
    }

    // MARK: - Reading a window

    @MainActor private struct Photo {
        let rep: NSBitmapImageRep
        let scale: CGFloat

        init?(_ view: NSView) {
            guard view.bounds.width > 0, view.bounds.height > 0,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard rep.bitmapData != nil, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
            self.rep = rep
            scale = CGFloat(rep.pixelsWide) / view.bounds.width
        }

        private func pixel(_ x: Int, _ y: Int) -> [Int] {
            guard let data = rep.bitmapData else { return [0, 0, 0, 0] }
            let at = y * rep.bytesPerRow + x * 4
            return (0..<4).map { Int(data[at + $0]) }
        }

        private func box(_ columns: ClosedRange<CGFloat>, _ rows: ClosedRange<CGFloat>) -> (x: Range<Int>, y: Range<Int>)? {
            let x0 = max(0, Int((columns.lowerBound * scale).rounded())), x1 = min(rep.pixelsWide, Int((columns.upperBound * scale).rounded()))
            let y0 = max(0, Int((rows.lowerBound * scale).rounded())), y1 = min(rep.pixelsHigh, Int((rows.upperBound * scale).rounded()))
            return x0 < x1 && y0 < y1 ? (x0..<x1, y0..<y1) : nil
        }

        /// The columns (points) holding a pixel further than `threshold` from `against`'s pixel at the same
        /// place, or, with none given, from the region's own most common pixel; nil when no pixel is.
        func inkColumns(_ columns: ClosedRange<CGFloat>, _ rows: ClosedRange<CGFloat>, threshold: Int,
                        against other: Photo? = nil) -> ClosedRange<CGFloat>? {
            guard let (xs, ys) = box(columns, rows) else { return nil }
            if let other, other.rep.pixelsWide != rep.pixelsWide || other.rep.pixelsHigh != rep.pixelsHigh { return nil }
            var ground: [Int] = []
            if other == nil {
                var counts: [[Int]: Int] = [:]
                for y in ys { for x in xs { counts[pixel(x, y), default: 0] += 1 } }
                guard let modal = counts.max(by: { ($0.value, $0.key.description) < ($1.value, $1.key.description) })?.key else { return nil }
                ground = modal
            }
            var first: Int?, last: Int?
            for x in xs {
                for y in ys {
                    let base = other?.pixel(x, y) ?? ground
                    let here = pixel(x, y)
                    if (0..<4).contains(where: { abs(here[$0] - base[$0]) > threshold }) {
                        if first == nil { first = x }
                        last = x
                        break
                    }
                }
            }
            guard let first, let last else { return nil }
            return (CGFloat(first) / scale)...(CGFloat(last + 1) / scale)
        }
    }

    private func topDown(_ rect: CGRect, of view: NSView, in target: NSView) -> CGRect {
        let r = view.convert(rect, to: target)
        return target.isFlipped ? r : CGRect(x: r.minX, y: target.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    private func all<T: NSView>(_ type: T.Type, under view: NSView) -> [T] {
        var out: [T] = []
        for sub in view.subviews {
            if let hit = sub as? T { out.append(hit) }
            out += all(type, under: sub)
        }
        return out
    }

    private func settle(_ rig: SettingsWindowRig, _ seconds: TimeInterval = 0.35) {
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(seconds)
        rig.window.contentView?.layoutSubtreeIfNeeded()
        rig.window.displayIfNeeded()
    }

    /// The Settings window with a page that has a search whose text is `text`, in a named appearance.
    private func freshRig(_ appearance: NSAppearance.Name, text: String) -> SettingsWindowRig? {
        guard let rig = SettingsWindowRig.build(in: self, failure: "the window has no shell: no bar was read") else { return nil }
        AppSettings.pageBarStyle = .moduleName
        rig.window.appearance = NSAppearance(named: appearance)
        rig.window.setContentSize(NSSize(width: 1060, height: 760))
        rig.pageBar?.setWindowAppearsActive(true)
        let base = SettingsWindowRig.content(search: true)
        let content = HelmPageToolbarContent(
            tabs: base.tabs, selectedTab: .constant("installed"), actions: base.actions,
            search: HelmToolbarSearch(prompt: "Search packages", text: .constant(text)))
        rig.model.selection = .module("homebrew")
        rig.channel.declare(content, token: "homebrew", generation: rig.channel.nextGeneration())
        settle(rig)
        return rig
    }

    private struct Zone {
        let field: NSSearchField
        let target: NSView
        let fieldRect: CGRect
        let barRows: ClosedRange<CGFloat>
        let glyphColumns: ClosedRange<CGFloat>
        let labelColumns: ClosedRange<CGFloat>
    }

    /// The field, the theme frame and the columns of the glyph and of the label, in points from the frame's top left.
    private func zone(_ rig: SettingsWindowRig, _ label: String) -> Zone? {
        guard let bar = rig.pageBar?.view, let target = rig.window.contentView?.superview,
              let plate = bar.view(for: .search), !plate.isHidden,
              let field = all(NSSearchField.self, under: plate).first, !field.isHidden else {
            XCTFail("\(label): the search zone shows no field: nothing was measured"); return nil
        }
        let glyphs = all(NSButton.self, under: field)
        let labels = field.subviews.filter { !($0 is NSButton) && !($0 is NSClipView) }
        guard let glyph = glyphs.first, let text = labels.first else {
            XCTFail("\(label): the field holds \(labels.count) label views and \(glyphs.count) buttons: no placeholder or no magnifier to measure"); return nil
        }
        let bars = topDown(bar.bounds, of: bar, in: target)
        let fieldRect = topDown(field.bounds, of: field, in: target)
        let glyphRect = topDown(glyph.bounds, of: glyph, in: target)
        let textRect = topDown(text.bounds, of: text, in: target)
        return Zone(field: field, target: target, fieldRect: fieldRect, barRows: bars.minY...bars.maxY,
                    glyphColumns: (glyphRect.minX + 3)...(glyphRect.maxX - 3),
                    labelColumns: max(textRect.minX, glyphRect.maxX + 2)...(min(textRect.maxX, fieldRect.minX + 150)))
    }

    /// Takes the editor and puts the caret at the end, so no selection is drawn over the text.
    private func edit(_ rig: SettingsWindowRig, _ zone: Zone, _ label: String) -> NSText? {
        XCTAssertTrue(rig.window.makeFirstResponder(zone.field), "\(label): the window refused the field an editor")
        settle(rig)
        guard let editor = zone.field.currentEditor() else {
            XCTFail("\(label): the field has no editor: nothing was measured"); return nil
        }
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        return editor
    }

    /// How the field is given its editor: by becoming first responder, or by the cell's `edit(withFrame:…)`.
    private enum EditorRoute { case firstResponder, cellEdit }

    /// Calls the cell's `edit(withFrame:…)` with the field's bounds. No row shows that a press reaches this
    /// call: a synthesised press gave the field no editor in a window that is never shown.
    private func cellEdit(_ rig: SettingsWindowRig, _ zone: Zone, _ label: String) -> NSText? {
        rig.window.makeFirstResponder(nil)
        guard let cell = zone.field.cell, let editor = rig.window.fieldEditor(true, for: zone.field) else {
            XCTFail("\(label): the field has no cell or the window no field editor: nothing was measured"); return nil
        }
        cell.edit(withFrame: zone.field.bounds, in: zone.field, editor: editor, delegate: zone.field, event: nil)
        settle(rig)
        guard zone.field.currentEditor() != nil else {
            XCTFail("\(label): the cell gave the field no editor: nothing was measured"); return nil
        }
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        return editor
    }

    private func photographs(_ zone: Zone, _ label: String) -> (Photo, Photo)? {
        guard let one = Photo(zone.target), let two = Photo(zone.target) else {
            XCTFail("\(label): the window gave no bitmap: nothing was measured"); return nil
        }
        return (one, two)
    }

    /// The columns the typed text's ink covers: the pixels that differ from the same field, edited, holding one space.
    private func typedInk(_ rig: SettingsWindowRig, _ appearance: NSAppearance.Name, entering: EditorRoute = .firstResponder) -> (typed: ClosedRange<CGFloat>, glyphDiff: ClosedRange<CGFloat>?, placeholder: ClosedRange<CGFloat>, glyph: ClosedRange<CGFloat>)? {
        let label = RenderedInk.label(of: appearance)
        guard let z = zone(rig, label), let rest = photographs(z, label) else { return nil }
        guard let placeholder = rest.0.inkColumns(z.labelColumns, z.barRows, threshold: Self.threshold),
              let again = rest.1.inkColumns(z.labelColumns, z.barRows, threshold: Self.threshold) else {
            XCTFail("\(label): the placeholder drew no ink at rest: nothing was measured"); return nil
        }
        XCTAssertEqual(placeholder.lowerBound, again.lowerBound, "\(label): two reads of the placeholder differ")
        guard let editor = (entering == .firstResponder ? edit(rig, z, label) : cellEdit(rig, z, label)) else { return nil }
        guard let view = editor as? NSTextView else { XCTFail("\(label): the editor is not a text view"); return nil }
        view.string = Self.blank
        view.setSelectedRange(NSRange(location: 1, length: 0))
        settle(rig)
        guard let empty = photographs(z, label) else { return nil }
        view.setSelectedRange(NSRange(location: 0, length: 1))
        view.insertText(Self.typed, replacementRange: view.selectedRange())
        settle(rig)
        guard (zone(rig, label)) != nil, let full = photographs(z, label) else { return nil }
        XCTAssertEqual(z.field.currentEditor()?.string, Self.typed, "\(label): the editor does not hold what was typed")
        let columns = (z.fieldRect.minX)...(min(z.fieldRect.maxX - 40, z.fieldRect.minX + 150))
        guard let typed = full.0.inkColumns(columns, z.barRows, threshold: Self.threshold, against: empty.0),
              let again = full.1.inkColumns(columns, z.barRows, threshold: Self.threshold, against: empty.1) else {
            XCTFail("\(label): the typed text drew no ink that differs from the empty editor: nothing was measured"); return nil
        }
        XCTAssertEqual(typed.lowerBound, again.lowerBound, "\(label): two reads of the typed text differ")
        XCTAssertLessThan(typed.upperBound - typed.lowerBound, 40,
            "\(label): the difference is \(typed.upperBound - typed.lowerBound) pt wide, too wide for \"\(Self.typed)\": it is not the typed text alone")
        let glyphDiff = full.0.inkColumns(z.glyphColumns, z.barRows, threshold: Self.threshold, against: empty.0)
        print("TYPEDINK \(label) | typed ink x \(typed.lowerBound)...\(typed.upperBound) | glyph columns \(z.glyphColumns.lowerBound)...\(z.glyphColumns.upperBound) | typed ink inside them \(glyphDiff.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "none") | placeholder ink starts \(placeholder.lowerBound) | field x \(z.fieldRect.minX)...\(z.fieldRect.maxX)")
        return (typed, glyphDiff, placeholder, z.glyphColumns)
    }

    // MARK: - (a) and (b)

    func testTheTypedTextsInkBeginsWhereThePlaceholdersInkBegan() {
        for appearance in RenderedInk.bothAppearances {
            guard let rig = freshRig(appearance, text: ""), let read = typedInk(rig, appearance) else { return }
            let label = RenderedInk.label(of: appearance)
            XCTAssertEqual(read.typed.lowerBound, read.placeholder.lowerBound, accuracy: Self.tolerance,
                "\(label): the typed text's ink begins at x \(read.typed.lowerBound), the placeholder's began at x \(read.placeholder.lowerBound): the line jumped \(read.placeholder.lowerBound - read.typed.lowerBound) pt left when editing began")
        }
    }

    func testNothingTypedIsDrawnOverTheMagnifier() {
        for appearance in RenderedInk.bothAppearances {
            guard let rig = freshRig(appearance, text: ""), let read = typedInk(rig, appearance) else { return }
            let label = RenderedInk.label(of: appearance)
            XCTAssertNil(read.glyphDiff,
                "\(label): typed ink reaches the magnifier's columns \(read.glyph.lowerBound)...\(read.glyph.upperBound), at x \(read.glyphDiff.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "")")
        }
    }

    // MARK: - (a) and (b) through the cell's edit

    /// The cell's `edit(withFrame:…)`, called directly, places the editor by its own override. `makeFirstResponder`
    /// reaches the editor through `select(withFrame:…)` and does not call it; no row shows that a press does.
    func testTheTypedTextStartsWhereThePlaceholderDidWhenTheCellEdits() {
        for appearance in RenderedInk.bothAppearances {
            guard let rig = freshRig(appearance, text: ""), let read = typedInk(rig, appearance, entering: .cellEdit) else { return }
            let label = RenderedInk.label(of: appearance)
            XCTAssertEqual(read.typed.lowerBound, read.placeholder.lowerBound, accuracy: Self.tolerance,
                "\(label): after the cell edited the typed text's ink begins at x \(read.typed.lowerBound), the placeholder's began at x \(read.placeholder.lowerBound)")
            XCTAssertNil(read.glyphDiff, "\(label): after the cell edited typed ink reaches the magnifier's columns")
        }
    }

    // MARK: - (c)

    func testBeginningToEditMovesNoInk() {
        for appearance in RenderedInk.bothAppearances {
            let label = RenderedInk.label(of: appearance)
            guard let rig = freshRig(appearance, text: Self.typed) else { return }
            guard let z = zone(rig, label) else { return }
            XCTAssertNil(z.field.currentEditor(), "\(label): precondition: the field already has an editor")
            XCTAssertEqual(z.field.stringValue, Self.typed, "\(label): precondition: the binding's text did not reach the field")
            guard let before = photographs(z, label),
                  let resting = before.0.inkColumns(z.labelColumns, z.barRows, threshold: Self.threshold),
                  let restingAgain = before.1.inkColumns(z.labelColumns, z.barRows, threshold: Self.threshold) else {
                XCTFail("\(label): the resting text drew no ink: nothing was measured"); return
            }
            XCTAssertEqual(resting.lowerBound, restingAgain.lowerBound, "\(label): two reads of the resting text differ")
            // The same text, edited, against the same editor holding one space: the difference is the text.
            guard let editor = edit(rig, z, label), let withText = photographs(z, label) else { return }
            let saved = editor.string
            editor.string = Self.blank
            settle(rig)
            guard let without = photographs(z, label) else { return }
            XCTAssertEqual(saved, Self.typed, "\(label): the editor did not take the field's text")
            let columns = (z.fieldRect.minX)...(min(z.fieldRect.maxX - 40, z.fieldRect.minX + 150))
            guard let editing = withText.0.inkColumns(columns, z.barRows, threshold: Self.threshold, against: without.0) else {
                XCTFail("\(label): the edited text drew no ink that differs from the empty editor: nothing was measured"); return
            }
            XCTAssertLessThan(editing.upperBound - editing.lowerBound, 40,
                "\(label): the difference is \(editing.upperBound - editing.lowerBound) pt wide, too wide for \"\(Self.typed)\": it is not the text alone")
            print("EDITMOVE \(label) | resting text ink starts \(resting.lowerBound) | edited text ink starts \(editing.lowerBound)")
            XCTAssertEqual(editing.lowerBound, resting.lowerBound, accuracy: Self.tolerance,
                "\(label): the text's ink began at x \(resting.lowerBound) with no editor and at x \(editing.lowerBound) with one: beginning to edit moved it \(resting.lowerBound - editing.lowerBound) pt left")
        }
    }
}
