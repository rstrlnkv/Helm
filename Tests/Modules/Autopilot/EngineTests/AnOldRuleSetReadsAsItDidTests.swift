import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The record every deployed Mac holds reads through `StoredRuleSet` as it read
/// before it.
///
/// Guards: the module's stored rule format (owner decision 4: a record that
/// worked keeps working). The fixture is the format `JSONEncoder` made of
/// `[WatchedFolder]` before the rules were read one by one: every condition and
/// action case, sealed or not, numbered or not.
final class AnOldRuleSetReadsAsItDidTests: XCTestCase {

    private let deployed = #"[{"enabled":true,"path":"\/Users\/x\/Downloads","id":"f1","rules":[{"conditions":[{"name":{"_0":"contains","_1":"a"}},{"fileExtension":{"_0":["pdf","png"]}},{"size":{"megabytes":4,"_0":"largerThan"}},{"dateAdded":{"_0":"olderThan","days":30}}],"enabled":true,"name":"All","id":"r1","action":{"move":{"to":"\/Users\/x\/Docs"}},"match":"all"},{"conditions":[{"kind":{"_0":"image"}}],"enabled":false,"name":"N1","id":"a1","action":{"sortIntoSubfolder":{"_0":"month"}},"match":"any"},{"conditions":[{"tag":{"_0":"red"}}],"enabled":true,"name":"N2","id":"a2","action":{"trash":{}},"match":"any"}],"depth":1},{"enabled":false,"path":"\/Users\/x\/Pic","id":"f2","rules":[],"depth":8}]"#

    private var bench: ASealedRecordBench!

    override func setUp() {
        bench = ASealedRecordBench(home: scratchDirectory("home").path)
    }

    private func assertRead(_ helm: AutopilotEngine, file: StaticString = #filePath, line: UInt = #line) {
        let folders = helm.folders
        XCTAssertEqual(folders.map(\.id), ["f1", "f2"], file: file, line: line)
        XCTAssertEqual(folders[0].rules.map(\.id), ["r1", "a1", "a2"], file: file, line: line)
        XCTAssertEqual(folders[0].rules[0].conditions.count, 4, file: file, line: line)
        XCTAssertEqual(folders[1].depth, 8, file: file, line: line)
        XCTAssertNil(helm.status.refusal, file: file, line: line)
        XCTAssertTrue(helm.status.unapplied.isEmpty, file: file, line: line)
    }

    func testASealedNumberedRecordReads() throws {
        bench.plant(deployed, seq: 3)
        XCTAssertNotNil(bench.payload, "precondition: the fixture was written")
        XCTAssertNotNil(bench.backing.raw[bench.macKey], "precondition: and sealed")
        assertRead(bench.engine())
    }

    func testARecordSealedBeforeThereWereNumbersReads() throws {
        bench.plant(deployed, seq: 0)
        XCTAssertNotNil(bench.backing.raw[bench.macKey], "precondition: the fixture was sealed")
        assertRead(bench.engine())
    }

    func testAnUnsealedRecordIsAdoptedAndSealed() throws {
        bench.plantUnsealed(deployed)
        XCTAssertNil(bench.backing.raw[bench.macKey], "precondition: no seal yet")
        let helm = bench.engine()
        assertRead(helm)
        XCTAssertNotNil(bench.backing.raw[bench.macKey], "the adopted record was not sealed")
        XCTAssertNil(bench.engine().status.refusal)
    }

    func testSavingAnUnchangedListWritesWhatTheEncoderWrites() throws {
        bench.plant(deployed, seq: 3)
        let helm = bench.engine()
        let list = helm.folders
        XCTAssertEqual(list.count, 2, "precondition: the record was read")

        helm.folders = list

        let written = try XCTUnwrap(bench.payload)
        let today = try JSONEncoder().encode(list.map(\.storable))
        // `JSONEncoder` orders the members of an object differently on every call.
        let x = try JSONSerialization.jsonObject(with: written) as AnyObject
        let y = try JSONSerialization.jsonObject(with: today) as AnyObject
        XCTAssertTrue(x.isEqual(y))
        XCTAssertEqual(try JSONDecoder().decode([WatchedFolder].self, from: written), list.map(\.storable))
    }
}
