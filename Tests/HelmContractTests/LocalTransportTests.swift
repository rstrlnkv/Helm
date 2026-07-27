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

/// Replay remembers one event per name, not one event.
///
/// Homebrew emits a streaming log line and a level-triggered state into the
/// same transport. With a single slot, a view model built while the log was
/// streaming replayed a log line and never learned the engine was busy — so
/// reopening the page mid-upgrade showed an idle screen with live buttons.
final class LocalTransportReplayTests: XCTestCase {

    func testEveryEventNameIsReplayedNotJustTheLast() async {
        let transport = LocalTransport()
        transport.emit(EngineEvent(name: "opState", payload: Data([1])))
        transport.emit(EngineEvent(name: "opLog", payload: Data([2])))
        transport.emit(EngineEvent(name: "opLog", payload: Data([3])))

        var seen: [String: Data] = [:]
        for await event in transport.events {
            seen[event.name] = event.payload
            if seen.count == 2 { break }
        }
        XCTAssertEqual(seen["opState"], Data([1]), "state was lost behind the log stream")
        XCTAssertEqual(seen["opLog"], Data([3]), "the latest line of each name wins")
    }

    /// The order the engine established, not a dictionary's.
    func testReplayFollowsTheOrderTheNamesFirstAppeared() async {
        let transport = LocalTransport()
        transport.emit(EngineEvent(name: "first", payload: Data()))
        transport.emit(EngineEvent(name: "second", payload: Data()))

        var order: [String] = []
        for await event in transport.events {
            order.append(event.name)
            if order.count == 2 { break }
        }
        XCTAssertEqual(order, ["first", "second"])
    }
}
