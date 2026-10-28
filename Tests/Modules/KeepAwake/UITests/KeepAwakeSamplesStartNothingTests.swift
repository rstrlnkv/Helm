import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// `-HelmKeepAwakeSample <name>` shows one of Keep Awake's states for a screenshot.
/// A screenshot of a state is a picture; it must not be a state the Mac is actually in.
///
/// The three defects it guards, in the order a careless seam would commit them:
/// the branch builds the real engine (an assertion, a `pmset`, a sudoers prompt on
/// the developer's own Mac); the sample's seed writes the host's defaults instead
/// of a store of its own (a photographed setting stays set after the photograph);
/// a key left in the persistent domain turns samples on at every launch, because
/// `string(forKey:)` falls through to it.
@MainActor
final class KeepAwakeSamplesStartNothingTests: XCTestCase {

    private func descriptor(_ name: String) -> KeepAwakeDescriptor {
        KeepAwakeDescriptor(argumentDomain: ["HelmKeepAwakeSample": name],
                            argv: ["-HelmKeepAwakeSample", name])
    }

    /// Everything the engine puts on its wire while `body` runs, subscribed before
    /// `activate()` so the stream has no replay to lean on. The subscriber is
    /// cancelled after a grace, so a late second event still counts.
    private func events(of engine: any ModuleEngine,
                        during body: () async -> Void) async -> [EngineEvent] {
        let stream = engine.transport.events
        let collector = Task { () -> [EngineEvent] in
            var seen: [EngineEvent] = []
            for await event in stream { seen.append(event) }
            return seen
        }
        engine.activate()
        await body()
        await grace()
        collector.cancel()
        return await collector.value
    }

    /// Defect: a sample run starts a real engine, or writes the host's store.
    ///
    /// Total failure of the subject (an engine that emits nothing) prints "0 events"
    /// on the count line, so the stream is asserted to carry exactly one `.state`
    /// whose three fields are the *worst* sample's, which no default payload has.
    func testWorstSampleIsOneStateOnTheWireAndTouchesNothing() async throws {
        let backing = InMemoryKeyValueStore()
        let seeded: [String: Any] = [
            "module.keepawake.autoPower": true,
            "module.keepawake.sessionMinutes": 17,
            "module.keepawake.somethingTheSampleMustNotRewrite": "kept",
        ]
        backing.raw = seeded
        let store = NamespacedStore(namespace: KeepAwakeDescriptor.id.rawValue, backing: backing)

        let engine = descriptor("worst").makeEngine(store: store)
        XCTAssertFalse(engine is KeepAwakeEngine,
                       "a sample run built the real engine, which holds assertions and runs pmset")
        XCTAssertTrue(engine.standsIn, "the sample engine does not say it stands in, so the host lets the person switch Keep Awake off and records a real off for a picture")

        let seen = await events(of: engine) {
            for command in KeepAwakeCommand.allCases {
                _ = try? await engine.transport.send(EngineCommand(name: command.rawValue))
            }
        }

        let states = seen.filter { $0.name == KeepAwakeEvent.state.rawValue }
        XCTAssertEqual(seen.count, 1, "the sample put \(seen.count) events on the wire: \(seen.map(\.name))")
        XCTAssertEqual(states.count, 1, "no .state, or more than one, among \(seen.map(\.name))")
        let payload = try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self,
                                               from: try XCTUnwrap(states.first).payload)
        XCTAssertFalse(payload.batteryStopped)
        XCTAssertTrue(payload.clamshellActive, "the worst sample holds the lid shut")
        XCTAssertEqual(payload.holdingApps.count, 4, "the worst sample names four holding apps")

        XCTAssertTrue(NSDictionary(dictionary: backing.raw).isEqual(to: seeded),
                      "the host store changed under a sample run: \(backing.raw)")
    }

    /// Defect: a name nobody declared falls through to the real engine, or to a
    /// half-made sample. Control: the same path with a known name speaks (case
    /// above), so silence here is the refusal and not a dead wire.
    func testAnUnknownSampleNameIsRefusedAndSilent() async {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: KeepAwakeDescriptor.id.rawValue, backing: backing)
        let engine = descriptor("no-such-sample").makeEngine(store: store)
        XCTAssertFalse(engine is KeepAwakeEngine, "an unknown name started the real engine")
        XCTAssertTrue(engine.standsIn, "an unknown sample name yields an engine that does not stand in")
        let seen = await events(of: engine) {}
        XCTAssertTrue(seen.isEmpty, "an unknown sample emitted \(seen.map(\.name))")
        XCTAssertTrue(backing.raw.isEmpty, "an unknown sample wrote \(backing.raw)")
        XCTAssertEqual(KeepAwakeSample.verdict(argumentDomain: ["HelmKeepAwakeSample": "no-such-sample"],
                                               argv: ["-HelmKeepAwakeSample", "no-such-sample"]),
                       .unknown("no-such-sample"))
    }

    /// Defect: a stray persistent `HelmKeepAwakeSample` key (a `defaults write`)
    /// turns samples on at every launch. Only the argument domain, which the
    /// caller passes in, may name a sample. The key is planted in this test
    /// process's own domain and taken out again.
    func testNothingButTheArgumentDomainTurnsASampleOn() {
        XCTAssertEqual(KeepAwakeSample.verdict(argumentDomain: [:], argv: []), .none)

        UserDefaults.standard.set("worst", forKey: KeepAwakeSample.key)
        defer { UserDefaults.standard.removeObject(forKey: KeepAwakeSample.key) }
        XCTAssertEqual(KeepAwakeSample.verdict(argumentDomain: [:], argv: []), .none,
                       "a persistent key turned a sample on")

        XCTAssertEqual(KeepAwakeSample.verdict(argumentDomain: [:], argv: [KeepAwakeSample.argument]),
                       .noName)
        XCTAssertEqual(KeepAwakeSample.verdict(argumentDomain: [KeepAwakeSample.key: "worst"],
                                               argv: [KeepAwakeSample.argument, "worst"]),
                       .show(.worst))
    }
}
