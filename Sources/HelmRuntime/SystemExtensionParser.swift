import Foundation

public struct SystemExtensionInfo: Equatable, Sendable, Identifiable, Codable {
    public var id: String { identifier }
    public let identifier: String
    public let teamID: String
    public let name: String
    public let version: String
    public let state: String
    public let enabled: Bool

    public init(identifier: String, teamID: String, name: String,
                version: String, state: String, enabled: Bool) {
        self.identifier = identifier
        self.teamID = teamID
        self.name = name
        self.version = version
        self.state = state
        self.enabled = enabled
    }
}

/// Parses `systemextensionsctl list`. Columns are tab-separated:
/// `enabled ⇥ active ⇥ teamID ⇥ bundleID (version) ⇥ name ⇥ [state]`
enum SystemExtensionParser {
    static func parse(_ output: String) -> [SystemExtensionInfo] {
        output.split(separator: "\n").compactMap { line -> SystemExtensionInfo? in
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 6 else { return nil }
            let bundleField = columns[3].trimmingCharacters(in: .whitespaces)
            guard bundleField.contains("."), bundleField.contains("(") else { return nil }

            let identifier = bundleField.components(separatedBy: " ").first ?? bundleField
            let version = bundleField
                .drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
            let state = columns[5].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return SystemExtensionInfo(identifier: identifier,
                                       teamID: columns[2].trimmingCharacters(in: .whitespaces),
                                       name: columns[4].trimmingCharacters(in: .whitespaces),
                                       version: String(version),
                                       state: state,
                                       enabled: columns[0].contains("*"))
        }
    }

    /// The apps those extensions belong to: an extension id is the host app's
    /// id plus one component (com.acme.app.networkExtension → com.acme.app).
    static func hostIdentifiers(_ output: String) -> Set<String> {
        Set(parse(output).flatMap { info -> [String] in
            let parts = info.identifier.split(separator: ".")
            guard parts.count > 3 else { return [info.identifier] }
            return [info.identifier, parts.dropLast().joined(separator: ".")]
        })
    }
}

/// The one place that shells out to `systemextensionsctl` — every consumer
/// (uninstaller, leftovers scanner, the settings audit) parses the same list.
public enum SystemExtensionCLI {
    /// The tool's own answer, or `nil` when it did not give one.
    ///
    /// **An empty list and a tool that failed are two facts.** The exit status was
    /// dropped here, so a `systemextensionsctl` that could not run read as «nothing
    /// is loaded on this Mac» — and «nothing is loaded» is what stops a launch agent
    /// whose label is a live system extension from being called a leftover.
    public static func listing() -> String? {
        // This used to wait before reading, which is the deadlock order, and
        // paid 67 ms in the run-loop poll on every call.
        let result = HelmProcess.run("/usr/bin/systemextensionsctl", ["list"])
        return result.status == 0 ? result.output : nil
    }

    // **The folded pair is gone, and nothing here can lose the tool's silence
    // again.** `listOutput()` answered `""` for a tool that did not run and
    // `installed()` parsed that into an empty list, so «no extensions on this
    // Mac» and «the tool was not there» arrived as one value. The last reader of
    // either was the uninstaller's `systemExtensions` command, which no screen
    // ever sent; it went on 2026-08-16 and took them with it. Every reader below
    // can say that the tool did not answer, which is what a caller deciding
    // whether something may be deleted — or drawing a control on the strength of
    // what is loaded — has to be able to tell.

    /// The list, or `nil` when `systemextensionsctl` itself did not answer.
    public static func installedIfAnswered() -> [SystemExtensionInfo]? {
        listing().map(SystemExtensionParser.parse)
    }

    /// The apps whose extensions are loaded, or `nil` when `systemextensionsctl`
    /// itself did not answer.
    ///
    /// It replaces a folded `hostIdentifiers()` built on `listOutput()`, whose
    /// empty answer meant «this Mac has no extensions» and «the tool did not run»
    /// in one value. The uninstaller reads it to decide whether a live extension
    /// is why macOS refused to move a bundle, which is a claim, so the two have to
    /// be different values.
    public static func hostIdentifiersIfAnswered() -> Set<String>? {
        listing().map(SystemExtensionParser.hostIdentifiers)
    }
}
