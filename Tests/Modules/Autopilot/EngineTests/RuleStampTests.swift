import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The mechanism that stops a rule acting on the same file forever.
///
/// A rule that sorts a file into a subfolder of the folder it watches will see
/// that file again on the next sweep, and again after that. The stamp is an
/// extended attribute, so it travels with the file across a move within a
/// volume — which is exactly the case that matters.
final class RuleStampTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-stamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    func testAFreshFileIsNotStamped() throws {
        let url = try file("a.pdf")
        XCTAssertFalse(RuleStamp.isStamped(url.path, by: "rule-1"))
    }

    func testStampingThenReading() throws {
        let url = try file("a.pdf")
        RuleStamp.stamp(url.path, by: "rule-1")
        XCTAssertTrue(RuleStamp.isStamped(url.path, by: "rule-1"))
    }

    /// Per rule, not per file. Two rules on the same folder each get their own
    /// turn at a file — the second one is not blocked by the first having run.
    func testTheStampIsPerRule() throws {
        let url = try file("a.pdf")
        RuleStamp.stamp(url.path, by: "rule-1")
        XCTAssertFalse(RuleStamp.isStamped(url.path, by: "rule-2"))
    }

    /// The case the stamp exists for: the file moves and stays stamped, so the
    /// rule that moved it does not pick it up again where it landed.
    func testTheStampSurvivesAMove() throws {
        let url = try file("a.pdf")
        RuleStamp.stamp(url.path, by: "rule-1")
        let sub = directory.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let moved = sub.appendingPathComponent("a.pdf")
        try FileManager.default.moveItem(at: url, to: moved)
        XCTAssertTrue(RuleStamp.isStamped(moved.path, by: "rule-1"))
    }

    /// Several rules stamp the same file over time, and none of them may erase
    /// another's mark.
    func testStampsAccumulate() throws {
        let url = try file("a.pdf")
        RuleStamp.stamp(url.path, by: "rule-1")
        RuleStamp.stamp(url.path, by: "rule-2")
        XCTAssertTrue(RuleStamp.isStamped(url.path, by: "rule-1"))
        XCTAssertTrue(RuleStamp.isStamped(url.path, by: "rule-2"))
    }

    /// Stamping is a courtesy, not a permission: a file on a volume that has no
    /// extended attributes, or one Helm cannot write to, must not become a file
    /// the runner refuses to touch — nor one it loops on. The call reports
    /// whether it stuck.
    func testStampingSaysWhetherItWorked() throws {
        let url = try file("a.pdf")
        XCTAssertTrue(RuleStamp.stamp(url.path, by: "rule-1"))
        XCTAssertFalse(RuleStamp.stamp(directory.appendingPathComponent("gone.pdf").path,
                                       by: "rule-1"))
    }

    /// A file nobody can read the attribute of is treated as unstamped, which
    /// is the safe direction only because the runner asks first and acts once.
    func testAMissingFileReadsAsUnstamped() {
        XCTAssertFalse(RuleStamp.isStamped(directory.appendingPathComponent("gone").path,
                                           by: "rule-1"))
    }
}
