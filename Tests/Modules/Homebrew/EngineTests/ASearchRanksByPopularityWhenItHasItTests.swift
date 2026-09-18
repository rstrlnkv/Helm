import XCTest
@testable import Module_Homebrew_Engine

/// The port's two states, both of which happen every day: a Mac that has the
/// readings and a Mac that has never had them — a first launch, a refused
/// fetch, a machine with no network. The second must search exactly as it
/// searches today.
private final class SearchRunner: ProcessRunner, @unchecked Sendable {
    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        guard args.first == "search" else { return (0, "") }
        return args.contains("--cask") ? (0, "") : (0, "hello-world\nhelm\n")
    }

    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
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

private struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

private struct FixedPopularity: PopularityReading {
    let formulaeCounts: [String: Int]
    func readings() -> PopularityReadings {
        PopularityReadings(formulae: InstallCounts(counts: formulaeCounts), casks: .none)
    }
    func refreshIfDue() async {}
}

final class ASearchRanksByPopularityWhenItHasItTests: XCTestCase {

    private func engine(_ popularity: PopularityReading) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: SearchRunner(),
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker(), popularity: popularity)
    }

    func testTheReadingsReachTheRanking() {
        let hits = engine(FixedPopularity(formulaeCounts: ["helm": 900, "hello-world": 4]))
            .search("hel")
        XCTAssertEqual(hits?.map(\.name), ["helm", "hello-world"])
    }

    /// The control. With no readings the order is brew's, which is alphabetical.
    func testWithoutReadingsTheOrderIsBrewsOwn() {
        let hits = engine(NoPopularity()).search("hel")
        XCTAssertEqual(hits?.map(\.name), ["hello-world", "helm"])
    }
}
