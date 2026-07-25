import Foundation

public enum StaleKind: String, Codable, Sendable, CaseIterable {
    case launchAgent      // ~/Library/LaunchAgents, /Library/LaunchAgents
    case launchDaemon     // /Library/LaunchDaemons
    case preference       // ~/Library/Preferences/*.plist
    case systemExtension   // an extension whose host app is gone
    case plugin           // QuickLook, PreferencePanes, Internet Plug-Ins, Audio
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

    public init(path: String, identifier: String, kind: StaleKind, sizeBytes: Int,
                missingTarget: String? = nil, runAtLoad: Bool = false) {
        self.path = path
        self.identifier = identifier
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.missingTarget = missingTarget
        self.runAtLoad = runAtLoad
    }
}
