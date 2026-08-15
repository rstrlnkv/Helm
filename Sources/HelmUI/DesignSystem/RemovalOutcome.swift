import SwiftUI
import HelmRuntime

/// What actually happened when Helm tried to delete something.
///
/// Three screens used to announce "Removed — N freed" whether or not anything
/// was refused, and threw the list of failures away. macOS refuses often
/// enough — a container without Full Disk Access, a file the app is holding —
/// that a cheerful banner over a silent failure is the app lying about its own
/// work. This says what stayed, and why, in the module's own words.
public struct HelmRemovalFailure: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    /// The reason in the user's language, supplied by the module.
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    /// A refusal as it comes back from `HelmTrash`, with its reason put into the
    /// reader's language.
    ///
    /// Disk, Duplicates and Leftovers each spelled this map out — the same two
    /// lines, reaching past this type to `TrashReasonText` for the sentence. The
    /// lookup belongs beside the sentences, and the third copy of it arrived the
    /// day Leftovers stopped carrying a refusal shape of its own.
    ///
    /// `refresh` is the verb of the caller's own refresh control, where the
    /// sentence ends by naming one — Duplicates passes `.search`. Its own
    /// initializer rather than a defaulted parameter, because the three scan
    /// modules build theirs point-free (`map(HelmRemovalFailure.init)`) and a
    /// default does not survive that reference.
    public init(_ refusal: HelmTrash.Refusal, refresh: TrashReasonText.Refresh) {
        self.init(path: refusal.path,
                  reason: TrashReasonText.sentence(refusal.reason.rawValue, refresh: refresh))
    }

    public init(_ refusal: HelmTrash.Refusal) {
        self.init(refusal, refresh: .scan)
    }
}

public struct HelmRemovalOutcome: View {
    private let succeededText: String
    private let removed: Int
    private let failures: [HelmRemovalFailure]
    private let needsFullDiskAccess: Bool
    /// What this row will say.
    ///
    /// **Stored rather than derived, because the fourth verdict is not a reading
    /// of the numbers — it is the absence of any.** A `Bool` beside `removed`
    /// and `failures` would have let a caller build "nothing came back, and five
    /// moved", a state no transport can produce; `unanswered` is its own entry
    /// point instead, so the combination cannot be written down.
    let verdict: Verdict

    /// `removed` is the count, not the sentence, because the sentence cannot be
    /// asked whether it is true. Disk builds its banner before it knows the
    /// outcome, so a batch where every path refused still announced "Removed —
    /// 0 bytes freed, 1 item could not be moved" — a claim, its own refutation,
    /// and two em-dashes, in one caption.
    public init(succeededText: String, removed: Int,
                failures: [HelmRemovalFailure],
                needsFullDiskAccess: Bool = false) {
        self.succeededText = succeededText
        self.removed = removed
        self.failures = failures
        self.needsFullDiskAccess = needsFullDiskAccess
        self.verdict = Self.verdict(removed: removed, failed: failures.count)
    }

    /// The removal whose reply never came back.
    ///
    /// `TransportClient.request` answers nil for a request that threw and for a
    /// reply that would not decode, and three modules fold that nil to zeroes —
    /// which `verdict` then reads as `.silent`. So a person pressed a
    /// destructive button, waited, and the app had no comment while the rescan
    /// underneath quietly changed the list.
    ///
    /// It is not `.succeeded` and it is not `.failed`: nothing is known to have
    /// moved, nothing is known to have stayed, and nothing failed. It carries
    /// no numbers because there are none to carry.
    public static var unanswered: HelmRemovalOutcome { HelmRemovalOutcome(verdict: .unanswered) }

    /// The removal whose reply was lost **and whose refresh was lost with it**.
    ///
    /// `unanswered` ends by pointing at the list — «the list above shows where the
    /// files are now» — and that is true only because the caller rescans on the
    /// same path. The rescan is a request like any other and can go unanswered
    /// too, and there the sentence was guaranteeing exactly what nothing knew.
    /// So the caller says which round this is, and this one claims nothing about
    /// the list except that it is old.
    ///
    /// Two entry points rather than a parameter beside the counts, for the reason
    /// `unanswered`'s own comment gives: a lost reply carries no numbers, and the
    /// combination «nothing came back, and five moved» must not be writable.
    public static var unansweredWithStaleList: HelmRemovalOutcome {
        HelmRemovalOutcome(verdict: .unansweredStaleList)
    }

    private init(verdict: Verdict) {
        succeededText = ""
        removed = 0
        failures = []
        needsFullDiskAccess = false
        self.verdict = verdict
    }

    /// What this line has to say, given what actually happened.
    ///
    /// Pulled out because the `failures.isEmpty` branch was not consulting
    /// `removed` at all — the parameter existed for exactly that question and
    /// only one of the two branches asked it. A caller builds its success
    /// sentence before it knows the outcome and defaults every count to zero,
    /// so an engine reply carrying nothing rendered as unqualified success over
    /// a row that was still there.
    enum Verdict: Equatable {
        /// Nothing moved and nothing was refused: no sentence is true, so none
        /// is drawn. It needs no wording of its own — every sentence this
        /// component has is about something that happened.
        case silent
        case succeeded
        case failed
        /// The reply was lost, so none of the three above can be told apart.
        /// Reached only through `unanswered`, never from a count.
        case unanswered
        /// The reply was lost and so was the refresh that would have brought the
        /// list up to date. Reached only through `unansweredWithStaleList`.
        case unansweredStaleList
    }

    static func verdict(removed: Int, failed: Int) -> Verdict {
        if failed > 0 { return .failed }
        return removed > 0 ? .succeeded : .silent
    }

