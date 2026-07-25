import SwiftUI

/// The surfaces that give every Helm screen the same voice as the About page:
/// a glowing icon plate, instrument-style figures, and one card treatment.
public enum HelmSurface {
    public static let cardRadius: CGFloat = 12
    public static let cardFill = Color.primary.opacity(0.05)
    public static let cardStroke = Color.primary.opacity(0.08)
    public static let hairline = Color.primary.opacity(0.10)
}

public extension View {
    /// The card used across Helm: soft fill, hairline edge, continuous corners.
    func helmCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                    .fill(HelmSurface.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                    .strokeBorder(HelmSurface.cardStroke)
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
        public let id = UUID()
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
        .padding(.vertical, 12)
        // A system material so page content reads as blurred underneath when
        // it scrolls past, the way macOS treats floating panels.
        .background(
            RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                .strokeBorder(HelmSurface.cardStroke)
        )
    }
}

public extension View {
    /// Pins an instrument strip above a scrolling page: the panel floats with
    /// margins, and the content below gets matching inset so nothing is ever
    /// cut off flush against it.
    func helmMetricsHeader<Strip: View>(@ViewBuilder _ strip: () -> Strip) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            strip()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
    }
}
