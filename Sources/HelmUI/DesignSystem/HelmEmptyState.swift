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
///
/// **And the sentence is optional too**, which is the third case: a page whose
/// explanation is already on screen, in a banner directly above. Keep Awake's app
/// list draws one when its stored rules cannot be read — «add the apps again» is
/// the banner's own last clause, and the invitation underneath was explaining
/// what an app rule is and reporting that none was chosen, which the banner had
/// just contradicted. So an invitation may be a plate and a verb. Every other
/// call site says something, and should: `nil` here is for when the words are
/// somewhere the reader is already looking.
public struct HelmEmptyState<Actions: View>: View {
    private let symbol: String?
    private let tint: Color
    private let title: String?
    private let message: String?
    private let note: String?
    private let actions: Actions

    public init(symbol: String? = nil,
                tint: Color = .secondary,
                title: String? = nil,
                message: String? = nil,
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
                // 16, not 17. `.title2` is 17 on macOS and this was typed as
                // one; the scale steps 13 · 16 · 22, and an empty state's
                // heading is the step above a section heading and well below a
                // hero figure.
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            if let message {
                Text(message)
                    // **Said, not inherited.** With no font of its own this took
                    // whatever the slot it was mounted in provides, and one of
                    // those slots is a `Form`'s section header — which is
                    // semibold. So the same component drew its sentence in two
                    // weights on one screen, 500 pt apart, on the VPN page.
                    // A sentence is the scale's body step wherever it is.
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Self.textWidth)
            }
            if let note {
                // The second sentence of a statement: why there is nothing, or
                // what was not looked at. Quieter than the first, because
                // somebody who has their answer should not have to read it.
                Text(note)
                    .font(HelmText.rowDetail)
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
    private static var spacing: CGFloat { HelmSpace.s5 }
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
/// The same shapes problem, smaller: a bare spinner, a spinner with a caption,
/// a spinner with a caption at a different size — and a spinner with a caption
/// and a Stop button, which is the one that never came here at all. Work in
/// Helm reads directories and runs other programs, so most of it can be
/// stopped; a busy state that had nowhere to put the button left its author to
/// centre a `VStack` between two `Spacer()`s instead, which is how the fourth
/// shape happened and why the guard was blind to it.
///
/// The slot is `HelmEmptyState`'s slot, down to the `Actions == EmptyView`
/// overload: waiting with nothing to do about it stays one argument long.
public struct HelmBusyState<Actions: View>: View {
    private let message: String?
    private let actions: Actions

    public init(_ message: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        HelmCenteredContent(spacing: HelmSpace.s5) {
            ProgressView().controlSize(.small)
            if let message {
                Text(message)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
            }
            actions
                // Not `.large`, which is what an empty state gives its button:
                // that one is the page's invitation and this one interrupts
                // something. Set here all the same, so the answer is given once.
                .controlSize(.regular)
                // The spinner sits one step above its caption; a button that
                // close to a line of text reads as part of the sentence.
                .padding(.top, HelmSpace.s2)
        }
    }
}

public extension HelmBusyState where Actions == EmptyView {
    /// Waiting with nothing to be done about it — a spinner, or a spinner and a
    /// line saying what is being waited for.
    init(_ message: String? = nil) {
        self.init(message) { EmptyView() }
    }
}
