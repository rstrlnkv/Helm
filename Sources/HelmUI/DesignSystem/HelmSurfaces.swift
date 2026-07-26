import SwiftUI

/// The surfaces that give every Helm screen the same voice as the About page:
/// a glowing icon plate, instrument-style figures, and one card treatment.
public enum HelmSurface {
    public static let cardRadius: CGFloat = 12
    /// Measured against a real `Form` section on the same background: at 0.05
    /// the card sat 10 L from the panel where the system's section sits 7, in
    /// both themes — a heavier card claiming to be the same surface.
    public static let cardFill = Color.primary.opacity(0.035)
    public static let hairline = Color.primary.opacity(0.10)
    /// For things that float *over* content — a tooltip following the cursor.
    /// Cards sit in the page and take no border (see `helmCard`); a floating
    /// element needs an edge to separate it from whatever it covers.
    public static let floatingEdge = Color.primary.opacity(0.08)
}

public extension View {
    /// The one card in Helm: soft fill, continuous corners, no border.
    ///
    /// No border on purpose. Half of Helm's containers are macOS grouped-Form
    /// sections, which the system draws as a plain fill and which we cannot
    /// restyle — so an outlined card of our own would read as a different kind
    /// of box on the next page over. The system's treatment is the anchor.
    func helmCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                    .fill(HelmSurface.cardFill)
            )
    }
}

/// The icon plate from the About page, reused wherever a screen introduces
/// itself: the symbol sits on its tint, lit from behind by a soft glow.
public struct HelmIconPlate: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44

    public init(symbol: String, tint: Color, size: CGFloat = 44) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        ZStack {
            RadialGradient(colors: [tint.opacity(0.35), .clear],
                           center: .center, startRadius: 1, endRadius: size)
                .frame(width: size * 2, height: size * 2)
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(tint)
                )
        }
        .frame(width: size, height: size)
    }
}

/// A screen's masthead: icon plate, title, one line of what the screen is for,
/// and whatever control belongs at the far end (usually the on/off switch).
public struct HelmPageHeader<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailing: Trailing

    public init(symbol: String, tint: Color, title: String, subtitle: String,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 14) {
            HelmIconPlate(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.2)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

/// Instrument readout: monospaced figures over small-caps labels, split by
/// hairlines — the About page's version/build/modules row, generalized.
public struct HelmMetricStrip: View {
    public struct Metric: Identifiable {
        /// The label, not a fresh UUID: metrics are rebuilt inline from view
        /// model state, and a new identity on every publish made `ForEach` tear
        /// down and re-create every cell instead of updating it.
        public var id: String { label }
        public let value: String
        public let label: String
        public let tint: Color?

        public init(_ value: String, _ label: String, tint: Color? = nil) {
            self.value = value
            self.label = label
            self.tint = tint
        }
    }

    let metrics: [Metric]

    public init(_ metrics: [Metric]) { self.metrics = metrics }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(HelmSurface.hairline)
                        .frame(width: 1, height: 26)
                }
                VStack(spacing: 3) {
                    Text(metric.value)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(metric.tint ?? .primary)
                    Text(metric.label)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
