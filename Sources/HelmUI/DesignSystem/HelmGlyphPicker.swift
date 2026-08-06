import SwiftUI

/// The symbols a tab can be marked with, in the groups somebody would look for
/// them in.
///
/// Not «every SF Symbol»: that is a search field over five thousand names, and
/// the question here is «which of these six pictures is my tab», which is
/// answered by looking rather than by typing. Shortcuts asks it the same way —
/// a grid, a handful of categories, no search.
public enum HelmGlyphCatalogue {
    public struct Category: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let symbols: [String]
    }

    public static var categories: [Category] {
        [
            .init(id: "general", title: L("General"), symbols: [
                "square.grid.2x2", "star", "bolt", "flag",
                "tag", "bookmark", "bell", "heart",
            ]),
            .init(id: "work", title: L("Work"), symbols: [
                "folder", "doc", "tray", "archivebox",
                "calendar", "clock", "checklist", "briefcase",
            ]),
            .init(id: "system", title: L("System"), symbols: [
                "gearshape", "wrench.and.screwdriver", "cpu", "memorychip",
                "internaldrive", "externaldrive", "gauge.with.dots.needle.33percent", "battery.100",
            ]),
            .init(id: "network", title: L("Network"), symbols: [
                "network", "wifi", "antenna.radiowaves.left.and.right", "globe",
                "lock.shield", "link", "arrow.up.arrow.down", "cloud",
            ]),
            .init(id: "media", title: L("Media"), symbols: [
                "play.circle", "music.note", "speaker.wave.2", "camera",
                "photo", "film", "mic", "headphones",
            ]),
            .init(id: "nature", title: L("Nature"), symbols: [
                "moon", "sun.max", "cloud.rain", "leaf",
                "drop", "flame", "snowflake", "sparkles",
            ]),
        ]
    }

    /// Every symbol on offer, for a caller that needs to hand one out.
    public static var all: [String] { categories.flatMap(\.symbols) }
}

/// Choosing one of them: a category down the side, a grid beside it.
///
/// Sized for a popover off a 300 pt panel, so the grid is four across — wider
/// and the popover is wider than the thing it belongs to.
public struct HelmGlyphPicker: View {
    private let selected: String?
    private let choose: (String) -> Void
    @State private var category: String

    public init(selected: String?, choose: @escaping (String) -> Void) {
        self.selected = selected
        self.choose = choose
        // Open on the category the current symbol is in, not on the first one:
        // the picker is opened to *change* a choice far more often than to make
        // the first one.
        _category = State(initialValue: HelmGlyphCatalogue.categories.first {
            $0.symbols.contains(selected ?? "")
        }?.id ?? HelmGlyphCatalogue.categories[0].id)
    }

    private var symbols: [String] {
        HelmGlyphCatalogue.categories.first { $0.id == category }?.symbols ?? []
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Category"), selection: $category) {
                ForEach(HelmGlyphCatalogue.categories) { group in
                    Text(group.title).tag(group.id)
                }
            }
            .labelsHidden()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 4),
                      spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    Button { choose(symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(symbol == selected ? Color.white : Color.primary)
                            .frame(width: 40, height: 32)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(symbol == selected ? AnyShapeStyle(Color.accentColor)
                                      : AnyShapeStyle(HelmSurface.wellFill)))
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                    .accessibilityLabel(symbol)
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
