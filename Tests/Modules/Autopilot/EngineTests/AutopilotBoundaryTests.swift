import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

private func facts(_ name: String, added: Date) -> FileFacts {
    FileFacts(name: name, kind: .document, bytes: 4, added: added, modified: added,
              now: Date(timeIntervalSince1970: 1_784_116_800))
}

/// The edges of the three things that have no natural stopping point: the
/// collision counter, the stamp's stored value, and the scope gate a
/// destination has to pass.
final class AutopilotBoundaryTests: XCTestCase {

    private let stamp = RuleStamp(key: TestRuleKey.material)
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("bounds")
    }

    // MARK: - The end of the collision counter

    /// `free(_:)` gives up at 999 and hands back the name that is taken. What
    /// happens then is the only thing that matters: the move must fail, not
    /// succeed. 999 numbered files in one folder is what a year of a daily
    /// screenshot rule with a fixed name looks like.
    ///
    /// This is the one failure the module could commit that nobody can undo, so
    /// the assertion is on the *contents* of the occupied name, not on an
    /// outcome value.
    func testACollisionCounterThatRunsOutRefusesRatherThanOverwrites() throws {
        let destination = root.appendingPathComponent("D")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("ORIGINAL".utf8).write(to: destination.appendingPathComponent("a.pdf"))
        for index in 2...999 {
            try Data("\(index)".utf8).write(to: destination.appendingPathComponent("a \(index).pdf"))
        }
        let arriving = root.appendingPathComponent("a.pdf")
        try Data("ARRIVING".utf8).write(to: arriving)

        let rule = Rule(id: "r", name: "r", enabled: true,
                        conditions: [.fileExtension(["pdf"])],
                        action: .move(to: destination.path))
        let outcome = RuleRunner().run(RulePlan(facts: facts("a.pdf", added: Date()), rule: rule),
                                       at: arriving.path, key: TestRuleKey.material)

        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("a.pdf"),
                                  encoding: .utf8), "ORIGINAL",
                       "the file that was already there was overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: arriving.path),
                      "the arriving file went somewhere and it was not the destination")
        if case .moved = outcome { XCTFail("reported a move that cannot have happened safely") }
        XCTAssertFalse(stamp.isStamped(arriving.path, by: "r"),
                       "a move that did not happen was recorded as done")
    }

    // MARK: - What the stamp is asked to hold

    /// The attribute is on somebody's file and any process can write it. Garbage
    /// in it must read as "not stamped" — the safe direction, because the runner
    /// asks before acting — and must not stop a real stamp from being written
    /// over the top of it afterwards.
    func testAStampFullOfGarbageReadsAsUnstampedAndCanBeReplaced() throws {
        let file = root.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: file)
        let junk = Data("{ this is not a JSON array".utf8)
        _ = junk.withUnsafeBytes {
            setxattr(file.path, RuleStamp.attribute, $0.baseAddress, $0.count, 0, 0)
        }

        XCTAssertFalse(stamp.isStamped(file.path, by: "r"))
        XCTAssertTrue(stamp.stamp(file.path, by: "r"),
                      "a file whose attribute holds junk can never be marked again")
        XCTAssertTrue(stamp.isStamped(file.path, by: "r"))
    }

    /// Rule ids are `UUID` strings, but they are stored, migrated and
    /// hand-editable, and they are the JSON payload. A quote, a backslash, an
    /// emoji and Cyrillic all have to round-trip, and none of them may take
    /// another rule's mark with it.
    func testAStampSurvivesRuleIdsThatAreNotUUIDs() throws {
        let file = root.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: file)
        let ids = ["plain", "a\"quoted\"", "back\\slash", "🙂", "правило", "", "  ", "[]"]

        for id in ids {
            XCTAssertTrue(stamp.stamp(file.path, by: id), "\(id.debugDescription) would not stick")
        }
        for id in ids {
            XCTAssertTrue(stamp.isStamped(file.path, by: id),
                          "\(id.debugDescription) was lost when a later rule stamped the same file")
        }
        XCTAssertFalse(stamp.isStamped(file.path, by: "not-one-of-them"))
    }

    // MARK: - Where a destination may point

    /// Where a rule may be aimed: never outside the user's own files, checked on
    /// the destination as well as on the file, because a rule is a decision
    /// made once and executed forever. Answered by `WatchScope`, the module's
    /// own gate, and not by `UserFileScope`, which answers "may this be trashed
    /// without breaking the machine" and says yes to all of these.
    ///
    /// Helm holds Full Disk Access and these rules come from a plist any process
    /// running as the user can write, so a gate that permits `~/Library/Messages`
    /// makes the module a data-exfil tool with somebody else's permissions, and
    /// one that permits a `LaunchAgents` folder makes it the script action this
    /// module deliberately does not have.
    func testARuleCannotBeAimedAtSomethingThatIsNotTheUsersFiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for destination in ["/Library/LaunchAgents", "/Library/LaunchDaemons",
                            "/Library/Preferences", "/Applications/Utilities",
                            "/etc", "/var/root", "/Users/someone-else/Documents",
                            "\(home)/Library", "\(home)/Library/LaunchAgents",
                            "\(home)/Library/Safari", "\(home)/Library/Messages",
                            home, "/", "/Volumes", "/Volumes/Backup"] {
            XCTAssertFalse(WatchScope.allows(destination, home: home),
                           "\(destination) is accepted as a rule's destination")
        }
    }

    /// And where it may. The other side of the same gate, so a narrower gate
    /// cannot lock somebody out of the folders the module is *for*.
    func testTheFoldersARuleIsForStayReachable() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for destination in ["\(home)/Downloads", "\(home)/Desktop",
                            "\(home)/Documents/Invoices/2026",
                            "/Volumes/Backup/Photos"] {
            XCTAssertTrue(WatchScope.allows(destination, home: home),
                          "\(destination) is the module's whole purpose and was refused")
        }
    }

    /// The premise the two tests below rest on, pinned so a change in
    /// Foundation shows up here as this sentence failing rather than as the
    /// gate quietly reopening.
    ///
    /// `resolvingSymlinksInPath` canonicalizes nothing at all unless **every**
    /// component of the path already exists — not merely the missing tail. So
    /// a destination that has yet to be created, which is exactly what a rule
    /// naming a folder is, reaches the gate spelled however the plist spelled
    /// it.
    func testAPathWithAMissingComponentIsNotCanonicalizedAtAll() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertEqual(URL(fileURLWithPath: "\(home)/library/Preferences")
            .resolvingSymlinksInPath().path, "\(home)/Library/Preferences",
            "every component exists, so the case is fixed")
        let missing = "\(home)/library/Preferences/Helm-\(UUID().uuidString)"
        XCTAssertEqual(URL(fileURLWithPath: missing).resolvingSymlinksInPath().path, missing,
                       "one missing component and the case of the rest is left alone too")
    }

    /// `~/Library` is refused however the plist spells it.
    ///
    /// The rules are JSON in `UserDefaults` that any process running as the
    /// user can write, so a planted `.move(to: "~/library/Application Support/Sorted")`
    /// must not miss the `~/Library` test on case alone. `RuleRunner.move`
    /// calls `createDirectory(withIntermediateDirectories:)`, which on the
    /// case-insensitive volume Helm ships to lands inside the real
    /// `~/Library/Application Support`, and the hourly sweep would carry files
    /// there. The panel returns canonical paths, so only a written plist
    /// reaches this.
    func testTheLibraryRefusalDoesNotDependOnHowItIsSpelled() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // The leaf does not exist, because a destination a rule asks to be
        // created is a leaf that does not exist. That is the whole case.
        let leaf = "Helm-\(UUID().uuidString)"
        for destination in ["\(home)/library/Application Support/\(leaf)",
                            "\(home)/LIBRARY/\(leaf)",
                            "\(home)/Library/Application Support/\(leaf)",
                            "\(home)/library/LaunchAgents/\(leaf)",
                            "\(home)/library"] {
            XCTAssertFalse(WatchScope.allows(destination, home: home),
                           "\(destination) is accepted as a rule's destination")
        }
    }

    /// And the same gate, with a home that exists only as a string. Nothing
    /// here touches the disk, so it says what the rule *is* rather than what
    /// this machine happens to have in it.
    func testTheLibraryRefusalHoldsForAHomeThatIsNotOnThisDisk() {
        let home = "/Users/nobody-\(UUID().uuidString)"
        for destination in ["\(home)/library/Sorted", "\(home)/Library/Sorted",
                            "\(home)/LiBrArY/Sorted"] {
            XCTAssertFalse(WatchScope.allows(destination, home: home),
                           "\(destination) is accepted as a rule's destination")
        }
        XCTAssertTrue(WatchScope.allows("\(home)/Downloads/Sorted", home: home),
                      "and the folders the module is for are still reachable")
    }

    /// A destination that does not exist yet is still canonicalized, so the
    /// gate answers about where the path *leads* rather than how it is
    /// written. Without this the sorting action — whose destination is a
    /// subfolder that by definition does not exist on the first sweep — is
    /// judged on a spelling.
    func testADestinationThatDoesNotExistYetIsStillResolved() throws {
        let home = root.appendingPathComponent("home")
        let real = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = home.appendingPathComponent("out")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertTrue(WatchScope.allows(real.appendingPathComponent("Images").path,
                                        home: home.path),
                      "a bucket a sorting rule is about to create was refused")
        XCTAssertFalse(WatchScope.allows(link.appendingPathComponent("Images").path,
                                         home: home.path),
                       "a symlinked ancestor walked the rule out of the home directory")
    }

    /// The gate is about where a path *leads*, not how it is spelled: a
    /// destination chosen through the panel can be replaced by a symlink
    /// afterwards, and the rule would go on using it every hour.
    func testASymlinkOutOfScopeIsRefusedThroughTheLink() throws {
        let home = root.appendingPathComponent("home")
        let inside = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let link = inside.appendingPathComponent("out")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertTrue(WatchScope.allows(inside.path, home: home.path))
        XCTAssertFalse(WatchScope.allows(link.path, home: home.path),
                       "a symlink walked the rule out of the home directory")
    }

    func testTheUsersOwnFoldersStayReachable() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for destination in ["\(home)/Downloads", "\(home)/Documents/Invoices",
                            "\(home)/Library/Application Support/Thing", root.path] {
            XCTAssertTrue(UserFileScope.isRemovable(destination),
                          "\(destination) is the user's own and a rule was refused it")
        }
    }
}

