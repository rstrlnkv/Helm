import SwiftUI

/// **One row of the settings sidebar: the glyph, filled when the row is selected, and the name; in the
/// rail the glyph alone.** The name is the tooltip in both, for a name cut short in the column, and the
/// accessibility label.
///
/// **It dims in a window that is not the active one** (`\.helmWindowAppearsActive`): the glyph, the name
/// and the mark take `HelmText.inactiveOpacity`; the fill stays, as System Settings' sidebar keeps its
/// selection and greys it. The environment value is the window's own reading, so whoever hosts the row in
/// a hosting controller of its own sets it on that root (`SettingsWindow`'s `TellsWindowActivity`).
///
/// **The kit knows nothing of permissions.** A row that cannot act is handed a `Warning`: the mark's
/// tooltip and the sentence VoiceOver reads after the position. VoiceOver reads "n of m" from
/// `Position`, because a column of buttons is not a list and says no position by itself.
public struct HelmSidebarRow: View {

    /// The row's mark and what it says: `mark` is the tooltip and the mark's own label, `spoken` the note
    /// read after the row's position, which names no subject of its own.
    public struct Warning {
        public let mark: String
        public let spoken: String

        public init(mark: String, spoken: String) {
            self.mark = mark
            self.spoken = spoken
        }
    }

    /// Where the row stands among the rows of the column, `index` from 1.
    public struct Position {
        public let index: Int
        public let count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }
    }

    /// The owner's measure for the row, which Helm's ladders have no rung within a point of.
    public static let height: CGFloat = 36
    private static let glyphSide: CGFloat = 16 * 1.3
    private static let selectionRadius: CGFloat = 8
    /// The side `HelmStatusDot` draws its dot at.
    private static let dotSide: CGFloat = 8

    private let title: String
    private let glyph: ShellGlyph
    private let selected: Bool
    private let collapsed: Bool
    private let warning: Warning?
    private let position: Position?
    private let action: () -> Void
    @State private var hover = false
    @Environment(\.helmWindowAppearsActive) private var active

    public init(title: String, glyph: ShellGlyph, selected: Bool, collapsed: Bool,
                warning: Warning? = nil, position: Position? = nil, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.selected = selected
        self.collapsed = collapsed
        self.warning = warning
        self.position = position
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HelmSpace.s4) {
                ShellGlyphView(glyph, filled: selected, size: Self.glyphSide)
                    // In the rail the mark sits on the glyph's own frame, so the glyph does not shift
                    // between a row that has one and one that has not. Centred on the frame's corner,
                    // the dot clears the glyph's strokes.
                    .overlay(alignment: .topTrailing) {
                        if collapsed, let warning { mark(warning).offset(x: Self.dotSide / 2, y: -Self.dotSide / 2) }
                    }
                if !collapsed {
                    HStack(spacing: HelmSpace.s3) {
                        Text(title).font(HelmText.rowTitle).lineLimit(1)
                        if let warning { mark(warning) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .opacity(active ? 1 : HelmText.inactiveOpacity)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : HelmSpace.s4)
            .frame(height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: Self.selectionRadius, style: .continuous)
                    .fill(selected ? HelmSurface.rowSelection : hover ? HelmSurface.rowHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The position and the note, or whichever of them the row has.
    private var spoken: String {
        switch (position, warning) {
        case let (position?, warning?): return HelmA11y.position(position.index, of: position.count, after: warning.spoken)
        case let (position?, nil): return HelmA11y.position(position.index, of: position.count)
        case let (nil, warning?): return warning.spoken
        case (nil, nil): return ""
        }
    }

    /// The row is on and cannot act. One fact, a small round mark; the pane the row leads to is where it
    /// is fixed.
    private func mark(_ warning: Warning) -> some View {
        Circle()
            .fill(HelmSignal.warning)
            .frame(width: Self.dotSide, height: Self.dotSide)
            .help(warning.mark)
            .accessibilityLabel(warning.mark)
    }
}
