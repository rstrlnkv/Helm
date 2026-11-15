import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// What `ActiveExtensions.setDisabled` tells the engine's record: the exit status of
/// the first `launchctl` call, cross-checked against `print-disabled` when it is
/// non-zero. A wrong answer here is a label left disabled with no record, or a
/// record that never lets go.
final class ASwitchAnswerIsLaunchdsTests: XCTestCase {
    private func answer(_ status: Int32, disabled: Bool, listed: Set<String>?) -> SwitchAnswer {
        ActiveExtensions.answer(status: status, disabled: disabled, label: "a.b",
                                listed: { listed })
    }

    func testStatusZeroIsAcceptedWithoutAskingTheList() {
        let a = ActiveExtensions.answer(status: 0, disabled: true, label: "a.b",
                                        listed: { XCTFail("list asked"); return nil })
        XCTAssertEqual(a, .accepted)
    }

    func testATimeoutOrALaunchFailureIsUnknownWithoutAskingTheList() {
        for status in [HelmProcess.timedOutStatus, -1] {
            let a = ActiveExtensions.answer(status: status, disabled: true, label: "a.b",
                                            listed: { XCTFail("list asked"); return ["a.b"] })
            XCTAssertEqual(a, .unknown)
        }
    }

    func testANonZeroStatusWithNoListIsUnknown() {
        XCTAssertEqual(answer(1, disabled: true, listed: nil), .unknown)
        XCTAssertEqual(answer(1, disabled: false, listed: nil), .unknown)
    }

    func testANonZeroStatusIsBelievedOnlyWhenTheListAgreesWithTheWish() {
        XCTAssertEqual(answer(1, disabled: true, listed: ["a.b"]), .accepted)
        XCTAssertEqual(answer(1, disabled: true, listed: []), .refused)
        XCTAssertEqual(answer(1, disabled: false, listed: []), .accepted)
        XCTAssertEqual(answer(1, disabled: false, listed: ["a.b"]), .refused)
    }
}
