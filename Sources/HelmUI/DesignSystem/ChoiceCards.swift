// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// A row of picture cards, one of which is chosen — the shape macOS System
/// Settings uses when the options differ in what they *look* like rather than
/// in what they are called. A pop-up menu names three things; this shows them.
///
/// **Buttons, not tap gestures**, for the reason `HelmPaletteSwatches` records:
/// a view whose only interaction is `onTapGesture` never joins the key-view
/// loop, so Full Keyboard Access cannot reach it and only VoiceOver hides that.
///
/// The preview is the caller's: this control knows nothing about what it is
/// choosing between.
///
/// **`AppearancePicker` is this control**, and for a while it was not: light
/// / dark / auto was the same row of pictures hand-built beside this one, at a
/// different size, a different corner radius, a different ring and a different
/// label treatment. Two answers to «what does a picture-choice look like in
/// Helm» is the variant this file exists to prevent. What survived the merge is
/// the appearance picker's, because each part of it was argued somewhere:
/// a hairline on *every* thumbnail (the one matching the window's own
/// appearance measured 1.00:1 against the card behind it and floated in
/// nothing), and a label that says which one is chosen by **weight** rather
/// than by a second colour — two colours saying it made the other two look
/// disabled.
public struct HelmChoiceCards<Value: Hashable, Preview: View>: View {
    public struct Item: Identifiable {
        public let id: Value
        public let label: String
        public let preview: Preview
        public init(id: Value, label: String, preview: Preview) {
            self.id = id
            self.label = label
            self.preview = preview
        }
    }

    @Binding private var selection: Value
    private let items: [Item]

    private let thumbnail: CGSize

    /// The default picture. Everything else about this control is fixed; the
    /// size is not, because **the picture is as wide as its label needs**.
    ///
    /// Measured, in Russian: light / dark / auto are one word each and sit
    /// happily under 74 pt, while «Имя в строке меню» folds onto two lines
    /// there and fits on one at 104 — and a row of three cards where one label
    /// is two lines and two are one has three different baselines and no
    /// alignment at all. A caller passes the size its own longest word in eight
    /// languages asks for. A preview drawn in fractions of its frame follows it
    /// either way.
    public static var thumbnail: CGSize { CGSize(width: 74, height: 46) }

    public init(selection: Binding<Value>, items: [Item],
                thumbnail: CGSize = HelmChoiceCards.thumbnail) {
        _selection = selection
        self.items = items
        self.thumbnail = thumbnail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button { selection = item.id } label: {
                    VStack(spacing: 6) {
                        item.preview
                            .frame(width: thumbnail.width, height: thumbnail.height)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            // The accent ring on the chosen one; a hairline on
                            // all of them so the unchosen ones have an edge at
                            // all. A preview whose own fill matches the card
                            // behind it otherwise floats in nothing — measured
                            // at 1.00:1 for the light thumbnail in light
                            // appearance, and 1.12:1 dark on dark.
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor
                                                           : HelmSurface.hairline,
                                                  lineWidth: selected ? 2.5 : 0.5)
                            }
                        Text(item.label)
                            .font(.caption)
                            // Weight, not colour: the ring already says which
                            // one is chosen, and a second colour saying it
                            // again is what makes the two that are not chosen
                            // look disabled.
                            .fontWeight(selected ? .semibold : .regular)
                            .foregroundStyle(selected ? Color.primary : HelmText.quiet)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: thumbnail.width)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}
