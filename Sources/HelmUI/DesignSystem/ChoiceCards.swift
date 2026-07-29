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

    public init(selection: Binding<Value>, items: [Item]) {
        _selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button { selection = item.id } label: {
                    VStack(spacing: 6) {
                        item.preview
                            .frame(width: 104, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor
                                                           : Color.primary.opacity(0.12),
                                                  lineWidth: selected ? 2 : 1)
                            }
                        Text(item.label)
                            .font(.caption)
                            // `HelmText.strong` does not exist — `.quiet` for
                            // both states rather than SwiftUI's `.primary`,
                            // which measures below the 4.5:1 floor these
                            // tokens exist to clear.
                            .foregroundStyle(HelmText.quiet)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 104)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}
