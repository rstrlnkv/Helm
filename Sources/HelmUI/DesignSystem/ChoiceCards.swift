// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// A row of picture cards, one of which is chosen — the shape macOS System
/// Settings uses when the options differ in what they *look* like rather than
/// in what they are called. A pop-up menu names three things; this shows them.
///
/// **Buttons, not tap gestures**: a view whose only interaction is
/// `onTapGesture` never joins the key-view loop, so Full Keyboard Access
/// cannot reach it.
///
/// The preview is the caller's: this control knows nothing about what it is
/// choosing between. `AppearancePicker` is this control, so Helm has one answer
/// to «what does a picture-choice look like»: a hairline on every thumbnail,
/// since one matching the card floats in nothing, and the chosen label marked
/// by weight rather than a second colour, which makes the others look disabled.
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
    /// size is not, because **the picture is as wide as its label needs**: a
    /// row where one label wraps and the others do not has three baselines. A
    /// caller whose longest label in eight languages needs more passes its own
    /// size (only the showcase does); a preview drawn in fractions of its frame
    /// follows it.
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
                            // The accent ring on the chosen one, a hairline on
                            // the rest, and the reason for both at the modifier.
                            .helmPreviewEdge(chosen: selected)
                        Text(item.label)
                            // 10, the scale's bottom step for a tick label, and
                            // the size the thumbnail widths are measured against:
                            // at another size a label that fits would wrap.
                            .font(HelmText.pictureCaption)
                            // Weight, not colour: the ring already says which
                            // is chosen, and a second colour makes the rest look
                            // disabled.
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
