import XCTest
import HelmContract
import HelmUI
import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The console keeps the last of what `brew` said, not all of it.
///
/// Every `opLog` event appends a line and nothing ever trimmed the array. It is
/// cleared in two places — pressing Clear, and starting an install — so on the
/// ordinary path (upgrade, then upgrade again, then search) it only grew, for
/// the life of the app: this view model is cached per host view model and the
/// cache is dropped only when the module is switched off.
///
/// The engine keeps stderr on purpose, because a console should show what the
/// tool says, and ARCHITECTURE.md records a `brew` command passing 64 KB of
/// deprecation warnings without trying. Each line also becomes a view — the
/// page renders `ForEach` over the whole array and scrolls on every count
/// change — so the cost is paid twice.
///
/// 1000 is `LogTail`'s bound, and this is the same problem: a running record
/// somebody reads the end of. Taking it from the front is what a terminal's
/// scrollback does, and the alternative is a number nobody chose.
@MainActor
final class TheConsoleIsBoundedTests: XCTestCase {

    private final class SilentTransport: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private func model() -> (HomebrewViewModel, SilentTransport) {
        let transport = SilentTransport()
        return (HomebrewViewModel(vm: ModuleViewModel(transport: transport)), transport)
    }

    /// Sends `count` lines and returns once the model has stopped taking them.
    ///
    /// Draining until the count is **stable**, not until it reaches a number:
    /// the first version waited for the expected figure, which on an unbounded
    /// console stops exactly at the figure it was checking for and reports the
    /// bound as working. A single `Task.yield()` per line is not enough either
    /// — the model consumes on a task of its own, and that lost 30 lines of
    /// 1500 and one of 20, which reads as a bound nearly right rather than as a
    /// harness dropping events.
    private func log(_ count: Int, into transport: SilentTransport,
                     model: HomebrewViewModel) async {
        for index in 0..<count {
            transport.stream.continuation.yield(
                EngineEvent(name: HomebrewEvent.opLog.rawValue,
                            payload: Data("line \(index)".utf8)))
        }
        var settled = 0
        var last = -1
        while settled < 50 {
            await Task.yield()
            if model.consoleLines.count == last { settled += 1 } else { settled = 0 }
            last = model.consoleLines.count
        }
    }

    func testTheConsoleStopsGrowingAtItsBound() async {
        let (model, transport) = model()

        await log(HomebrewViewModel.consoleLimit + 500, into: transport, model: model)

        XCTAssertEqual(model.consoleLines.count, HomebrewViewModel.consoleLimit,
                       "the console grew without a bound: a long `brew upgrade` keeps every "
                       + "line it ever printed, in memory and as a view, for the life of "
                       + "the app")
    }

    /// And it keeps the **end**, which is the half a person is reading: the
    /// result of the operation, not its opening banner.
    func testItKeepsTheNewestLines() async {
        let (model, transport) = model()

        await log(HomebrewViewModel.consoleLimit + 3, into: transport, model: model)

        XCTAssertEqual(model.consoleLines.last, "line \(HomebrewViewModel.consoleLimit + 2)",
                       "the newest line is not the last one shown")
        XCTAssertEqual(model.consoleLines.first, "line 3",
                       "the trim took from the wrong end")
    }

    /// Below the bound nothing is dropped, or a short operation would come back
    /// missing its first lines for no reason.
    func testAShortOperationKeepsEveryLine() async {
        let (model, transport) = model()

        await log(20, into: transport, model: model)

        XCTAssertEqual(model.consoleLines.count, 20)
        XCTAssertEqual(model.consoleLines.first, "line 0")
    }
}
