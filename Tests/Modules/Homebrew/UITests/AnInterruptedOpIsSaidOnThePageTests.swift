import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The engine reports an operation Helm quit under (`BrewStatus.interruptedOp`);
/// the page has to *say* it, or the report went nowhere — the Cellar changed
/// with no observer and the person reads a calm page. The word lands in the
/// console, the surface that already narrates operations.
@MainActor
final class AnInterruptedOpIsSaidOnThePageTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }
    private final class QuietRunner: ProcessRunner, @unchecked Sendable {
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            onExit(0)
            return NoProcess()
        }
    }

    /// Explicit languages, never `.current`: the suite runs in whatever this
    /// machine is set to. The label is a brew command and must survive every
    /// translation whole — it is the only thing that says *what* was running.
    func testTheNoticeCarriesTheLabelInEveryLanguage() {
        for language in AppLanguage.allCases {
            let line = HbStr.interruptedAtQuit("upgrade all", language: language)
            XCTAssertTrue(line.contains("upgrade all"),
                          "\(language): the notice lost the operation it names: \(line)")
        }
        // And the table is really a table, not English eight times.
        let english = HbStr.interruptedAtQuit("upgrade all", language: .en)
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(HbStr.interruptedAtQuit("upgrade all", language: language),
                              english, "\(language) fell back to English")
        }
    }

    func testTheFirstStatusAfterAnInterruptedQuitWritesTheConsole() async {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        marker.write("upgrade all")

        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: QuietRunner(),
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport, marker: marker)
        defer { _ = engine }
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        await model.refreshStatus()

        XCTAssertEqual(model.consoleLines.count, 1,
                       "the interrupted operation was reported to nobody")
        XCTAssertTrue(model.consoleLines.first?.contains("upgrade all") ?? false,
                      "the notice does not say which operation it was: "
                      + (model.consoleLines.first ?? "<nothing>"))

        // Once: the marker was consumed, the next status is an ordinary one.
        await model.refreshStatus()
        XCTAssertEqual(model.consoleLines.count, 1, "the notice repeats itself")
    }
}
