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
    public init(_ refusal: HelmTrash.Refusal) {
        self.init(path: refusal.path,
                  reason: TrashReasonText.sentence(refusal.reason.rawValue))
    }
}

public struct HelmRemovalOutcome: View {
    private let succeededText: String
    private let removed: Int
    private let failures: [HelmRemovalFailure]
    private let needsFullDiskAccess: Bool

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
        switch Self.verdict(removed: removed, failed: failures.count) {
        case .silent:
            EmptyView()
        case .succeeded:
            Text(succeededText)
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(HelmSignal.warning)
                    Text(Self.heading(succeeded: removed > 0 ? succeededText : nil,
                                      failed: failures.count))
                        .font(.caption)
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
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: failure.path)])
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

    static func heading(succeeded: String?, failed: Int) -> String {
        let items = Plural.items(failed, language: AppLanguage.current.rawValue)
        guard let succeeded else {
            return L("\(items) could not be moved",
                     [.ru: "Не удалось переместить: \(items)",
                      .es: "No se pudieron mover: \(items)",
                      .fr: "Impossible de déplacer : \(items)",
                      .de: "Nicht verschoben: \(items)",
                      .ja: "移動できませんでした：\(items)",
                      .zh: "无法移动：\(items)",
                      .pt: "Não foi possível mover: \(items)"])
        }
        return L("\(succeeded) — \(items) could not be moved",
                 [.ru: "\(succeeded) — не удалось переместить: \(items)",
                  .es: "\(succeeded) — no se pudieron mover: \(items)",
                  .fr: "\(succeeded) — impossible de déplacer : \(items)",
                  .de: "\(succeeded) — nicht verschoben: \(items)",
                  .ja: "\(succeeded) — 移動できませんでした：\(items)",
                  .zh: "\(succeeded) — 无法移动：\(items)",
                  .pt: "\(succeeded) — não foi possível mover: \(items)"])
    }

    private static func more(_ n: Int) -> String {
        L("…and \(n) more", [.ru: "…и ещё \(n)", .es: "…y \(n) más", .fr: "…et \(n) de plus",
                             .de: "…und \(n) weitere", .ja: "…ほか \(n) 件", .zh: "…还有 \(n) 项",
                             .pt: "…e mais \(n)"])
    }

    private static var grant: String {
        L("Grant…")
    }
}
