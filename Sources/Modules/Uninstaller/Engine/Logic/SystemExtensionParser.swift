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
public enum SystemExtensionParser {
    public static func parse(_ output: String) -> [SystemExtensionInfo] {
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
    public static func hostIdentifiers(_ output: String) -> Set<String> {
        Set(parse(output).flatMap { info -> [String] in
            let parts = info.identifier.split(separator: ".")
            guard parts.count > 3 else { return [info.identifier] }
            return [info.identifier, parts.dropLast().joined(separator: ".")]
        })
    }
}
