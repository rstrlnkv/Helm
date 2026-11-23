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

/// A fake that answers questions only: the two stubs it would otherwise repeat,
/// given once, **and only to a fake that asks for them by conforming**. The port
/// gives `runCapturingDiagnostics` no default on purpose (`Ports.swift`: a silent
/// fallback would make the one query that needs the other stream untestable), so
/// a fake about `doctor` or about streaming conforms to `ProcessRunner` and writes
/// its own. This one answers `runCapturingDiagnostics` with status 0 and nothing
/// (not `doctor`: no fake here needs to answer on the diagnostics stream) and ends
/// every streamed child at once.
protocol QueryOnlyRunner: ProcessRunner {}

extension QueryOnlyRunner {
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

/// Answers every query with status 0 and nothing on standard output, and ends
/// every streamed child at once.
struct IdleRunner: QueryOnlyRunner, @unchecked Sendable {
    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
}
