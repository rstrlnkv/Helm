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

    /// Whether every extension id in this output reached us whole.
    ///
    /// False when the bundle-id column (the fourth) of any line with six or more
    /// columns holds U+FFFD, the mark of a byte that was not UTF-8. Only that
    /// column counts: a damaged id matches nothing and is dropped, and a caller
    /// reads an id's absence from the list as leave to call a launch agent
    /// carrying it a leftover. A damaged name, team or state is read by nobody
    /// who acts on it, so it leaves the listing readable. The line counts
    /// whether or not `parse` accepts it, because a line the parser skips drops
    /// its id just as surely.
    static func isReadable(_ output: String) -> Bool {
        !output.split(separator: "\n").contains { line in
            let columns = line.components(separatedBy: "\t")
            return columns.count >= 6 && columns[3].contains("\u{FFFD}")
        }
    }
}

/// The one place that shells out to `systemextensionsctl` — every consumer
/// (uninstaller, leftovers scanner) parses the same list.
public enum SystemExtensionCLI {
    /// How long one `systemextensionsctl list` is given. A read-only query that
    /// can sit is bounded, as `SystemSSHKeys` and `SystemSSHAgent` are; an answer
    /// comes back in well under a second (`/usr/bin/time -p
    /// /usr/bin/systemextensionsctl list`). Both readers run on a user's act, a
    /// scan or a refused move to the Trash, and a tool that never answered would
    /// park that act for good.
    static let listingDeadline: TimeInterval = 5

    /// The tool's own answer, or `nil` when it gave none in time, exited
    /// non-zero, or named an extension in bytes that are not UTF-8.
    ///
    /// **An empty list and a tool that failed are two facts.** The exit status was
    /// dropped here, so a `systemextensionsctl` that could not run read as «nothing
    /// is loaded on this Mac» — and «nothing is loaded» is what stops a launch agent
    /// whose label is a live system extension from being called a leftover.
    public static func listing() -> String? {
        listing(tool: "/usr/bin/systemextensionsctl")
    }

    /// The same answer over the tool at `path`, run through the bounded `HelmProcess.run`.
    static func listing(tool path: String) -> String? {
        listing { deadline in
            // This used to wait before reading, which is the deadlock order, and
            // paid 67 ms in the run-loop poll on every call.
            HelmProcess.run(path, ["list"], timeout: deadline)
        }
    }

    /// The same answer over a tool that is handed in, so a test can stand in
    /// for `systemextensionsctl`. The closure is given `listingDeadline`.
    ///
    /// A tool that did not finish in time, and one whose output has an id in
    /// bytes that are not UTF-8, each leave a line in the log: the caller is
    /// told only that nothing answered. A non-zero exit leaves none.
    static func listing(running tool: (_ deadline: TimeInterval) -> HelmProcess.Result) -> String? {
        let result = tool(listingDeadline)
        if result.status == HelmProcess.timedOutStatus {
            HelmLog.shared.warn("process", "systemextensionsctl list did not answer within "
                + "\(Int(listingDeadline)) s — read as no answer")
            return nil
        }
        guard result.status == 0 else { return nil }
        guard SystemExtensionParser.isReadable(result.output) else {
            HelmLog.shared.warn("process", "systemextensionsctl named an extension in bytes that "
                + "are not UTF-8 — read as no answer")
            return nil
        }
        return result.output
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

    /// The list, or `nil` when `listing()` has none to give; its doc comment
    /// says when.
    public static func installedIfAnswered() -> [SystemExtensionInfo]? {
        listing().map(SystemExtensionParser.parse)
    }

    /// The apps whose extensions are loaded, or `nil` when `listing()` has none
    /// to give; its doc comment says when.
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
