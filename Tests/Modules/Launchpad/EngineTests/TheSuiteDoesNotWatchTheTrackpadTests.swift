import XCTest
import HelmRuntime
@testable import Module_Launchpad_Engine

/// `MultitouchSupportPort` is the one place a watch reaches the trackpads, and a test process must not reach it: this Mac has a
/// trackpad, so an answer of `.watching` would mean the owner's hand was being read by the suite.
final class TheSuiteDoesNotWatchTheTrackpadTests: XCTestCase {
    func testThePortAnswersNoTrackpadAndStartsNothingInATestProcess() {
        XCTAssertTrue(TestProcess.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/System/Library/PrivateFrameworks/MultitouchSupport.framework"),
                      "the subject needs the framework there to refuse it")
        let port = MultitouchSupportPort()
        XCTAssertEqual(port.start(onFrame: { _ in XCTFail("a frame reached the suite") }, onStandDown: {}), .noTrackpad)
        port.stop()
    }

    func testTheEngineBuiltTheWayTheAppBuildsItWatchesNothingEither() {
        let engine = LaunchpadEngine(utilitiesFolderName: { "Utilities" }, pinchEnabled: { true })
        engine.activate()
        XCTAssertEqual(engine.pinchWatch, .noTrackpad)
        engine.deactivate()
    }
}
