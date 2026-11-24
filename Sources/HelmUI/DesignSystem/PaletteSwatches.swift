// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import AppKit

/// `PaletteColor.offered` and a colour of your own, as one compact control, and
/// no local variants (Architecture/TestsAndMeasurement.md § Why the commands are run).
///
/// **A pop-up, not a row of swatches.** A settings card is a list of rows with
/// a control at the end of each, and two palettes in one card would be two
/// rainbows of different widths. The control is a 12 pt dot
/// (`PaletteColor.swatchImage`, `swatchImage(of:)`) with the palette behind
/// it, as in Calendar and Reminders. A pop-up is also one keyboard stop that
/// opens a list Full Keyboard Access already knows how to walk.
///
/// **A `Picker`, not a `Menu`**, because a `Menu` whose label is a bare
/// `Circle` photographs as nothing, offscreen and in a real window: AppKit
/// draws it outside the layer `cacheDisplay` reads. A control nobody can
/// photograph is a control nobody has seen.
public struct HelmPaletteSwatches: View {
    private let name: String
    private let selection: String
    private let pick: (String) -> Void

    /// - Parameter name: what this colour is *for*, in the caller's words.
    ///   Hidden on screen, where the row beside it says so, and read aloud: a
    ///   picker with no name is «pop up button» and nothing else.
    public init(_ name: String, selection: String, pick: @escaping (String) -> Void) {
        self.name = name
        self.selection = selection
        self.pick = pick
    }

    /// Which item the menu has selected: one of `PaletteColor.offered`, or the free choice.
    private enum Choice: Hashable { case palette(PaletteColor), custom }

    /// Kept alive by the view, because `NSColorPanel` holds its target
    /// weakly: a bridge created inside the action would be gone before the
    /// first colour came back.
    @State private var bridge = ColorPanelBridge()

    public var body: some View {
        // A `Picker`, not a `Menu`: the reason is on the type's doc comment.
        Picker(name, selection: choice) {
            ForEach(PaletteColor.offered, id: \.rawValue) { palette in
                Label {
                    Text(palette.label)
                } icon: {
                    // An image, not a tinted symbol: an `NSMenuItem` drops the
                    // tint and the list came out as words. See
                    // `PaletteColor.swatchImage`.
                    Image(nsImage: palette.swatchImage)
                }
                .tag(Choice.palette(palette))
            }
            Divider()
            // Calendar's own last item (see `HelmA11y.otherColour`). Its swatch
            // is the colour in use when that is a custom one, so the menu shows
            // what was chosen.
            Label {
                Text(HelmA11y.otherColour)
            } icon: {
                Image(nsImage: PaletteTint.custom(selection).map(PaletteColor.swatchImage(of:))
                      ?? PaletteColor.white.swatchImage)
            }
            .tag(Choice.custom)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityValue(currentLabel)
    }

    /// The selection, in both directions. Choosing «Other colour…» does not itself
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

    /// **The system panel itself, not a popover with a colour well**: a
    /// `ColorPicker` is a well that opens this panel, so it would add a click.
    /// Calendar opens the panel. Continuous, so the menu-bar icon follows the
    /// wheel while somebody drags it.
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

/// `NSColorPanel`'s target, which it holds **weakly**: the panel wants an
/// object and a selector, and one created inside the action is gone before the
/// first colour comes back. Held by whoever opens the panel: the swatch row's
/// `@State`, or the Screenshots editor's `EditorColourPanel`.
public final class ColorPanelBridge: NSObject {
    public var onPick: (NSColor) -> Void = { _ in }

    public override init() { super.init() }

    /// `@MainActor` on the method, not the class: AppKit sends an action on the
    /// main thread, and the class's `init` has to stay nonisolated for the
    /// `@State` default above to build.
    @MainActor
    @objc public func colourChanged(_ sender: NSColorPanel) { onPick(sender.color) }
}
