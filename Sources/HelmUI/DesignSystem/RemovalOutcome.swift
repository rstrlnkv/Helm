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
    @Environment(\.helmTraits) private var traits

    private let succeededText: String
    private let removed: Int
    private let failures: [HelmRemovalFailure]
    private let needsFullDiskAccess: Bool
    /// What this row will say.
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
                        .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
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
    /// `language` is explicit, defaulting to the app's, because the other seven
    /// cannot be read back otherwise.
    static func heading(succeeded: String?, failed: Int,
                        language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(failed, language: language.rawValue)
        guard let succeeded else {
            return L(.itemsCouldNotBeMoved(items), language: language)
        }
        return L(.succeededItemsCouldNotBeMoved(succeeded, items), language: language)
    }

    private static func more(_ n: Int) -> String {
        L(.andMore(String(n)))
    }

    private static var grant: String {
        L(.grant)
    }

    /// The sentence this row says quietly: what is known, with nothing to act on.
    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
    }
}
