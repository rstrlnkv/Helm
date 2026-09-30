import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
import HelmRuntime
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The install of Homebrew is the one operation the engine names in English
/// words that are not a command (`HomebrewEngine.installBrewLabel`), and the
/// running pill already words it (`HbStr.operationName`). The same label is
/// what the engine writes into the quit marker when it launches the
/// installer's wrapper, and the launch after a quit that interrupted the
/// install says it in the console through `HbStr.interruptedAtQuit` — which,
/// for any other label, quotes it as it came, and for this one says a whole
/// sentence with no label in it.
///
/// The whole road: one engine starts the install with Apple's tools present
/// and the password given, and is dropped while the wrapper runs, which is
/// what a quit leaves behind; a second engine over the same marker answers the
/// page's first status. The line the page writes must not carry the engine's
/// English label into a translated sentence.
@MainActor
final class AnInterruptedInstallIsSaidInThePersonsLanguageTests: XCTestCase {

    private struct NoBrew: BrewLocator { func brewPath() -> String? { nil } }
    private struct GivenPassword: PrivilegedRunner {
        func runAdmin(_ script: String) -> PrivilegedOutcome { .done }
    }
    /// Starts the wrapper and ends it only when told: Helm "quits" under it,
    /// and the test ends it afterwards so the first engine's activity phase is
    /// closed rather than left open in the process.
    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _streams = 0
        private var exits: [@Sendable (Int32) -> Void] = []
        var streams: Int { lock.lock(); defer { lock.unlock() }; return _streams }
        func finish() {
            lock.lock(); let pending = exits; exits = []; lock.unlock()
            for exit in pending { exit(143) }
        }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _streams += 1; exits.append(onExit); lock.unlock()
            return NoProcess()
        }
    }
    private struct ToolsHere: CommandLineToolsPort {
        func isExecutable(_ path: String) -> Bool { true }
        func selectedDeveloperDirectory() -> String? { nil }
        func requestInstall() -> ToolsRequest { .filed }
        func installerIsRunning() -> Bool { false }
    }

    private func engine(_ runner: ProcessRunner, _ marker: OpMarker,
                        _ transport: LocalTransport) -> HomebrewEngine {
        HomebrewEngine(locator: NoBrew(), runner: runner, privileged: GivenPassword(),
                       user: "tester", transport: transport, marker: marker,
                       popularity: NoPopularity(), weight: NoPackageWeight(),
                       tools: ToolsHere(), ticker: NoWaitTicker())
    }

    func testTheConsoleLineAfterAnInterruptedInstallIsNotEnglishInsideATranslation() async {
        for language in AppLanguage.allCases where language != .en {
            await AppLanguage.only(language) {
                let marker = InMemoryOpMarker()
                let runner = HangingRunner()
                // The quit: nothing concludes the operation before the next
                // engine reads the marker.
                let before = engine(runner, marker, LocalTransport())
                defer { runner.finish(); _ = before }
                before.installBrew()
                XCTAssertEqual(runner.streams, 1, "\(language.rawValue): the installer's wrapper was never launched")

                let transport = LocalTransport()
                let after = engine(runner, marker, transport)
                defer { _ = after }
                let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
                await model.refreshStatus()

                guard let line = model.consoleLines.first else {
                    return XCTFail("\(language.rawValue): the interrupted install was reported to nobody")
                }
                XCTAssertFalse(line.contains(HomebrewEngine.installBrewLabel),
                               "\(language.rawValue): the console quotes the engine's English label: \(line)")
            }
        }
    }
}
