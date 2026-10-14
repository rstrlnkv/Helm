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

    // MARK: - Two phases under one label

    /// Two phases can carry one label and overlap. A phase is an open interval,
    /// not a label: begin, begin and one end leave one entry, not none, and it
    /// keeps the first begin's date — the date of the phase still running when
    /// the inner of two nested phases ends.
    /// The pause between the two begins is what lets the dates tell them apart;
    /// the assertion that they differ comes first, so a clock that did not
    /// move cannot make the start-date row pass.
    func testOneOfTwoPhasesUnderOneLabelEndingLeavesTheOtherWithItsOwnStart() throws {
        HelmActivity.begin("disk.scan")
        let first = try XCTUnwrap(HelmActivity.running.first?.started)
        Thread.sleep(forTimeInterval: 0.05)
        let secondBegan = Date()
        XCTAssertGreaterThan(secondBegan.timeIntervalSince(first), 0.04,
                             "the two begins have indistinguishable dates; the row proves nothing")
        HelmActivity.begin("disk.scan")
        HelmActivity.end("disk.scan")

        let left = HelmActivity.running
        print("first begin: \(first.timeIntervalSinceReferenceDate)  "
              + "second begin >= \(secondBegan.timeIntervalSinceReferenceDate)  "
              + "left: \(left.map { "\($0.label)@\($0.started.timeIntervalSinceReferenceDate)" })")
        XCTAssertEqual(left.map(\.label), ["disk.scan"],
                       "begin, begin, end under one label must leave exactly one running")
        XCTAssertEqual(left.first?.started, first,
                       "the one left running began at the first begin, not at the second")
    }

    func testTwoPhasesUnderOneLabelEndingLeaveNone() {
        HelmActivity.begin("disk.scan")
        HelmActivity.begin("disk.scan")
        XCTAssertEqual(HelmActivity.running.map(\.label), ["disk.scan", "disk.scan"],
                       "two open phases under one label are two running")
        HelmActivity.end("disk.scan")
        HelmActivity.end("disk.scan")
        XCTAssertTrue(HelmActivity.running.isEmpty, "both ended, one stayed open")
    }

    /// The same through the scope the engines use: an inner phase of the same
    /// label closing does not close the outer one.
    func testAnInnerPhaseOfTheSameLabelClosingLeavesTheOuterOpen() throws {
        HelmActivity.phase("disk.scan") {
            let outer = HelmActivity.running.first?.started
            Thread.sleep(forTimeInterval: 0.05)
            HelmActivity.phase("disk.scan") {}
            XCTAssertEqual(HelmActivity.running.map(\.label), ["disk.scan"],
                           "the outer phase is still running after the inner one ended")
            XCTAssertEqual(HelmActivity.running.first?.started, outer)
        }
        XCTAssertTrue(HelmActivity.running.isEmpty)
    }

    /// A sweep takes the module's labels whatever follows the module's name
    /// after the dot, leaves a label that merely starts with the same letters,
    /// and an `end` that arrives afterwards from the task that outlived the
    /// module takes nothing of what is left.
    func testASweepTakesTheModulesLabelsAndALateEndTakesNothing() {
        HelmActivity.begin("disk.scan")
        HelmActivity.begin("disk.trash")
        HelmActivity.begin("diskette.scan")
        HelmActivity.begin("duplicates.hash")
        HelmActivity.sweep(module: "disk")
        XCTAssertEqual(Set(HelmActivity.running.map(\.label)), ["diskette.scan", "duplicates.hash"])

        HelmActivity.end("disk.scan")
        HelmActivity.end("disk.trash")
        XCTAssertEqual(HelmActivity.running.count, 2, "a late end of a swept phase took another's")
        HelmActivity.begin("disk.scan")
        XCTAssertEqual(HelmActivity.running.filter { $0.label == "disk.scan" }.count, 1)
    }

    /// A module's sweep drops every open instance of its labels, two of one
    /// label included, and leaves every instance of another module's. The late
    /// `end` of each swept instance takes none of those that are left, and a
    /// phase begun afterwards is one running, not one beside a leftover.
    func testASweepDropsEveryInstanceOfAnOpenLabel() {
        HelmActivity.begin("disk.scan")
        HelmActivity.begin("disk.scan")
        HelmActivity.begin("disk.trash")
        HelmActivity.begin("duplicates.hash")
        HelmActivity.begin("duplicates.hash")
        HelmActivity.sweep(module: "disk")
        XCTAssertEqual(HelmActivity.running.map(\.label), ["duplicates.hash", "duplicates.hash"],
                       "the sweep leaves another module's instances alone, all of them")

        HelmActivity.end("disk.scan")
        HelmActivity.end("disk.scan")
        XCTAssertEqual(HelmActivity.running.count, 2, "a late end of a swept phase took another's")
        HelmActivity.begin("disk.scan")
        XCTAssertEqual(HelmActivity.running.filter { $0.label == "disk.scan" }.count, 1,
                       "a phase begun after the sweep is one running, not one plus a leftover")
    }

    /// A phase that began past the limit is swept with its module like any
    /// other. Were its count left behind, the `end` of a later registered phase
    /// of the same label would be spent on it and that phase would stay listed.
    func testASweepAlsoTakesAPhaseThatRanUnregistered() {
        for index in 0..<HelmActivity.liveLimit { HelmActivity.begin("other.\(index)") }
        HelmActivity.begin("disk.scan")
        XCTAssertFalse(HelmActivity.running.contains { $0.label == "disk.scan" },
                       "the registry was full, so the phase began unregistered")
        HelmActivity.sweep(module: "disk")
        HelmActivity.end("other.0")
        HelmActivity.begin("disk.scan")
        HelmActivity.end("disk.scan")
        XCTAssertFalse(HelmActivity.running.contains { $0.label == "disk.scan" },
                       "the swept phase's count was left, and this end was spent on it")
    }

    /// Bounded means open instances: the registry holds at most `liveLimit`
    /// of them however they are labelled, so one label begun again and again
    /// without an end cannot grow it. The ends that follow close what was
    /// registered and leave nothing behind, those of phases that ran
    /// unregistered included.
    func testTheSameLabelBegunManyTimesStaysWithinTheLimit() {
        let times = HelmActivity.liveLimit * 3
        for _ in 0..<times { HelmActivity.begin("disk.scan") }
        print("begun \(times) times, running instances: \(HelmActivity.running.count), "
              + "limit: \(HelmActivity.liveLimit)")
        XCTAssertLessThanOrEqual(HelmActivity.running.count, HelmActivity.liveLimit)
        for _ in 0..<times { HelmActivity.end("disk.scan") }
        XCTAssertTrue(HelmActivity.running.isEmpty, "every begin was ended, something stayed")
    }

    // MARK: - The line it produces

    /// With two instances of one label open, a line written under that label
    /// still names it once: the describer drops one instance, the newest, not
    /// every instance that shares its name. `HelmLog.memory` passes the label
    /// and nothing that tells the instances apart, so the registry's own listing
    /// is what this reads.
    func testAPhaseIsToldAboutItsTwinUnderTheSameLabel() {
        HelmActivity.begin("disk.scan")
        Thread.sleep(forTimeInterval: 0.05)
        HelmActivity.begin("disk.scan")
        let line = HelmActivity.describe(HelmActivity.running, excluding: "disk.scan")
        print("line written by one of two disk.scan: \"\(line)\"")
        XCTAssertEqual(line.components(separatedBy: "disk.scan").count - 1, 1,
                       "the line names the label once")
    }

    /// The same on a list handed in whole, so the describer's own behaviour is
    /// held apart from the registry's: two entries of one label and a third
    /// of another, asked about by the label that is twice there.
    func testTheDescriberDropsOneInstanceOfTheAskingLabelOnly() {
        let now = Date()
        let running = [HelmActivity.Running(label: "disk.scan", started: now.addingTimeInterval(-30)),
                       HelmActivity.Running(label: "disk.scan", started: now.addingTimeInterval(-5)),
                       HelmActivity.Running(label: "duplicates.hash", started: now.addingTimeInterval(-9))]
        let line = HelmActivity.describe(running, now: now, excluding: "disk.scan")
        print("describer, two disk.scan and one other: \"\(line)\"")
        XCTAssertEqual(line.components(separatedBy: "disk.scan").count - 1, 1,
                       "one disk.scan asked, so one disk.scan is named")
        XCTAssertTrue(line.contains("duplicates.hash 9 s"))
    }

    /// A label that is open once is dropped whole: the one instance is the
    /// phase asking, and it is not told about itself.
    func testAPhaseOpenOnceIsStillNotToldAboutItself() {
        HelmActivity.begin("disk.scan")
        XCTAssertEqual(HelmActivity.describe(HelmActivity.running, excluding: "disk.scan"), "")
    }

    /// Elapsed time is always shown and never timed out. A phase that has been
    /// running for forty minutes is the finding — hiding it would be hiding the
    /// one class of defect this exists to surface.
    func testTheLineNamesEachPhaseAndItsAge() {
        let now = Date()
        let running = [HelmActivity.Running(label: "disk.scan", started: now.addingTimeInterval(-31)),
                       HelmActivity.Running(label: "duplicates.hash", started: now.addingTimeInterval(-4))]
        XCTAssertEqual(HelmActivity.describe(running, now: now), "disk.scan 31 s, duplicates.hash 4 s")
    }

    /// An empty registry is a real answer and has to read as one — and as no
    /// more than one. The registry knows only about named phases; SwiftUI's
    /// render, a VPN refresh, the update check and the trash sweep all run
    /// outside it, so «nothing running» claimed an idle app on the strength of
    /// an empty dictionary. The line says what it knows: no *phases*.
    func testAnEmptyRegistryClaimsOnlyPhases() {
        XCTAssertEqual(HelmActivity.describe([], now: Date()), "no phases running")
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
