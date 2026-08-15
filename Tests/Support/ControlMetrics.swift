import AppKit

/// Real AppKit control metrics, for the width-model tests.
///
/// Four width guards measured a push button by building an `NSButton` and
/// asking `fittingSize` — each with its own copy of the same six lines, the
/// way `scratchDirectory` was hand-rolled in dozens of files before it moved
/// here. The estimate this style replaced put a two-control bar at 538 where
/// SwiftUI draws 563.5, which is why the measurement is a real control and
/// lives in one place.
public enum ControlMetrics {

    /// A small bordered button, as the toolbars draw their controls.
    public static func smallButton(_ title: String) -> CGFloat {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.sizeToFit()
        return button.fittingSize.width
    }

    /// A regular-size bordered button — which is also what a
    /// `.borderedProminent` SwiftUI button measures as.
    public static func button(_ title: String) -> CGFloat {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.sizeToFit()
        return button.fittingSize.width
    }

    /// A small bordered button carrying only a symbol: the bottom rung of a
    /// label-to-icon ladder.
    public static func smallSymbolButton(_ name: String) -> CGFloat {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.sizeToFit()
        return button.fittingSize.width
    }

    /// A bare text label at the given font.
    public static func label(_ string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }
}
