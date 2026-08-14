import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// What Autopilot did while nobody was looking.
///
/// Every other module acts because somebody pressed something a moment before,
/// so the result on screen is the record. This one acts on a timer and on files
/// arriving, and until now the only trace was the log — counts and redacted
/// paths, which answers "did anything happen" and never "what happened to my
/// file". A folder that tidies itself is only trustworthy if it can say what it
/// tidied.
///
/// Deliberately a report and not a console: no filters, no search, no undo. The
/// question it exists to answer is "where did that go", and the answer is one
/// line per file.
struct HistorySection: View {
    let history: [ActionRecord]
    let clear: () -> Void

    private var summary: ActionHistory.Summary { ActionHistory.summary(of: history) }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            header
            if history.isEmpty {
                Text(ApStr.historyEmpty)
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.quiet)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(history) { row($0) }
                }
            }
        }
        .helmCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(ApStr.historyTitle).font(.headline)
            // The count is a promise the list has to keep, so both come from
            // the same window: a header saying seventeen over a list of nine is
            // worse than no header.
            if summary.total > 0 {
                HelmBadge(Plural.files(summary.total,
                                       language: AppLanguage.current.rawValue))
            }
            let problems = summary.refused + summary.failed
            if problems > 0 {
                Text(ApStr.historyProblems(problems))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
            }
            Spacer(minLength: 8)
            if !history.isEmpty {
                Button(ApStr.historyClear, action: clear)
                    .controlSize(.small)
            }
        }
    }

    private func row(_ record: ActionRecord) -> some View {
        HStack(spacing: 8) {
            Text(HelmDates.dayAndMinute(record.at))
                // **10 is meant here, and the column is why.** This is a figure
                // read down a column, so the house says `.helmFigure()` — and
                // that is SF Mono 11, where the widest of the eight languages
                // measures 115.6 pt against a frame of 96. At tabular 11 the
                // widest is 100.4, still over. Moving the size means moving the
                // column,
                // and the column belongs to the row's composition rather than
                // to its vocabulary: recorded as a finding, not swept.
                .font(.caption.monospacedDigit())
                .foregroundStyle(HelmText.quiet)
                // The width is fixed and the format is macOS's, not ours:
                // Russian and Portuguese measure 92 pt in this font, four short
                // of the frame. Without the limit the overflow wraps to a second
                // line and takes the height of the whole row with it.
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            Text(record.file)
                .font(HelmText.rowTitle)
                .lineLimit(1).truncationMode(.middle)
            Text(detail(record))
                .font(HelmText.rowDetail)
                .foregroundStyle(record.kind == .failed || record.kind == .refused
                                 ? Color.orange : HelmText.quiet)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            // The rule's name is the one word that says why, and the person
            // writing it chose it: "Invoices" explains more than any sentence
            // this screen could compose.
            Text(record.rule)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
        }
        // Read as one thing. Six separate labels per row turns a page of
        // twenty into a hundred and twenty stops.
        .accessibilityElement(children: .combine)
        // "Where did that go" ends at the folder the file went to, and every
        // other list in Helm can open it. Offered only where the record knows
        // the answer — a trashed or refused row has nothing to point at, and an
        // item that silently does nothing is worse than one that is absent.
        .contextMenu {
            if let path = record.revealPath {
                Button(HelmA11y.showInFinder) { reveal(path) }
            }
        }
        // The same action where VoiceOver can reach it, since the menu above
        // needs a right-click. `DiskResultView` documents the pairing.
        .accessibilityActions {
            if let path = record.revealPath {
                Button(HelmA11y.showInFinder) { reveal(path) }
            }
        }
    }

    private func reveal(_ path: String) { HelmReveal.inFinder(path) }

    /// "trashed" needs no second half; the rest read as verb then value. A
    /// refusal is the exception: its detail is the reason's rawValue — stored
    /// data, not words — so it is read back into the enum and spoken whole. A
    /// detail no current reason claims (a record a newer Helm wrote) falls
    /// through to the verb-and-value form rather than to silence.
    private func detail(_ record: ActionRecord) -> String {
        if record.kind == .refused,
           let reason = RuleOutcome.Refusal(rawValue: record.detail) {
            return ApStr.historyRefusal(reason)
        }
        let verb = ApStr.historyVerb(record.kind)
        return record.detail.isEmpty ? verb : "\(verb) \(record.detail)"
    }

}
