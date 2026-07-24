import XCTest
@testable import HelmContract

final class LocalTransportTests: XCTestCase {
    /// A subscriber that attaches AFTER an emit must still receive the last
    /// event (replay). This is the launch race: the engine emits its initial
    /// state during activate(), and the view model subscribes only afterwards.
    func testLateSubscriberReceivesLastEvent() async {
        let t = LocalTransport()
        t.emit(EngineEvent(name: "state", payload: Data([1])))

        var received: EngineEvent?
        for await e in t.events { received = e; break }

        XCTAssertEqual(received?.name, "state")
        XCTAssertEqual(received?.payload, Data([1]))
    }

    /// Replay hands over the LATEST event, not a stale one.
    func testReplayIsLatestEvent() async {
        let t = LocalTransport()
        t.emit(EngineEvent(name: "state", payload: Data([1])))
        t.emit(EngineEvent(name: "state", payload: Data([2])))

        var received: EngineEvent?
        for await e in t.events { received = e; break }

        XCTAssertEqual(received?.payload, Data([2]))
    }

    /// A live subscriber still receives events emitted after it attaches.
    func testLiveSubscriberReceivesSubsequentEmit() async {
        let t = LocalTransport()
        let events = t.events
        t.emit(EngineEvent(name: "state", payload: Data([9])))

        var received: EngineEvent?
        for await e in events { received = e; break }

        XCTAssertEqual(received?.payload, Data([9]))
    }
}
