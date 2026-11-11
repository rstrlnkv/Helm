import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The trash action asks `HelmTrash.removeOne` and reads its sum.
///
/// **Nothing here reaches the real Trash.** Every run passes `trashing:` a
/// closure that moves into a scratch bin, or throws.
final class ATrashRuleGoesThroughHelmTrashTests: XCTestCase {

    private var home: URL!
    private var watched: URL!
    private var bin: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        watched = home.appendingPathComponent("Downloads")
        bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }

    private func write(_ name: String) throws -> URL {
        let url = watched.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func plan(_ url: URL) -> RulePlan {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: url.lastPathComponent, path: url.path, kind: .document,
                              bytes: 1, added: now, modified: now, now: now)
        return RulePlan(facts: facts,
                        rule: Rule(id: "r", name: "r", enabled: true,
                                   conditions: [.name(.contains, "")], action: .trash))
    }

    private func run(_ url: URL, trashing: @escaping @Sendable (URL) throws -> URL?) -> RuleOutcome {
        RuleRunner(home: home.path, trashing: trashing)
            .run(plan(url), at: url.path, key: TestRuleKey.material)
    }

    func testTheOutcomeIsTheURLTheMoveAnswered() throws {
        let file = try write("a.pdf")
        let landed = bin.appendingPathComponent("a 2.pdf")
        let outcome = run(file) { url in
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }
        XCTAssertEqual(outcome, .trashed(to: landed.path))
        XCTAssertNotEqual(landed.lastPathComponent, file.lastPathComponent, "the control is a colliding name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: landed.path))
    }

    func testAMoveThatWillNotSayWhereGivesAnEmptyPlace() throws {
        let file = try write("b.pdf")
        XCTAssertEqual(run(file) { try FileManager.default.removeItem(at: $0); return nil }, .trashed(to: ""))
    }

    /// A move that returns and leaves the file is not `.trashed`: the rule's
    /// history would otherwise say a file was trashed that is still in Downloads.
    func testAMoveThatReturnsAndLeavesTheFileIsAFailureNotTrashed() throws {
        let file = try write("f.pdf")
        let outcome = run(file) { _ in nil }
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAFileGoneBetweenTheChecksAndTheMoveIsMissing() throws {
        let file = try write("c.pdf")
        let outcome = run(file) { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError) }
        XCTAssertEqual(outcome, .refused(.missing))
    }

    func testAPermissionRefusalIsAFailureWithTheSystemsSentence() throws {
        let file = try write("d.pdf")
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        XCTAssertEqual(run(file) { _ in throw error }, .failed(HelmFailure.describe(error)))
    }

    /// The path leads somewhere else by the time of the move: the entry stops,
    /// the closure never runs, and the runner reports it in its own words.
    func testAPathThatLeadsElsewhereAtTheMoveIsRefusedAsChanged() throws {
        final class Reads: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func next() -> PathCanonical.AncestryIdentity? {
                lock.lock(); defer { lock.unlock() }
                n += 1
                return PathCanonical.AncestryIdentity(device: 1, inode: UInt64(n))
            }
        }
        let file = try write("e.pdf")
        let reads = Reads()
        let moved = Reads()
        let runner = RuleRunner(home: home.path, ancestry: { _ in reads.next() },
                                trashing: { _ in _ = moved.next(); return nil })
        let outcome = runner.run(plan(file), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(outcome, .refused(.changedSinceCheck))
        XCTAssertEqual(moved.next()?.inode, 1, "the move ran after the path changed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// The move is `HelmTrash`'s: no `trashItem` in this file.
    func testTheRunnerHoldsNoTrashItemOfItsOwn() throws {
        let code = try RepoSource.lines(of: "Sources/Modules/Autopilot/Engine/RuleRunner.swift")
            .map(RepoSource.code).joined(separator: "\n")
        XCTAssertFalse(code.contains("trashItem"), "RuleRunner trashes outside HelmTrash")
        XCTAssertTrue(code.contains("HelmTrash.removeOne"))
    }
}