/// Two ways a sorting rule could turn on the folders it made itself.
final class AutopilotSelfSortTests: XCTestCase {

    private func facts(_ name: String, isDirectory: Bool, bytes: Int) -> FileFacts {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return FileFacts(name: name, path: "/tmp/\(name)",
                         kind: isDirectory ? .folder : .document,
                         bytes: bytes, added: now, modified: now,
                         isDirectory: isDirectory, now: now)
    }

    /// A folder's byte count is 0, so "smaller than" would be true of every
    /// folder in the watched directory, the buckets a sort rule made included.
    /// A folder has no size to compare; the condition says no.
    func testASizeConditionNeverMatchesAFolder() {
        let rule = Rule(id: "r", name: "r", enabled: true,
                        conditions: [.size(.smallerThan, megabytes: 1)], action: .trash)
        XCTAssertFalse(RuleMatcher.matches(facts("Images", isDirectory: true, bytes: 0), rule))
        XCTAssertTrue(RuleMatcher.matches(facts("a.pdf", isDirectory: false, bytes: 10), rule))
    }

    /// And the other end: whatever a rule matched, a folder cannot be moved
    /// inside itself. Asked of the file system, it fails with EINVAL every sweep.
    func testAFolderIsNotMovedIntoItself() throws {
        let home = scratchDirectory("self")
        let bucket = home.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)

        let runner = RuleRunner(home: home.path)
        let plan = RulePlan(
            facts: FileFacts(name: "Images", path: bucket.path, kind: .folder, bytes: 0,
                             added: Date(), modified: Date(), isDirectory: true),
            rule: Rule(id: "r", name: "r", enabled: true,
                       conditions: [.kind(.folder)], action: .move(to: bucket.path)))

        XCTAssertEqual(runner.run(plan, at: bucket.path, key: TestRuleKey.material), .targetOutOfScope)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bucket.path))
    }
}
