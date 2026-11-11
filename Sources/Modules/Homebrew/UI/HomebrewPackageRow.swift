import SwiftUI
import HelmUI

/// A row of the master list — no button, at any width:
/// `mark · name · badges … version · chevron`.
/// The one place an action ever draws is `packageDetail`, whether it sits
/// beside this list or replaces it — selecting a row is what reaches it,
/// which is the only way a selectable `List` row and a button never fight
/// the same click.
///
/// `desc` is passed only from the single-column branch, where there is no
/// package view beside the row to carry it — the row has the whole pane
/// to itself there, and keeps the description rather than dropping it,
/// since nothing else on that screen says what the package is before it is
/// selected. `nil` omits the second line entirely rather than reserving an
/// empty one, since the split layout never re-flows a row that never draws
/// a description at all.
struct HomebrewPackageRow: View {
    @Environment(\.helmTraits) private var traits
    let name: String
    let detail: String?
    let isCask: Bool
    let singleColumn: Bool
    var pinned = false
    var hasUpdate: Bool?
    var desc: String?

    var body: some View {
        HStack(spacing: HelmSpace.s3) {
            // **nil is «this list never marks updates», and draws no column at
            // all** — the search hits, and the updates list, where every row is
            // outdated and a mark on each would be an ornament. A `Bool` is
            // «this list marks them», and then every row keeps the slot whether
            // or not its own package has an update: otherwise on the
            // installed list the marked row's name starts a mark's width to
            // the right of every other name in the column, so the one package
            // that wants attention is the one whose name does not line up.
            // A leading column is the shape Mail's unread dot has always had.
            if let hasUpdate {
                // The only carrier of "an update exists" for this row, and a
                // glyph rather than a dot for two reasons it takes both to
                // settle. SwiftUI does not make a `Shape` an accessibility
                // element, so an `.accessibilityLabel` on a `Circle` sits on
                // nothing and VoiceOver reads the row without the fact; an `Image` is an element and the label lands on it.
                // And a dot has colour and no form, so the one reader who most
                // needs a second channel — somebody who sees the screen but not
                // the orange — has a marker that differs from "no marker" by
                // hue alone. The arrow is `packageDetail`'s own symbol for this
                // same fact, so the row and the package screen say it one way.
                Image(systemName: Self.updateMarkSymbol)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                    .accessibilityLabel(HbStr.updateAvailable)
                    // Kept in the layout and taken out of both readings when
                    // there is nothing to say: invisible, and not an element
                    // VoiceOver stops on to read «Update available» over a
                    // package that has none.
                    .opacity(hasUpdate ? 1 : 0)
                    .accessibilityHidden(!hasUpdate)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                HStack(spacing: HelmSpace.s3) {
                    Text(name).lineLimit(1)
                    // Only when it says something: 46 of 47 rows were
                    // "formula", and a label with one value is an ornament. A
                    // pinned formula and a cask can both carry a badge here —
                    // see `updatesList`'s own comment on why that is
                    // representable even though `brew pin` never does it.
                    if isCask { HelmBadge(HbStr.cask, tint: Self.caskTint) }
                    if pinned { HelmBadge(HbStr.pinned) }
                }
                if let desc {
                    Text(desc).font(HelmText.smallPrint).foregroundStyle(HelmText.quiet).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // **A column, not a word after the name**: inline, a version starts
            // where its name ends and a list of them cannot be read down. At the
            // trailing edge they line up under the column's own heading
            // (`HomebrewColumnHeader`), in figures that do not jump as they change.
            if let detail {
                Text(detail).font(HelmText.figureFont).foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            RowChevron(singleColumn: singleColumn)
        }
        .helmListRow()
        .helmOpensAScreen(singleColumn)
    }

    /// The update mark's symbol — named once because the heading over the
    /// installed list reserves exactly its width (`HomebrewColumnHeader`), and a
    /// heading that reserved a different glyph's would put «Package» a point or
    /// two off the names under it. The symbol and not a built view: the row's
    /// mark has to stay an `Image` at its own call site.
    static let updateMarkSymbol = "arrow.up.circle.fill"

    /// The cask badge's ink, on the row and in the inspector alike; no signal
    /// token means it (`HelmSignal` is warning, success, danger).
    static let caskTint = Color.purple
}

/// **The heading over a list's columns: what the names are, and what the
/// figure at the trailing edge is.**
///
/// A `Section` header inside the `List` rather than a strip above it, which
/// is the whole of how it lines up: the list insets its headers and rows by
/// one amount, so nothing here measures an inset. The one thing a header cannot know is
/// what a row puts at its two edges, so it reserves those widths with the
/// same views, hidden: the update mark's slot on the installed list, and
/// the chevron in the single-column pane, which would otherwise push every
/// version a chevron's width left of «Version».
///
/// In the house's section voice (`HelmSectionTitle`), and marked a header
/// for the rotor.
struct HomebrewColumnHeader: View {
    /// Whether the rows under it keep the update mark's slot.
    let marksUpdates: Bool
    let singleColumn: Bool

    var body: some View {
        HStack(spacing: HelmSpace.s3) {
            if marksUpdates {
                Image(systemName: HomebrewPackageRow.updateMarkSymbol).font(HelmText.rowDetail).hidden()
            }
            HelmSectionTitle(HbStr.columnPackage)
            Spacer(minLength: 0)
            HelmSectionTitle(HbStr.tileVersion)
            RowChevron(singleColumn: singleColumn).hidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// **The mark that says a row leads somewhere, and only where it does.**
///
/// Below `HomebrewSplit`'s threshold a press on a row replaces the list
/// with that row's own screen; above it the same press moves the inspector
/// beside the list and the pane does not change. So the chevron is drawn
/// from the one fact that decides which of those happens, and never
/// otherwise: a chevron over a row that opens nothing is a promise the
/// wide page does not keep.
///
/// `HelmText.separator` is the token for exactly this — "marks, never
/// text", 3.07:1 light and 4.07:1 dark, over the 3:1 a mark that carries
/// meaning answers to. It is hidden from the accessibility tree because it
/// is not a control and says nothing the row does not: the row itself
/// carries the hint, in `helmOpensAScreen`.
private struct RowChevron: View {
    let singleColumn: Bool

    var body: some View {
        if singleColumn {
            Image(systemName: "chevron.forward")
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.separator)
                .accessibilityHidden(true)
        }
    }
}

/// **One row of either package list on this page: what does not divide it from
/// the next one.**
///
/// The height is the list's own, not the row's: both lists pass
/// `HelmSpace.s8` as `helmStripedList(rowPitch:)`, which is the minimum height
/// of every row in them and the step the stripe repeats at under the last one,
/// so the two cannot be two numbers. A `frame(minHeight: HelmSpace.s7)` on the
/// row would not do: a `List`'s own row insets take it to 36 pt for a single
/// line of content; the step is 40, the ladder's nearest to that. 34 is off
/// the ladder, and the insets take it to 42 — a step that long over one line
/// of text reads as a settings form rather than as a list of things.
///
/// **The separator is hidden.** macOS draws one per row across the whole
/// column, which at this step is a rule every few lines in a 310 pt column of
/// short names; the approved drawing has a hairline at a twentieth of that
/// weight, which macOS's is not and cannot be made into. What separates one row
/// from the next is the alternating fill `helmStripedList(rowPitch:)` turns on for
/// both of them, and the `Section` headers over them, which carry the structure
/// the rules would stand in for. Hiding the separator also puts this page with
/// the app's other striped list screens: `OrphansView`, Uninstaller and Leftovers
/// all hide theirs on the row.
extension View {
    func helmListRow() -> some View {
        listRowSeparator(.hidden)
    }
}

private extension View {
    /// **What a row promises when pressing it changes the whole pane.**
    ///
    /// The chevron beside the row is a mark and not an element
    /// (`RowChevron` says why), so without this the single-column list
    /// reads to VoiceOver exactly as the two-column one does — same rows, same
    /// names, and no word anywhere about the press replacing the list. A hint
    /// is the right channel for it: it is read after the row's own name, it is
    /// skipped by anyone who has hints off, and it does not become part of the
    /// row's name the way a label would.
    ///
    /// Nothing at all above the threshold, rather than a hint saying something
    /// milder: there the press moves the inspector beside the list, which is a
    /// selection and is what macOS already announces for a selectable row.
    @ViewBuilder
    func helmOpensAScreen(_ singleColumn: Bool) -> some View {
        if singleColumn {
            accessibilityHint(HbStr.opensItsOwnScreen)
        } else {
            self
        }
    }
}
