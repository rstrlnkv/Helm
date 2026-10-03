import HelmTestSupport
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The chosen object is drawn 10 pt higher than the same object not chosen — read off the pixels.** The source scan
/// next door only proves the file spells a 10; this renders `PaletteObject` both ways, in both appearances, and finds
/// the topmost row of ink. The mount starts in its final state, so no travel is in flight and the reading is the
/// resting place, which is what Reduce Motion shows at once as well.
final class ThePaletteObjectStandsTenPointsHigherTests: XCTestCase {
    private let room: CGFloat = 24

    @MainActor private func topInkRow(tool: AnnotationTool, raised: Bool, appearance: NSAppearance.Name) throws -> Int {
        let height = Int(room + EditorPalette.height)
        let mount = MountedRender(
            VStack(spacing: 0) {
                Color.clear.frame(height: room)
                PaletteObject(tool: tool, ink: .red, raised: raised)
            },
            width: 60, height: CGFloat(height), appearance: appearance)
        defer { mount.drop() }
        mount.settle(10)
        let whole = try XCTUnwrap(mount.ink(0...height), "\(tool): nothing read")
        XCTAssertGreaterThan(whole, 0, "\(tool) raised=\(raised): nothing was drawn")
        // The shadows (6 % and 8 % black, blurred) reach several points past the object and move with it, but they are
        // faint: the object's edge is the first row carrying a quarter of the densest row's ink.
        let rows = try (0..<height).map { try XCTUnwrap(mount.ink($0...($0 + 1))) }
        let densest = try XCTUnwrap(rows.max())
        return try XCTUnwrap(rows.firstIndex { $0 * 4 >= densest }, "\(tool) raised=\(raised): no row carries ink")
    }

    @MainActor func testTheRaisedObjectStandsTenPointsAboveTheRestingOne() throws {
        for appearance in RenderedInk.bothAppearances {
            for tool in [AnnotationTool.pen, .highlighter, .pencil] {
                let resting = try topInkRow(tool: tool, raised: false, appearance: appearance)
                let raised = try topInkRow(tool: tool, raised: true, appearance: appearance)
                XCTAssertEqual(resting - raised, 10, accuracy: 1,
                               "\(tool), \(RenderedInk.label(of: appearance)): resting top \(resting), raised top \(raised)")
            }
        }
    }
}
