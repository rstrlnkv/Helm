import Foundation

/// Pure: derives the candidate leftover paths for an app from its bundle id and
/// name, relative to a `~/Library` dir. No filesystem access — the engine filters
/// these to what actually exists (resolving `isGlob` candidates against siblings).
public enum LeftoverMatcher {
    public struct Candidate: Equatable {
        public let url: URL
        public let kind: LeftoverKind
        public let matchedByName: Bool
        /// true → `url`'s last component is a `*` pattern to match against siblings
        /// (Group Containers `*.<id>`, ByHost/LaunchAgents `<id>*.plist`).
        public let isGlob: Bool
    }

    public static func candidates(bundleID id: String, appName name: String, library lib: URL) -> [Candidate] {
        func u(_ parts: String...) -> URL { parts.reduce(lib) { $0.appendingPathComponent($1) } }
        var out: [Candidate] = []
        func add(_ url: URL, _ kind: LeftoverKind, name byName: Bool = false, glob: Bool = false) {
            out.append(.init(url: url, kind: kind, matchedByName: byName, isGlob: glob))
        }
        add(u("Application Support", id), .appSupport)
        add(u("Application Support", name), .appSupport, name: true)
        add(u("Caches", id), .caches)
        // Helpers and extensions get their own containers named after the app's
        // id plus a suffix (…tool.helper, …tool.packet-extension-mac); matching
        // the exact id alone leaves them behind.
        add(u("Caches").appendingPathComponent("\(id)*"), .caches, glob: true)
        add(u("Preferences", "\(id).plist"), .preferences)
        add(u("Preferences", "ByHost").appendingPathComponent("\(id)*.plist"), .preferences, glob: true)
        add(u("Containers", id), .containers)
        add(u("Containers").appendingPathComponent("\(id)*"), .containers, glob: true)
        add(u("Group Containers").appendingPathComponent("*.\(id)"), .groupContainers, glob: true)
        add(u("Group Containers").appendingPathComponent("*\(id)*"), .groupContainers, glob: true)
        add(u("Saved Application State", "\(id).savedState"), .savedState)
        add(u("Logs", id), .logs)
        add(u("Logs", name), .logs, name: true)
        add(u("HTTPStorages", id), .httpStorages)
        add(u("HTTPStorages", "\(id).binarycookies"), .httpStorages)
        add(u("WebKit", id), .webKit)
        add(u("Cookies", "\(id).binarycookies"), .cookies)
        add(u("Application Scripts", id), .appScripts)
        add(u("Application Scripts").appendingPathComponent("\(id)*"), .appScripts, glob: true)
        add(u("LaunchAgents").appendingPathComponent("\(id)*.plist"), .launchAgent, glob: true)
        return out
    }
}
