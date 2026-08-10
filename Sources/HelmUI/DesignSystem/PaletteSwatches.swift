// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import AppKit

/// The ten palette colours as a grid of swatches. One of these, no local
/// variants: it was a private method inside `KeepAwakeSettingsPage` until VPN
/// needed the same control, and CLAUDE.md's list of things written twice
/// before they moved exists to stop the second copy.
///
/// **A menu, not a row of ten.** Two of these in one card — the active colour
/// and the countdown colour — were two rainbows 270 pt wide, and a settings
/// card is a list of rows with a control at the end of each. The control is a
/// 14 pt dot now, and the ten live behind it, which is what Calendar and
/// Reminders do with exactly this choice.
///
/// It also settles an accessibility problem rather than working around one. The
/// row had to be ten `Button`s specifically so Full Keyboard Access could reach
/// them — as ten `onTapGesture`s none entered the key-view loop, Tab skipped
/// every swatch, and the colour could not be chosen without a mouse while
/// VoiceOver worked, which is what hid it. A `Menu` is one stop that opens a
/// list the keyboard already knows how to walk.
public struct HelmPaletteSwatches: View {
    /// Ten swatches on one line, beside the label whose colour they set.
    ///
    /// There was a 5×2 grid as well, and it was the default. Two of them in one
    /// column — the active colour and the countdown colour — came out different
    /// widths, so their right edges did not line up and the card read as
    /// crooked. A row cannot do that. The grid had no call site left once both
    /// moved, and a layout nobody asks for is a branch that stops being true
    /// without anybody finding out.
    private let name: String
    private let selection: String
    private let pick: (String) -> Void

    /// - Parameter name: what this colour is *for*, in the caller's words.
    ///   Hidden on screen — the row beside it already says so — and read aloud,
    ///   which is the whole point: a picker with no name is «pop up button» and
    ///   nothing else, and `NamedControlsTests` fails on one.
    public init(_ name: String, selection: String, pick: @escaping (String) -> Void) {
        self.name = name
        self.selection = selection
        self.pick = pick
    }

    /// Which item the menu has selected: one of the eight, or the free choice.
    private enum Choice: Hashable { case palette(PaletteColor), custom }

    /// Kept alive by the view, because `NSColorPanel` holds its target
    /// weakly: a bridge created inside the action would be gone before the
    /// first colour came back.
    @State private var bridge = ColorPanelBridge()

    public var body: some View {
        // A `Picker`, not a `Menu`. Both are one compact control; this one is
        // what the rest of the settings pages already use, it draws its own
        // selection, and — the reason it was chosen over the first attempt —
        // it is **visible to the probes**. A `Menu` whose label is a bare
        // `Circle` photographed as nothing at all, offscreen and in a real
        // window both, because AppKit draws it outside the layer
        // `cacheDisplay` reads. Shipping a control nobody could photograph
        // would have been shipping one nobody had seen.
        Picker(name, selection: choice) {
            ForEach(PaletteColor.offered, id: \.rawValue) { palette in
                Label {
                    Text(palette.label)
                } icon: {
                    // An image, not a tinted symbol: an `NSMenuItem` drops the
                    // tint and the list came out as ten words. See
                    // `PaletteColor.swatchImage`.
                    Image(nsImage: palette.swatchImage)
                }
                .tag(Choice.palette(palette))
            }
            Divider()
            // Calendar's own last item, and its own word for it — `Other…` in
            // `CalendarUI.framework`'s table, «Другой…» in Russian. The swatch
            // beside it is the colour in use when that is a custom one, so the
            // menu shows what was chosen rather than only that something was.
            Label {
                Text(HelmA11y.otherColour)
            } icon: {
                Image(nsImage: PaletteTint.custom(selection).map(swatch(of:))
                      ?? PaletteColor.white.swatchImage)
            }
            .tag(Choice.custom)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityValue(currentLabel)
    }

    /// The selection, in both directions. Choosing «Other…» does not itself
    /// change the colour — it opens the panel, and the colour changes when one
    /// is picked there. A person who opens it and closes it again has changed
    /// nothing, which is what the same menu does in Calendar.
    private var choice: Binding<Choice> {
        Binding(get: {
            if let palette = PaletteColor(rawValue: selection) { return .palette(palette) }
            return .custom
        }, set: { new in
            switch new {
            case .palette(let palette): pick(palette.rawValue)
            case .custom: openColourPanel()
            }
        })
    }

    /// **The system panel itself, not a popover containing a colour well.**
    ///
    /// A SwiftUI `ColorPicker` *is* a well — a button that opens this panel —
    /// so presenting one in a popover put a second click and a floating swatch
    /// between «Other…» and the thing it names. Calendar opens the panel.
    ///
    /// Continuous, so the icon in the menu bar follows the panel while somebody
    /// is dragging around the wheel: this control's whole subject is a colour
    /// they are looking at somewhere else on screen.
    private func openColourPanel() {
        let panel = NSColorPanel.shared
        bridge.onPick = { pick(PaletteTint.token(for: Color(nsColor: $0))) }
        panel.setTarget(bridge)
        panel.setAction(#selector(ColorPanelBridge.colourChanged(_:)))
        panel.showsAlpha = false
        panel.isContinuous = true
        // Opens on the colour in use rather than on whatever the panel was left
        // showing — which, shared app-wide as it is, could be anything.
        panel.color = PaletteTint.custom(selection) ?? NSColor(current.color)
        panel.makeKeyAndOrderFront(nil)
    }

    /// A disc in an arbitrary colour, drawn the same way the palette's own are.
    private func swatch(of colour: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            colour.setFill()
            disc.fill()
            NSColor.labelColor.withAlphaComponent(0.20).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Read aloud: the palette's name, or the word for a colour that has none.
    private var currentLabel: String {
        PaletteColor(rawValue: selection)?.label ?? HelmA11y.otherColour
    }

    /// The palette colour currently chosen, falling back to the first rather
    /// than drawing nothing: a picker whose selection matches no tag draws
    /// blank, and a control with no label is a hit target nobody can find.
    private var current: PaletteColor {
        PaletteColor(rawValue: selection) ?? PaletteColor.allCases[0]
    }
}

/// `NSColorPanel`'s target, which it holds **weakly**.
///
/// A closure cannot be one — the panel wants an object and a selector — and an
/// object created inside the action that opens the panel is deallocated before
/// the first colour comes back, which reads as a panel that does nothing. Held
/// by the view for as long as the view is there.
final class ColorPanelBridge: NSObject {
    var onPick: (NSColor) -> Void = { _ in }

    @objc func colourChanged(_ sender: NSColorPanel) { onPick(sender.color) }
}