    public var body: some View {
        switch verdict {
        case .silent:
            EmptyView()
        case .succeeded:
            quiet(succeededText)
        // `.succeeded`'s shape exactly: it is a statement of what is known, not
        // a warning. No triangle, no list of refusals and no Grant button —
        // nothing was refused, and nothing here is anybody's to fix.
        case .unanswered:
            quiet(Self.noAnswer)
        // The same shape again, and only the words differ: what this round knows
        // about the list is one fact less.
        case .unansweredStaleList:
            quiet(Self.noAnswerStaleList)
        case .failed:
            // **The two levels below were one level.** The heading was
            // `.caption` and the failures under it `.caption2`, which macOS
            // resolves to 10 both — so the hierarchy was in the source and not
            // on the screen. The heading is the note step (11) and the list
            // under it stays at 10, which is the difference this block was
            // always written to have.
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                HStack(spacing: HelmSpace.s4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(HelmSignal.warning)
                    Text(Self.heading(succeeded: removed > 0 ? succeededText : nil,
                                      failed: failures.count))
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                    Spacer(minLength: 8)
                    if needsFullDiskAccess {
                        Button(Self.grant) { PermissionNeed.fullDiskAccess.openSettings() }
                            .controlSize(.small)
                    }
                }
                // Named, not counted: "3 files could not be moved" is not
                // something anyone can act on.
                ForEach(failures.prefix(4)) { failure in
                    HStack(spacing: 6) {
                        Text((failure.path as NSString).lastPathComponent)
                            .font(.caption2)
                            .lineLimit(1).truncationMode(.middle)
                        Text("·").font(.caption2).foregroundStyle(HelmText.faint)
                        // Not `lineLimit(1)`. These sentences exist to say what
                        // macOS refused and what to do about it, and measured at
                        // 10 pt the Russian ran past the row in three of the four
                        // reasons — so the half that named the next step was the
                        // half that got truncated. Two lines, and the row grows.
                        Text(failure.reason)
                            .font(.caption2)
                            .foregroundStyle(HelmText.quiet)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button {
                            // Reached most often for a file that could not be
                            // moved, which is where the fallback earns itself.
                            HelmReveal.inFinder(failure.path)
                        } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(HelmA11y.showInFinder), \((failure.path as NSString).lastPathComponent)")
                        .controlSize(.small)
                    }
                }
                if failures.count > 4 {
                    Text(Self.more(failures.count - 4))
                        .font(.caption2)
                        .foregroundStyle(HelmText.quiet)
                }
            }
        }
    }

    /// **A full stop, not a second em dash.** `succeeded` is the caller's own
    /// sentence and already carries one — "Moved to the Trash: 3 items — 4 KB" —
    /// so joining with another put two in one caption, which is the very defect
    /// `init`'s comment above says was fixed. The Uninstaller's own copy of this
    /// line used a comma, so the app disagreed with itself about it. CJK takes its
    /// own full stop; French an unbreakable space before the colon.
    ///
    /// `language` is explicit, defaulting to the app's, because an inline table
    /// cannot be read back in the other seven otherwise.
    static func heading(succeeded: String?, failed: Int,
                        language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(failed, language: language.rawValue)
        guard let succeeded else {
            return L("\(items) could not be moved",
                     [.ru: "Не удалось переместить: \(items)",
                      .es: "No se pudieron mover: \(items)",
                      .fr: "Impossible de déplacer\u{00A0}: \(items)",
                      .de: "Nicht verschoben: \(items)",
                      .ja: "移動できませんでした：\(items)",
                      .zh: "无法移动：\(items)",
                      .pt: "Não foi possível mover: \(items)"], language: language)
        }
        return L("\(succeeded). \(items) could not be moved",
                 [.ru: "\(succeeded). Не удалось переместить: \(items)",
                  .es: "\(succeeded). No se pudieron mover: \(items)",
                  .fr: "\(succeeded). Impossible de déplacer\u{00A0}: \(items)",
                  .de: "\(succeeded). Nicht verschoben: \(items)",
                  .ja: "\(succeeded)。移動できませんでした：\(items)",
                  .zh: "\(succeeded)。无法移动：\(items)",
                  .pt: "\(succeeded). Não foi possível mover: \(items)"], language: language)
    }

    private static func more(_ n: Int) -> String {
        L("…and \(n) more", [.ru: "…и ещё \(n)", .es: "…y \(n) más", .fr: "…et \(n) de plus",
                             .de: "…und \(n) weitere", .ja: "…ほか \(n) 件", .zh: "…还有 \(n) 项",
                             .pt: "…e mais \(n)"])
    }

    private static var grant: String {
        L("Grant…")
    }

    /// What a lost reply says. It names no count, calls nothing a failure and
    /// apologises for nothing — it points at the list, which the rescan
    /// underneath has just brought up to date, as the answer to the only
    /// question left.
    ///
    /// Internal rather than private: the pair below is one machine fact in two
    /// sentences, and that they open the same way is a claim with a test under it.
    static var noAnswer: String {
        L("Helm got no answer, so it does not know what moved. The list above shows where the files are now.")
    }

    /// And what it says when the refresh was lost too. It withdraws the second
    /// half of the promise: nothing on this page has been read since before the
    /// press, so the list is where the files *were*.
    ///
    /// It names no verb for trying again. Five call sites in four modules draw
    /// this component and their refresh buttons say three different things, so a
    /// literal here would be wrong in two of five.
    static var noAnswerStaleList: String {
        L("Helm got no answer, so it does not know what moved. The list above still shows where the files were before.")
    }

    /// The two sentences this row says quietly, drawn identically because they
    /// are the same kind of statement: what is known, with nothing to act on.
    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
    }
}
