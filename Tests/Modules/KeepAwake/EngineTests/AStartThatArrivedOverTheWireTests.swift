import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// `start`, as it actually reaches the engine: a command name and a bag of
/// bytes.
///
/// `TheEngineHasTheLastWordOnASessionsLengthTests` calls `startSession` in
/// Swift, where the argument is an `Int` because the compiler says so. The
/// caller the engine's own doc comment worries about is this one —
///
///     case .start:
///         if let payload = EngineReply.decode(KeepAwakeStart.self, from: cmd) {
///             self.startSession(minutes: payload.minutes)
///         }
///
/// — where the payload is whatever the transport carried. Every value here is
/// something `JSONDecoder` can be handed: a number too large for `Int`, a
/// fractional one from anything that speaks JSON's single number type, the
/// field missing, the field renamed, no bytes at all. The refusal has to be
/// the same in all of them — **nothing starts** — because the direction this
/// module does not fail in is a Mac held awake on the strength of a number
/// nobody wrote.
@MainActor
final class AStartThatArrivedOverTheWireTests: XCTestCase {

    private var store: NamespacedStore!
    private var assertions: FakeAssertions!
    private var clock: FakeClock!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        assertions = FakeAssertions()
        clock = FakeClock()
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: assertions, displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: clock)
    }

    private func send(_ command: KeepAwakeCommand, _ json: String) async -> Data? {
        try? await engine.transport.send(
            EngineCommand(name: command.rawValue, payload: Data(json.utf8)))
    }

    private func assertNothingStarted(_ what: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(engine.isActive, what, file: file, line: line)
        XCTAssertFalse(assertions.held, what, file: file, line: line)
        XCTAssertNil(engine.endDate, what, file: file, line: line)
    }

    // MARK: - The control, first

    /// A payload the page really sends, spelled by the type both sides share.
    /// Everything below is a refusal, and a test of a refusal passes for free
    /// when the thing was never possible in the first place.
    func testAnOrdinaryStartFromTheWireStartsTheSessionItAsksFor() async throws {
        let payload = try JSONEncoder().encode(KeepAwakeStart(minutes: 15))
        _ = try await engine.transport.send(
            EngineCommand(name: KeepAwakeCommand.start.rawValue, payload: payload))

        XCTAssertTrue(engine.isActive)
        XCTAssertEqual(engine.endDate, clock.current.addingTimeInterval(15 * 60))
    }

    /// And zero over the wire is still «until I say stop», not «no session».
    func testZeroFromTheWireIsASessionWithNoDeadline() async {
        _ = await send(.start, #"{"minutes":0}"#)

        XCTAssertTrue(engine.isActive)
        XCTAssertNil(engine.endDate)
        XCTAssertTrue(assertions.held)
    }

    // MARK: - Bytes that are not a start

    func testBytesThatAreNotJSONStartNothing() async {
        _ = await send(.start, "not json at all")

        assertNothingStarted("a payload that is not JSON started a session")
    }

    func testNoBytesAtAllStartNothing() async {
        _ = try? await engine.transport.send(
            EngineCommand(name: KeepAwakeCommand.start.rawValue))

        assertNothingStarted("an empty payload started a session")
    }

    /// JSON, an object, and no `minutes` — a sender one version behind, or one
    /// that renamed the field. `Int` has a zero and zero means «for ever» in
    /// this module, so a decoder that shrugged here would hold the Mac awake
    /// indefinitely on a message that said nothing.
    func testAnObjectWithNoMinutesStartsNothing() async {
        _ = await send(.start, "{}")
        assertNothingStarted("an object with no minutes started a session with no deadline")

        _ = await send(.start, #"{"duration":15}"#)
        assertNothingStarted("a renamed field started a session with no deadline")

        _ = await send(.start, #"{"minutes":null}"#)
        assertNothingStarted("a null started a session with no deadline")
    }

    /// The other shapes JSON can carry: a list, a bare number, a string where
    /// the object should be.
    func testAPayloadOfTheWrongShapeStartsNothing() async {
        for junk in ["[]", "15", #""15""#, #"[{"minutes":15}]"#, "true", "null"] {
            _ = await send(.start, junk)
            assertNothingStarted("\(junk) started a session")
        }
    }

    /// JSON has one number type and it is not `Int`. Anything that produces the
    /// payload from a float — JavaScript, `jq`, a hand-typed message — can send
    /// this, and `15.5` is not a whole number of minutes.
    func testAFractionalNumberOfMinutesStartsNothing() async {
        _ = await send(.start, #"{"minutes":15.5}"#)

        assertNothingStarted("a fractional payload started a session")
    }

    /// Past `Int.max`, which is where the multiply in `startSession` traps —
    /// and this is the one caller with nothing between it and that multiply.
    func testANumberTooLargeForAnIntStartsNothing() async {
        for junk in ["99999999999999999999", "1e400", "-99999999999999999999"] {
            _ = await send(.start, "{\"minutes\":\(junk)}")
            assertNothingStarted("\(junk) minutes started a session")
        }
    }

    /// Inside `Int` and absurd. This one *is* a start — the engine's job is to
    /// bound it, not to refuse it — and what must not happen is the trapping
    /// multiply or a deadline nobody could have asked for.
    func testEveryMinuteThereIsComesBackBoundedRatherThanTrapping() async throws {
        let payload = try JSONEncoder().encode(KeepAwakeStart(minutes: .max))
        _ = try await engine.transport.send(
            EngineCommand(name: KeepAwakeCommand.start.rawValue, payload: payload))

        let end = try XCTUnwrap(engine.endDate, "an absurd request became a session with no end")
        XCTAssertLessThanOrEqual(end.timeIntervalSince(clock.current), TimerPolicy.longestSession)
    }

    /// A negative is not a short session and not an indefinite one.
    func testANegativeNumberOfMinutesStartsNothing() async {
        _ = await send(.start, #"{"minutes":-1}"#)

        assertNothingStarted("a session of minus a minute held the Mac awake")
    }

    // MARK: - The name on the envelope

    /// A name this engine does not know leaves without doing anything and
    /// answers the same empty reply every other arm does. Asserted because the
    /// engine parses the name through `KeepAwakeCommand` precisely so a typo is
    /// refused at the door rather than falling through a `default`.
    func testACommandNameTheEngineDoesNotKnowChangesNothing() async throws {
        let reply = try await engine.transport.send(
            EngineCommand(name: "startt", payload: Data(#"{"minutes":15}"#.utf8)))

        XCTAssertEqual(reply, Data())
        assertNothingStarted("an unknown command name started a session")
    }

    /// The arms that take no payload must not care what one carries. `stop` is
    /// the one that matters: refusing to stop because of the bytes attached
    /// would leave the Mac held awake by a message nobody can correct.
    func testStopAndResumeIgnoreWhateverIsAttachedToThem() async {
        _ = await send(.start, #"{"minutes":0}"#)
        XCTAssertTrue(engine.isActive, "precondition")

        _ = await send(.stop, "not json at all")

        XCTAssertFalse(engine.isActive, "a stop was refused because of a payload it never reads")
        XCTAssertFalse(assertions.held)
    }
}
