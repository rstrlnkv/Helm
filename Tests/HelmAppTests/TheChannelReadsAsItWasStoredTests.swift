import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **Past defect guarded: a stored "dev" read as Beta is a setting lost on the next
/// `setChannel`.** The channel is the bare `updateChannel` key in `UserDefaults.standard`
/// (decision 6, `UpdateService.swift`), and its read moved behind a port: the cast is
/// `object as? String`, so what a property list holds decides, not what Swift put in.
///
/// Held here: what each stored value reads as, and that a write lands under the same
/// bare key, which a deployed copy of Helm reads back.
@MainActor
final class TheChannelReadsAsItWasStoredTests: XCTestCase {

    private func service(over backing: InMemoryKeyValueStore) -> UpdateService {
        UpdateService(notices: FakeAutomationNotice(),
                      store: AppSettings.store.over(InMemoryKeyValueStore()),
                      feed: { _ in throw URLError(.notConnectedToInternet) },
                      channelBacking: backing)
    }

    func testEachStoredValueReadsAsItAlwaysDid() {
        let cases: [(Any?, UpdateCheck.Channel)] = [
            ("stable", .beta), ("beta", .beta), ("dev", .dev),
            ("garbage", .beta), (NSNumber(value: 1), .beta), (nil, .beta),
        ]
        for (stored, expected) in cases {
            let backing = InMemoryKeyValueStore()
            backing.set(stored, forKey: "updateChannel")
            XCTAssertEqual(service(over: backing).channel, expected, "stored \(String(describing: stored))")
        }
    }

    func testTheChoiceIsWrittenUnderTheBareKey() {
        let backing = InMemoryKeyValueStore()
        let s = service(over: backing)

        s.setChannel(.dev)

        XCTAssertEqual(backing.object(forKey: "updateChannel") as? String, "dev")
        XCTAssertEqual(backing.raw.keys.sorted(), ["updateChannel"], "the choice was written under another key too")
        s.setChannel(.beta)
    }
}
