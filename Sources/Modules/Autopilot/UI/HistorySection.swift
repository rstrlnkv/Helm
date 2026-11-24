import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// What Autopilot did while nobody was looking, and the way to undo it.
///
/// Every other module acts on a press, so the result on screen is the record.
/// This one acts on a timer and on files arriving, and the log holds only counts
/// and redacted paths. A folder that tidies itself is trustworthy only if it can
/// say what it tidied **and take it back**.
///
/// Not a console: no filters, no search. It answers "where did that go" and
/// "put it back", and the grouping makes the second answerable: five hundred
/// rows is not something anybody can act on, and "the twelve files that
/// arrived at 14:22" is.
struct HistorySection: View {
    let history: [ActionRecord]
    /// The same history in passes, grouped once by the view model rather than
    /// on every body pass.
    let runs: [ActionRun]
    /// Why there is nothing to draw, when there is nothing. Decided over the
    /// folders as well as the passes: two of the three reasons are about the
    /// rules, which this view is not given.
    let empty: HistoryEmpty.Reason?
    let clear: (AutopilotViewModel.Discard) -> Void

    /// Whether the stored history is not Helm's, and the two gestures, passed in
    /// like `clear`: this view draws and asks. **No defaults**: a default here is
    /// "offer no return", a whole feature switched off in silence by a call site
    /// that forgot an argument.
    let refused: Bool
    let canPutBack: (ActionRecord) -> Bool
    let canPutBackRun: (ActionRun) -> Bool
    let putBack: (ActionRecord) -> Void
    let putBackRun: (ActionRun) -> Void
    /// What the last return came to for this row, when there is something to
    /// say: a file that did not go back, or came back under another name. No
    /// default, like the gestures above.
    let note: (ActionRecord) -> String?

    private var summary: ActionHistory.Summary { ActionHistory.summary(of: history) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                header
                if refused { refusedCard }
                if let empty {
                    Text(ApStr.historyEmpty(empty))
                        .font(HelmText.rowTitle)
                        .foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if empty == nil {
                VStack(alignment: .leading, spacing: HelmSpace.s4) {
                    ForEach(runs) { pass($0) }
                }
                .padding(.top, HelmSpace.s5)
            }
        }
        .helmCard()
    }

    private var header: some View {
        HStack(spacing: HelmSpace.s4) {
            Text(ApStr.historyTitle).font(HelmText.sectionHeading)
                // A heading, so the rotor can reach the record without reading
                // the whole list above it.
                .accessibilityAddTraits(.isHeader)
            // The count is a promise the list keeps, so both come from the same
            // window: seventeen over a list of nine is worse than no header.
            if summary.total > 0 {
                HelmBadge(Plural.files(summary.total,
                                       language: AppLanguage.current.rawValue))
            }
            let problems = summary.refused + summary.failed
            if problems > 0 {
                Text(ApStr.historyProblems(problems))
                    .helmQuietDetail()
            }
            Spacer(minLength: HelmSpace.s4)
            // Not while the card below is showing, which carries the same
            // gesture under a label that says what it does.
            if !history.isEmpty, !refused {
                Button(HelmWord.clear) { clear(.history) }
                    .controlSize(.small)
            }
        }
    }

    /// A history something else wrote. Shown rather than hidden — a rewritten
    /// history is itself something that happened — with the one way out beside
    /// it, the way a refused rule set has one.
    private var refusedCard: some View {
        HelmBanner(ApStr.historyTampered) {
            Button(ApStr.discardHistory) { clear(.refusedHistory) }
                .controlSize(.small)
        }
    }

    /// One pass: its header, then its rows.
    private func pass(_ run: ActionRun) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HStack(spacing: HelmSpace.s4) {
                Text(ApStr.passHeader(at: run.at, folder: run.folder, files: run.records.count))
                    .helmQuietDetail()
                    .lineLimit(1)
                Spacer(minLength: HelmSpace.s4)
                if canPutBackRun(run) {
                    Button(ApStr.putBackFiles(run.undoable.count)) { putBackRun(run) }
                        .controlSize(.small)
                }
            }
            ForEach(run.records) { row($0) }
        }
    }

    private func row(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s1) {
            HStack(spacing: HelmSpace.s4) {
                // The time is the pass's, not the row's: a sweep's records are all
                // of one moment, so a time here would repeat the header above.
                Spacer().frame(width: HelmSpace.s4)
                Text(record.file)
                    .font(HelmText.rowTitle)
                    .lineLimit(1).truncationMode(.middle)
                // Tail, not middle: this column never holds a path, and a sentence
                // cut in the middle reads as nonsense. The file name above keeps
                // `.middle`: both its ends carry meaning.
                Text(ApStr.historyDetail(record))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(record.kind == .failed || record.kind == .refused
                                     ? HelmSignal.warning : HelmText.quiet)
                    .lineLimit(1).truncationMode(.tail)
                // The row stays after it goes back, marked. A history that deleted
                // what it had undone would be hiding an action Autopilot took.
                if record.undoneAt != nil {
                    HelmBadge(ApStr.putBackAlready)
                }
                Spacer(minLength: HelmSpace.s4)
                // The rule's name is the one word that says why, and the person
                // chose it: "Invoices" explains more than any composed sentence.

                Text(record.rule)
                    .helmQuietDetail()
                    .lineLimit(1)
            }
            // What the last return came to for this file, aligned under the file
            // name so a rename note sits with the file it renames.
            if let note = note(record) {
                HStack(spacing: HelmSpace.s4) {
                    Spacer().frame(width: HelmSpace.s4)
                    HelmSettingsNote(note)
                    Spacer(minLength: HelmSpace.s4)
                }
            }
        }
        // Read as one thing. Six separate labels per row turns a page of
        // twenty into a hundred and twenty stops.
        .accessibilityElement(children: .combine)
        // "Where did that go" ends at the folder the file went to. Offered only
        // where the record knows the answer: an item that silently does nothing
        // is worse than one that is absent.
        //
        // **The return is offered on the record's shape, not on a verdict.**
        // Asking the disk per row would be a `stat` per row to draw a menu
        // nobody opened; the verdict comes after the press, in the report.
        .contextMenu { items(record) }
        // The same actions where VoiceOver can reach them, since the menu above
        // needs a right-click. `DiskResultView` documents the pairing.
        .accessibilityActions { items(record) }
    }

    @ViewBuilder private func items(_ record: ActionRecord) -> some View {
        if let path = record.revealPath {
            Button(HelmA11y.showInFinder) { reveal(path) }
        }
        if canPutBack(record) {
            Button(ApStr.putBack) { putBack(record) }
        }
    }

    private func reveal(_ path: String) { HelmReveal.inFinder(path) }

}
