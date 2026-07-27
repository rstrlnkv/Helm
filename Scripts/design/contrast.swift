import AppKit

/// What a recessed text colour actually measures against the window it sits on.
///
/// The numbers in `HelmText` used to be arithmetic against pure black on pure
/// white, which is neither colour the app draws: `Color.primary` is
/// `labelColor` (85% black) and it lands on `windowBackgroundColor`. Every
/// token read about 1.5:1 better on paper than on screen, and one of them
/// claimed to clear a threshold it was under.
///
/// Run: `swift Scripts/design/contrast.swift`

// The probe segfaults reading dynamic system colours without a real app object.
_ = NSApplication.shared

func lum(_ c: NSColor) -> Double {
    let s = c.usingColorSpace(.sRGB)!
    func lin(_ v: CGFloat) -> Double {
        let d = Double(v)
        return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
}

/// Paint `fg` (which carries alpha) onto `bg` and return what lands.
func over(_ fg: NSColor, _ bg: NSColor) -> NSColor {
    let f = fg.usingColorSpace(.sRGB)!, b = bg.usingColorSpace(.sRGB)!
    let a = f.alphaComponent
    return NSColor(srgbRed: f.redComponent * a + b.redComponent * (1 - a),
                   green: f.greenComponent * a + b.greenComponent * (1 - a),
                   blue: f.blueComponent * a + b.blueComponent * (1 - a),
                   alpha: 1)
}

func ratio(_ a: NSColor, _ b: NSColor) -> Double {
    let x = lum(a), y = lum(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

let tokens: [(String, CGFloat)] = [("quiet", 0.64), ("faint", 0.55), ("separator", 0.50),
                                   ("body (1.0)", 1.0), ("0.70", 0.70), ("0.75", 0.75),
                                   ("0.80", 0.80)]

for (name, appearance) in [("light", NSAppearance(named: .aqua)!),
                           ("dark", NSAppearance(named: .darkAqua)!)] {
    NSAppearance.current = appearance
    let bg = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
    let label = NSColor.labelColor.usingColorSpace(.sRGB)!
    print("\n\(name): window \(String(format: "%.4f", lum(bg))), labelColor alpha \(String(format: "%.2f", label.alphaComponent))")
    print("  system .secondary \(String(format: "%.2f", ratio(over(NSColor.secondaryLabelColor, bg), bg))):1")
    print("  system .tertiary  \(String(format: "%.2f", ratio(over(NSColor.tertiaryLabelColor, bg), bg))):1")
    for (n, o) in tokens {
        // Color.primary is labelColor; .opacity() multiplies its alpha.
        let c = label.withAlphaComponent(label.alphaComponent * o)
        print("  \(n.padding(toLength: 12, withPad: " ", startingAt: 0)) \(String(format: "%.2f", ratio(over(c, bg), bg))):1")
    }
}

print("\nopacity needed to hit a target, worst of the two appearances:")
for target in [4.5, 3.5, 3.0] {
    var lo: CGFloat = 0.1, hi: CGFloat = 1.0
    for _ in 0..<40 {
        let mid = (lo + hi) / 2
        var worst = Double.infinity
        for ap in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
            NSAppearance.current = ap
            let bg = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
            let label = NSColor.labelColor.usingColorSpace(.sRGB)!
            worst = min(worst, ratio(over(label.withAlphaComponent(label.alphaComponent * mid), bg), bg))
        }
        if worst < target { lo = mid } else { hi = mid }
    }
    print(String(format: "  %.1f:1 needs opacity %.3f", target, Double(hi)))
}
