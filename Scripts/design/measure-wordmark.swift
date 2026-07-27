import SwiftUI
import AppKit
_ = NSApplication.shared

struct Badge: View {
    let text: String, tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background {
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.95), tint],
                                              startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Capsule().strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0)],
                            startPoint: .top, endPoint: .center), lineWidth: 0.7)
                    }
            }
            .shadow(color: tint.opacity(0.35), radius: 2, y: 1)
    }
}

let word = Text("Helm").font(.system(size: 34, weight: .semibold)).tracking(-0.4)

@MainActor func capTopInPoints() -> Double {
    let r = ImageRenderer(content: word.frame(width: 200).background(.white))
    r.scale = 4
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let bm = NSBitmapImageRep(data: tiff) else { return -1 }
    for y in 0..<bm.pixelsHigh {
        for x in 0..<bm.pixelsWide {
            if let c = bm.colorAt(x: x, y: y), c.brightnessComponent < 0.4 {
                return Double(y) / 4          // scale 4 → points from the line top
            }
        }
    }
    return -1
}

struct Hero: View {
    let text: String, tint: Color, inset: CGFloat
    var body: some View {
        Text("Helm").font(.system(size: 34, weight: .semibold)).tracking(-0.4)
            .overlay(alignment: .topTrailing) {
                Badge(text: text, tint: tint).fixedSize()
                    .alignmentGuide(.trailing) { $0[.leading] - 7 }
                    .alignmentGuide(.top) { $0[.top] - inset }
            }
            .frame(width: 300)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

MainActor.assumeIsolated {
    let cap = capTopInPoints()
    print(String(format: "cap top of H: %.2f pt below the line top", cap))
    let candidates = [cap, cap + 1.5, cap + 3]
    let rows = VStack(spacing: 0) {
        ForEach(candidates, id: \.self) { inset in
            Hero(text: "DEV", tint: .blue, inset: CGFloat(inset))
            Hero(text: "BETA", tint: .orange, inset: CGFloat(inset))
        }
    }
    let r = ImageRenderer(content: rows); r.scale = 3
    if let img = r.nsImage, let tiff = img.tiffRepresentation,
       let bm = NSBitmapImageRep(data: tiff),
       let png = bm.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("insets: " + candidates.map { String(format: "%.2f", $0) }.joined(separator: ", "))
    }
}
