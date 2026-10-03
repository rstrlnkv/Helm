import AppKit
import Carbon.HIToolbox
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The thickness slider is marked at each of its steps (`AnnotationThickness.allCases`) and the opacity slider is not;
/// a Return or space on a highlighted item of the open menu is a choice, not a key equivalent; only the palette's grid
/// turns the black swatch white.**
///
/// The marks are plain shapes (`EditorPopover.stepMarks`), so they composite in an offscreen `NSHostingView` and are
/// **measured on the rendered card**, in both appearances and with the knob at each step: the bitmap is scanned for vertical
/// runs of ink 1 pt wide and 5 pt tall with clear columns beside them (a glyph stem is not that shape). The slider's own track
/// composites offscreen as a solid bar, which gives the rows the marks must sit between; the slider's edges are the card's
/// insets. The second half asks `isSentByAKey` of a Return and a space.
@MainActor
final class ThePopoverSliderAndTheOpenMenusReturnKeyTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// Ink is any alpha: the card has no glass offscreen, so the ground is clear.
    private struct Photo {
        let rep: NSBitmapImageRep
        let data: UnsafeMutablePointer<UInt8>
        let scale: Int

        func ink(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return false }
            return data[y * rep.bytesPerRow + x * 4 + 3] > 0
        }

        /// Runs of rows where more than half the width is ink: the two tracks.
        func bars() -> [(top: Int, bottom: Int)] {
            var out: [(top: Int, bottom: Int)] = []
            var open: Int?
            for y in 0...rep.pixelsHigh {
                let inked = y < rep.pixelsHigh ? (0..<rep.pixelsWide).filter { ink($0, y) }.count : 0
                if inked * 2 > rep.pixelsWide {
                    if open == nil { open = y }
                } else if let top = open {
                    out.append((top, y))
                    open = nil
                }
            }
            return out
        }

        /// A mark, found by its **bottom**: a run of ink `width` columns wide that ends on a row with clear ground under it and has clear
        /// columns beside it for `height` rows (one row fewer is allowed: offscreen, the knob's solid shape can touch the top row
        /// of a mark at the end steps, and a glyph's stem is wider than this). Returns the column and the row below the mark.
        func marks(width: Int, height: Int) -> [(x: Int, bottom: Int)] {
            var out: [(x: Int, bottom: Int)] = []
            for x in 1..<(rep.pixelsWide - width - 1) {
                for y in 0..<rep.pixelsHigh where ink(x, y) && !ink(x, y + 1) {
                    var rows = 0
                    while y - rows >= 0, (0..<width).allSatisfy({ ink(x + $0, y - rows) }), !ink(x - 1, y - rows), !ink(x + width, y - rows) { rows += 1 }
                    if rows == height || rows == height - 1 { out.append((x, y + 1)) }
                }
            }
            return out
        }
    }

    private func photo(thickness: AnnotationThickness, appearance: NSAppearance.Name) throws -> Photo {
        AppLanguage.override = .en
        let model = EditorBarModel()
        model.show(tool: .pen, style: AnnotationStyle(thickness: thickness), canUndo: false, canRedo: false)
        let probe = NSHostingView(rootView: EditorPopover(model: model, height: nil))
        probe.sizingOptions = [.intrinsicContentSize]
        let size = probe.fittingSize
        let mount = MountedRender(EditorPopover(model: model, height: nil), width: size.width, height: size.height, appearance: appearance)
        defer { mount.drop() }
        mount.settle(20)
        let rep = try XCTUnwrap(mount.host.bitmapImageRepForCachingDisplay(in: mount.host.bounds))
        mount.host.cacheDisplay(in: mount.host.bounds, to: rep)
        return Photo(rep: rep, data: try XCTUnwrap(rep.bitmapData), scale: max(1, rep.pixelsHigh / max(1, Int(size.height))))
    }

    func testTheThicknessSliderHasAMarkAtEachStepAndTheOpacityOneHasNone() throws {
        for appearance in RenderedInk.bothAppearances {
            for step in AnnotationThickness.allCases {
                let at = "\(RenderedInk.label(of: appearance)), step \(step)"
                let shot = try photo(thickness: step, appearance: appearance)
                let bars = shot.bars()
                XCTAssertEqual(bars.count, 2, "control: the two tracks are not both drawn (\(at)): \(bars)")
                guard bars.count == 2 else { continue }
                let s = shot.scale
                let marks = shot.marks(width: s, height: 5 * s)
                XCTAssertEqual(marks.count, 3, "one mark per step and no more, on either slider (\(at)): \(marks)")
                guard marks.count == 3 else { continue }
                // The slider's edges are the card's padding, not the bars': the knob's solid shape widens them at the end steps.
                // `inset` copies `EditorPopover.knobInset` and the `5` of `marks(width:height:)` above copies its `markHeight`, both private there.
                let left = Double(s) * (HelmSpace.s5 + HelmSpace.s1)
                let inset = 9.5 * Double(s)
                let span = Double(s) * (EditorPopover.width - 2 * (HelmSpace.s5 + HelmSpace.s1)) - 2 * inset
                for (index, mark) in marks.enumerated() {
                    let expected = left + inset + span * Double(index) / 2
                    XCTAssertEqual(Double(mark.x) + Double(s) / 2, expected, accuracy: 1.5 * Double(s), "mark \(index) is not at its step (\(at))")
                    XCTAssertGreaterThanOrEqual(mark.bottom - 5 * s, bars[0].bottom, "mark \(index) is not under the thickness track (\(at))")
                    XCTAssertLessThan(mark.bottom, bars[1].top, "mark \(index) is on the opacity slider's side of the card (\(at))")
                }
                XCTAssertEqual(Set(marks.map(\.bottom)).count, 1, "the marks are not on one line (\(at))")
            }
        }
    }

    /// The flag is the palette grid's alone: a swatch made without it, which is what the eight-inks pop-over makes, keeps its
    /// black. The unit test of `drawn` passes the flag by hand and cannot see which side the default or a call site is on.
    func testOnlyThePalettesGridTurnsBlackWhite() throws {
        XCTAssertFalse(EditorSwatch(color: .black, selected: false, press: {}).blackTurnsWhiteInDark, "the default turns black white")
        let inks = SwiftSource.uncommented(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorColoursPopover.swift"))
        XCTAssertTrue(inks.contains("EditorSwatch("), "control: the pop-over makes swatches")
        XCTAssertFalse(inks.contains("blackTurnsWhiteInDark"), "the eight-inks pop-over sets the flag")
        let grid = SwiftSource.uncommented(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift"))
        XCTAssertTrue(grid.contains("selected: model.lit == color, blackTurnsWhiteInDark: true"), "the grid's swatch does not set the flag")
    }

    /// The menu's own keyboard use: arrows to an item and Return (or space) to take it is a choice, not a letter that matched
    /// a key equivalent.
    func testReturnAndSpaceAreNotDroppedAsAKeyEquivalent() {
        XCTAssertFalse(EditorMenu.isSentByAKey(key(kVK_Return, "\r")), "Return on a highlighted item is dropped")
        XCTAssertFalse(EditorMenu.isSentByAKey(key(kVK_Space, " ")), "space on a highlighted item is dropped")
        XCTAssertFalse(EditorMenu.isSentByAKey(nil), "no event")
    }

    private func key(_ code: Int, _ characters: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: UInt16(code))!
    }

    /// Inputs the rule was not first written for. Every letter of `EditorKeys.toolKeys` is dropped however it was typed
    /// (Shift, Command, capital); a letter outside that table, an empty string and the same key codes in a Cyrillic layout
    /// are not a key equivalent of any item, so there is nothing for the guard to drop and nothing it can fire.
    func testTheRuleOnShiftedCommandedForeignAndEmptyKeys() {
        for entry in EditorKeys.toolKeys {
            let lower = entry.letter.lowercased()
            XCTAssertTrue(EditorMenu.isSentByAKey(key(entry.code, lower)), "\(lower)")
            XCTAssertTrue(EditorMenu.isSentByAKey(key(entry.code, entry.letter.uppercased(), flags: .shift)), "shift \(lower)")
            XCTAssertTrue(EditorMenu.isSentByAKey(key(entry.code, lower, flags: .command)), "command \(lower)")
        }
        XCTAssertFalse(EditorMenu.isSentByAKey(key(kVK_ANSI_X, "x")), "a letter that is no tool key")
        XCTAssertFalse(EditorMenu.isSentByAKey(key(kVK_ANSI_A, "ф")), "Cyrillic on the A key: no item shows it")
        XCTAssertFalse(EditorMenu.isSentByAKey(key(kVK_ANSI_R, "к")), "Cyrillic on the R key")
        XCTAssertFalse(EditorMenu.isSentByAKey(key(kVK_ANSI_A, "")), "empty characters")
        let click = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: .command, timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        XCTAssertFalse(EditorMenu.isSentByAKey(click), "a click with Command held is a choice")
    }
}
