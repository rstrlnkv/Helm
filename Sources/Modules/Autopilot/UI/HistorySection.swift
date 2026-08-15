import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// What Autopilot did while nobody was looking, and the way to undo it.
///
/// Every other module acts because somebody pressed something a moment before,
/// so the result on screen is the record. This one acts on a timer and on files
/// arriving, and the only other trace is the log — counts and redacted paths,
/// which answers "did anything happen" and never "what happened to my file". A
/// folder that tidies itself is only trustworthy if it can say what it tidied
/// **and take it back**.
///
/// Still not a console: no filters, no search. Two questions, and the second
/// one is why the record grew an identity — "where did that go", and "put it
/// back". The grouping is what makes the second answerable: five hundred rows
/// is not something anybody can act on, and "the twelve files that arrived at
/// 14:22" is.
struct HistorySection: View {
    let history: [ActionRecord]
    /// The same history in passes, grouped once by the view model rather than
    /// on every body pass.
    let runs: [ActionRun]
    /// Why there is nothing to draw, when there is nothing. Decided by the
    /// engine over the folders as well as the passes — two of the three reasons
    /// are about the rules, which this view has never been given and should not
    /// be.
    let empty: HistoryEmpty.Reason?
    let clear: () -> Void

    /// Whether the stored history is not Helm's, and the two gestures. Passed
    /// in rather than reached for, like `clear`: this view draws and asks, and
    /// the view model is what knows how to send.
    ///
    /// **No defaults.** A default here is "offer no return", which is a whole
    /// feature switched off by a call site that forgot an argument — silently,
    /// with nothing failing.
    let refused: Bool
    let canPutBack: (ActionRecord) -> Bool
    let canPutBackRun: (ActionRun) -> Bool
    let putBack: (ActionRecord) -> Void
    let putBackRun: (ActionRun) -> Void
    /// What the last return came to for this row, when there is something to
    /// say — a file that did not go back, or one that came back under another
    /// name. On the row it is about, not only in the banner at the foot of the
    /// page. No default, like the gestures above: a call site that forgot it
    /// would drop the note in silence.
    let note: (ActionRecord) -> String?

    private var summary: ActionHistory.Summary { ActionHistory.summary(of: history) }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            header
            if refused { refusedCard }
            if let empty {
                Text(ApStr.historyEmpty(empty))
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: HelmSpace.s4) {
                    ForEach(runs) { pass($0) }
                }
            }
        }
        .helmCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(ApStr.historyTitle).font(.headline)
                // A heading, so the rotor can reach the record without reading
                // the whole list above it.
                .accessibilityAddTraits(.isHeader)
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
            // Not while the card below is showing, which carries the same
            // gesture under a label that says what it does.
            if !history.isEmpty, !refused {
                Button(ApStr.historyClear, action: clear)
                    .controlSize(.small)
            }
        }
    }

    /// A history something else wrote. Shown rather than hidden — a rewritten
    /// history is itself something that happened — with the one way out beside
    /// it, the way a refused rule set has one.
    private var refusedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ApStr.historyTampered)
                .font(HelmText.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
            Button(ApStr.discardHistory, action: clear)
                .controlSize(.small)
        }
        .foregroundStyle(Color.orange)
    }

    /// One pass: its header, then its rows.
    private func pass(_ run: ActionRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(ApStr.passHeader(at: run.at, folder: run.folder, files: run.records.count))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if canPutBackRun(run) {
                    Button(ApStr.putBackFiles(run.undoable.count)) { putBackRun(run) }
                        .controlSize(.small)
                }
            }
            ForEach(run.records) { row($0) }
        }
    }

    private func row(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
            // **The time is the pass's, not the row's.** It used to sit here, in
            // a 96-point column, and once the rows were grouped it said the same
            // thing as the header directly above it — five times over, since a
            // sweep's records are all of one moment. The column is gone with it,
            // and so is the finding about its width in eight languages: the
            // header is a line of its own and has the room.
            Spacer().frame(width: HelmSpace.s4)
            Text(record.file)
                .font(HelmText.rowTitle)
                .lineLimit(1).truncationMode(.middle)
            Text(detail(record))
                .font(HelmText.rowDetail)
                .foregroundStyle(record.kind == .failed || record.kind == .refused
                                 ? Color.orange : HelmText.quiet)
                .lineLimit(1).truncationMode(.middle)
            // The row stays after it goes back, marked. A history that deleted
            // what it had undone would be hiding an action Autopilot took.
            if record.undoneAt != nil {
                HelmBadge(ApStr.putBackAlready)
            }
            Spacer(minLength: 8)
            // The rule's name is the one word that says why, and the person
            // writing it chose it: "Invoices" explains more than any sentence
            // this screen could compose.
            Text(record.rule)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
        }
        // What the last return came to for this file, on its own row. Aligned
        // under the file name — the same leading gap the row opens with — so a
        // «march.pdf came back as march 2.pdf» sits with the file it renames
        // rather than in the banner alone.
        if let note = note(record) {
            HStack(spacing: 8) {
                Spacer().frame(width: HelmSpace.s4)
                Text(note)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
        }
        }
        // Read as one thing. Six separate labels per row turns a page of
        // twenty into a hundred and twenty stops.
        .accessibilityElement(children: .combine)
        // "Where did that go" ends at the folder the file went to, and every
        // other list in Helm can open it. Offered only where the record knows
        // the answer — a refused row has nothing to point at, and an item that
        // silently does nothing is worse than one that is absent.
        //
        // **The return is offered on the record's shape, not on a verdict.**
        // Asking the disk per row would be five hundred `stat`s to draw a menu
        // nobody has opened; the verdict comes after the press, in the report.
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
