import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// Which figure the hero shows, chosen beside the module's name.
///
/// **It lives in the header because it is a question about the figure, and the
/// figure is the first thing on the page.** Between the periods it was one more
/// button in a row of seven, where «which number» and «over what» read as one
/// list of seven equal choices — and they are two questions.
///
/// A segmented control here rather than two buttons: it is a two-way choice of
/// one thing, it sits in a strip that has no width to spare, and unlike the
/// hero's row this one never has to wrap. The glyph pair measures 52 pt, which
/// the header has.
///
/// The choice is kept in the module's store rather than passed down, because
/// the header and the page are two views with no parent between them —
/// `.helmStoreChanged` is what keeps them saying the same thing.
struct LayoutHeaderMetric: View {

    let store: NamespacedStore
    @State private var metric: HeroMetric

    init(store: NamespacedStore) {
        self.store = store
        _metric = State(initialValue: HeroMetric(
            rawValue: store.string(LayoutKey.heroMetric, default: "")) ?? .words)
    }

    var body: some View {
        Picker(LyStr.whatTheFigureShows, selection: $metric) {
            ForEach(HeroMetric.allCases, id: \.self) { option in
                Image(systemName: option.symbol)
                    .accessibilityLabel(option.name)
                    .help(option.name)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .onChange(of: metric) { _, new in store.set(new.rawValue, for: LayoutKey.heroMetric) }
        // The page writes the same key when it is rebuilt for another reason,
        // and a header holding a stale choice would draw one figure while the
        // page draws the other.
        .onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { _ in
            let stored = HeroMetric(rawValue: store.string(LayoutKey.heroMetric, default: "")) ?? .words
            if stored != metric { metric = stored }
        }
    }
}
