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
        // Empty is not a label: launchd lets a job omit `Label` and take its
        // name from the file, and a blank one has to be special-cased by every
        // rule downstream.
        let label = (plist["Label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Off the end, not everywhere: `deletingPathExtension` on
        // "com.vendor.plistwatcher.plist" keeps the name, where replacing every
        // ".plist" made it "com.vendorwatcher" — an identifier that matches no
        // installed app (so the job looked orphaned) and that `launchctl
        // disable` would aim at something else entirely.
        let fallback = ((path as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        let program = (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first
        return LaunchAgentInfo(identifier: label ?? fallback,
                               program: program,
                               runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false)
    }
}
