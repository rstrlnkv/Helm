import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The edges of the four things that have no natural stopping point: the
/// collision counter, the stamp's stored value, the date formatters, and the
/// scope gate a destination has to pass.
final class AutopilotBoundaryTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-bounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func facts(_ name: String, added: Date) -> FileFacts {
        FileFacts(name: name, kind: .document, bytes: 4, added: added, modified: added,
                  now: Date(timeIntervalSince1970: 1_784_116_800))
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
                                       at: arriving.path)

        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("a.pdf"),
                                  encoding: .utf8), "ORIGINAL",
                       "the file that was already there was overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: arriving.path),
                      "the arriving file went somewhere and it was not the destination")
        if case .moved = outcome { XCTFail("reported a move that cannot have happened safely") }
        XCTAssertFalse(RuleStamp.isStamped(arriving.path, by: "r"),
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

        XCTAssertFalse(RuleStamp.isStamped(file.path, by: "r"))
        XCTAssertTrue(RuleStamp.stamp(file.path, by: "r"),
                      "a file whose attribute holds junk can never be marked again")
        XCTAssertTrue(RuleStamp.isStamped(file.path, by: "r"))
    }

    /// Rule ids are `UUID` strings today, but they are stored, migrated and
    /// hand-editable, and they are the JSON payload. A quote, a backslash, an
    /// emoji and Cyrillic all have to round-trip, and none of them may take
    /// another rule's mark with it.
    func testAStampSurvivesRuleIdsThatAreNotUUIDs() throws {
        let file = root.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: file)
        let ids = ["plain", "a\"quoted\"", "back\\slash", "🙂", "правило", "", "  ", "[]"]

        for id in ids {
            XCTAssertTrue(RuleStamp.stamp(file.path, by: id), "\(id.debugDescription) would not stick")
        }
        for id in ids {
            XCTAssertTrue(RuleStamp.isStamped(file.path, by: id),
                          "\(id.debugDescription) was lost when a later rule stamped the same file")
        }
        XCTAssertFalse(RuleStamp.isStamped(file.path, by: "not-one-of-them"))
    }

    // MARK: - Dates with nothing behind them

    /// `FolderReader` substitutes `Date.distantPast` when a file has neither an
    /// added date nor a creation date — a file restored from a backup, or one on
    /// a filesystem that does not keep either. Both date-shaped actions then get
    /// handed a year-one date, and both of them are producing a *name*: the
    /// answer has to stay one usable path component rather than an empty string
    /// or something with a separator in it.
    func testADateThatIsMissingStillMakesAUsableName() {
        let missing = facts("a.pdf", added: .distantPast)

        let bucket = SortBucket.name(for: missing, scheme: .month)
        XCTAssertFalse(bucket.isEmpty)
        XCTAssertFalse(bucket.contains("/"))
        XCTAssertFalse(bucket.hasPrefix("."))
        XCTAssertTrue(bucket.allSatisfy { $0.isNumber || $0 == "-" },
                      "a bucket named \(bucket.debugDescription) is not a date and will not sort")

        let renamed = RenamePattern.apply("{date}", to: missing)
        XCTAssertNotNil(renamed)
        XCTAssertFalse(renamed?.contains("/") ?? true)
    }

    /// The month bucket has to keep sorting chronologically by name, which is
    /// the whole reason it is `yyyy-MM` and not a month name. Asserted as an
    /// ordering over a year of dates rather than as literal strings: the
    /// formatter carries no time zone, so the exact bucket a given instant falls
    /// into is the machine's business, but the order never is.
    func testMonthBucketsSortChronologicallyByName() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let buckets = (0..<14).map { month -> String in
            SortBucket.name(for: facts("a.pdf", added: start.addingTimeInterval(Double(month) * 31 * 86_400)),
                            scheme: .month)
        }

        XCTAssertEqual(buckets, buckets.sorted(),
                       "sorting the bucket names does not put the months in order")
        XCTAssertTrue(buckets.allSatisfy { $0.count == 7 && $0.dropFirst(4).first == "-" })
        XCTAssertTrue(Set(buckets).count >= 13, "a year and a bit produced fewer than 13 months")
    }

    /// The two sides of a month boundary must land in adjacent buckets and never
    /// in the same one, whichever time zone the machine is in. Built from the
    /// current calendar so the boundary is a real local one rather than an
    /// assumption about UTC.
    func testTheTwoSidesOfAMonthBoundaryAreDifferentBuckets() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 1
        let firstOfAugust = try XCTUnwrap(Calendar.current.date(from: components))
        let lastOfJuly = firstOfAugust.addingTimeInterval(-1)

        let before = SortBucket.name(for: facts("a.pdf", added: lastOfJuly), scheme: .month)
        let after = SortBucket.name(for: facts("a.pdf", added: firstOfAugust), scheme: .month)

        XCTAssertNotEqual(before, after, "a second apart across a month boundary sorted together")
        XCTAssertLessThan(before, after)
    }

    // MARK: - Where a destination may point

    /// Guarantee 4: a rule cannot reach outside the user's own files. It is
    /// checked on the destination as well as on the file, because a rule is a
    /// decision made once and executed forever.
    ///
    /// `UserFileScope` is not that check. It was written for a different
    /// question — what the disk module may *trash* without breaking the machine
    /// — and its list of protected prefixes has no opinion about writing. So a
    /// destination of `/Library/LaunchAgents` passes it: on an admin account a
    /// rule that says "every .plist that lands in Downloads goes to
    /// /Library/LaunchAgents" is a rule that turns "a file appeared" into code
    /// that runs at login, which is the exact thing `RuleAction`'s comment says
    /// the module must never make possible.
    /// Where a rule may be aimed. Answered by `WatchScope`, the module's own
    /// gate, and not by `UserFileScope` — which was written for a different
    /// question ("may this be trashed without breaking the machine") and says
    /// yes to all of these.
    ///
    /// The distinction is not academic. Helm holds Full Disk Access and these
    /// rules come from a plist any process running as the user can write, so a
    /// gate that permits `~/Library/Messages` makes the module a data-exfil
    /// tool with somebody else's permissions, and one that permits a
    /// `LaunchAgents` folder makes it the script action this module
    /// deliberately does not have.
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

    /// And where it may. The other side of the same gate, so a fix to the line
    /// above cannot lock somebody out of the folders the module is *for*.
    func testTheFoldersARuleIsForStayReachable() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for destination in ["\(home)/Downloads", "\(home)/Desktop",
                            "\(home)/Documents/Invoices/2026",
                            "/Volumes/Backup/Photos"] {
            XCTAssertTrue(WatchScope.allows(destination, home: home),
                          "\(destination) is the module's whole purpose and was refused")
        }
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

    /// A folder's byte count is 0, so "smaller than" was true of every folder
    /// in the watched directory — including the buckets a sort rule had just
    /// created. A folder has no size to compare; the condition says no.
    func testASizeConditionNeverMatchesAFolder() {
        let rule = Rule(id: "r", name: "r", enabled: true,
                        conditions: [.size(.smallerThan, megabytes: 1)], action: .trash)
        XCTAssertFalse(RuleMatcher.matches(facts("Images", isDirectory: true, bytes: 0), rule))
        XCTAssertTrue(RuleMatcher.matches(facts("a.pdf", isDirectory: false, bytes: 10), rule))
    }

    /// And the other end: whatever a rule matched, a folder cannot be moved
    /// inside itself. Before this it failed with EINVAL on every sweep forever.
    func testAFolderIsNotMovedIntoItself() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-self-\(UUID().uuidString)")
        let bucket = home.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let runner = RuleRunner(home: home.path)
        let plan = RulePlan(
            facts: FileFacts(name: "Images", path: bucket.path, kind: .folder, bytes: 0,
                             added: Date(), modified: Date(), isDirectory: true),
            rule: Rule(id: "r", name: "r", enabled: true,
                       conditions: [.kind(.folder)], action: .move(to: bucket.path)))

        XCTAssertEqual(runner.run(plan, at: bucket.path), .refused(.outOfScope))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bucket.path))
    }
}
