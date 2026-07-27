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
}

public struct HelmRemovalOutcome: View {
    private let succeededText: String
    private let failures: [HelmRemovalFailure]
    private let needsFullDiskAccess: Bool

    public init(succeededText: String, failures: [HelmRemovalFailure],
                needsFullDiskAccess: Bool = false) {
        self.succeededText = succeededText
        self.failures = failures
        self.needsFullDiskAccess = needsFullDiskAccess
    }

    public var body: some View {
        if failures.isEmpty {
            Text(succeededText)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.70))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(Self.heading(succeeded: succeededText, failed: failures.count))
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.7))
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
                        Text(failure.reason)
                            .font(.caption2)
                            .foregroundStyle(Color.primary.opacity(0.70))
                            .lineLimit(1)
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
                        .foregroundStyle(Color.primary.opacity(0.70))
                }
            }
        }
    }

    private static func heading(succeeded: String, failed: Int) -> String {
        let items = Plural.items(failed, language: AppLanguage.current.rawValue)
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
        L("Grant…", [.ru: "Выдать…", .es: "Conceder…", .fr: "Accorder…", .de: "Erteilen…",
                     .ja: "許可…", .zh: "授予…", .pt: "Conceder…"])
    }
}
