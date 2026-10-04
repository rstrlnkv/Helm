import AppKit
import CoreGraphics
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«N more» is one line at its own width in every language, whatever the shot it stands on; and the row's mask
/// cuts the rings of the shots beyond its ends without leaving a white sliver of one.** Read here off a rendering of
/// `ShotToastView` in-process (an offscreen host, appearance named, the toast's own model): the label's ink against
/// the text's natural width, the far shot's ring and its neighbour's against the label, and the rings across a row
/// of seven at every rest.
///
/// **What an offscreen render does not hold:** glass never composites there, so the capsule behind the label is not
/// in the picture. The label's ink is, and the capsule is that ink plus the label's own padding (`HelmSpace.s4`
/// either side), which is how its edges are reckoned. The label is found as the difference between the same row of
/// seven rendered with it and the three newest alone, which have none. The mask's left edge is where the render
/// of the row of seven begins to have any pixel at the middle of the rings (a shadow, which the mask cuts).
///
/// **One test here is red on purpose** (`testTheMasksLeftEdgeLeavesTheLabelsCapsuleWhole`): the defect it names is in
/// the toast's view and is not repaired by a test.
///
/// Total failure of the subject prints: a label broken onto two lines or cut to an ellipsis in one language, a ring
/// column that stands at the mask's edge, a render in which the label is not found at all.
@MainActor
final class TheMoreLabelStandsInOneLineAndTheRowsEdgeDrawsNoSliverTests: XCTestCase {

