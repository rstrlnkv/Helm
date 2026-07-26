import Foundation

public enum StaleKind: String, Codable, Sendable, CaseIterable {
    case launchAgent      // ~/Library/LaunchAgents, /Library/LaunchAgents
    case launchDaemon     // /Library/LaunchDaemons
    case preference       // ~/Library/Preferences/*.plist
    case systemExtension   // an extension whose host app is gone
    case plugin           // QuickLook, PreferencePanes, Internet Plug-Ins, Audio
}

/// Why an item appears in the list. Everything found is shown — hiding what
/// is in use leaves the user trusting a list they cannot check.
public enum ItemStatus: String, Codable, Sendable, Equatable {
    /// The owner is gone: safe to remove.
    case orphaned
    /// Belongs to installed software, or points at a file that exists.
    case inUse
    /// Apple's, shared plumbing, or a system location: never removable.
    case protectedItem
}

public struct StaleItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let identifier: String
    public let kind: StaleKind
    public let sizeBytes: Int
    /// What the job points at, when it names an executable that is missing.
    public let missingTarget: String?
    /// Loaded at login — worth flagging, since removing it changes behaviour.
    public let runAtLoad: Bool
    public let status: ItemStatus

    /// Only orphans may be trashed, and never a system extension: those are
    /// not files Helm can move — macOS removes them with their app or from
    /// System Settings. Offering a checkbox would promise what we cannot do.
    public var removable: Bool { status == .orphaned && kind != .systemExtension }

    public init(path: String, identifier: String, kind: StaleKind, sizeBytes: Int,
                missingTarget: String? = nil, runAtLoad: Bool = false,
                status: ItemStatus = .orphaned) {
        self.path = path
        self.identifier = identifier
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.missingTarget = missingTarget
        self.runAtLoad = runAtLoad
        self.status = status
    }
}
