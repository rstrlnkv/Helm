import SwiftUI
import HelmUI

/// A row of the master list — no button:
/// `mark · name · badges … version`.
/// Actions draw only in the inspector, so a selectable `List` row and a button
/// never fight the same click.
struct HomebrewPackageRow: View {
    @Environment(\.helmTraits) private var traits
    let name: String
    let detail: String?
    let isCask: Bool
    var pinned = false
    var hasUpdate: Bool?

    var body: some View {
        HStack(spacing: HelmSpace.s3) {
            // **nil is «this list never marks updates», and draws no column** —
            // the updates list, where every row is outdated. A `Bool` keeps the
            // slot on every row, so the names line up.
            if let hasUpdate {
                // A glyph rather than a dot: SwiftUI does not make a `Shape`
                // an accessibility element, so a label on a `Circle` is lost;
                // and a dot differs from no dot by hue alone. The same symbol
                // as `packageDetail`'s for this fact.
                Image(systemName: Self.updateMarkSymbol)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                    .accessibilityLabel(HbStr.updateAvailable)
                    // Kept in the layout, hidden from sight and VoiceOver.
                    .opacity(hasUpdate ? 1 : 0)
                    .accessibilityHidden(!hasUpdate)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                HStack(spacing: HelmSpace.s3) {
                    Text(name).lineLimit(1)
                    // No "formula" badge: nearly every row would carry it.
                    if isCask { HelmBadge(HbStr.cask, tint: Self.caskTint) }
                    if pinned { HelmBadge(HbStr.pinned) }
                }
            }
            Spacer(minLength: 0)
            // **A column, not a word after the name,** so versions read down
            // under `HomebrewColumnHeader`, in figures that do not jump.
            if let detail {
                Text(detail).font(HelmText.figureFont).foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        // The height is the list's own (`helmStripedList(rowPitch:)`), so the
        // row and the stripe cannot be two numbers.
        //
        // **The separator is hidden,** as on the app's other striped lists:
        // the stripe and the `Section` headers carry the structure.
        .listRowSeparator(.hidden)
    }

    /// The update mark's symbol — named once because the heading over the
    /// installed list reserves exactly its width (`HomebrewColumnHeader`).
    static let updateMarkSymbol = "arrow.up.circle.fill"

    /// The cask badge's ink, on the row and in the inspector alike; no signal
    /// token means it (`HelmSignal` is warning, success, danger).
    static let caskTint = Color.purple
}

/// **The heading over a list's columns: what the names are, and what the
/// figure at the trailing edge is.**
///
/// A `Section` header inside the `List`, so the list insets it as it insets
/// the rows. It reserves the update mark's slot with the same view, hidden.
///
/// In the house's section voice (`HelmSectionTitle`), and marked a header
/// for the rotor.
struct HomebrewColumnHeader: View {
    /// Whether the rows under it keep the update mark's slot.
    let marksUpdates: Bool

    var body: some View {
        HStack(spacing: HelmSpace.s3) {
            if marksUpdates {
                Image(systemName: HomebrewPackageRow.updateMarkSymbol).font(HelmText.rowDetail).hidden()
            }
            HelmSectionTitle(HbStr.columnPackage)
            Spacer(minLength: 0)
            HelmSectionTitle(HbStr.tileVersion)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
