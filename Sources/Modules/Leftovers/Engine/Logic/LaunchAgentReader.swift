import Foundation

struct LaunchAgentInfo: Equatable, Sendable {
    let identifier: String
    /// The executable launchd would run, when the job names one.
    let program: String?
    let runAtLoad: Bool
}

/// Pure reading of a launchd job definition, so "does this point at something
/// that no longer exists" can be decided without touching the disk in tests.
enum LaunchAgentReader {

    /// The label launchd gives a job that omits `Label`: the file's own name.
    ///
    /// One spelling, read twice — here as the fallback, and by
    /// `LaunchLabel.mayBeSwitched` as the label this file would actually register
    /// under. Written out twice it would be a rule the two could come to disagree
    /// about, which is the whole subject of `LaunchLabel`.
    ///
    /// Off the end, not everywhere: `deletingPathExtension` on
    /// "com.vendor.plistwatcher.plist" keeps the name, where replacing every
    /// ".plist" made it "com.vendorwatcher" — an identifier that matches no
    /// installed app (so the job looked orphaned) and that `launchctl disable`
    /// would aim at something else entirely.
    static func labelFromFileName(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func read(plist: [String: Any], path: String) -> LaunchAgentInfo {
        // Empty is not a label: launchd lets a job omit `Label` and take its
        // name from the file, and a blank one has to be special-cased by every
        // rule downstream.
        let label = (plist["Label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let fallback = labelFromFileName(path)
        let program = (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first
        return LaunchAgentInfo(identifier: label ?? fallback,
                               program: program,
                               runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false)
    }
}
