import AppKit
import SwiftUI

/// **How a switcher in the settings window's toolbar labels its segments.**
///
/// All four were drawn side by side in the mockup (2026-09-17) and the owner
/// took all four, as a choice made by right-clicking the switcher:
///
/// - `text` — each segment as wide as its word, a hairline between two
///   unselected ones. The system segmented control split the capsule into
///   equal shares of the longest word: 4 × 122 pt for Homebrew in Russian,
///   with «Поиск» sitting in a field three times its own width.
/// - `icons` — a glyph per segment, 40 pt each, the word in the tooltip.
/// - `iconsAndText` — a glyph beside each word.
/// - `iconsNamingSelected` — glyphs, and the selected segment carries its word.
public enum ToolbarSwitcherStyle: String, CaseIterable, Sendable {
    case text, icons, iconsAndText, iconsNamingSelected

    public static let storageKey = "toolbarSwitcherStyle"

    /// Anything unknown, including nothing stored, is `text` — the mockup's
    /// recommendation.
    public init(stored: String) {
        self = ToolbarSwitcherStyle(rawValue: stored) ?? .text
    }

    /// The words the choice is offered under. Three are AppKit's own, read out
    /// of its `Toolbar.loctable` — the names every toolbar's context menu
    /// already uses for the same choice; the fourth has no system spelling.
    public var label: String {
        switch self {
        case .text: return L("Text Only")
        case .icons: return L("Icon Only")
        case .iconsAndText: return L("Icon and Text")
        case .iconsNamingSelected: return L("Icon Only, Text When Selected")
        }
    }
}

public extension Notification.Name {
    static let helmToolbarSwitcherStyleChanged = Notification.Name("helmToolbarSwitcherStyleChanged")
}

public extension EnvironmentValues {
    @Entry var helmSwitcherStyle: ToolbarSwitcherStyle = .text
    /// Where a right-click on a switcher writes the choice. Nil where nothing
    /// stores it — a page mounted on its own — and the menu is then not offered.
    @Entry var helmSetSwitcherStyle: (@MainActor @Sendable (ToolbarSwitcherStyle) -> Void)? = nil
}

public extension View {
    /// Follows `ToolbarSwitcherStyle` as it is changed and hands every switcher
    /// below the way to change it.
    func helmTracksSwitcherStyle(_ current: @escaping () -> ToolbarSwitcherStyle,
                                 set: @escaping @MainActor @Sendable (ToolbarSwitcherStyle) -> Void)
        -> some View {
        modifier(SwitcherStyleTracker(current: current, set: set))
    }
}

private struct SwitcherStyleTracker: ViewModifier {
    let current: () -> ToolbarSwitcherStyle
    let set: @MainActor @Sendable (ToolbarSwitcherStyle) -> Void
    @State private var style: ToolbarSwitcherStyle?

    func body(content: Content) -> some View {
        content
            .environment(\.helmSwitcherStyle, style ?? current())
            .environment(\.helmSetSwitcherStyle, set)
            .onReceive(NotificationCenter.default.publisher(for: .helmToolbarSwitcherStyleChanged)) { _ in
                style = current()
            }
    }
}

/// One segment: the value it selects, its word and its glyph.
public struct HelmSwitcherSegment<Value: Hashable> {
    public let value: Value
    public let label: String
    public let symbol: String

    public init(_ value: Value, _ label: String, symbol: String) {
        self.value = value
        self.label = label
        self.symbol = symbol
    }
}

/// **A switcher for the window's toolbar, drawn by Helm rather than by the
/// system segmented control** — because the system control has one width per
/// segment and draws no divider there, and those were the two things asked for.
///
/// The toolbar gives the item its glass capsule; this draws what is inside it.
public struct HelmToolbarSwitcher<Value: Hashable>: View {
    private let name: String
    private let segments: [HelmSwitcherSegment<Value>]
    @Binding private var selection: Value

    @Environment(\.helmSwitcherStyle) private var style
    @Environment(\.helmSetSwitcherStyle) private var setStyle

    public init(_ name: String, selection: Binding<Value>, segments: [HelmSwitcherSegment<Value>]) {
        self.name = name
        self.segments = segments
        self._selection = selection
    }

    // MARK: - Geometry, one set of numbers for the drawing and the estimate

    static var textPadding: CGFloat { 12 }
    static var iconSegment: CGFloat { 40 }
    static var iconAndTextPadding: CGFloat { 11 }
    static var iconColumn: CGFloat { 15 }
    static var iconGap: CGFloat { 6 }
    static var inset: CGFloat { 3 }
    static var divider: CGFloat { 1 }

    /// How wide the switcher draws in `style` — the word widths measured at the
    /// font the segments set them in. For `iconsNamingSelected` the widest word
    /// is the one counted, so the answer does not change with the selection.
    public static func width(of labels: [String], in style: ToolbarSwitcherStyle) -> CGFloat {
        guard !labels.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let inks = labels.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
        let count = CGFloat(labels.count)
        let chrome = (count - 1) * divider + inset * 2
        switch style {
        case .text:
            return inks.reduce(0, +) + count * textPadding * 2 + chrome
        case .icons:
            return count * iconSegment + chrome
        case .iconsAndText:
            return inks.reduce(0, +) + count * (iconColumn + iconGap + iconAndTextPadding * 2) + chrome
        case .iconsNamingSelected:
            let named = (inks.max() ?? 0) + iconColumn + iconGap + textPadding * 2
            return (count - 1) * iconSegment + named + chrome
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                segmentButton(segment)
                if index < segments.count - 1 {
                    // Only between two segments neither of which is selected:
                    // the selected pill is its own edge, as in AppKit's own
                    // segmented controls.
                    let quiet = segment.value != selection && segments[index + 1].value != selection
                    Rectangle()
                        .fill(quiet ? HelmSurface.hairline : Color.clear)
                        .frame(width: Self.divider, height: 16)
                }
            }
        }
        .padding(Self.inset)
        .fixedSize()
        .animation(HelmMotion.interface, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .contextMenu {
            if let setStyle {
                Picker(L("Tab labels"), selection: Binding(get: { style }, set: { setStyle($0) })) {
                    ForEach(ToolbarSwitcherStyle.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }

    private func segmentButton(_ segment: HelmSwitcherSegment<Value>) -> some View {
        let selected = segment.value == selection
        return Button {
            selection = segment.value
        } label: {
            label(segment, selected: selected)
                .foregroundStyle(selected ? Color.primary : HelmText.quiet)
                .frame(height: 30)
                .background {
                    if selected {
                        Capsule().fill(HelmSurface.panelSelection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(segment.label)
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func label(_ segment: HelmSwitcherSegment<Value>, selected: Bool) -> some View {
        switch style {
        case .text:
            Text(segment.label)
                .lineLimit(1)
                .padding(.horizontal, Self.textPadding)
        case .icons:
            Image(systemName: segment.symbol)
                .frame(width: Self.iconSegment)
        case .iconsAndText:
            HStack(spacing: Self.iconGap) {
                Image(systemName: segment.symbol).frame(width: Self.iconColumn)
                Text(segment.label).lineLimit(1)
            }
            .padding(.horizontal, Self.iconAndTextPadding)
        case .iconsNamingSelected:
            if selected {
                HStack(spacing: Self.iconGap) {
                    Image(systemName: segment.symbol).frame(width: Self.iconColumn)
                    Text(segment.label).lineLimit(1)
                }
                .padding(.horizontal, Self.textPadding)
            } else {
                Image(systemName: segment.symbol)
                    .frame(width: Self.iconSegment)
            }
        }
    }
}
