import SwiftUI

/// A page with nothing on it yet, or nothing left to show.
///
/// One shape for every empty page, so the app reads as built rather than
/// assembled. Two things wear it, and they are not the same thing:
///
/// - **an invitation**: nothing here *yet*, and there is something to do about
///   it. It gets the symbol and the button.
/// - **a statement**: nothing matched, nothing is left, nothing was found. It
///   is a sentence and nothing else; a button here would be an invitation to
///   repeat what just failed.
///
/// The difference is which arguments are given, so a caller cannot make one
/// look like the other. The sentence is optional too, for a page whose
/// explanation is already in a banner directly above (Keep Awake's app list
/// when its stored rules cannot be read). Every other call site says something.
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
                // 16, the scale's step above a section heading.
                Text(title).font(HelmText.plateTitle)
            }
            if let message {
                Text(message)
                    // Said, not inherited: in a `Form`'s section header the
                    // slot is semibold. A sentence is the body step wherever
                    // it is.
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
                // Set here rather than at each call site.
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

extension HelmEmptyState where Actions == EmptyView {
    /// A statement: nothing matched, nothing is left. No button — one here
    /// would invite somebody to repeat what just came back empty.
    ///
    /// The symbol is optional even so: "nothing was found" after a scan has
    /// earned a green check, while "type to search" is a caption and drawing a
    /// plate above it would announce an outcome where none happened yet.
    public init(symbol: String? = nil, tint: Color = .secondary,
         title: String? = nil, message: String, note: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title,
                  message: message, note: note) { EmptyView() }
    }
}

/// Work in progress on an otherwise empty page.
///
/// The slot is `HelmEmptyState`'s, with room for a Stop button, since most of
/// Helm's work reads directories or runs other programs and can be stopped.
/// The `Actions == EmptyView` overload keeps a plain wait one argument long.
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
                    .helmQuietDetail()
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

extension HelmBusyState where Actions == EmptyView {
    /// Waiting with nothing to be done about it — a spinner, or a spinner and a
    /// line saying what is being waited for.
    public init(_ message: String? = nil) {
        self.init(message) { EmptyView() }
    }
}

/// A button's label while the button's own work runs: a small spinner before the words.
public struct HelmBusyLabel: View {
    private let title: String
    private let busy: Bool

    public init(_ title: String, busy: Bool) {
        self.title = title
        self.busy = busy
    }

    public var body: some View {
        if busy {
            HStack(spacing: HelmSpace.s3) {
                ProgressView().controlSize(.small)
                Text(title)
            }
        } else {
            Text(title)
        }
    }
}
