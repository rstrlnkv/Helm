import XCTest
@testable import HelmRuntime

/// A grant is read back from the probe for its own need and nobody else's.
final class PermissionNeedTests: XCTestCase {
    func testStateReadsBackFromTheProbe() {
        XCTAssertEqual(PermissionNeed.accessibility.state(accessibility: .granted,
                                                          fullDisk: .denied,
                                                          screenRecording: .denied), .granted)
        XCTAssertEqual(PermissionNeed.fullDiskAccess.state(accessibility: .granted,
                                                           fullDisk: .denied,
                                                           screenRecording: .granted), .denied)
    }

    /// The third grant answers for itself and for nobody else: each of the three
    /// is denied alone, and only its own need reads it.
    func testEachGrantAnswersOnlyForItsOwnNeed() {
        for denied in PermissionNeed.allCases {
            let reading = (accessibility: denied == .accessibility ? PermissionState.denied : .granted,
                           fullDisk: denied == .fullDiskAccess ? PermissionState.denied : .granted,
                           screenRecording: denied == .screenRecording ? PermissionState.denied : .granted)
            for need in PermissionNeed.allCases {
                let state = need.state(accessibility: reading.accessibility, fullDisk: reading.fullDisk,
                                       screenRecording: reading.screenRecording)
                XCTAssertEqual(state, need == denied ? .denied : .granted,
                               "\(need) read the answer for \(denied)")
            }
        }
    }
}
