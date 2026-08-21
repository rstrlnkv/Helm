import SwiftUI

/// **The rule: a row says what the decision needs, and a glyph beside it holds
/// the rest.**
///
/// A setting's line is a caption, not a page. When there is genuinely more to
/// say — what a permission leaves behind, what an option costs, an example of
/// the thing being described — the extra belongs *beside* the row rather than
/// under it: one short sentence in the row, and an ⓘ next to its name that opens
/// the wider explanation. The caption stays scannable down a column of settings;
/// the explanation gets room to be an explanation.
///
/// This exists because Keep Awake's lid row was **606 characters in German** —
/// seven drawn lines under one switch, 3.5× the next-longest caption on the same
/// page. Every word of it was true and none of it was skippable, which is the
/// shape this component is for: not padding to cut, but a paragraph in the wrong
/// place.
///
/// **What goes where.** In the row: what somebody needs to take the decision.
/// Behind the glyph: what follows from it — consequences, recovery, an example
/// they may have to type. If a fact is the only way out of a state the app
/// cannot reach (`sudo rm` on a rule left behind by a deleted Helm), it belongs
/// in the explanation, in full, and it may not be the thing that got cut.
///
/// **A popover, not an inline reveal and not a sheet**, and the Form is the
/// reason. These rows live inside a scrolling grouped `Form` whose label column
/// is *narrower* than the row: an inline block grows the column it is already
/// constrained by, pushes every row below it down, and would be the same wall of
/// text with a press in front of it. A sheet is the other error — «leave the
/// page» for a question about one line of it. A popover is anchored to the row
/// it explains, sized on its own terms rather than the column's, dismissed by
/// Escape or by clicking away, and it is what macOS itself puts behind the ⓘ in
/// System Settings. Two of this app's own settings pages already open one from a
/// control inside the form (`VPNConnectionCard`, Keep Awake's own duration
/// editor), so this is a shape the window is known to draw rather than an
/// assumption about it.
///
/// **The app's reveal rules do not reach inside a popover** — the block that
/// grows and clips (`helmAccordion`) is for a disclosure *in* the page, and what
/// arrives here is a window macOS opens with its own animation and its own
/// answer to Reduce Motion. The one thing Helm animates is the glyph, through
/// `helmSymbolSwap`, which collapses with the setting like every other token.
///
/// **The content is blocks rather than a string**, so the explanation can be
/// several points and an example without the caller assembling a paragraph out
/// of newlines — and so that a picture is one more case here and one more line
/// in `blockView`, rather than a new component. That case is deliberately not
/// written yet: there is nothing to draw in it today, and a case nothing
/// constructs is a promise with no test under it.
public struct HelmExplainer: View {

    /// What the glyph opens: a heading and the points under it.
    ///
    /// The title is the caller's — normally the row's own name, so the popover
    /// says which row it belongs to without a second string to translate and
    /// without a name that can drift from the control it explains.
    public struct Content: Equatable {
        public let title: String
        public let blocks: [Block]

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
    /// whether the disclosure is open — a control whose whole purpose is to
    /// show and hide answers its own press with silence otherwise.
    @State private var open = false

    public init(_ content: Content) {
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
        // A glyph is the whole face of this control. Read aloud it is «button»
        // until it is named, and the name is macOS's own for exactly this
        // control — «Подробнее» in the system's tables, not a translation.
        .accessibilityLabel(HelmA11y.moreInfo)
        // …and which of its two things it has just done. The popover is a
        // window, so nothing about the page changes when it opens: without this
        // the press has no answer at all.
        .accessibilityValue(HelmA11y.expanded(open))
        .help(HelmA11y.moreInfo)
        .popover(isPresented: $open, arrowEdge: .bottom) { HelmExplainerPage(content) }
    }

    private var glyph: String { open ? "info.circle.fill" : "info.circle" }
}

/// What the glyph opens, as a view of its own.
///
/// Not nested inside the button, because a popover is a window and a window
/// cannot be photographed offscreen: `cacheDisplay(in:to:)` renders the view it
/// is asked about, and `NSPopover` is not in that tree. As a type the page is
/// mountable on its own, so what the explanation *looks like* can be read off a
/// bitmap in both appearances and in all eight languages, which is the only form
/// in which a claim about it is worth anything.
struct HelmExplainerPage: View {

    private let content: HelmExplainer.Content

    init(_ content: HelmExplainer.Content) {
        self.content = content
    }

    /// 320 pt: the width macOS's own settings popovers open at, and — by
    /// coincidence rather than by dependency — what `helmPanelWidth` is. Not
    /// shared with it: a panel's width is a fact about the menu bar. Wider reads
    /// as a document, narrower turns three sentences into nine lines.
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
                // The one place this app sets a monospaced face on purpose:
                // what is inside is not language, it is something to be typed
                // exactly. A style rather than a size, so it scales with the
                // system's setting like the rest of the page.
                .font(.system(.subheadline, design: .monospaced))
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
