import SwiftUI
import AppKit

_ = NSApplication.shared

/// Renders the two constructions and reports where the ink of the word sits.
/// The claim under test: with the badges as an overlay the word is centred on
/// the column; in an HStack it is pushed left by half the badges' width.
@MainActor func inkCentre(_ view: some View, width: CGFloat) -> (lo: Int, hi: Int)? {
    let renderer = ImageRenderer(content:
        view.frame(width: width).background(.white))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    var lo = Int.max, hi = Int.min
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            guard let c = bitmap.colorAt(x: x, y: y) else { continue }
            // Any ink at all, but not the badge fills — sample only the rows
            // the 34 pt word occupies at full darkness.
            if c.brightnessComponent < 0.35 { lo = min(lo, x); hi = max(hi, x) }
        }
    }
    return lo <= hi ? (lo, hi) : nil
}

let badges = HStack(spacing: 5) {
    Text("BETA").font(.caption2.weight(.semibold)).padding(.horizontal, 6)
        .padding(.vertical, 2).background(Capsule().fill(.orange.opacity(0.25)))
    Text("DEV").font(.caption2.weight(.semibold)).padding(.horizontal, 6)
        .padding(.vertical, 2).background(Capsule().fill(.blue.opacity(0.25)))
}

let word = Text("Helm").font(.system(size: 34, weight: .semibold)).tracking(-0.4)

let asOverlay = word.overlay(alignment: .topTrailing) {
    badges.opacity(0).fixedSize()
        .alignmentGuide(.trailing) { $0[.leading] - 7 }
        .alignmentGuide(.top) { $0[.top] - 9 }
}
let asRow = HStack(alignment: .top, spacing: 7) { word; badges.opacity(0) }

let width: CGFloat = 380
MainActor.assumeIsolated {
    for (name, view) in [("overlay", AnyView(asOverlay)), ("hstack", AnyView(asRow))] {
        guard let (lo, hi) = inkCentre(view, width: width) else { print("\(name): no ink"); continue }
        let centre = Double(lo + hi) / 2 / 2          // scale 2 → points
        let offset = centre - Double(width) / 2
        print(String(format: "%@: word centre %.1f pt, column centre %.1f pt, off by %+.1f",
                     name, centre, Double(width) / 2, offset))
    }
}
