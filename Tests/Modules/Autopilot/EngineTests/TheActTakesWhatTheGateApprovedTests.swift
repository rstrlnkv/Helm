import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The window between the gate and the act.
///
/// `WatchScope.allows` resolves a path's symlinked ancestors at *check* time;
/// `moveItem` and `trashItem` resolve them again at *move* time. Between the two
/// sit `fileExists`, `createDirectory` and the collision loop, and a process that
/// can write anywhere inside a watched folder can swap a directory for a link in
/// that window. Helm holds Full Disk Access and the swapper may hold none, so
/// what comes out is not something they could have taken themselves.
///
/// **The race is not raced here.** Measured against the real runner it was won
/// about eight times in a hundred, and a test that loses is a test that passes
/// for the wrong reason. So the swap is hung on the runner's own reading of
/// where the path leads: the gate's reading is answered truthfully — from the
/// real `PathCanonical` — and the swap lands the instant afterwards, every run.
/// Nothing else about the runner is faked, the files are real, and every
/// assertion below is about what is on the disk when it is over.
///
/// Each test asserts the swap *happened* before asserting nothing was carried
/// out of the vault: an absence proves nothing when the subject never ran.
final class TheActTakesWhatTheGateApprovedTests: XCTestCase {

    private var home: URL!
    /// Where the rule watches, and where the swapper may write.
    private var watched: URL!
    /// A real directory inside the watched folder, and the thing that gets
    /// replaced by a link.
    private var subfolder: URL!
    /// `~/Library` stands for every folder a rule may not reach and Helm can:
    /// `WatchScope` refuses it outright, so nothing the runner is asked about
    /// here is a path it would ever approve.
    private var vault: URL!
    /// The name the vault's file and the decoy share — the swap works by making
    /// one path resolve to the other, so the leaf has to match.
    ///
    /// Unownable, because the trash arm really does trash: with the guard
    /// removed this file lands in `~/.Trash` on the machine running the suite,
    /// and a cleanup that removes `~/.Trash/x.pdf` would be deleting somebody's
    /// own work.
    private var leaf: String!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        watched = home.appendingPathComponent("Downloads")
        subfolder = watched.appendingPathComponent("d")
        vault = home.appendingPathComponent("Library/Mail")
        leaf = unownableLeaf("x.pdf")
        reclaimFromTrash(leaf)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data("PRIVATE".utf8).write(to: vault.appendingPathComponent(leaf))
        try Data("decoy".utf8).write(to: subfolder.appendingPathComponent(leaf))
    }

    /// The swapper, forced to win.
    ///
    /// Answers `watching`'s first reading from the real filesystem, then does the
    /// swap — which puts it exactly where a lucky attacker lands, and puts it
    /// there on every run. Later readings see the swapped disk, because they are
    /// the same real call.
    private final class WinTheRace: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let watching: String
        private let swap: @Sendable () -> Void

        init(after watching: String, swap: @escaping @Sendable () -> Void) {
            self.watching = watching
            self.swap = swap
        }

        var won: Bool { lock.withLock { done } }

        func read(_ path: String) -> PathCanonical.AncestryIdentity? {
            let answer = PathCanonical.ancestryIdentity(of: path)
            lock.lock()
            let first = path == watching && !done
            if first { done = true }
            lock.unlock()
            if first { swap() }
            return answer
        }
    }

    /// Replace `at` — a real directory — with a symlink to `with`, the way a
    /// process that can write in the watched folder does.
    private func swapping(_ at: URL, with: URL) -> @Sendable () -> Void {
        { [at, with] in
            try? FileManager.default.removeItem(at: at)
            try? FileManager.default.createSymbolicLink(at: at, withDestinationURL: with)
        }
    }

    private func facts(_ url: URL) -> FileFacts {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return FileFacts(name: url.lastPathComponent, path: url.path, kind: .document,
                         bytes: 7, added: now, modified: now, now: now)
    }

    private func plan(_ url: URL, _ action: RuleAction) -> RulePlan {
        RulePlan(facts: facts(url),
                 rule: Rule(id: "r", name: "r", enabled: true,
                            conditions: [.name(.contains, "")], action: action))
    }

    private func vaultFileIsUntouched() throws {
        let kept = vault.appendingPathComponent(leaf)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path),
                      "the file was carried out of a folder no rule may reach")
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "PRIVATE")
    }

    // MARK: - The source

    /// The measured exploit: the gate approves `Downloads/d/x.pdf`, `d` becomes a
    /// link to the vault, and the move carries the vault's file to a folder the
    /// swapper can read.
    func testAnAncestorSwappedAfterTheGateStopsTheMove() throws {
        let bait = subfolder.appendingPathComponent(leaf)
        let out = watched.appendingPathComponent("Out")
        let race = WinTheRace(after: bait.path, swap: swapping(subfolder, with: vault))
        let runner = RuleRunner(home: home.path, ancestry: race.read)

        let outcome = runner.run(plan(bait, .move(to: out.path)), at: bait.path, key: TestRuleKey.material)

        XCTAssertTrue(race.won, "the swap never happened, so this test proves nothing")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: subfolder.path),
                       vault.path, "the watched subfolder does not lead into the vault")
        XCTAssertEqual(outcome, .refused(.changedSinceCheck))
        try vaultFileIsUntouched()
        XCTAssertFalse(FileManager.default.fileExists(atPath:
                        out.appendingPathComponent(leaf).path),
                       "the vault's file arrived where the swapper can read it")
    }

    /// The same window, one action along: a rename resolves the path again too,
    /// and the pattern is applied to whatever the link now points at.
    func testAnAncestorSwappedAfterTheGateStopsTheRename() throws {
        let bait = subfolder.appendingPathComponent(leaf)
        let race = WinTheRace(after: bait.path, swap: swapping(subfolder, with: vault))
        let runner = RuleRunner(home: home.path, ancestry: race.read)

        let outcome = runner.run(plan(bait, .rename(pattern: "{name}-taken")), at: bait.path, key: TestRuleKey.material)

        XCTAssertTrue(race.won, "the swap never happened, so this test proves nothing")
        XCTAssertEqual(outcome, .refused(.changedSinceCheck))
        try vaultFileIsUntouched()
        let renamed = (leaf as NSString).deletingPathExtension + "-taken.pdf"
        XCTAssertFalse(FileManager.default.fileExists(atPath:
                        vault.appendingPathComponent(renamed).path))
    }

    /// A tag is a write to whatever the path leads to when the write happens —
    /// and this arm is the one that was already closed. It refuses any path
    /// whose resolution differs from its spelling, asked where it acts rather
    /// than at the gate, so the swap fails a stronger question than "did this
    /// change". Kept as a test because the arm is one line from a metadata write
    /// into a folder no rule may reach, and nothing else says so.
    func testAnAncestorSwappedAfterTheGateStopsTheTag() throws {
        let bait = subfolder.appendingPathComponent(leaf)
        let race = WinTheRace(after: bait.path, swap: swapping(subfolder, with: vault))
        let runner = RuleRunner(home: home.path, ancestry: race.read)

        let outcome = runner.run(plan(bait, .addTag("Sorted")), at: bait.path, key: TestRuleKey.material)

        XCTAssertTrue(race.won, "the swap never happened, so this test proves nothing")
        XCTAssertEqual(outcome, .refused(.outOfScope))
        let tags = try vault.appendingPathComponent(leaf)
            .resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        XCTAssertEqual(tags, [], "the vault's file was written to")
    }

    /// And the arm that deletes. `trashItem` resolves the path itself, so the
    /// vault's file is what would go to the Trash — a removal the person never
    /// asked for, of a file the rule was never allowed to see.
    func testAnAncestorSwappedAfterTheGateStopsTheTrashing() throws {
        let bait = subfolder.appendingPathComponent(leaf)
        let race = WinTheRace(after: bait.path, swap: swapping(subfolder, with: vault))
        let runner = RuleRunner(home: home.path, ancestry: race.read)

        let outcome = runner.run(plan(bait, .trash), at: bait.path, key: TestRuleKey.material)

        XCTAssertTrue(race.won, "the swap never happened, so this test proves nothing")
        XCTAssertEqual(outcome, .refused(.changedSinceCheck))
        try vaultFileIsUntouched()
    }

    // MARK: - The destination

    /// The other end of the same window, and the wider one: the destination is
    /// gated, then created, then the collision loop runs — and a link swapped in
    /// over the destination sends the file *into* the vault rather than out of
    /// it, which is a rule writing where no rule may reach.
    func testADestinationSwappedAfterItWasApprovedStopsTheMove() throws {
        let file = try write("moving.pdf", in: watched)
        let out = watched.appendingPathComponent("Out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let target = out.appendingPathComponent("moving.pdf")
        let race = WinTheRace(after: target.path, swap: swapping(out, with: vault))
        let runner = RuleRunner(home: home.path, ancestry: race.read)

        let outcome = runner.run(plan(file, .move(to: out.path)), at: file.path, key: TestRuleKey.material)

        XCTAssertTrue(race.won, "the swap never happened, so this test proves nothing")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: out.path),
                       vault.path, "the destination does not lead into the vault")
        XCTAssertEqual(outcome, .refused(.changedSinceCheck))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
                        vault.appendingPathComponent("moving.pdf").path),
                       "the rule wrote into a folder it may not reach")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "the file was moved somewhere and it was not the destination")
    }
}
