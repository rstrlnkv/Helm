import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A rule a newer Helm wrote is not applied and not lost.
///
/// Guards: owner decision 4. One rule this build cannot decode used to fail the
/// whole list, and the next save wrote the list back without it; a Dev, Beta,
/// Dev round trip lost the newer rules. Every case plants a sealed record and
/// asserts first that the engine read it.
final class ARuleFromANewerHelmSurvivesASaveTests: XCTestCase {

    private typealias B = ASealedRecordBench
    private var bench: ASealedRecordBench!
    private let future = #"{"id":"b","name":"nb","enabled":true,"match":"all","conditions":[{"futureCase":{"_0":1}}],"action":{"trash":{}}}"#

    override func setUp() {
        bench = ASealedRecordBench(home: scratchDirectory("home").path)
    }

    private func storedReading() throws -> (folders: [WatchedFolder], unapplied: [UnappliedRule], stubs: [RemovedFolder]) {
        guard case let .read(folders, unapplied, stubs, _) = StoredRuleSet.read(try XCTUnwrap(bench.payload)) else {
            XCTFail("the stored record is not readable"); return ([], [], [])
        }
        return (folders, unapplied, stubs)
    }

    func testTheRulesItCanReadRunAndTheOtherWaitsAtItsIndex() throws {
        bench.plant("[" + B.folder("f", rules: [B.rule("a"), future, B.rule("c")]) + "]", seq: 2)
        XCTAssertNotNil(bench.backing.raw[bench.macKey], "precondition: the fixture was sealed")
        let helm = bench.engine()
        XCTAssertEqual(helm.folders.first?.rules.map(\.id), ["a", "c"], "rules 1 and 3 run, 2 does not")
        XCTAssertNil(helm.status.refusal)
        XCTAssertEqual(helm.status.unapplied.map(\.index), [1])

        var edited = helm.folders
        edited[0].rules[0].name = "renamed"
        helm.folders = edited

        let after = try storedReading()
        XCTAssertEqual(after.folders[0].rules.map(\.name), ["renamed", "nc"])
        XCTAssertEqual(after.unapplied.map(\.index), [1])
        XCTAssertEqual(after.unapplied.map(\.raw), [Data(future.utf8)], "rule 2's bytes changed")
        let fresh = bench.engine()
        XCTAssertEqual(fresh.folders.first?.rules.map(\.name), ["renamed", "nc"])
        XCTAssertNil(fresh.status.refusal, "the engine's own save is not read as a refusal")
        XCTAssertEqual(fresh.status.unapplied.count, 1)
    }

    func testAnUnknownMemberAndARemovedFolderSurviveASaveOfSomethingElse() throws {
        let member = #","futureKey":{"a":[1,2]}"#
        let stub = #"{"id":"gone","path":"/p/gone","rules":[\#(future)],"helmRemovedFolder":true}"#
        let text = "[" + B.folder("f", rules: [B.rule("a", extra: member)]) + "," + B.folder("g", rules: [B.rule("c")])
            + "," + stub + "]"
        bench.plant(text, seq: 2)
        let helm = bench.engine()
        XCTAssertEqual(helm.folders.map(\.id), ["f", "g"], "precondition: the folders were read, the stub is not one")
        XCTAssertEqual(helm.status.unapplied.map(\.folderID), ["gone"], "the stub's rule is carried as unapplied")

        var edited = helm.folders
        edited[1].rules[0].name = "other folder edited"
        helm.folders = edited

        let written = String(decoding: try XCTUnwrap(bench.payload), as: UTF8.self)
        XCTAssertTrue(written.contains(B.rule("a", extra: member)), "the rule with an unknown member changed")
        XCTAssertTrue(written.contains(stub), "the removed folder's rule did not survive")
        XCTAssertNil(bench.engine().status.refusal)
    }
}
