// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// The ten palette colours as a grid of swatches. One of these, no local
/// variants: it was a private method inside `KeepAwakeSettingsPage` until VPN
/// needed the same control, and CLAUDE.md's list of things written twice
/// before they moved exists to stop the second copy.
///
/// **Buttons, not tap gestures.** A view whose only interaction is
/// `onTapGesture` never enters the key-view loop, so with Full Keyboard Access
/// on, Tab skipped every swatch and the colour could not be chosen without a
/// mouse — VoiceOver worked, which is what hid it. Ten `KeyViewProxy` views
/// appear under the hosting view for the button form and none for the gesture
/// form; `.buttonStyle(.plain)` leaves the drawing exactly as it was.
public struct HelmPaletteSwatches: View {
    /// `.grid` is the original 5×2 field, kept as the default so Keep Awake's
    /// two call sites change nothing. `.row` is a single line of ten, smaller,
    /// for a place that only has one row's worth of space beside a label.
    public enum Layout { case grid, row }

    private let selection: String
    private let layout: Layout
    private let pick: (String) -> Void

    public init(selection: String, layout: Layout = .grid, pick: @escaping (String) -> Void) {
        self.selection = selection
        self.layout = layout
        self.pick = pick
    }

    public var body: some View {
        switch layout {
        case .grid:
            // 5 columns × 2 rows for the 10 palette colours.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 24, maximum: 44)), count: 5),
                      spacing: 12) {
                ForEach(PaletteColor.allCases, id: \.rawValue) { palette in
                    swatch(palette, diameter: 24, checkmarkSize: 11)
                }
            }
            .padding(.vertical, 4)
        case .row:
            HStack(spacing: 8) {
                ForEach(PaletteColor.allCases, id: \.rawValue) { palette in
                    swatch(palette, diameter: 20, checkmarkSize: 9)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// One swatch button, shared by both layouts so they cannot drift apart —
    /// button semantics, help, accessibility traits and the selection ring are
    /// identical; only the size changes.
    private func swatch(_ palette: PaletteColor, diameter: CGFloat, checkmarkSize: CGFloat) -> some View {
        let selected = selection == palette.rawValue
        return Button { pick(palette.rawValue) } label: {
            Circle()
                .fill(palette.color)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay {
                    if selected {
                        // Dark on the three light swatches, white on
                        // the rest — a white check on yellow is not a
                        // check anyone can see.
                        Image(systemName: "checkmark")
                            .font(.system(size: checkmarkSize, weight: .bold))
                            .foregroundStyle(palette == .white || palette == .yellow
                                             || palette == .mint ? .black : .white)
                    }
                }
                .overlay {
                    if selected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(palette.label)
        // The button carries its own trait and its own action; only
        // "which one is chosen" has to be said here.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(palette.label)
    }
}
