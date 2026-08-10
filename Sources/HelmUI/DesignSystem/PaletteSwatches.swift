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

    @State private var showingPicker = false
    /// What the colour well is bound to while the popover is open. Seeded from
    /// the stored token so the panel opens on the colour that is in use, not on
    /// black.
    @State private var custom: Color = .accentColor

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
        // The system colour panel, opened by choosing «Other…» and anchored to
        // the control that opened it.
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            ColorPicker(HelmA11y.otherColour, selection: $custom, supportsOpacity: false)
                .labelsHidden()
                .padding(14)
                .onChange(of: custom) { _, picked in pick(PaletteTint.token(for: picked)) }
        }
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
            case .custom:
                custom = PaletteTint.customColor(selection) ?? current.color
                showingPicker = true
            }
        })
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
