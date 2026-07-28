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
        VStack(alignment: .leading, spacing: 10) {
            header
            if history.isEmpty {
                Text(ApStr.historyEmpty)
                    .font(.callout)
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
                    .font(.caption)
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
            Text(Self.when.string(from: record.at))
                .font(.caption.monospacedDigit())
                .foregroundStyle(HelmText.quiet)
                .frame(width: 96, alignment: .leading)
            Text(record.file)
                .font(.callout)
                .lineLimit(1).truncationMode(.middle)
            Text(detail(record))
                .font(.caption)
                .foregroundStyle(record.kind == .failed || record.kind == .refused
                                 ? Color.orange : HelmText.quiet)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            // The rule's name is the one word that says why, and the person
            // writing it chose it: "Invoices" explains more than any sentence
            // this screen could compose.
            Text(record.rule)
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
        }
        // Read as one thing. Six separate labels per row turns a page of
        // twenty into a hundred and twenty stops.
        .accessibilityElement(children: .combine)
    }

    /// "trashed" needs no second half; the rest read as verb then value.
    private func detail(_ record: ActionRecord) -> String {
        let verb = ApStr.historyVerb(record.kind)
        return record.detail.isEmpty ? verb : "\(verb) \(record.detail)"
    }

    /// Date and time, short: a report covering thirty days needs the day, and a
    /// morning's worth of moves needs the minute.
    private static let when: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
