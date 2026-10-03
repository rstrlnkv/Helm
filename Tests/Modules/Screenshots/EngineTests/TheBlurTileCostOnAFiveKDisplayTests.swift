import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **What one pointer event of a blur draft costs on a 5K display.** The overlay rebuilds the draft's tile on every
/// pointer event, so this is the time between two frames of a drag over the whole display. It depends on this Mac,
/// so it is a report and not a gate: it skips itself unless `HELM_BENCH` is set.
final class TheBlurTileCostOnAFiveKDisplayTests: XCTestCase {
    func testTheTileOfTheWholeDisplayAtEachStepIsReported() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] != nil, "a report of this Mac's speed: HELM_BENCH=1")
        let (w, h) = (5120, 2880)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let display = try XCTUnwrap(context.makeImage())
        for (name, rect) in [("whole display", CGRect(x: 0, y: 0, width: 2560, height: 1440)),
                             ("quarter", CGRect(x: 100, y: 100, width: 1280, height: 720)),
                             ("small", CGRect(x: 100, y: 100, width: 200, height: 120))] {
            for block: CGFloat in [10, 16, 24] {
                var times: [Double] = []
                for _ in 0..<5 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let tile = Pixelate.tile(of: display, rect: rect, blockPoints: block, scale: 2)
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    XCTAssertNotNil(tile)
                }
                print("BLURCOST \(name) block \(block)pt: \(times.map { String(format: "%.0f", $0) }.joined(separator: " ")) ms")
            }
        }
    }
}
