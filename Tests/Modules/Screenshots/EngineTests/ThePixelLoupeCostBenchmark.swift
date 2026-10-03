import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **What one read of the loupe costs on a 5K frame.** The overlay reads it on every drag event of a held handle,
/// so the budget is one frame of a 120 Hz display. The answer depends on this Mac, so it is a report: silent
/// without `HELM_BENCH=1`. With it set the reads happen first (every one must be a loupe) and the mean is
/// asserted against the budget and printed.
final class ThePixelLoupeCostBenchmark: XCTestCase {

    func testOneReadOnA5KFrameFitsInOneDragEvent() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 5120, height: 2880, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 5120, height: 2880))
        let frame = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), scale: 2,
                                  image: try XCTUnwrap(context.makeImage()))
        let reads = 300
        var read = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<reads {
            if PixelLoupe.around(CGPoint(x: Double(index * 7 % 2500), y: Double(index * 5 % 1400)), in: frame) != nil { read += 1 }
        }
        let mean = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(reads) / 1_000_000
        XCTAssertEqual(read, reads, "a read returned no loupe, so the time is of nothing")
        print("PixelLoupe.around on 5120x2880: \(mean) ms a read over \(reads) reads")
        XCTAssertLessThan(mean, 8.3, "more than one frame at 120 Hz per drag event")
    }
}