    private struct Picture {
        let rgba: [UInt8], width: Int, height: Int, scale: Int
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let at = (y * width + x) * 4
            return (Int(rgba[at]), Int(rgba[at + 1]), Int(rgba[at + 2]), Int(rgba[at + 3]))
        }
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let p = pixel(x, y)
            return p.a >= 250 && p.r >= 250 && p.g >= 250 && p.b >= 250
        }
    }

    private func photograph(_ model: ShotToastModel, width: CGFloat = 760, height: CGFloat = 330) throws -> Picture {
        let mount = MountedRender(ShotToastView(model: model), width: width, height: height, appearance: .aqua)
        mount.settle(20)
        let host = mount.host
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "no bitmap")
        host.cacheDisplay(in: host.bounds, to: rep)
        XCTAssertEqual(rep.samplesPerPixel, 4)
        XCTAssertEqual(rep.bitsPerSample, 8)
        let data = try XCTUnwrap(rep.bitmapData)
        let rowBytes = rep.pixelsWide * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rowBytes { bytes[y * rowBytes + x] = data[y * rep.bytesPerRow + x] }
        }
        return Picture(rgba: bytes, width: rep.pixelsWide, height: rep.pixelsHigh,
                       scale: max(1, rep.pixelsWide / Int(host.bounds.width)))
    }

    /// The row: `count` shots, the three newest named; the far one seen (age 2) of this picture width, the others 200.
    private func row(farWidth: Int, farHeight: Int? = nil, count: Int = 7, offset: CGFloat = 0,
                     newestOnly: Bool = false) throws -> ShotToastModel {
        let model = ShotToastModel()
        let wide = try ShotToastRig.picture(width: 520, height: 300)
        let far = try ShotToastRig.picture(width: farWidth, height: farHeight ?? (farWidth < 100 ? 120 : 100))
        if !newestOnly { for _ in 0..<(count - 3) { model.add(wide, caption: "old", file: nil) } }
        model.add(far, caption: "far", file: nil)
        model.add(wide, caption: "mid", file: nil)
        model.add(wide, caption: "new", file: nil)
        model.unfolded = true
        model.offset = offset
        model.shown = true
        model.hovering = false
        return model
    }

    /// The extent of what differs between two photographs, in points: the label's ink.
    private func ink(_ with: Picture, _ without: Picture) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat)? {
        XCTAssertEqual(with.width, without.width)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<with.height {
            for x in 0..<with.width {
                let a = with.pixel(x, y), b = without.pixel(x, y)
                let far = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
                guard far >= 90 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let s = CGFloat(with.scale)
        return (CGFloat(minX) / s, CGFloat(maxX + 1) / s, CGFloat(minY) / s, CGFloat(maxY + 1) / s)
    }

    /// The runs of white along one row of pixels, in points: the rings' sides.
    private func whiteRuns(_ picture: Picture, atRow y: Int) -> [(from: CGFloat, to: CGFloat)] {
        var runs: [(from: CGFloat, to: CGFloat)] = []
        var start: Int?
        let s = CGFloat(picture.scale)
        for x in 0...picture.width {
            let white = x < picture.width && picture.isWhite(x, y)
            if white, start == nil { start = x }
            if !white, let from = start { runs.append((CGFloat(from) / s, CGFloat(x) / s)); start = nil }
        }
        return runs.filter { $0.to - $0.from >= 1 && $0.to - $0.from <= 6 }
    }

    private func naturalWidth(of text: String) -> CGFloat {
        let base = NSFont.preferredFont(forTextStyle: .callout)
        let font = NSFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    /// The ring of the shot of this width: the picture, three points of white each side.
    private func ring(_ pictureWidth: Int) -> CGFloat { CGFloat(min(pictureWidth, 200) + 6) }

    /// A row of the photograph of the three newest alone that crosses the three rings' sides.
    private func middleRow(of picture: Picture) -> Int {
        let rows = (0..<picture.height).filter { whiteRuns(picture, atRow: $0).count >= 6 }
        return rows.isEmpty ? 0 : rows[rows.count / 2]
    }

    private struct Reading {
        var inkLeft: CGFloat, inkRight: CGFloat, inkTop: CGFloat, inkBottom: CGFloat
        var farRingLeft: CGFloat, nextRingLeft: CGFloat, nextRingTop: CGFloat, maskLeft: CGFloat
        var natural: CGFloat
    }

    private func read(farWidth: Int, n: Int, alone: Picture, aloneRow: Int) throws -> Reading {
        let with = try photograph(try row(farWidth: farWidth, count: n + 3))
        let found = try XCTUnwrap(ink(with, alone), "the label was not found in the render of \(n) more on a shot \(farWidth) wide")
        let y = aloneRow // a pixel row already, as `middleRow` counts them
        var maskX = 0
        while maskX < with.width, with.pixel(maskX, y).a == 0 { maskX += 1 }
        let runs = whiteRuns(alone, atRow: aloneRow)
        XCTAssertGreaterThanOrEqual(runs.count, 6, "the control: the three rings are in the render of the newest alone")
        // The next ring's top, where its left side first turns white (its corner is round, so a point in).
        let probe = Int((runs.count > 2 ? runs[2].from + 1.5 : 0) * CGFloat(alone.scale))
        let top = (0..<alone.height).first { alone.isWhite(probe, $0) } ?? 0
        return Reading(inkLeft: found.left, inkRight: found.right, inkTop: found.top, inkBottom: found.bottom,
                       farRingLeft: runs.first?.from ?? 0, nextRingLeft: runs.count > 2 ? runs[2].from : 0,
                       nextRingTop: CGFloat(top) / CGFloat(alone.scale),
                       maskLeft: CGFloat(maskX) / CGFloat(with.scale), natural: naturalWidth(of: ScStr.more(n)))
    }

    private func readings(farWidth: Int, n: Int, alone: Picture, aloneRow: Int) throws -> [(AppLanguage, Reading)] {
        var out: [(AppLanguage, Reading)] = []
        var thrown: Error?
        AppLanguage.each { language in
            do { out.append((language, try read(farWidth: farWidth, n: n, alone: alone, aloneRow: aloneRow))) }
            catch { thrown = error }
        }
        if let thrown { throw thrown }
        return out
    }

    // MARK: One line, at its own width

    func testTheLabelIsOneUntruncatedLineInEveryLanguageOnAShotOfAnyWidth() throws {
        for farWidth in [36, 200] {
            let alone = try photograph(try row(farWidth: farWidth, newestOnly: true))
            let aloneRow = middleRow(of: alone)
            for n in [1, 9, 17] {
                let all = try readings(farWidth: farWidth, n: n, alone: alone, aloneRow: aloneRow)
                XCTAssertEqual(all.count, AppLanguage.allCases.count)
                var failures: [String] = []
                for (language, r) in all {
                    let width = r.inkRight - r.inkLeft, height = r.inkBottom - r.inkTop
                    if width < r.natural - 4 { failures.append("\(language): ink \(width) pt of a text \(r.natural) pt: truncated") }
                    if width > r.natural + 3 { failures.append("\(language): ink \(width) pt of a text \(r.natural) pt: more than the text") }
                    if height > 20 { failures.append("\(language): ink \(height) pt high: two lines") }
                }
                XCTAssertTrue(failures.isEmpty, "N = \(n), a shot \(farWidth) pt wide: \(failures.sorted())")
            }
        }
    }

    private struct Placement {
        var report: [String] = [], covered: [String] = [], textCut: [String] = [], capsuleCut: [String] = [], overlapped: [String] = []
    }

    /// Where the label stands against the next shot's ring and the mask's left edge, in every language, for the
    /// numbers of the report; read once for the tests below (it is 96 renders).
    private static var placed: Placement?

    private func placement() throws -> Placement {
        if let placed = Self.placed { return placed }
        var out = Placement()
        for farWidth in [36, 200] {
            let alone = try photograph(try row(farWidth: farWidth, newestOnly: true))
            let aloneRow = middleRow(of: alone)
            for n in [1, 9, 17] {
                for (language, r) in try readings(farWidth: farWidth, n: n, alone: alone, aloneRow: aloneRow) {
                    let capsuleLeft = r.inkLeft - HelmSpace.s4, capsuleRight = r.inkRight + HelmSpace.s4
                    let tag = "\(language) N=\(n) ring \(ring(farWidth))"
                    out.report.append("\(tag): capsule \(capsuleLeft)...\(capsuleRight), far ring from \(r.farRingLeft), next ring from \(r.nextRingLeft), mask from \(r.maskLeft)")
                    // The text is covered where it stands past the next ring's left side and lower than its top.
                    if r.inkRight > r.nextRingLeft, r.inkBottom > r.nextRingTop {
                        out.covered.append("\(tag): text to \(r.inkRight) down to \(r.inkBottom), the next ring from \(r.nextRingLeft) down from \(r.nextRingTop)")
                    }
                    if capsuleRight > r.nextRingLeft {
                        out.overlapped.append("\(tag): capsule to \(capsuleRight), \(capsuleRight - r.nextRingLeft) pt past the next ring's left side")
                    }
                    if capsuleLeft < r.maskLeft - 0.5 {
                        out.capsuleCut.append("\(tag): capsule from \(capsuleLeft), mask from \(r.maskLeft): \(r.maskLeft - capsuleLeft) pt of it cut")
                    }
                    if r.inkLeft < r.maskLeft - 0.5 { out.textCut.append("\(tag): TEXT from \(r.inkLeft), mask from \(r.maskLeft)") }
                }
            }
        }
        print("MORE-LABEL REPORT\n" + out.report.joined(separator: "\n"))
        print("MORE-LABEL CAPSULE PAST THE NEXT RING (reported, not asserted: glass is not in the render)\n" + out.overlapped.joined(separator: "\n"))
        Self.placed = out
        return out
    }

    /// The next shot is above the label in the stack (`zIndex` falls with age): its ring must not stand over the
    /// label's text, whatever the language and the number, on the narrowest shot.
    func testTheNextShotsRingDoesNotStandOverTheLabelsText() throws {
        let placed = try placement()
        XCTAssertTrue(placed.covered.isEmpty, "the next shot stands over the label's text: \(placed.covered)")
    }

    /// **Left red on purpose: a defect in working code, cosmetic.** The label stands `labelOut` (10 pt) out of its
    /// shot's ring, and the mask, `rowOverhang` (9 pt) out of the row's edge, cuts what stands past it: on a shot as
    /// wide as the slot (a ring of 206 pt in a slot of 200) at the first rest, the capsule's left end is 6.5 pt
    /// past the mask's edge and the capsule is cut flat; the text is whole. The capsule's edge is the ink's less the
    /// label's own padding, not photographed (glass does not composite offscreen).
    func testTheMasksLeftEdgeLeavesTheLabelsCapsuleWhole() throws {
        let placed = try placement()
        XCTAssertTrue(placed.textCut.isEmpty, "the mask cuts the label's text: \(placed.textCut)")
        XCTAssertTrue(placed.capsuleCut.isEmpty, "the mask cuts the label's capsule: \(placed.capsuleCut)")
    }

    // MARK: The row's edge

    /// Seven shots at every rest: the rings of the shots beyond the mask are not drawn, not even their edge. Counted
    /// as the white runs across the rings' middle: six, the sides of three rings.
    func testTheRowOfSevenShowsThreeRingsAndNoSliverOfAFourthAtAnyRest() throws {
        for offset in [0, 1, 2, 3, 4].map({ CGFloat($0) * ShotShelf.pitch }) {
            let picture = try photograph(try row(farWidth: 520, farHeight: 300, offset: offset))
            let rows = (0..<picture.height).filter { whiteRuns(picture, atRow: $0).count >= 4 }
            XCTAssertGreaterThan(rows.count, 40, "the control: the rings are in the render (offset \(offset))")
            guard rows.count > 40 else { continue }
            for y in rows[(rows.count / 4)...(rows.count * 3 / 4)] {
                let runs = whiteRuns(picture, atRow: y)
                XCTAssertEqual(runs.count, 6, "offset \(offset), row \(y): \(runs) is not the sides of three rings")
                if runs.count != 6 { break }
            }
        }
    }
}
