import XCTest
@testable import HelmRuntime

/// Every file the log can create is a file the log knows how to destroy.
///
/// The one-time purge of the pre-redaction log — written because the file had
/// been carrying VPN names, application names and home paths, and there is a
/// "Copy log" button whose whole purpose is pasting it into a bug report —
/// removed `helm.log` and `helm.log.1`. Rollover has never written
/// `helm.log.1`; it writes `helm.previous.log`. The name was guessed at the
/// moment the purge was written and never checked against the rotation twenty
/// lines below it, so the half of the log that most needed destroying survived
/// it, and survived the Clear button too.
///
/// These are about the names agreeing, because that is what came apart.
final class LogFileNamesTests: XCTestCase {

    func testTheRolloverIsOneOfTheFilesTheLogAccountsFor() {
        XCTAssertTrue(HelmLog.allFileURLs.contains(HelmLog.previousFileURL),
                      "rollover writes a file that nothing clears")
        XCTAssertTrue(HelmLog.allFileURLs.contains(HelmLog.fileURL))
        XCTAssertEqual(HelmLog.allFileURLs.count, 2)
    }

    /// The durable one. A third name invented in a third place is exactly how
    /// this happened, and asserting on the two that are currently right cannot
    /// catch it.
    ///
    /// Counts the file names the log actually builds — the arguments to
    /// `appendingPathComponent` — and requires each to be built in one place.
    /// A queue label that happens to read `helm.log` is not a file and does not
    /// count; the first version of this test flagged it, which is the same
    /// carelessness that produced the defect.
    func testEveryLogFileNameIsBuiltInExactlyOnePlace() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HelmRuntime/HelmLog.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        var counts: [String: Int] = [:]
        for line in text.components(separatedBy: "\n") {
            let body = line.trimmingCharacters(in: .whitespaces)
            guard !body.hasPrefix("//"), !body.hasPrefix("///") else { continue }
            guard let call = body.range(of: "appendingPathComponent(\"") else { continue }
            let rest = body[call.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { continue }
            counts[String(rest[..<close]), default: 0] += 1
        }

        XCTAssertFalse(counts.isEmpty, "the scan stopped finding the file names")
        let repeated = counts.filter { $0.value > 1 }.keys.sorted()
        XCTAssertEqual(repeated, [], "built in more than one place, so two places can disagree")
        XCTAssertEqual(Set(counts.keys), ["Library/Logs/Helm", "helm.log", "helm.previous.log",
                                          ".redaction-reset"],
                       "a name here that no property declares is a name nothing clears")
    }

    /// The purge's latch is the one file the log must **not** clear.
    ///
    /// It records that the one-time purge already happened. A purge that
    /// removed its own latch could run again — which is the failure this whole
    /// file exists around, wearing different clothes: the latch used to live in
    /// `UserDefaults.standard`, i.e. in the *calling process's* domain, so
    /// "once" meant once per process identity and any tool linking HelmRuntime
    /// wiped the user's log the first time it ran. It did exactly that, to a
    /// dev build's triage evidence, before it was caught.
    func testTheResetMarkerIsNotSomethingClearingTheLogDestroys() {
        XCTAssertFalse(HelmLog.allFileURLs.contains(HelmLog.resetMarkerURL),
                       "clearing the log would delete the record that the purge already ran, "
                       + "which lets the purge run a second time and take a real log with it")
        XCTAssertEqual(HelmLog.resetMarkerURL.deletingLastPathComponent(), HelmLog.directory)
    }
}
