import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **Past defect: an answer for the channel just left landed on the card.** Switching
/// channels drops the other channel's offer and asks again, and the first question was
/// still in flight: when it came back last it wrote its answer over the new one, and its
/// end cleared the spinner of the check still waiting.
@MainActor
final class AnOldChannelsAnswerDoesNotLandTests: XCTestCase {

    /// Holds every caller of `hold()` until `release` is called; each feed closure decides whether to call it.
    private actor Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private(set) var arrived = 0
        nonisolated let count = Count()
        func hold() async { arrived += 1; count.bump(); await withCheckedContinuation { waiting.append($0) } }
        func release() { waiting.forEach { $0.resume() }; waiting = [] }
        func releaseOldest() { if !waiting.isEmpty { waiting.removeFirst().resume() } }
    }

    /// `arrived`, readable from a wait's synchronous condition.
    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        func bump() { lock.lock(); n += 1; lock.unlock() }
    }

    private let devList = """
        [{"tag_name":"v999.0.0-dev.1","html_url":"https://x/v999","body":"","prerelease":true,
          "draft":false,"assets":[]}]
        """

    private func service(feed: @escaping UpdateService.Feed) -> UpdateService {
        UpdateService(notices: FakeAutomationNotice(),
                      store: AppSettings.store.over(InMemoryKeyValueStore()),
                      feed: feed,
                      channelBacking: InMemoryKeyValueStore())
    }

    func testTheBetaAnswerHeldBehindTheSwitchDoesNotEraseTheDevOffer() async {
        let gate = Gate()
        let s = service { [devList] req in
            if req.url?.absoluteString.contains("releases/latest") == true {
                await gate.hold()
                return (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(devList.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        s.checkNow()
        await waitUntil("the Beta question is held") { s.checking }
        await grace()
        s.setChannel(.dev)
        await waitUntil("the Dev offer") { s.available?.version == "v999.0.0-dev.1" }

        await gate.release()
        await grace()

        XCTAssertEqual(s.available?.version, "v999.0.0-dev.1", "the old channel's answer replaced the offer")
    }

    func testAnAutomaticCheckFinishingDuringAManualOneLeavesTheSpinner() async {
        let gate = Gate()
        let s = service { req in
            // The first question (the manual one) is held; the automatic one answers at once.
            if await gate.arrived == 0 { await gate.hold() }
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }

        s.checkNow()
        await waitUntil("the manual check is held") { s.checking }
        await grace()
        s.checkOnLaunch()   // automatic: no stamp, so it asks
        await grace()

        XCTAssertTrue(s.checking, "an automatic check's end stopped a manual check's spinner")

        await gate.release()
        await waitUntil("the manual answer ends the spinner") { !s.checking }
    }

    func testAnOlderManualCheckFinishingLateLeavesTheNewerOnesSpinner() async {
        let gate = Gate()
        let s = service { req in
            await gate.hold()
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }

        s.checkNow()
        await waitUntil("the first manual check is held") { gate.count.value == 1 }
        s.checkNow()
        await waitUntil("the second manual check is held") { gate.count.value == 2 }

        await gate.releaseOldest()
        await grace()
        XCTAssertTrue(s.checking, "the older manual check's end stopped the newer one's spinner")

        await gate.release()
        await waitUntil("the newest answer ends the spinner") { !s.checking }
    }

    func testABetaQuestionThatFailsAfterTheSwitchLeavesNoFailureNote() async {
        struct Down: Error {}
        let gate = Gate()
        let s = service { [devList] req in
            if req.url?.absoluteString.contains("releases/latest") == true {
                await gate.hold()
                throw Down()
            }
            return (Data(devList.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        s.checkNow()
        await waitUntil("the Beta question is held") { gate.count.value == 1 }
        s.setChannel(.dev)
        await waitUntil("the Dev offer") { s.available?.version == "v999.0.0-dev.1" }

        await gate.release()
        await grace()

        XCTAssertNil(s.note, "the channel left failed and its failure landed on the new channel's card")
    }
}
