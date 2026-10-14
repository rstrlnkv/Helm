import AppKit
import XCTest

/// **A view photographed once per turn of the run loop, with a timestamp**, and
/// the judgement that a change left no frame after its grace that differs from
/// the settled drawing, in its picture or in what its layers are presenting.
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
///
/// **A picture alone reads a layer fade as a cut.** `cacheDisplay` draws a
/// layer's model values, so a fade run by Core Animation (a layer animation, or
/// `animator().alphaValue`) over a model that is already final photographs as
/// one image for as long as it runs; a SwiftUI fade redraws its own tree each
/// turn and shows in the picture. Each frame therefore also carries the opacities
/// the layer tree under the view is presenting.
///
/// **Only a layer of the page's drawing that a person could see counts.**
/// AppKit keeps layers of its own under a scroll view. The scroll pocket's mask
/// and blur are hidden or under a hidden layer, have no area, and change
/// opacity from turn to turn; counted, they make turns differ that have one
/// picture. The overlay scroller's knob is in sight while it flashes: after a
/// switch of the Log page's level tabs it showed its knob and then stepped it
/// down to nothing, on a clock of AppKit's own (the model value moved with the
/// presented one, and neither the knob's layer nor any layer above it had an
/// animation), and `cacheDisplay` does not draw it. The scroll bar belongs to
/// the system's chrome, not to the page's drawing, and its flash is not a
/// transition between tabs, so a layer whose delegate is an `NSScroller` is not
/// counted and nothing under it is walked. See `Frame.presented` for the rule.
@MainActor
public enum FrameRecorder {

    public struct Frame {
        public let at: TimeInterval
        public let pixels: Data
        /// The opacities the layers under the view presented in this turn, those
        /// strictly between 0 and 1 and in walk order, each read as
        /// `ModulePageRender` reads them: the presentation layer's, else the
        /// model's, the layer's own and not multiplied by its ancestors'. A
        /// layer at either end adds nothing of its own, so a layer with no
        /// sublayers arriving or leaving at a whole opacity does not make a turn
        /// differ; one on its way does.
        ///
        /// Only a layer of the page's drawing that a person could see is
        /// counted, and its sublayers are walked only when it lets them show:
        /// - a hidden layer is not counted and neither are its sublayers;
        /// - a layer whose delegate is an `NSScroller` (AppKit's scroll bar, the
        ///   overlay knob's layer among its sublayers) is not counted and
        ///   neither are its sublayers: the scroll bar is the system's chrome,
        ///   whose knob the picture does not draw either, and its flash is not a
        ///   transition between tabs;
        /// - a layer presenting opacity 0 is not counted and neither are its
        ///   sublayers, which are invisible under it whatever they present;
        /// - a layer whose bounds, converted into the view's layer, do not
        ///   overlap the view's bounds is not counted, nor is a layer with no
        ///   area (zero width or height);
        /// - when `photograph` was given a `band`, a layer whose converted bounds
        ///   do not overlap the band's rows is not counted either;
        /// - a layer that is not counted because of its area or the band, and
        ///   that clips its sublayers to its bounds (`masksToBounds`), takes its
        ///   sublayers with it; one that does not clip has them walked, since
        ///   they can reach into the view or the band from outside it.
        ///
        /// Not considered: a layer clipped away by the `masksToBounds` of an
        /// ancestor that is itself in the view and the band, a layer cut out by
        /// a `mask`, one covered by another layer, and one that draws nothing.
        public let presented: [Float]
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
    /// the rest and nothing else. The picture is cut to the band, and a layer
    /// counts toward `Frame.presented` only where its bounds overlap the band's
    /// rows.
    public static func photograph(_ view: NSView, turns: Int = 45, band: ClosedRange<Int>? = nil,
                                  since start: Date) throws -> [Frame] {
        var out: [Frame] = []
        for _ in 0..<turns {
            view.layoutSubtreeIfNeeded()
            let pixels = try XCTUnwrap(RenderedInk.bytes(view, points: band), "the view drew nothing")
            out.append(Frame(at: Date().timeIntervalSince(start), pixels: pixels,
                             presented: presentedOpacities(under: view, band: band)))
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.016))
        }
        return out
    }

    private static func presentedOpacities(under view: NSView, band: ClosedRange<Int>?) -> [Float] {
        guard let root = view.layer else { return [] }
        var out: [Float] = []
        func walk(_ layer: CALayer) {
            if layer.isHidden || layer.delegate is NSScroller { return }
            let opacity = layer.presentation()?.opacity ?? layer.opacity
            if opacity == 0 { return }
            let shown = root.convert(layer.bounds, from: layer).intersection(root.bounds)
            var visible = !shown.isEmpty
            if visible, let band {
                // The picture's rows count from the top whichever way the layer
                // space runs.
                let top = root.isGeometryFlipped ? shown.minY : root.bounds.height - shown.maxY
                visible = top < CGFloat(band.upperBound) && top + shown.height > CGFloat(band.lowerBound)
            }
            if visible, opacity < 1 { out.append(opacity) }
            if !visible, layer.masksToBounds { return }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(root)
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

    /// Frames after the grace turns that differ from the last one, in their
    /// picture or in their presented opacities (the layers of the page's
    /// drawing that a person could see, as `Frame.presented` counts them). The
    /// failure says how many of those frames had the settled picture and
    /// differed in the layers alone, so a red row says whether to look at
    /// pixels or at layers. The subject is asserted first: the drawing before
    /// and after the change must differ, or «nothing moved» is about a change
    /// that never happened.
    public static func judge(_ shots: [Frame], before: Data, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let settled = try XCTUnwrap(shots.last)
        XCTAssertNotEqual(before, settled.pixels,
                          "\(label): the drawing did not change, so this case proves nothing",
                          file: file, line: line)
        func unsettled(_ frame: Frame) -> Bool {
            frame.pixels != settled.pixels || frame.presented != settled.presented
        }
        let moving = shots.dropFirst(grace).filter(unsettled)
        let byLayersAlone = moving.filter { $0.pixels == settled.pixels }.count
        let all = shots.filter(unsettled)
        // The whole account, on every run and not only a red one: which turns
        // differed from the end and when, so a green run can be read for how
        // close it came.
        let unsettledTurns = shots.enumerated().filter { unsettled($0.element) }
            .map { "#\($0.offset)@\(Int($0.element.at * 1000))ms" }
        print("[frames] \(label): \(unsettledTurns.count)/\(shots.count) unsettled \(unsettledTurns)")
        XCTAssertEqual(moving.count, 0,
                       "\(label): \(moving.count) frames after the first \(grace) turns were not the settled drawing (\(all.count) in all), the last at \(Int((moving.last?.at ?? 0) * 1000)) ms; \(byLayersAlone) of the \(moving.count) had the settled picture and differed only in what the layers presented",
                       file: file, line: line)
    }
}
