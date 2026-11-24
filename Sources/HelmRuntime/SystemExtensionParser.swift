import Foundation

public struct SystemExtensionInfo: Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let enabled: Bool

    public init(identifier: String, version: String, enabled: Bool) {
        self.identifier = identifier
        self.version = version
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
            return SystemExtensionInfo(identifier: identifier, version: String(version),
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
    /// **An empty list and a tool that failed are two facts.** Read as «nothing
    /// is loaded on this Mac», a tool that could not run would let a launch
    /// agent whose label is a live system extension be called a leftover.
    static func listing() -> String? {
        let result = HelmProcess.run("/usr/bin/systemextensionsctl", ["list"])
        return result.status == 0 ? result.output : nil
    }

    // Every reader below can say that the tool did not answer: a caller deciding
    // whether something may be deleted, or drawing a control on the strength of
    // what is loaded, has to tell that from «no extensions on this Mac».

    /// The list, or `nil` when `systemextensionsctl` itself did not answer.
    public static func installedIfAnswered() -> [SystemExtensionInfo]? {
        listing().map(SystemExtensionParser.parse)
    }

    /// The apps whose extensions are loaded, or `nil` when `systemextensionsctl`
    /// itself did not answer.
    ///
    /// The uninstaller reads it to decide whether a live extension is why macOS
    /// refused to move a bundle, which is a claim, so «no extensions» and «the
    /// tool did not run» have to be different values.
    public static func hostIdentifiersIfAnswered() -> Set<String>? {
        listing().map(SystemExtensionParser.hostIdentifiers)
    }
}
