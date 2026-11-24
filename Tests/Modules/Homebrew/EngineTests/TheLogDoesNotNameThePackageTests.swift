import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Homebrew_Engine

/// **The log carries counts and outcomes, and never the name of a package.**
///
/// What somebody has installed describes their machine, and `helm.log` is the file
/// they attach to a bug report (Architecture/DiagnosticsLog.md). This module's
/// lines are about a package by nature — «install wget started», «doctor fix
/// refused» — so each one that carries a name carries `Redact.pkg(name)`, written at
/// the site. Nothing else makes a new site do the same, and a site that forgets
/// reads exactly like one that remembers until somebody opens the file.
///
/// Every line that names a package is driven here: an operation's start, end and
/// failure, the doctor-fix refusal, the warning for an operation left running at
/// quit, and the Cellar walk's unreadable-keg warning. Each is first required to
/// *exist* — an assertion about what a line contains proves nothing when the line
/// was never written.
final class TheLogDoesNotNameThePackageTests: XCTestCase {

    /// Distinctive enough that finding it in a message cannot be a coincidence.
    private let package = "secret-pkg-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        tailTheLog()
    }

    private var lines: [String] {
        loggedLines("homebrew")
    }

    private struct FixedLocator: BrewLocator {
        let path: String
        func brewPath() -> String? { path }
    }

    /// Lists one other package, and ends every child at once with `code`: the
    /// conclude path has run by the time the call returns.
    private func runner(code: Int32 = 0) -> ScriptedRunner {
        ScriptedRunner(streams: .finish(code),
                       answers: [BrewAnswer(["list", "--formula"], 0, "other-formula 1.0.0\n")])
    }

    private func engine(_ runner: ProcessRunner, marker: OpMarker = InMemoryOpMarker())
        -> HomebrewEngine {
        brewEngine(runner, locator: FixedLocator(path: "/opt/homebrew/bin/brew"), marker: marker)
    }

    /// The subject lines: those written about an operation, a refusal or a walk.
    private func assertWrittenWithoutTheName(_ subject: Int, _ what: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let written = lines
        XCTAssertGreaterThanOrEqual(written.count, subject, """
            \(what): the line was not written, so an assertion about what it contains proves \
            nothing: \(written)
            """, file: file, line: line)
        XCTAssertFalse(written.contains { $0.contains(package) }, """
            \(what): the log names a package somebody has installed: \(written). `Redact.pkg` \
            is what every other line of this module writes.
            """, file: file, line: line)
    }

    func testAnOperationsStartAndEndDoNotNameThePackage() {
        engine(runner(code: 0)).install(name: package, isCask: false)
        let done = lines
        XCTAssertTrue(done.contains { $0.hasSuffix("started") } && done.contains { $0.hasSuffix("done") },
                      "the start and the end were not both written: \(done)")
        assertWrittenWithoutTheName(2, "install, exit 0")
    }

    func testAFailedOperationDoesNotNameThePackage() {
        engine(runner(code: 1)).install(name: package, isCask: false)
        XCTAssertTrue(lines.contains { $0.contains("failed, exit 1") },
                      "the failure was not written: \(lines)")
        assertWrittenWithoutTheName(2, "install, exit 1")
    }

    func testTheDoctorFixRefusalDoesNotNameThePackage() {
        engine(runner()).runDoctorFix(["uninstall", package])
        XCTAssertTrue(lines.contains { $0.hasPrefix("doctor fix refused:") },
                      "the refusal was not written: \(lines)")
        assertWrittenWithoutTheName(1, "doctor fix refusal")
    }

    func testTheInterruptedAtQuitWarningDoesNotNameThePackage() {
        let marker = InMemoryOpMarker()
        marker.write("upgrade \(package)")
        XCTAssertEqual(engine(runner(), marker: marker).status().interruptedOp, "upgrade \(package)")
        XCTAssertTrue(lines.contains { $0.contains("was still running when Helm last quit") },
                      "the warning was not written: \(lines)")
        assertWrittenWithoutTheName(1, "interrupted at quit")
    }

    func testTheUnreadableKegWarningDoesNotNameThePackage() throws {
        let prefix = scratchDirectory("brew-log-keg")
        let keg = prefix.appendingPathComponent("Cellar/\(package)/1.0")
        try FileManager.default.createDirectory(at: keg, withIntermediateDirectories: true)
        try Data(count: 50_000).write(to: keg.appendingPathComponent("bin"))
        let closed = prefix.appendingPathComponent("Cellar/\(package)")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: closed.path)
        }
        let weight = CellarWeight(locator: FixedLocator(
            path: prefix.appendingPathComponent("bin/brew").path))

        XCTAssertNil(weight.bytes(ofPackage: package, isCask: false))
        XCTAssertTrue(lines.contains { $0.contains("measured nothing") },
                      "the warning was not written: \(lines)")
        assertWrittenWithoutTheName(1, "unreadable keg")
    }
}
