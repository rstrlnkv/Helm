import AppKit
import XCTest

/// **A view photographed once per turn of the run loop, with a timestamp**, and
/// the judgement that a change left no frame after its grace that differs from
/// the settled drawing.
///
/// Moved out of `TheTabSwitchHoldsStillAtItsEdgesTests` when a second place
/// needed it (`EveryTabSwitchIsACutTests`): a recorder written twice is two
/// definitions of «settled».
///
/// **The bound is zero unsettled frames after the grace**, not «at most two
/// anywhere»: a curve short enough to fit in two frames is still a curve, and a
/// count cannot tell two slow frames at the start from two frames of motion.
/// The grace is one turn — the table is allowed its first turn to hear about its
/// rows, and nothing after it. A rebuild of a page takes a whole turn, so a curve
/// can land in few frames, and two turns of grace would leave one frame between a
/// real curve and a pass. What a run measured is printed on every run as
/// `[frames]`, and that line is the number to quote.
@MainActor
public enum FrameRecorder {

    public struct Frame {
        public let at: TimeInterval
        public let pixels: Data
    }

    /// Turns of grace for AppKit's table to hear about its rows.
    public static let grace = 1

    /// One frame per run-loop turn, timed from `start`, which the caller takes
    /// before making the change. Synchronous: `RunLoop.run` is unavailable from
    /// an async context, so a caller that awaits its change does so first and
    /// hands the time it began to this.
    ///
    /// `band` is a row range in points, as `RenderedInk.bytes` takes it: a case
    /// that lets one part of the view move, and holds the rest to a cut, frames
    /// the rest and nothing else.
    public static func photograph(_ view: NSView, turns: Int = 45, band: ClosedRange<Int>? = nil,
                                  since start: Date) throws -> [Frame] {
        var out: [Frame] = []
        for _ in 0..<turns {
            view.layoutSubtreeIfNeeded()
            let pixels = try XCTUnwrap(RenderedInk.bytes(view, points: band), "the view drew nothing")
            out.append(Frame(at: Date().timeIntervalSince(start), pixels: pixels))
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.016))
        }
        return out
    }

    /// `HELM_FRAMES_DIR` names a folder for the PNGs; without it nothing is written.
    public static func write(_ frames: [Frame], of view: NSView, named: String) {
        guard let dir = ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let width = view.bounds.width, height = view.bounds.height
        for (index, frame) in frames.enumerated() {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2),
                                             pixelsHigh: Int(height * 2), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                             bitsPerPixel: 32),
                  let target = rep.bitmapData else { continue }
            _ = frame.pixels.withUnsafeBytes { raw in
                memcpy(target, raw.baseAddress!, min(raw.count, rep.bytesPerRow * rep.pixelsHigh))
            }
            let stamp = String(format: "%03d-%04dms", index, Int(frame.at * 1000))
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/\(named)-\(stamp).png"))
        }
    }

    /// Frames after the grace turns that are not the last one. The subject is
    /// asserted first: the drawing before and after the change must differ, or
    /// «nothing moved» is about a change that never happened.
    public static func judge(_ shots: [Frame], before: Data, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let settled = try XCTUnwrap(shots.last)
        XCTAssertNotEqual(before, settled.pixels,
                          "\(label): the drawing did not change, so this case proves nothing",
                          file: file, line: line)
        let moving = shots.dropFirst(grace).filter { $0.pixels != settled.pixels }
        let all = shots.filter { $0.pixels != settled.pixels }
        // The whole account, on every run and not only a red one: which turns
        // differed from the end and when, so a green run can be read for how
        // close it came.
        let unsettledTurns = shots.enumerated().filter { $0.element.pixels != settled.pixels }
            .map { "#\($0.offset)@\(Int($0.element.at * 1000))ms" }
        print("[frames] \(label): \(unsettledTurns.count)/\(shots.count) unsettled \(unsettledTurns)")
        XCTAssertEqual(moving.count, 0,
                       "\(label): \(moving.count) frames after the first \(grace) turns were not the settled drawing (\(all.count) in all), the last at \(Int((moving.last?.at ?? 0) * 1000)) ms",
                       file: file, line: line)
    }
}
