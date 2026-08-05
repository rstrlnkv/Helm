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
    private let trailing: AnyView?

    public init(symbol: String, tint: Color, name: String) {
        self.symbol = symbol; self.tint = tint; self.name = name; self.trailing = nil
    }

    public init<T: View>(symbol: String, tint: Color, name: String,
                         @ViewBuilder trailing: () -> T) {
        self.symbol = symbol; self.tint = tint; self.name = name
        self.trailing = AnyView(trailing())
    }

    public var body: some View {
        HStack(spacing: 8) {
            HelmIconPlate(symbol: symbol, tint: tint, size: 18)
            Text(name)
                .font(HelmText.rowTitle.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
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

    public init(_ value: String, _ label: String, small: Bool = false) {
        self.value = value; self.label = label; self.small = small
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
