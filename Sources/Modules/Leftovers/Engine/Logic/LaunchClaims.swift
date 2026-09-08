import Foundation

/// Which files register a launchd label, and what it means when more than one
/// does.
///
/// **launchd's switch is aimed at a label, and a label is not a file.**
/// `ActiveExtensions.setDisabled` runs `launchctl disable gui/<uid>/<label>`, and
/// `com.vendor.updater` sits in `~/Library/LaunchAgents` and in
/// `/Library/LaunchAgents` on plenty of Macs — one agent for the person, one for
/// everybody. Both load into `gui/<uid>`, so both files claim one switch. The scan
/// is right to return two rows; what is not two is the act. With one of them badged
/// «Leftover» in orange and the other «In use» in green, «Turn off» on the obvious
/// rubbish stopped the working job, with nothing on screen having said so.
///
/// Which of the two registrations launchd actually kept is not something this app
/// can read — that needs a `launchctl print` port it does not have — so the safe
/// answer is that neither row may be switched, and each row names the other
/// (`StaleItem.labelAlsoClaimedBy`).
///
/// **One rule, two readings.** The scan asks it of the launch items it has just
/// read; the engine asks it of the two folders at the moment of the press, which is
/// the fresher of the two — a list on screen is as old as the scan that drew it.
/// The offer and the act cannot come to disagree about a row, which is the whole
/// reason `LaunchLabel` is a single predicate.
enum LaunchClaims {

    /// One file, and the label it registers with launchd.
    struct Claim: Equatable, Sendable {
        let label: String
        let path: String
    }

    /// The folder launchd loads a user's agents from, spelled once.
    ///
    /// `LaunchLabel.mayBeSwitched` matches the end of a path against it and
    /// `agentFolders` builds both folders from it — two readings of one fact, and a
    /// name only one of them knew would be an error nowhere: the engine would read
    /// folders whose rows the page never treats as switchable.
    static let agentFolder = "Library/LaunchAgents"

    /// The folders launchd loads a **user's** agents from: the person's own and
    /// root's, which is exactly the set `LaunchLabel.mayBeSwitched` allows a switch
    /// to be aimed from.
    ///
    /// `/Library/LaunchDaemons` is deliberately not here. A daemon loads in the
    /// system domain, so a daemon of the same name is a different job and not a
    /// second claim on this switch — and `launchctl disable gui/<uid>/…` would not
    /// reach it anyway.
    static func agentFolders(home: URL) -> [URL] {
        [home.appendingPathComponent(agentFolder), URL(fileURLWithPath: "/" + agentFolder)]
    }

    /// The files that register this label.
    ///
    /// An empty label registers nothing: launchd lets a job omit `Label` and take
    /// its name from the file, and `gui/<uid>/` with nothing after it names the
    /// domain rather than a service in it (`LaunchLabel.isSwitchable`). Counting
    /// those together would make every unlabelled job a rival of every other.
    static func claimants(of label: String, in claims: [Claim]) -> [String] {
        guard !label.isEmpty else { return [] }
        return claims.filter { $0.label == label }.map(\.path)
    }

    /// The same question asked of a reading of the disk, which carries whether
    /// there was a folder it could not count.
    ///
    /// The count and «was everything counted» are two halves of one reading and
    /// are never useful apart: a caller holding only the count is a caller
    /// treating a folder that did not open as a folder with nothing in it.
    static func claimants(of label: String, in reading: Reading) -> [String] {
        claimants(of: label, in: reading.claims)
    }

    /// For every file that is not alone in registering its label, one other file
    /// that registers it too — keyed by path, which is the row's own id.
    ///
    /// One name is enough for what the row has to say: there is another file
    /// wearing this name, here it is, and that is why this row does not offer to
    /// switch anything off.
    static func rivals(among claims: [Claim]) -> [String: String] {
        var rivals: [String: String] = [:]
        for claim in claims {
            let others = claimants(of: claim.label, in: claims).filter { $0 != claim.path }
            if let first = others.first { rivals[claim.path] = first }
        }
        return rivals
    }

    /// One reading of the two agent folders: what registers a label there, and
    /// whether both folders opened.
    ///
    /// **The second half is not a detail of the first.** A folder that would not
    /// open hands back nothing, and nothing is what a folder with no rival in it
    /// hands back too — so a count taken without it is the strongest claim this
    /// module makes («no second file registers this label, the switch may go
    /// through») resting on a read that never happened. Both folders are ordinary
    /// candidates for it: `/Library/LaunchAgents` is root's and Helm is not root,
    /// and `~/Library/LaunchAgents` sits behind a TCC grant that is denied on 23 of
    /// the 42 launches ARCHITECTURE.md records.
    struct Reading: Equatable, Sendable {
        /// What the folders that opened hold.
        let claims: [Claim]
        /// Whether every agent folder answered with its contents. False when one
        /// of them refused, which is «anything could be in there» and never
        /// «nothing is».
        let everyFolderOpened: Bool
    }

    /// What every `.plist` in the two agent folders registers, read now.
    ///
    /// Read through `LaunchAgentReader`, the same reader the scan uses, so both
    /// sides agree about the label a file claims — including a file whose contents
    /// would not come, whose label is then its own name, which is the convention
    /// launchd itself goes by.
    ///
    /// `contents(of:)` rather than `children(of:)`, which is the port's own rule:
    /// every reader of a source draws a conclusion from an empty answer, and this
    /// one draws the act.
    static func onDisk(home: URL, files: LeftoversFilePort) -> Reading {
        let readings = agentFolders(home: home).map { files.contents(of: $0) }
        return Reading(
            claims: readings.flatMap(\.entries)
                .filter { $0.pathExtension == "plist" }
                .map { url in
                    // A plist read per file, handing back autoreleased Foundation
                    // objects — ARCHITECTURE.md § Memory, inside the iteration.
                    autoreleasepool {
                        Claim(label: LaunchAgentReader.read(plist: files.readPlist(url)?.raw ?? [:],
                                                            path: url.path).identifier,
                              path: url.path)
                    }
                },
            everyFolderOpened: !readings.contains(.refused))
    }
}
