import AppKit
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The count and the "Choose…" button of the Editor tab hold their line at the width the 860 pt window gives the page
/// (646 pt), in every language: the group is drawn as wide at 646 as it is when nothing presses on it.**
///
/// The rendered page gives no control to read: SwiftUI draws the button into the hosting view's own layer, so
/// `everyView(ofType: NSButton.self)` finds none, and the accessibility tree is not populated under the suite. What can be
/// read is the ink. The same page is photographed twice, at 1200 pt, where the note beside the group has all the room it
/// wants and nothing presses on the group, and at 646 pt. In both, the columns that carry ink in the row's band are
/// taken by their distance from the card's right edge; the 900 pt photograph says how wide the group is (its leftmost
/// ink), and the 646 pt one must carry the same columns over that width. A button squeezed by its neighbour is drawn
/// narrower — its label cut to «Выб…» — and the columns of the group no longer agree.
///
/// Measured: the ink of the row's band, not a model of the widths: `ControlMetrics` is asked only to say the group is
/// at least as wide as a small button, so the reading is of a button and not of a gap.
@MainActor
final class TheChooseButtonKeepsItsLineTests: XCTestCase {

    private let pageWidth: CGFloat = 646
    private let roomyWidth: CGFloat = 1200
    private let reach = 240

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The ink columns of the tools row, by distance from the card's right edge, `reach` of them.
    private func inkByDistance(language: AppLanguage, width: CGFloat) throws -> [Bool] {
        let mount = ScreenshotsPageRender.mount(language: language, appearance: .aqua, tab: .editor, width: width)
        let lines = try XCTUnwrap(RenderedLines.read(mount.host, margin: 0), "\(language) \(width): no reading")
        let divider = try XCTUnwrap(lines.firstIndex { $0.bottom - $0.top <= 2 && $0.right - $0.left > 400 },
                                    "\(language) \(width): the card's divider between the two rows is not there")
        let row = Array(lines[(divider + 1)...])
        XCTAssertFalse(row.isEmpty, "\(language) \(width): nothing under the divider")
        let top = Int(row.map(\.top).min() ?? 0), bottom = Int(row.map(\.bottom).max() ?? 0)
        let rightEdge = Int(lines[divider].right)
        let host = mount.host
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = max(1, rep.pixelsHigh / max(1, Int(host.bounds.height)))
        let data = try XCTUnwrap(rep.bitmapData)
        func pixel(_ x: Int, _ y: Int) -> [Int] {
            (0..<3).map { Int(data[(y * scale) * rep.bytesPerRow + (x * scale) * 4 + $0]) }
        }
        let ground = pixel(rightEdge - 1, (top + bottom) / 2)
        var ink = [Bool](repeating: false, count: reach)
        for distance in 0..<reach {
            let x = rightEdge - 1 - distance
            for y in top...bottom {
                let p = pixel(x, y)
                if abs(p[0] - ground[0]) + abs(p[1] - ground[1]) + abs(p[2] - ground[2]) > 60 { ink[distance] = true; break }
            }
        }
        return ink
    }

    func testTheGroupIsAsWideAt646AsItIsWithRoomToSpareInEveryLanguage() throws {
        var failures: [String] = []
        for language in AppLanguage.allCases {
            let roomy = try inkByDistance(language: language, width: roomyWidth)
            let pressed = try inkByDistance(language: language, width: pageWidth)
            // The group is the ink from the edge to the first blank stretch of 40 columns (inside it the count and the button
            // are 21 apart); what lies beyond is the title and the note, which the roomy page keeps far off.
            var groupWidth = 0
            var blank = 0
            for (distance, on) in roomy.enumerated() {
                if on { groupWidth = distance + 1; blank = 0 } else { blank += 1 }
                if blank >= 40 { break }
            }
            // The subject happened: the roomy photograph holds a group, wider than a small button, and nothing else within reach.
            let smallest = ControlMetrics.smallButton(ScStr.choose)  // the mounts left the language set
            XCTAssertGreaterThan(CGFloat(groupWidth), smallest, "\(language): the reading found no group as wide as its button (\(groupWidth))")
            XCTAssertLessThan(groupWidth, reach - 20, "\(language): the group reaches the end of the reading: something else is in it")
            guard groupWidth < reach - 20 else { continue }
            let differing = (0..<(groupWidth + 8)).filter { roomy[$0] != pressed[$0] }
            if differing.count > 2 {
                failures.append("\(language): the group is \(groupWidth) pt at \(Int(roomyWidth)) and differs in \(differing.count) columns at \(Int(pageWidth)) (from \(differing.first ?? 0) to \(differing.last ?? 0) pt off the edge)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
