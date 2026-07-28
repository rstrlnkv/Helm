import SwiftUI

/// A page with nothing on it yet, or nothing left to show.
///
/// There were ten of these and they were drawn eight different ways: spacing 10
/// or 14, text wrapped at 360, 380, 420 or not at all, the button sometimes
/// large and sometimes not, one of them a hand-rolled `VStack` with its own
/// `Spacer`s. Nobody chose any of that — each was written next to the screen it
/// belonged to, and every one of them was reasonable on its own. Together they
/// made the app look assembled rather than built.
///
/// Two things wear this shape and they are not the same thing:
///
/// - **an invitation** — nothing here *yet*, and there is something to do about
///   it. It gets the symbol and the button.
/// - **a statement** — nothing matched, nothing is left, nothing was found. It
///   is a sentence and nothing else; a button here would be an invitation to
///   repeat what just failed.
///
/// The difference is which arguments are given, so a caller cannot accidentally
/// make one look like the other.
public struct HelmEmptyState<Actions: View>: View {
    private let symbol: String?
    private let tint: Color
    private let title: String?
    private let message: String
    private let note: String?
    private let actions: Actions

    public init(symbol: String? = nil,
                tint: Color = .secondary,
                title: String? = nil,
                message: String,
                note: String? = nil,
                @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.note = note
        self.actions = actions()
    }

    public var body: some View {
        HelmCenteredContent(spacing: Self.spacing) {
            if let symbol {
                HelmIconPlate(symbol: symbol, tint: tint, size: Self.plate)
            }
            if let title {
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            Text(message)
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Self.textWidth)
            if let note {
                // The second sentence of a statement: why there is nothing, or
                // what was not looked at. Quieter than the first, because
                // somebody who has their answer should not have to read it.
                Text(note)
                    .font(.caption)
                    .foregroundStyle(HelmText.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Self.textWidth)
            }
            actions
                // Set here rather than at each call site: two of the old ones
                // were large and two were not, for no reason either could give.
                .controlSize(.large)
        }
    }

    /// One answer each, so there is nothing left to decide at a call site.
    private static var spacing: CGFloat { 14 }
    private static var plate: CGFloat { 56 }
    /// Wide enough for two lines of a sentence at this size, narrow enough that
    /// the eye does not have to travel back across the window to read them.
    private static var textWidth: CGFloat { 380 }
}

public extension HelmEmptyState where Actions == EmptyView {
    /// A statement: nothing matched, nothing is left. No button — one here
    /// would invite somebody to repeat what just came back empty.
    ///
    /// The symbol is optional even so: "nothing was found" after a scan has
    /// earned a green check, while "type to search" is a caption and drawing a
    /// plate above it would announce an outcome where none happened yet.
    init(symbol: String? = nil, tint: Color = .secondary,
         title: String? = nil, message: String, note: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title,
                  message: message, note: note) { EmptyView() }
    }
}

/// Work in progress on an otherwise empty page.
///
/// The same three shapes problem, smaller: a bare spinner, a spinner with a
/// caption, and a spinner with a caption at a different size.
public struct HelmBusyState: View {
    private let message: String?

    public init(_ message: String? = nil) { self.message = message }

    public var body: some View {
        HelmCenteredContent(spacing: 10) {
            ProgressView().controlSize(.small)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
