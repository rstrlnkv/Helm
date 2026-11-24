import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A sealed record this build cannot parse is refused and kept, not read as no
/// rules.
///
/// Guards: owner decision 4. Read as `[]`, it would draw the empty page, and the
/// first folder added would write over it. The seal fits here, so this is not
/// `tampered` and Discard is not offered: the way out is Reset, or a newer Helm.
final class AnUnreadableRuleSetIsRefusedNotEmptiedTests: XCTestCase {

    private var bench: ASealedRecordBench!

    override func setUp() {
        bench = ASealedRecordBench(home: scratchDirectory("home").path)
        bench.plant(#"{"x":1}"#, seq: 2)
    }

    func testTheRecordIsRefusedAsUnreadable() {
        XCTAssertNotNil(bench.backing.raw[bench.macKey], "precondition: the fixture was sealed")
        let helm = bench.engine()
        XCTAssertEqual(helm.folders, [])
        XCTAssertEqual(helm.status.refusal, .unreadable)
    }

    func testASaveIsRefusedAndTheRecordIsLeftAsItWas() {
        let before = bench.stored
        let helm = bench.engine()
        XCTAssertEqual(helm.status.refusal, .unreadable, "precondition: the engine reads it as unreadable")

        helm.folders = [WatchedFolder(id: "fresh", path: "/tmp", enabled: true, rules: [], depth: 1)]

        XCTAssertEqual(bench.stored, before, "payload, seal, number or mark moved")
        XCTAssertEqual(helm.status.refusal, .unreadable)
    }

    func testDiscardIsForTamperingAlone() {
        let before = bench.stored
        let helm = bench.engine()
        XCTAssertEqual(helm.status.refusal, .unreadable, "precondition")

        helm.discardRefusedRules()

        XCTAssertEqual(bench.stored, before, "nothing here deletes a record it cannot read")
    }
}
