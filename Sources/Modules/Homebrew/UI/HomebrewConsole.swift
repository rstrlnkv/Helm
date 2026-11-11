import AppKit
import SwiftUI
import HelmUI

struct HomebrewConsole: View {
    @ObservedObject var hb: HomebrewViewModel
    /// What the page draws of `showsConsole` (`HomebrewSettingsPage.shownConsole`): while it is
    /// false the scroll view is not mounted, so a closed console costs none. A run that opens it
    /// starts followed; a run over lines still kept keeps the scroll view and its `followsConsole`.
    let open: Bool
    @Environment(\.helmTraits) private var traits

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HStack(spacing: HelmSpace.s4) {
                statusPill
                Spacer()
                if hb.running {
                    // The only way out of a brew that will not finish: without it the
                    // module is dead until an app restart.
                    Button(HomebrewSettingsPage.stopTitle(for: hb.op)) { hb.stopOperation() }.controlSize(.small)
                }
                Button(HbStr.clear) { hb.clearConsole() }.controlSize(.small).disabled(hb.running)
            }
            // A view that is always there: a `Group` with nothing in it takes the padding,
            // the height and the well's fill with it, so the block would measure short and
            // the well would arrive in mid-flight. `Color.clear` also keeps the well's width.
            ZStack(alignment: .topLeading) {
                Color.clear
                if open {
                    ConsoleScroll(rows: hb.consoleRows, sequence: hb.consoleSequence)
                        // The offset must not read the reveal's moving frame, or it keeps a
                        // fraction of a point and every line stays soft until a remount.
                        .geometryGroup()
                        // `.identity`: an `if` inside the page's `withAnimation` would
                        // otherwise fade. The well arrives by height (`HelmAccordion`); the
                        // lines do not travel with it, they land at once and the
                        // `.clipped()` below shows them as the well reaches them.
                        .transition(.identity)
                }
            }
            // The scroll view lands at its place while the block is still rising: only
            // this clip keeps it inside the well in flight.
            .clipped()
            // **The inset is outside the scroll view, so its clip sits at the
            // inset.** Padding inside the scrolled content scrolls away with
            // it: the first line was off the top edge at rest only, and once
            // the console scrolled, a line partly cut by the top was cut at the
            // box's edge, its ink a point or two from it. With the padding out
            // here the visible text region is inset from the box on all four
            // sides in every scroll position, and a partly scrolled line is
            // clipped at the inset. The well's fill and corners are on the
            // outer box, below.
            .padding(Self.consoleInset)
            .frame(height: Self.consoleHeight)
            // `card` and not `ctl`: this page's own choice for a block-sized
            // well, not a rule of the design system.
            // The well's fill, `HelmSurface.wellFill`, is the token whose own
            // doc comment names console output.
            .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .fill(HelmSurface.wellFill))
        }
        .padding(HelmSpace.s5)
    }

    /// **How tall the console is: ten lines of what `brew` printed.**
    ///
    /// The space ladder stops at 40 and the type scale is not a scale of heights, so
    /// the height is derived: `brew upgrade` announces
    /// each step with a `==>` line and fetches under it, so a window that holds
    /// fewer than a handful of those shows the fetch and not what it belongs to,
    /// while one twice this deep is the page it arrives into.
    ///
    /// **The line is what SwiftUI lays out, asked of SwiftUI.** Ten of them with
    /// `HelmSpace.s1` between — the step the console's own stack uses — plus
    /// `consoleInset` above and below. Read off `NSFont`'s ascender, descender and leading the line is 13 pt at
    /// the default text size, while SwiftUI sets the same face on a 14 pt line: the pitch
    /// drawn is 16 and a formula counting 15 gives a box of nine whole lines, the
    /// tenth cut by the bottom edge with the inset gone (read once by hand, no guard).
    ///
    /// **Computed, not held, and it follows the system text size.** A `static
    /// let` would freeze at whatever the size was when the app launched, which is
    /// the reason `HelmMotion`'s reduce-motion flag is a computed property too: a
    /// person who raises their interface text size while Helm is open would
    /// otherwise get bigger lines in a box measured for the smaller ones.
    private static var consoleHeight: CGFloat {
        consoleLine * CGFloat(consoleLinesShown)
            + HelmSpace.s1 * CGFloat(consoleLinesShown - 1)
            + consoleInset * 2
    }

    /// What a console line is drawn in — one declaration, read by the rows and
    /// by the measurement of their height, so the box cannot be sized for a
    /// face the rows are not set in.
    static let consoleFont = HelmText.code

    /// One line's height, measured the way `SidebarComposerSheet` measures its
    /// note: a hosting controller asked what the text needs (`sizeThatFits`),
    /// which is SwiftUI's own answer and not a second account of it. A
    /// controller per read would be built per line of output, since the page
    /// redraws for each, so the reading is kept against the point size it was
    /// taken at and taken again when the system text size moves — the key is
    /// the size, so the cache cannot go stale the way a `static let` would.
    private static var consoleLine: CGFloat {
        let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
        if let held = measuredLine, held.size == size { return held.height }
        let height = NSHostingController(rootView: Text("M").font(consoleFont))
            .sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            .height
        measuredLine = (size, height)
        return height
    }

    private static var measuredLine: (size: CGFloat, height: CGFloat)?

    /// **How far the text sits from the box on every side.**
    ///
    /// `HelmSpace.s4`, the step between rows of one list: the monospaced lines
    /// were drawn flush to the well's edges, the first glyph on the left edge
    /// and the first line on the top. The box is taller by twice this, so the
    /// ten lines the derivation above promises are still ten with the inset
    /// taken off the top and the bottom.
    static let consoleInset = HelmSpace.s4

    /// The ten. Its own constant so the derivation above has something to name.
    static let consoleLinesShown = 10

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            // Waiting names what it waits for: the label is the operation's own
            // words («install Homebrew»), which say nothing about a window that
            // may be behind this one.
            HelmBusyLabel(HomebrewSettingsPage.pillTitle(for: hb.op), busy: true)
                .font(HelmText.rowDetail)
        case .done:
            Label(HbStr.done, systemImage: "checkmark.circle.fill").foregroundStyle(HelmSignal.success(increased: traits.increasedContrast)).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .stopped:
            // The person asked for this end; a red octagon would call their own
            // press a defect.
            Label(HbStr.stopped, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .authorizationDeclined:
            // A question answered no: neutral, with the sentence beside it.
            HStack(spacing: HelmSpace.s3) {
                Label(HbStr.cancelled, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
                if let note = HomebrewSettingsPage.failureNote(hb.op) {
                    Text(note).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .failed:
            HStack(spacing: HelmSpace.s3) {
                Label(HbStr.failed, systemImage: "xmark.octagon.fill").foregroundStyle(HelmSignal.danger(increased: traits.increasedContrast)).font(HelmText.rowDetail)
                if let note = HomebrewSettingsPage.failureNote(hb.op) {
                    Text(note).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .idle:
            EmptyView()
        }
    }
}

/// **The console's lines and the rule that follows them.** A struct of its own,
/// not a property of the page, so that its `followsConsole` lives exactly as
/// long as the scroll view does: a console the page has closed has no scroll
/// view, so the run that opens it starts followed; a run over lines still kept
/// keeps the scroll view, and a person who scrolled up stays where they are.
private struct ConsoleScroll: View {
    let rows: [HomebrewViewModel.ConsoleRow]
    /// `HomebrewViewModel.consoleSequence`: how many lines have ever arrived,
    /// so the newest line's identity is one less than this.
    let sequence: Int
    @State private var followsConsole = true
    /// Starts at the end, which is where a page mounted over lines opens —
    /// mounting is what coming back to the page, or a window returning from
    /// hidden, is. A short console still sits at the top of its box: an edge
    /// position moves nothing when there is nothing to scroll.
    @State private var position = ScrollPosition(edge: .bottom)
    /// What the hold below reads and never draws, so it is a reference and not
    /// a `@State` value: writing it must not redraw `HomebrewViewModel.consoleLimit` rows.
    @State private var book = Book()

    /// **The facts the hold needs between one arrival and the next.**
    /// `heights` is each row's measured height by its number; `firstID` the
    /// oldest row drawn when the last arrival was answered; `offset` where the
    /// scroll view stood.
    private final class Book {
        var heights: [Int: CGFloat] = [:]
        var firstID: Int?
        var offset: CGFloat = 0
    }

    /// The offset and the furthest the offset can go.
    struct Reach: Equatable {
        let offset: CGFloat
        let end: CGFloat
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                // Each row is its line's number and not its index: at the limit
                // an arrival drops the first line and every index moves up by
                // one, so an index is a different line's identity every time.
                ForEach(rows) { row in
                    // A text style follows the system text size where a frozen
                    // 11 does not (the same reason the fix command's field
                    // names its font by style). Held once because the box
                    // around this is measured in it.
                    Text(row.text).font(HomebrewConsole.consoleFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            book.heights[row.id] = height
                        }
                }
            }
            // The offered width, whether or not a line has arrived: a stack
            // takes the width of its widest child, so with no rows (a run that
            // has not printed yet, a failure with no line, a console just
            // cleared) it was 0 and the box drew as its insets alone, then
            // jumped to full width with the first line.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position)
        .onAppear { book.firstID = rows.first?.id }
        // **Follows the sequence, which moves with every arrival, never the
        // count.** At `HomebrewViewModel.consoleLimit` an arrival drops one
        // line and adds one, so the count stays where it is for ever and a
        // follow keyed to it went quiet at line number `consoleLimit`.
        //
        // **Following is a jump to the end and not an animated scroll.** Lines
        // arrive faster than an animation runs, and one restarted per arrival
        // trailed the end by thousands of points until the stream thinned; a
        // jump per arrival lands on the newest line each time.
        //
        // **A person who has scrolled up keeps the line they are reading.**
        // At the bound each arrival drops the oldest rows from the top, so an
        // offset that holds still lets the text slide down the box one row per
        // arrival. The rows dropped were measured while they were drawn, so
        // the offset is lowered by their heights and the spacing between them,
        // in the update that dropped them. When the line being read is among
        // the dropped, the offset would go below the top and stops at it: the
        // oldest lines that are left, not the end, which nobody asked for.
        .onChange(of: sequence) { _, _ in
            let first = rows.first?.id
            defer { book.firstID = first }
            if followsConsole {
                position.scrollTo(edge: .bottom)
            } else if let first, let was = book.firstID, first > was {
                var trimmed: CGFloat = 0
                for id in was..<first {
                    trimmed += (book.heights.removeValue(forKey: id) ?? 0) + HelmSpace.s1
                }
                position.scrollTo(y: max(0, book.offset - trimmed))
            }
        }
        // **Whether the person has scrolled up, read off the offset's own
        // moves.** A line arriving grows the content and leaves the offset
        // alone, so growth never reads as leaving the end; the follow's own
        // scroll only ever moves the offset down, so a move up while the
        // follow is on is the person leaving. The hold above moves the offset
        // up as well, but it runs only when `followsConsole` is already off,
        // so reading its move as leaving changes nothing; and reaching the end
        // again is the person coming back.
        .onScrollGeometryChange(for: Reach.self) { geometry in
            Reach(offset: geometry.contentOffset.y,
                  end: max(0, geometry.contentSize.height - geometry.containerSize.height))
        } action: { old, new in
            book.offset = new.offset
            guard new.offset != old.offset else { return }
            if new.offset < old.offset - 0.5 { followsConsole = false }
            if new.offset >= new.end - 1 { followsConsole = true }
        }
    }
}
