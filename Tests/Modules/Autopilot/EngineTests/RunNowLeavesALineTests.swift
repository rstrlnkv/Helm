import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A person pressed Run now and the journal said nothing.
///
/// `swept(command)` went to `sweep(folder)`, whose line is conditional on
/// having acted — right for the hourly sentinel, which must not write 24 lines
/// a day about nothing, and wrong for a command: a manual run that found
/// nothing to do and a manual run that never happened were the same silence.
/// `runNow` is the command's path now — fact, phase and memory reading, always
/// — and the sentinel keeps its condition.
///
/// Both paths are driven over the same folder in the same state, so what
/// separates the outcomes is the trigger and nothing else.
final class RunNowLeavesALineTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("helm-runnow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine(store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                                        backing: InMemoryKeyValueStore()),
                                 home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    /// An enabled folder with a rule nothing matches: readable, swept, and with
    /// nothing at all to act on — the state where the two paths must part.
    private var idleFolder: WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true,
                      rules: [Rule(id: "r", name: "r", enabled: true, match: .all,
                                   conditions: [.fileExtension(["nothing-has-this"])],
                                   action: .trash)],
                      depth: 1)
    }

    private func autopilotLines() -> [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == "autopilot" }
            .map(\.message)
    }

    func testAManualRunWhereNothingHappenedStillLeavesALine() {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()

        let report = engine.runNow(idleFolder)

        // The subject happened: the folder was really swept and really idle.
        XCTAssertEqual(report.folder, .read, "the folder could not be read, so this is "
                       + "measuring the wrong silence")
        XCTAssertEqual(report.acted + report.refused + report.failed, 0,
                       "something acted, so the conditional line would fire anyway "
                       + "and the assertion below proves nothing")
        XCTAssertTrue(autopilotLines().contains { $0.contains("run now") }, """
            the person pressed Run now over an idle folder and the journal says \
            nothing — «went clean» and «never ran» are the same silence
            """)
        XCTAssertFalse(HelmActivity.running.contains { $0.label == "autopilot.runNow" },
                       "the manual run left its phase open")
    }

    func testTheHourlySweepOverTheSameFolderStaysSilent() {
        HelmLog.shared.setEnabled(true)

        // Proven able to speak first, or the silence below is vacuous: the same
        // sentinel path over a folder where a rule acts does write its line.
        let acting = root.appendingPathComponent("take-me.bin")
        FileManager.default.createFile(atPath: acting.path, contents: Data([1]))
        var sorted = idleFolder
        sorted.rules = [Rule(id: "r", name: "r", enabled: true, match: .all,
                             conditions: [.fileExtension(["bin"])],
                             action: .move(to: "Sorted"))]
        _ = engine.sweep(sorted)
        XCTAssertTrue(autopilotLines().contains { $0.hasPrefix("swept ") },
                      "the sentinel path cannot speak at all, so its silence proves nothing")

        HelmLog.shared.clearTail()
        let report = engine.sweep(idleFolder)

        XCTAssertEqual(report.acted + report.refused + report.failed, 0,
                       "something acted, so this is not the idle hour being tested")
        XCTAssertFalse(autopilotLines().contains { $0.hasPrefix("swept ") }, """
            the hourly sentinel wrote a line about a folder where nothing \
            happened — 24 of these a day is the noise the condition kept out
            """)
    }
}
