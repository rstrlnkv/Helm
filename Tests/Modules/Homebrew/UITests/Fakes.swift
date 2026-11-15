import Foundation
import HelmRuntime
@testable import Module_Homebrew_Engine

// The `ProcessRunner` and `PrivilegedRunner` fakes the Homebrew model tests share,
// beside `FakeHomebrewWork`. A fake keeps its port's states only, and every
// construction names the port it stands in for (`runner:`, `privileged:`)
// (Architecture/TestsAndMeasurement.md § Fakes).
// `NoPrivileges` and `IdleRunner` answer with fixed stand-in values (declined, status 0,
// empty output) that no test asserts: no test reads them, so they are inert.

/// The password dialog answered no: nothing ran.
struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

/// Answers every query with status 0 and nothing on standard output, and ends
/// every streamed child at once.
struct IdleRunner: ProcessRunner, @unchecked Sendable {
    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}
