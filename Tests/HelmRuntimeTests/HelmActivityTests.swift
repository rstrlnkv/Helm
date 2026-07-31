import XCTest
@testable import HelmRuntime

/// What the app is doing, while it is doing it.
///
/// The memory trail says what a phase *cost* once it is over. It has never said
/// what was running, which is why a spike of 75 → 508 → 1066 → 1338 MB across
/// ninety seconds could sit in the log with no operation named beside it. The
/// same gap made a reader — today, holding this app's own log — take a run of
/// `idle` lines for an idle app, when `listApps` and `appSizes` were running
/// between them.
final class HelmActivityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HelmActivity.reset()
    }

    func testAPhaseIsVisibleWhileItRuns() {
        HelmActivity.phase("disk.scan") {
            XCTAssertEqual(HelmActivity.running.map(\.label), ["disk.scan"])
        }
    }

    func testItIsGoneWhenItEnds() {
        HelmActivity.phase("disk.scan") {}
        XCTAssertTrue(HelmActivity.running.isEmpty)
    }

    /// The two Duplicates phases and a Homebrew command can overlap, and the
    /// point of the line is to name all of them.
    func testTwoPhasesAtOnceAreBothVisible() {
        HelmActivity.phase("duplicates.walk") {
            HelmActivity.phase("homebrew.outdated") {
                XCTAssertEqual(Set(HelmActivity.running.map(\.label)),
                               ["duplicates.walk", "homebrew.outdated"])
            }
        }
        XCTAssertTrue(HelmActivity.running.isEmpty)
    }

    /// A scan that throws is the case a hand-written begin/end pair gets wrong,
    /// and it is the case that leaves a permanent lie behind.
    func testAThrowStillClosesThePhase() {
        struct Stop: Error {}
        XCTAssertThrowsError(try HelmActivity.phase("disk.scan") { throw Stop() })
        XCTAssertTrue(HelmActivity.running.isEmpty, "a phase that threw stayed open forever")
    }

    func testAPhaseReturnsWhatItsBodyReturns() {
        XCTAssertEqual(HelmActivity.phase("x") { 42 }, 42)
    }

    // MARK: - Not becoming the bug it exists to find

    /// A leaked interval must not be able to grow without bound: this is the
    /// mechanism for finding memory bugs, and it must not be one.
    func testTheLiveSetIsBounded() {
        for i in 0..<200 { HelmActivity.begin("phase.\(i)") }
        XCTAssertLessThanOrEqual(HelmActivity.running.count, HelmActivity.liveLimit)
    }

    /// Switching a module off drops its engine while a scan task may still be
    /// running, so `ModuleHost` sweeps what belonged to it. Everything else
    /// stays — another module's work is not this module's business.
    func testAModuleSweepTakesOnlyItsOwn() {
        HelmActivity.begin("disk.scan")
        HelmActivity.begin("duplicates.hash")
        HelmActivity.sweep(module: "disk")
        XCTAssertEqual(HelmActivity.running.map(\.label), ["duplicates.hash"])
    }

    // MARK: - The line it produces

    /// Elapsed time is always shown and never timed out. A phase that has been
    /// running for forty minutes is the finding — hiding it would be hiding the
    /// one class of defect this exists to surface.
    func testTheLineNamesEachPhaseAndItsAge() {
        let now = Date()
        let running = [HelmActivity.Running(label: "disk.scan", started: now.addingTimeInterval(-31)),
                       HelmActivity.Running(label: "duplicates.hash", started: now.addingTimeInterval(-4))]
        XCTAssertEqual(HelmActivity.describe(running, now: now), "disk.scan 31 s, duplicates.hash 4 s")
    }

    /// Nothing running is a real answer and has to read as one — the reader who
    /// mistook a timer sample for an idle app needed exactly this word.
    func testNothingRunningSaysSo() {
        XCTAssertEqual(HelmActivity.describe([], now: Date()), "nothing running")
    }

    /// Long-running phases are the interesting ones, so they lead.
    func testTheOldestPhaseComesFirst() {
        let now = Date()
        let running = [HelmActivity.Running(label: "young", started: now.addingTimeInterval(-2)),
                       HelmActivity.Running(label: "old", started: now.addingTimeInterval(-600))]
        XCTAssertTrue(HelmActivity.describe(running, now: now).hasPrefix("old 600 s"))
    }

    /// The line goes into a log that carries no names. A label is `disk.scan`,
    /// never a path or an app — so the describer must not be handed anything to
    /// redact, and the guard is that nothing here formats anything but labels.
    func testTheLineCarriesOnlyLabelsAndSeconds() {
        let now = Date()
        let line = HelmActivity.describe([.init(label: "uninstaller.appSizes", started: now)], now: now)
        XCTAssertEqual(line, "uninstaller.appSizes 0 s")
    }

    /// A phase's own line says what it cost; what it cannot know is what else
    /// was running. Asked with its own name, the describer answers about the
    /// rest — and says nothing at all when there is no rest, rather than
    /// "nothing running" under a line that names an operation.
    func testAPhaseIsNotToldAboutItself() {
        let now = Date()
        let running = [HelmActivity.Running(label: "uninstaller.appSizes", started: now)]
        XCTAssertEqual(HelmActivity.describe(running, now: now, excluding: "uninstaller.appSizes"), "")
    }

    func testAPhaseIsToldAboutTheOthers() {
        let now = Date()
        let running = [HelmActivity.Running(label: "duplicates.hash", started: now.addingTimeInterval(-9)),
                       HelmActivity.Running(label: "disk.scan", started: now.addingTimeInterval(-2))]
        XCTAssertEqual(HelmActivity.describe(running, now: now, excluding: "disk.scan"),
                       "duplicates.hash 9 s")
    }
}
