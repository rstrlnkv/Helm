import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The search a person watches emits its ticks over the transport — the wire
/// the page really listens to.
///
/// The removal's half of this guard is `ARemovalCanBeWatchedAndStoppedTests`;
/// this is the search's, and it was the half nothing held. Every fake in the UI
/// target spells the progress event itself, so the page tests prove the model
/// can *receive* a tick and nothing proved the engine sends one: the emit in
/// `DuplicatesEngine.find` could be deleted with the whole suite green, and the
/// busy screen would sit on «Reading files…» for the minutes a real folder
/// takes. The background scan passes no progress on purpose — nobody is
/// watching — so `find` is the one path this event has.
final class ASearchShowsItsProgressOverTheWireTests: XCTestCase {

    func testASearchDrivenOverTheWireEmitsItsTicks() async throws {
        let root = scratchDirectory("dup-search-progress")
        // Two identical files above the size floor: one candidate group, so the
        // hashing pass has ticks to send as well as the walk. The walk's ticks
        // carry `candidates: 0` and the busy line reads them as the plain
        // «reading»; the hashing's carry the total, and those are the ones the
        // bar is drawn from.
        try write("a.bin", in: root, bytes: 1_200_000, filler: 7)
        try write("b.bin", in: root, bytes: 1_200_000, filler: 7)

        let engine = DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
        let collector = ProgressCollector()
        let events = engine.transport.events
        let listening = Task {
            for await event in events where DuplicatesEvent(rawValue: event.name) == .progress {
                guard let tick = try? JSONDecoder().decode(DuplicateProgress.self,
                                                           from: event.payload)
                else { continue }
                collector.add(tick)
            }
        }

        let reply = try await engine.transport.send(EngineCommand(
            name: DuplicatesCommand.find.rawValue,
            payload: JSONEncoder().encode(DuplicateSearchRequest(path: root.path))))

        // The subject first: the search really ran to a real answer, or the
        // absence below is about a search that never happened.
        let found = try JSONDecoder().decode(DuplicateFindings.self, from: reply)
        XCTAssertEqual(found.groups.count, 1, "the fixture pair was not found at all")

        // The transport replays the last event per name to a late subscriber,
        // so a tick emitted before the loop above was listening still arrives.
        for _ in 0..<20_000 where !collector.ticks.contains(where: { $0.candidates > 0 }) {
            await Task.yield()
        }
        listening.cancel()

        let hashing = collector.ticks.filter { $0.candidates > 0 }
        XCTAssertFalse(hashing.isEmpty, """
            no hashing tick crossed the wire, so the page cannot draw how far the search \
            has got — the emit in `DuplicatesEngine.find` is the search's only progress \
            channel and it reached nothing.
            """)
        // Two candidates, two passes each — the total the sheet's bar divides by.
        XCTAssertEqual(Set(hashing.map(\.candidates)), [4],
                       "the tick's total is not the two passes over the two candidates")
    }
}
