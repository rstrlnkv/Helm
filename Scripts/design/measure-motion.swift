import AVFoundation
import AppKit

/// What an animation actually does, frame by frame.
///
/// "Ragged", "abrupt" and "too fast" are claims about frames, and this is how
/// they get checked. Five defects in the disk ring's animation were found with
/// it and none was visible by watching — two of them lasted a single frame.
///
/// The number is the **change between consecutive frames**: the sum of absolute
/// differences over a downscaled grayscale crop of the part that moves. A
/// smooth move is a bell — small, rising, plateau, falling, nothing. Every
/// defect is a spike, and the shapes are named in ARCHITECTURE.md § Dev loop.
///
/// Crop to the thing that moves. A whole-window difference is dominated by the
/// list and the breadcrumb changing at the drill, which is honest and not what
/// is being judged.
///
/// Record first — the window rect comes from System Events:
/// ```bash
/// B=$(osascript -e 'tell application "System Events" to tell process "Helm" \
///     to get {position, size} of window 1')
/// screencapture -v -V 12 -x -R"$(echo $B | tr -d ' ')" clip.mov
/// ```
/// Then, over the ring's own area of a 1125×757 window:
/// ```bash
/// swift Scripts/design/measure-motion.swift clip.mov 16.6 0.17 0.57 0.32 0.91
/// ```
/// Arguments: clip, step in ms, then the crop as fractions x0 x1 y0 y1
/// (default is the whole frame). Add `--frames <dir>` to write the PNGs too,
/// which is how a one-frame flash gets identified once the curve has found it.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: measure-motion.swift <clip.mov> <stepMS> [x0 x1 y0 y1] [--frames <dir>]")
    exit(2)
}
let clip = URL(fileURLWithPath: arguments[1])
let step = Double(arguments[2]) ?? 16.6
func fraction(_ index: Int, _ fallback: Double) -> Double {
    arguments.count > index ? (Double(arguments[index]) ?? fallback) : fallback
}
let (x0, x1, y0, y1) = (fraction(3, 0), fraction(4, 1), fraction(5, 0), fraction(6, 1))
let framesDirectory = arguments.firstIndex(of: "--frames").map { URL(fileURLWithPath: arguments[$0 + 1]) }

let asset = AVURLAsset(url: clip)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
// Exact frames, not the nearest keyframe: a defect that lasts one frame is
// invisible to a generator allowed to round.
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let waiting = DispatchSemaphore(value: 0)
var duration = CMTime.zero
Task { duration = (try? await asset.load(.duration)) ?? .zero; waiting.signal() }
waiting.wait()
let seconds = CMTimeGetSeconds(duration)
print(String(format: "duration %.2f s, step %.1f ms, crop x %.2f-%.2f y %.2f-%.2f",
             seconds, step, x0, x1, y0, y1))

/// Downscaled by eight: the question is where the paint moved, not by how much
/// any one pixel changed, and a smaller buffer makes the whole clip cheap.
func grey(_ full: CGImage) -> [Int] {
    let rect = CGRect(x: Double(full.width) * x0, y: Double(full.height) * y0,
                      width: Double(full.width) * (x1 - x0),
                      height: Double(full.height) * (y1 - y0))
    guard let cropped = full.cropping(to: rect) else { return [] }
    let w = max(1, cropped.width / 8), h = max(1, cropped.height / 8)
    var buffer = [UInt8](repeating: 0, count: w * h)
    let context = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buffer.map(Int.init)
}

var previous: [Int]?
var time = 0.0
var index = 0
var peak = 0
var rows: [(Double, Int)] = []
while time < seconds {
    let stamp = CMTime(seconds: time, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: stamp, actualTime: nil) else {
        time += step / 1000; continue
    }
    let now = grey(image)
    if let previous, previous.count == now.count {
        let change = zip(previous, now).reduce(0) { $0 + abs($1.0 - $1.1) }
        rows.append((time * 1000, change))
        peak = max(peak, change)
    }
    if let framesDirectory {
        let representation = NSBitmapImageRep(cgImage: image)
        try? representation.representation(using: .png, properties: [:])?
            .write(to: framesDirectory.appendingPathComponent(String(format: "f%04d.png", index)))
    }
    previous = now
    time += step / 1000
    index += 1
}

for (at, change) in rows where change > peak / 100 {
    let bar = String(repeating: "█", count: min(60, change * 60 / max(peak, 1)))
    print(String(format: "%8.0f ms %9d  %@", at, change, bar))
}
print("peak \(peak) over \(rows.count) samples")
