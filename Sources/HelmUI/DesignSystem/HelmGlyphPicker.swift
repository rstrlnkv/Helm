import SwiftUI

/// The symbols a tab can be marked with, in the groups somebody would look for
/// them in.
///
/// Not «every SF Symbol»: that is a search field over five thousand names, and
/// the question here is «which of these six pictures is my tab», which is
/// answered by looking rather than by typing. Shortcuts asks it the same way —
/// a grid, a handful of categories, no search.
enum HelmGlyphCatalogue {
    struct Category: Identifiable, Sendable {
        let id: String
        let title: String
        let symbols: [String]
    }

    static var categories: [Category] {
        [
            .init(id: "general", title: L(.general), symbols: [
                "square.grid.2x2", "star", "bolt", "flag",
                "tag", "bookmark", "bell", "heart",
            ]),
            .init(id: "work", title: L(.work), symbols: [
                "folder", "doc", "tray", "archivebox",
                "calendar", "clock", "checklist", "briefcase",
            ]),
            // Not "System": in Russian, Spanish and Portuguese the four
            // "System …" tags of other screens are adjectives («Системный»,
            // "Del sistema"), and this word would need a noun.
            //
            // The name is kept and the two symbols that were not hardware are
            // the ones that went: a gear and a wrench were the only members a
            // reader would have had to excuse. They are also Helm's own chrome
            // — `gearshape` marks the Settings page in the sidebar, in its
            // header and in the panel's footer, `wrench.and.screwdriver` the
            // panel's edit button — so a tab wearing one read as a control of
            // the app rather than as somebody's tab. A keyboard and a display
            // in their place, which keeps every category at two full rows of
            // the four-wide grid.
            .init(id: "hardware", title: L(.hardware), symbols: [
                "keyboard", "display", "cpu", "memorychip",
                "internaldrive", "externaldrive", "gauge.with.dots.needle.33percent", "battery.100",
            ]),
            .init(id: "network", title: L(.network), symbols: [
                "network", "wifi", "antenna.radiowaves.left.and.right", "globe",
                "lock.shield", "link", "arrow.up.arrow.down", "cloud",
            ]),
            .init(id: "media", title: L(.media), symbols: [
                "play.circle", "music.note", "speaker.wave.2", "camera",
                "photo", "film", "mic", "headphones",
            ]),
            .init(id: "nature", title: L(.nature), symbols: [
                "moon", "sun.max", "cloud.rain", "leaf",
                "drop", "flame", "snowflake", "sparkles",
            ]),
        ]
    }
}

/// Choosing one of them: a category picker over a grid.
///
/// 220 pt wide, four across.
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

    private var group: HelmGlyphCatalogue.Category? {
        HelmGlyphCatalogue.categories.first { $0.id == category }
    }

    private var symbols: [String] { group?.symbols ?? [] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L(.category), selection: $category) {
                ForEach(HelmGlyphCatalogue.categories) { group in
                    Text(group.title).tag(group.id)
                }
            }
            .labelsHidden()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 4),
                      spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.element) { index, symbol in
                    Button { choose(symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(symbol == selected ? HelmText.onFill : Color.primary)
                            .frame(width: 40, height: 32)
                            .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                                .fill(symbol == selected ? AnyShapeStyle(Color.accentColor)
                                      : AnyShapeStyle(HelmSurface.wellFill)))
                    }
                    .buttonStyle(.plain)
                    // The category and the place in it, not the symbol's name.
                    //
                    // The name was the only label the grid offered, so VoiceOver
                    // read «gauge dot with dot dots dot needle dot 33 percent»
                    // — an identifier for the drawing, in a picker whose whole
                    // argument is that you choose these by looking rather than
                    // by reading names. Neither part needs its own string: the
                    // category is already translated and the rest is a number.
                    .accessibilityLabel("\(group?.title ?? "") \(index + 1)")
                    .accessibilityAddTraits(symbol == selected ? [.isSelected] : [])
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
