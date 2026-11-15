import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// Guards: reads come with every sweep and event, so the "written by a newer
/// Helm" line must be said once per change of count, not once per read.
final class ANewerHelmRuleIsLoggedOncePerChangeTests: XCTestCase {
    private let future = #"{"id":"b","name":"nb","enabled":true,"match":"all","conditions":[{"futureCase":{"_0":1}}],"action":{"trash":{}}}"#

    override func setUp() {
        tailTheLog()
    }

    func testManyReadsSayItOnce() {
        let bench = ASealedRecordBench(home: scratchDirectory("home").path)
        bench.plant("[" + ASealedRecordBench.folder("f", rules: [ASealedRecordBench.rule("a"), future]) + "]", seq: 2)
        let helm = bench.engine()
        for _ in 0..<5 { _ = helm.status; _ = helm.folders }
        let lines = HelmLog.shared.recentEntries().filter {
            $0.category == AutopilotEngine.moduleID && $0.message.contains("written by a newer Helm")
        }
        XCTAssertEqual(helm.status.unapplied.count, 1, "precondition: one rule is unapplied")
        XCTAssertEqual(lines.count, 1, "said once per change, not once per read")
    }
}
