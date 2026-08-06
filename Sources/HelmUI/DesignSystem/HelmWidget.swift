import SwiftUI

/// The parts a panel widget is made of.
///
/// **A size is a different question, not a smaller answer.** 1×1 says how much,
/// 2×1 says how much and what to do about it, 2×N says why it is that much. So
/// these are not one view with a scale factor: they are the pieces each of the
/// three answers is built from, and a module picks the ones its answer needs.
///
/// Written once here because nine modules would otherwise each invent a
/// heading, and the panel's whole claim is that its tiles are the same object
/// seen at three magnifications.
public struct HelmWidgetHeader: View {
    private let symbol: String
    private let tint: Color
    private let name: String
    private let subtitle: String?
    private let active: Bool
    private let trailing: AnyView?

    private let compact: Bool

    public init(symbol: String, tint: Color, name: String,
                subtitle: String? = nil, active: Bool = true, compact: Bool = false) {
        self.symbol = symbol; self.tint = tint; self.name = name
        self.subtitle = subtitle; self.active = active; self.compact = compact
        self.trailing = nil
    }

    public init<T: View>(symbol: String, tint: Color, name: String,
                         subtitle: String? = nil, active: Bool = true, compact: Bool = false,
                         @ViewBuilder trailing: () -> T) {
        self.symbol = symbol; self.tint = tint; self.name = name
        self.subtitle = subtitle; self.active = active; self.compact = compact
        self.trailing = AnyView(trailing())
    }

    public var body: some View {
        if compact { stacked } else { inARow }
    }

    /// 1×1: the name goes **under** the plate, as it does in a small widget on
    /// iOS.
    ///
    /// In a row it had 70 pt — 134 of tile less the card's padding, the plate,
    /// the gap and the spacer — and 58 with a trailing mark. Measured against
    /// `.headline` in eight languages, that truncates the module's own name in
    /// 14 of 40 pairs: «Автоп…», «Кла…». In edit mode the corner controls take
    /// another 14 and even «Не спать» became «Не с…» — a mode meant to show you
    /// your arrangement was changing what the tiles said. Stacked, the name has
    /// the tile's whole width.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HelmIconBadge(symbol: symbol, color: tint, active: active)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            Text(name)
                .font(HelmText.sectionHeading)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var inARow: some View {
        // 26 and 13 semibold, which is what the two tiles this app shipped with
        // have always used. The widgets written since used 18 and a medium 13,
        // so a panel holding both had two sizes of the same plate one card
        // apart — the sort of difference nobody can name and everybody sees.
        HStack(spacing: 10) {
            HelmIconBadge(symbol: symbol, color: tint, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    // `HelmText.sectionHeading`, not `.headline`: the same
                    // 13 pt, one weight apart. `.headline` resolves to
                    // SF Bold and the app's own token at that size is semibold.
                    .font(HelmText.sectionHeading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
    }
}

/// The number, and what it is the number of.
///
/// Monospaced digits, because a figure that changes every second must not move
/// the words under it — the countdown is the case that proves it.
public struct HelmWidgetFigure: View {
    private let value: String
    private let label: String
    private let small: Bool

    /// The size decides, not the call site.
    ///
    /// Three widgets passed `small: size == .compact` and two passed nothing,
    /// so a 1×1 row held an 18 pt digit beside an 11 pt one — 34% apart, in the
    /// same grid. A parameter that every caller has to remember to compute is a
    /// parameter that half of them will not.
    public init(_ value: String, _ label: String, _ size: PanelWidgetSize) {
        self.value = value; self.label = label; self.small = size == .compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: small ? 15 : 20, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line of a 2×N widget's list: a name that gives way, a value that does
/// not.
public struct HelmWidgetRow: View {
    private let name: String
    private let value: String?

    public init(_ name: String, _ value: String? = nil) {
        self.name = name; self.value = value
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(HelmText.rowDetail)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(HelmText.rowDetail)
                    .monospacedDigit()
                    .foregroundStyle(HelmText.quiet)
            }
        }
    }
}

/// What a widget says when the thing it reports has never been measured.
///
/// Not an empty tile and not a zero: zero is a measurement, and a widget that
/// shows one it never took is lying in the most ordinary way a widget can.
public struct HelmWidgetUnmeasured: View {
    private let message: String

    public init(_ message: String) { self.message = message }

    public var body: some View {
        Text(message)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.faint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The card every widget sits on, whatever its size.
public struct HelmWidgetBody<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .helmPanelCard()
    }
}
