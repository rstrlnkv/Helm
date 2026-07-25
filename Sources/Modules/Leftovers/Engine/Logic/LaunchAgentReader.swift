import Foundation

public struct LaunchAgentInfo: Equatable, Sendable {
    public let identifier: String
    /// The executable launchd would run, when the job names one.
    public let program: String?
    public let runAtLoad: Bool

    public init(identifier: String, program: String?, runAtLoad: Bool) {
        self.identifier = identifier
        self.program = program
        self.runAtLoad = runAtLoad
    }
}

/// Pure reading of a launchd job definition, so "does this point at something
/// that no longer exists" can be decided without touching the disk in tests.
public enum LaunchAgentReader {
    public static func read(plist: [String: Any], path: String) -> LaunchAgentInfo {
        let label = plist["Label"] as? String
        let fallback = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".plist", with: "")
        let program = (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first
        return LaunchAgentInfo(identifier: label ?? fallback,
                               program: program,
                               runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false)
    }
}
