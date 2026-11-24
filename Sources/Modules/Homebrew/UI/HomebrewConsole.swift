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
                Button(HelmWord.clear) { hb.clearConsole() }.controlSize(.small).disabled(hb.running)
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
            // inset:** padding inside the scrolled content would scroll away,
            // and a partly scrolled line would be cut at the box's edge.
            .padding(Self.consoleInset)
            .frame(height: Self.consoleHeight)
            // `card` and not `ctl`: this page's choice for a block-sized well.
            .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .fill(HelmSurface.wellFill))
        }
        .padding(HelmSpace.s5)
    }

    /// **How tall the console is: ten lines of what `brew` printed.**
    ///
    /// `brew upgrade` announces each step with a `==>` line and fetches under
    /// it; fewer lines show the fetch without what it belongs to.
    ///
    /// **The line is what SwiftUI lays out, asked of SwiftUI.** Ten of them with
    /// `HelmSpace.s1` between, plus `consoleInset` above and below. `NSFont`'s
    /// metrics give a shorter line than SwiftUI draws, and the tenth line would
    /// be cut.
    ///
    /// **Computed, not held, so it follows the system text size** changed
    /// while Helm is open.
    private static var consoleHeight: CGFloat {
        consoleLine * CGFloat(consoleLinesShown)
            + HelmSpace.s1 * CGFloat(consoleLinesShown - 1)
            + consoleInset * 2
    }

    /// What a console line is drawn in — one declaration, read by the rows and
    /// by the measurement of their height, so the box cannot be sized for a
    /// face the rows are not set in.
    static let consoleFont = HelmText.code

    /// One line's height: a hosting controller asked what the text needs
    /// (`sizeThatFits`). The page redraws per line of output, so the reading is
    /// kept against the point size it was taken at and retaken when it moves.
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
    /// The box is taller by twice this, so ten lines still fit inside it.
    static let consoleInset = HelmSpace.s4

    static let consoleLinesShown = 10

    /// An end that is not a success: its mark, and the sentence beside it when
    /// there is one.
    private func failureLine(_ mark: some View) -> some View {
        HStack(spacing: HelmSpace.s3) {
            mark
            if let note = HomebrewSettingsPage.failureNote(hb.op) {
                HelmSettingsNote(note)
            }
        }
    }

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            // Waiting names what it waits for (`pillTitle`), not the operation.
            HelmBusyLabel(HomebrewSettingsPage.pillTitle(for: hb.op), busy: true)
                .font(HelmText.rowDetail)
        case .done:
            Label(HelmWord.done, systemImage: "checkmark.circle.fill").foregroundStyle(HelmSignal.success(increased: traits.increasedContrast)).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .stopped:
            // The person asked for this end: not red.
            Label(HelmWord.stopped, systemImage: "stop.circle.fill").helmQuietDetail()
        case .failed where hb.op.reason == .authorizationDeclined:
            // A question answered no: neutral, with the sentence beside it.
            failureLine(Label(HbStr.cancelled, systemImage: "stop.circle.fill").helmQuietDetail())
        case .failed:
            failureLine(Label(HbStr.failed, systemImage: "xmark.octagon.fill")
                .foregroundStyle(HelmSignal.danger(increased: traits.increasedContrast)).font(HelmText.rowDetail))
        case .idle:
            EmptyView()
        }
    }
}

/// **The console's lines and the rule that follows them.** A struct of its own,
/// so `followsConsole` lives exactly as long as the scroll view: a run that
/// opens the console starts followed; one over kept lines keeps the person's
/// scroll.
private struct ConsoleScroll: View {
    let rows: [HomebrewViewModel.ConsoleRow]
    /// `HomebrewViewModel.consoleSequence`: how many lines have ever arrived,
    /// so the newest line's identity is one less than this.
    let sequence: Int
    @State private var followsConsole = true
    /// Starts at the end, where a page mounted over lines opens. A short
    /// console still sits at the top: there is nothing to scroll.
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
                // Each row is its line's number, not its index: at the limit
                // every index moves up by one per arrival.
                ForEach(rows) { row in
                    // The font the box is measured in.
                    Text(row.text).font(HomebrewConsole.consoleFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            book.heights[row.id] = height
                        }
                }
            }
            // The offered width even with no rows, or the box jumps to full
            // width with the first line.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position)
        .onAppear { book.firstID = rows.first?.id }
        // **Follows the sequence, never the count,** which stops moving at
        // `HomebrewViewModel.consoleLimit`.
        //
        // **Following is a jump to the end, not an animated scroll:** lines
        // arrive faster than an animation runs.
        //
        // **A person who has scrolled up keeps the line they are reading.**
        // The rows trimmed from the top were measured while drawn, so the
        // offset is lowered by their heights and spacing; it stops at the top
        // if the line being read was trimmed.
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
        // **Whether the person has scrolled up, read off the offset's moves.**
        // Growth leaves the offset alone and the follow only moves it down, so
        // a move up while following is the person leaving (the hold above runs
        // only when following is off). Reaching the end again is coming back.
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
