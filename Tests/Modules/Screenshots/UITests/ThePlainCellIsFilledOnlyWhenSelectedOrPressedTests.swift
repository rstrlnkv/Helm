import AppKit
import SwiftUI
import HelmUI
import XCTest
@testable import Module_Screenshots_UI

/// **A plain cell is filled when it is selected or pressed and in no other case, and the other looks are as they were.**
/// `GlassCell` draws the capture panel's mode cells and gear and the editor's palette, and `pressed` was the grey
/// circle's alone until the gear's open menu asked it of a plain cell. A cell with no `pressed` argument and one with
/// `pressed: false` are drawn the same and empty; a selected one and a pressed one carry the same 14 % of the primary
/// colour, neither doubled by both. Read from the pixels beside the glyph, in both appearances (named, never inherited),
/// each cell drawn twice.
@MainActor
final class ThePlainCellIsFilledOnlyWhenSelectedOrPressedTests: XCTestCase {

    /// Opacity of what is drawn at a point near the cell's left edge, midway up: the fill and nothing of the glyph.
    private func alpha(_ cell: some View, appearance: NSAppearance.Name, at x: Int = 3, y: Int = 17) throws -> Int {
        let named = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: cell.frame(width: 44, height: 35))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 44, height: 35), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = named
        window.contentView = host
        host.appearance = named
        host.frame = NSRect(x: 0, y: 0, width: 44, height: 35)
        window.layoutIfNeeded()
        for _ in 0..<5 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        // The bitmap is in pixels, the point in points: a window that is not on a screen may still draw at 2x.
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        return Int(((rep.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?.alphaComponent ?? -1) * 255).rounded())
    }

    private func plain(selected: Bool = false, pressed: Bool? = nil) -> some View {
        if let pressed {
            return AnyView(GlassCell(name: "x", selected: selected, width: 44, height: 35, pressed: pressed, action: {}) { Color.clear.frame(width: 1, height: 1) })
        }
        return AnyView(GlassCell(name: "x", selected: selected, width: 44, height: 35, action: {}) { Color.clear.frame(width: 1, height: 1) })
    }

    func testAPlainCellWithNoPressedArgumentAndOneWithPressedFalseAreDrawnEmpty() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for _ in 0..<2 {
                XCTAssertEqual(try alpha(plain(), appearance: appearance), 0, "\(appearance.rawValue): a plain cell with no pressed argument is filled")
                XCTAssertEqual(try alpha(plain(pressed: false), appearance: appearance), 0, "\(appearance.rawValue): pressed: false filled a plain cell")
            }
        }
    }

    func testAPressedPlainCellAndASelectedOneCarryTheSameFillAndBothDoNotDoubleIt() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let selected = try alpha(plain(selected: true), appearance: appearance)
            let pressed = try alpha(plain(pressed: true), appearance: appearance)
            let both = try alpha(plain(selected: true, pressed: true), appearance: appearance)
            XCTAssertTrue((30...42).contains(selected), "\(appearance.rawValue): a selected cell is drawn at \(selected)/255, not 14 %")
            XCTAssertEqual(pressed, selected, accuracy: 2, "\(appearance.rawValue): a pressed plain cell is not filled as a selected one is")
            XCTAssertEqual(both, selected, accuracy: 2, "\(appearance.rawValue): selected and pressed doubled the fill")
        }
    }

    /// The grey circle: unpressed it is the panel's fill, pressed the opaque ink — as it was before the plain look took `pressed`.
    func testTheGreyCircleIsUnchangedAndTheOtherLooksIgnorePressed() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            func circle(_ pressed: Bool) throws -> Int {
                try alpha(GlassCell(name: "x", look: .greyCircle, width: 35, height: 35, pressed: pressed, action: {}) { Color.clear.frame(width: 1, height: 1) },
                          appearance: appearance, at: 22, y: 6)
            }
            let idle = try circle(false), pressed = try circle(true)
            XCTAssertEqual(pressed, 255, "\(appearance.rawValue): a pressed grey circle is not opaque")
            XCTAssertLessThan(idle, 255, "\(appearance.rawValue): an unpressed grey circle is as opaque as a pressed one")
            XCTAssertGreaterThan(idle, 0, "\(appearance.rawValue): the grey circle is not drawn")
            func bare(_ pressed: Bool) throws -> Int {
                try alpha(GlassCell(name: "x", look: .bare, width: 35, height: 35, pressed: pressed, action: {}) { Color.clear.frame(width: 1, height: 1) },
                          appearance: appearance, at: 22, y: 6)
            }
            func accent(_ pressed: Bool) throws -> Int {
                try alpha(GlassCell(name: "x", look: .accent, width: 35, height: 35, pressed: pressed, action: {}) { Color.clear.frame(width: 1, height: 1) },
                          appearance: appearance, at: 22, y: 6)
            }
            XCTAssertEqual(try bare(true), try bare(false), "\(appearance.rawValue): the bare look changed with pressed")
            XCTAssertEqual(try accent(true), try accent(false), "\(appearance.rawValue): the accent look changed with pressed")
            XCTAssertEqual(try bare(false), 0)
            XCTAssertEqual(try accent(false), 255)
        }
    }
}
