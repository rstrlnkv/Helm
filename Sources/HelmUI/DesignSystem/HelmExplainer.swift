import SwiftUI

/// **The rule: a row says what the decision needs, and a glyph beside it holds
/// the rest.**
///
/// A setting's line is a caption, not a page. When there is genuinely more to
/// say — what a permission leaves behind, what an option costs, an example —
/// it goes in an ⓘ beside the row's name, and the caption stays scannable down
/// a column of settings. In the row: what somebody needs to take the decision.
/// Behind the glyph: what follows from it, such as consequences, recovery, or a
/// command to type. A fact that is the only way out of a state the app cannot
/// reach (`sudo rm` on a rule left by a deleted Helm) goes in the explanation in
/// full.
///
/// **A popover, not an inline reveal and not a sheet.** An inline block pushes
/// every row below it down and is the same wall of text behind a press; a sheet
/// leaves the page for a question about one line of it. A popover is anchored
/// to its row, sized on its own terms, dismissed by Escape or a click away, and
/// is what System Settings puts behind its ⓘ.
///
/// The app's reveal rules do not reach inside: macOS opens the popover with its
/// own animation and its own answer to Reduce Motion. Helm animates only the
/// glyph, through `helmSymbolSwap`.
///
/// The content is blocks rather than a string, so an explanation can be several
/// points and an example without the caller assembling a paragraph out of
/// newlines.
public struct HelmExplainer: View {

    /// What the glyph opens: a heading and the points under it.
    ///
    /// The title is the caller's, normally the row's own name, so the popover
    /// says which row it belongs to with no second string to translate.
    public struct Content: Equatable {
        public let title: String
        let blocks: [Block]

        public init(title: String, blocks: [Block]) {
            self.title = title
            self.blocks = blocks
        }
    }

    /// One piece of the explanation. Exhaustive on purpose, and switched over
    /// without a `default:` — a kind that is added is a kind every drawing site
    /// has to answer for.
    public enum Block: Equatable {
        /// A point, in the language of the app.
        case text(String)
        /// Something to type, verbatim in every language: a command, a path.
        /// Selectable, because a person reading it has to get it into a
        /// terminal.
        case command(String)
    }

    private let content: Content
    /// The popover's own state, held here so a caller cannot forget to say
    /// whether it is open.
    @State private var open = false

    init(_ content: Content) {
        self.content = content
    }

    public var body: some View {
        Button {
            open.toggle()
        } label: {
            Image(systemName: glyph)
                // The row's own caption step, so the mark keeps its size beside
                // the name whatever the system's text size is set to.
                .font(HelmText.rowDetail)
                // Literal both ways: a mark carries meaning, so it answers to
                // the 3:1 threshold rather than to `.secondary`.
                .foregroundStyle(open ? Color.accentColor : HelmText.separator)
                .helmSymbolSwap(glyph)
        }
        .buttonStyle(.plain)
        // A glyph is the whole face of this control, so it is named, with
        // macOS's own word for exactly this control.
        .accessibilityLabel(HelmA11y.moreInfo)
        // …and which of its two things it has just done: the popover is a
        // window, so nothing on the page changes when it opens.
        .accessibilityValue(HelmA11y.expanded(open))
        .help(HelmA11y.moreInfo)
        .popover(isPresented: $open, arrowEdge: .bottom) { HelmExplainerPage(content) }
    }

    private var glyph: String { open ? "info.circle.fill" : "info.circle" }
}

/// What the glyph opens, as a view of its own.
///
/// Not nested inside the button, because a popover is a window and
/// `cacheDisplay(in:to:)` does not see it. As a type of its own the page can be
/// mounted and photographed in both appearances and all eight languages.
struct HelmExplainerPage: View {

    private let content: HelmExplainer.Content

    init(_ content: HelmExplainer.Content) {
        self.content = content
    }

    /// 320 pt: the width macOS's own settings popovers open at. Equal to
    /// `helmPanelWidth` by coincidence, so not shared with it. Wider reads as a
    /// document, narrower turns three sentences into nine lines.
    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(content.title)
                .font(HelmText.sectionHeading)
            // The offset is the identity: two identical points are two points,
            // and nothing here reorders.
            ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .padding(HelmSpace.s6)
    }

    @ViewBuilder private func blockView(_ block: HelmExplainer.Block) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(HelmText.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
        case .command(let command):
            Text(command)
                .font(HelmText.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, HelmSpace.s3)
                .padding(.horizontal, HelmSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        .fill(HelmSurface.wellFill)
                )
        }
    }
}
