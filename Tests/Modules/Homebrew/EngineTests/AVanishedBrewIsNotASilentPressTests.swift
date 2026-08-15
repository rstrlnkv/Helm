import Foundation
import XCTest
import HelmContract
@testable import Module_Homebrew_Engine

/// brew can vanish between `status()` and the press: the page loads its status
/// once, and nothing stops the person from running Homebrew's own uninstaller
/// in a terminal while Helm's window sits open. Every operation then hits
/// `guard let brew = locator.brewPath() else { return }` —
/// `HomebrewEngine.swift:185/189/193/197` — and *returns*: no `opState`, no
/// console line, no log. The button does nothing, visibly forever; the queries
/// at least warn (`listInstalled` writes "brew is not installed" to the log).
///
/// These tests FAIL against the current engine, deliberately: the press must
/// leave a trace on the transport — a state the page can show or a line the
/// console can print. The assertion is "something was said", not any
/// particular wording, so any honest fix passes.
final class AVanishedBrewIsNotASilentPressTests: XCTestCase {

    private struct GoneLocator: BrewLocator {
        func brewPath() -> String? { nil }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }
    /// Must never be reached: with no brew there is nothing to launch. A call
    /// arriving here is its own failure.
    private final class UnreachableRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _launched: [String] = []
        var launched: [String] { lock.lock(); defer { lock.unlock() }; return _launched }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            lock.lock(); _launched.append(launchPath); lock.unlock()
            return (127, "")
        }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) {
            lock.lock(); _launched.append(launchPath); lock.unlock()
            onExit(127)
        }
    }

    /// Everything the engine put on the transport, read back through the
    /// replay (`LocalTransport` keeps the last event per name): with the
    /// engine's fakes all synchronous, whatever was emitted is already there.
    private func trace(_ transport: LocalTransport) async -> [String] {
        transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
        var names: [String] = []
        for await event in transport.events {
            if event.name == "test.sentinel" { break }
            names.append(event.name)
        }
        return names
    }

    func testAPressWithNoBrewSaysSomethingSomewhere() async {
        let verbs: [(String, (HomebrewEngine) -> Void)] = [
            ("install", { $0.install(name: "wget", isCask: false) }),
            ("uninstall", { $0.uninstall(name: "wget", isCask: true) }),
            ("upgrade", { $0.upgrade(name: "wget") }),
            ("upgradeAll", { $0.upgradeAll() }),
        ]
        for (verb, press) in verbs {
            let runner = UnreachableRunner()
            let transport = LocalTransport()
            let engine = HomebrewEngine(locator: GoneLocator(), runner: runner,
                                        privileged: NoPrivileges(), user: "tester",
                                        transport: transport)

            press(engine)

            // The subject happened: the press went in and nothing launched —
            // an assertion about silence over a press that never occurred
            // would prove nothing.
            XCTAssertEqual(runner.launched, [],
                           "\(verb): a process launched although brew has no path")

            let events = await trace(transport)
            XCTAssertFalse(events.isEmpty, """
                \(verb) with brew gone is a silent return (HomebrewEngine.swift): \
                no opState, no console line, nothing in the log. The person \
                presses the button and nothing whatsoever happens — the page \
                still shows the package list brew answered before it vanished.
                """)
        }
    }
}
