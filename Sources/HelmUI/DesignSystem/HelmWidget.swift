import SwiftUI

/// The parts a panel widget is made of.
///
/// **A size is a different question, not a smaller answer.** 1×1 says how much,
/// 2×1 says how much and what to do about it, 2×N says why it is that much. So
/// these are not one view with a scale factor: they are the pieces each of the
/// three answers is built from, and a module picks the ones its answer needs.
///
/// Written once here, so the panel's tiles are the same object seen at three
/// magnifications rather than each module's own heading.
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

    /// The panel's module tile. It is `HelmIconPlate` at panel size, so the
    /// radius, the glyph proportion and the shadow are the app's, not this file's.
    private var badge: some View {
        HelmIconPlate(symbol: symbol, tint: tint, size: 26, active: active)
            .accessibilityHidden(true)
    }

    /// 1×1: the name goes **under** the plate, as in a small widget on iOS. In
    /// a row the name has too little width to survive translation, and edit
    /// mode's corner controls take more: stacked, it has the tile's whole width.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                badge
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
        // 26 and 13 semibold, one size for the plate in every tile, so two
        // widgets a card apart never show two sizes of it.
        HStack(spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    // `HelmText.sectionHeading`, not `.headline`, which
                    // resolves to bold at the same 13 pt.
                    .font(HelmText.sectionHeading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .helmQuietDetail()
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

    /// The size decides, not the call site: a parameter every caller must
    /// remember to compute is one half of them will not.
    public init(_ value: String, _ label: String, _ size: PanelWidgetSize) {
        self.value = value; self.label = label; self.small = size == .compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: small ? 15 : 20, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .helmQuietDetail()
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
