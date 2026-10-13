import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The sidebar's fold is driven by the timestamps of its link and by nothing else: a row ticks the link by
/// hand and reads the width at the timestamp it gave.** The rig builds a `SettingsShellViewController` over a
/// scratch store, never shown, with a `HandTickedFoldLink` in the view's `foldLink`. No row sleeps, waits, spins a run loop or sets a timeout:
/// what is asserted is the width at a timestamp, so a row passes or fails the same on a slow machine.
///
/// The table every row is cut from, 200 to 56 over `HelmMotion.sidebarFoldDuration` (0.26 s), accuracy 0.01:
/// the flip writes nothing; the first tick, at any finite timestamp, writes nothing; 0.065 s after it the width
/// is 89.511, 0.13 s after it 63.765, 0.195 s after it 57.280; a tick at or past the end writes 56 exactly, once,
/// and the fold's claim (`foldTarget`) and the link end with it. After every step the link runs exactly while
/// `foldTarget` is set, and after every tick and layout the card starts at the width.
///
/// A tick "exactly at the end" is sure to land only when the first tick was at 0: `1000.26 - 1000.0` is below 0.26 in
/// floating point. A row with a large first timestamp ticks surely past the end, and a row with 0 ticks at it.
@MainActor
final class TheFoldIsDrivenByTheLinksOwnClockTests: XCTestCase {

    private typealias Fold = ShellContentView.Fold

    /// What the shell was told, and whether Reduce Motion is on, both read by closures the shell holds.
    private final class Probe {
        var heard: [Fold] = []
        var reduce = false
    }

    /// Counts the key-value notifications of `sidebarWidth`, one per write.
    private final class Count: @unchecked Sendable {
        var n = 0
    }

    @MainActor private struct Rig {
        let c: SettingsShellViewController
        let link: HandTickedFoldLink
        let probe: Probe
        let writes: Count
        let observation: NSKeyValueObservation
        var shell: ShellContentView { c.shell }
    }

    private let rail = ShellGeometry.railWidth
    private let open = ShellGeometry.defaultSidebarWidth
    private let length = HelmMotion.sidebarFoldDuration

    /// The first timestamps of the rows that run the table: 0, where the end tick may be exact, and a large one.
    private let firstTimestamps: [CFTimeInterval] = [0, 123_456.789]

    /// The curve's progress at a quarter, a half and three quarters of the length, as `HelmMotion.interfaceCurve` has it.
    private let progress: [Double] = [0.767284, 0.946079, 0.991108]

    // MARK: - rigging

    private func controller(_ probe: Probe, store: NamespacedStore, link: HandTickedFoldLink?) -> SettingsShellViewController {
        let c = SettingsShellViewController(model: SettingsModel(host: ModuleHost.shared),
                                            toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27),
                                            bar: ShellPageBarView(), store: store)
        c.shell.reducesMotion = { [probe] in probe.reduce }
        if let link { c.shell.foldLink = link }
        c.shell.onFold = { [probe] in probe.heard.append($0) }
        c.loadViewIfNeeded()
        c.shell.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        c.shell.layoutSubtreeIfNeeded()
        return c
    }

    private func rig(collapsed: Bool = false) -> Rig {
        let store = AppSettings.store.over(InMemoryKeyValueStore())
        if collapsed { store.set(true, for: "sidebarCollapsed") }
        let probe = Probe()
        let link = HandTickedFoldLink()
        let c = controller(probe, store: store, link: link)
        let writes = Count()
        let observation = c.shell.observe(\.sidebarWidth, options: [.new]) { _, _ in writes.n += 1 }
        return Rig(c: c, link: link, probe: probe, writes: writes, observation: observation)
    }

    /// What every step must hold: the width, `foldTarget`, whether the link runs, the invariant between the last
    /// two, the card at the width after a layout, and (when given) the number of starts and of writes since `since`.
    /// Total failure prints: "<what>: the width was <w>, not <expected>" / "<what>: the fold target was <t>, not
    /// <expected>" / "<what>: the link <runs | does not run>" / "<what>: the link runs <b> while the fold target is
    /// <t>" / "<what>: the card starts at <x> at width <w>" / "<what>: <n> starts, not <expected>" / "<what>: <n>
    /// writes of the width, not <expected>".
    private func check(_ r: Rig, _ what: String, width: CGFloat, accuracy: CGFloat = 0, target: CGFloat?, running: Bool,
                       starts: Int? = nil, writes: Int? = nil, since: Int = 0,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.shell.sidebarWidth, width, accuracy: accuracy,
                       "\(what): the width was \(r.shell.sidebarWidth), not \(width)", file: file, line: line)
        XCTAssertEqual(r.shell.foldTarget, target,
                       "\(what): the fold target was \(String(describing: r.shell.foldTarget)), not \(String(describing: target))",
                       file: file, line: line)
        XCTAssertEqual(r.link.isRunning, running, "\(what): the link \(r.link.isRunning ? "runs" : "does not run")",
                       file: file, line: line)
        XCTAssertEqual(r.link.isRunning, r.shell.foldTarget != nil,
                       "\(what): the link runs \(r.link.isRunning) while the fold target is \(String(describing: r.shell.foldTarget))",
                       file: file, line: line)
        if let starts {
            XCTAssertEqual(r.link.starts, starts, "\(what): \(r.link.starts) starts, not \(starts)", file: file, line: line)
        }
        if let writes {
            XCTAssertEqual(r.writes.n - since, writes,
                           "\(what): \(r.writes.n - since) writes of the width, not \(writes)", file: file, line: line)
        }
        r.shell.layoutSubtreeIfNeeded()
        XCTAssertEqual(r.shell.card.frame.minX, r.shell.sidebarWidth, accuracy: 0.000_001,
                       "\(what): the card starts at \(r.shell.card.frame.minX) at width \(r.shell.sidebarWidth)", file: file, line: line)
    }

    /// One tick at `timestamp` and then `check`. Total failure prints, besides `check`'s lines: "<what>: the
    /// instrument is dead: nothing ever started the link".
    private func tick(_ r: Rig, at timestamp: CFTimeInterval, _ what: String, writes: Int? = nil, width: CGFloat,
                      accuracy: CGFloat = 0, target: CGFloat?, running: Bool, starts: Int? = nil,
                      file: StaticString = #filePath, line: UInt = #line) {
        let before = r.writes.n
        let answered = r.link.fire(at: timestamp)
        XCTAssertTrue(answered, "\(what): the instrument is dead: nothing ever started the link", file: file, line: line)
        check(r, what, width: width, accuracy: accuracy, target: target, running: running, starts: starts,
              writes: writes, since: before, file: file, line: line)
    }

    /// A flip that must start a fold from `from` to `to`, then the steps the table opens with.
    private func flipped(from: CGFloat, to: CGFloat, file: StaticString = #filePath, line: UInt = #line) -> Rig {
        let r = rig(collapsed: from == rail)
        check(r, "before the flip", width: from, target: nil, running: false, starts: 0, file: file, line: line)
        r.c.flipSidebar()
        check(r, "the flip", width: from, target: to, running: true, starts: 1, writes: 0, since: 0, file: file, line: line)
        return r
    }

    /// The window of a row: made here, never ordered in.
    private func window() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    // MARK: - the flip and the table

    /// The flip starts the link once on the shell itself, tells `onFold` once with the token's length, writes no
    /// width and sets `foldTarget`. Total failure prints: "the flip was heard as <folds>, not one fold from 200.0 to
    /// 56.0 over the token's length" / "the link was handed <view>, not the shell" / `check`'s lines at "the flip".
    func testAFlipStartsTheLinkOnceAndWritesNothing() {
        let r = flipped(from: open, to: rail)
        XCTAssertEqual(r.probe.heard, [Fold(from: open, to: rail, duration: HelmMotion.sidebarFoldDuration)],
                       "the flip was heard as \(r.probe.heard), not one fold from \(open) to \(rail) over the token's length")
        XCTAssertTrue(r.link.view === r.shell, "the link was handed \(String(describing: r.link.view)), not the shell")
    }

    /// The flip asks for the layout in its own turn, before any call of the link: the buttons keep the rail's
    /// placement from the turn of the flip, and `layout()` is what reads `foldTarget`. Total failure prints: "the
    /// instrument is dead: a layout was already asked for before the flip" / "the instrument is dead: the flip
    /// started <n> links" / "the flip did not ask for a layout".
    func testAFlipAsksForTheLayoutInItsOwnTurn() {
        let r = rig()
        r.shell.layoutSubtreeIfNeeded()
        XCTAssertFalse(r.shell.needsLayout, "the instrument is dead: a layout was already asked for before the flip")
        r.c.flipSidebar()
        XCTAssertEqual(r.link.starts, 1, "the instrument is dead: the flip started \(r.link.starts) links")
        XCTAssertTrue(r.shell.needsLayout, "the flip did not ask for a layout")
    }

    /// The first tick, at any finite timestamp, writes nothing: it only records where the clock stands. Total
    /// failure prints: `check`'s lines at "the first tick at <t>", with "<n> writes of the width, not 0" for a write /
    /// "the first tick at <t> was heard as <folds>".
    func testTheFirstTickWritesNothingAtAnyFiniteTimestamp() {
        for t0 in [0, 7.5, -3, 123_456.789, 10] as [CFTimeInterval] {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", writes: 0, width: open, target: rail, running: true, starts: 1)
            XCTAssertEqual(r.probe.heard.count, 1, "the first tick at \(t0) was heard as \(r.probe.heard)")
        }
    }

    /// 200 to 56 by the table: first tick, a quarter, a half, three quarters, the end. Each travelling tick is
    /// exactly one write, the landing is exactly one write of the target and ends the claim and the link; the fold
    /// is told once through the whole travel. Total failure prints: `check`'s lines at "<quarter> after the first tick
    /// at <t0>" (the width is the table's number: 89.511, 63.765, 57.280) / "the end" / "the fold was told <n> times".
    func testAFoldToTheRailTravelsByTheTable() {
        for t0 in firstTimestamps {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", writes: 0, width: open, target: rail, running: true)
            let table: [(CFTimeInterval, CGFloat)] = [(0.065, 89.511), (0.13, 63.765), (0.195, 57.280)]
            for (offset, width) in table {
                tick(r, at: t0 + offset, "\(offset) s after the first tick at \(t0)", writes: 1, width: width, accuracy: 0.01,
                     target: rail, running: true, starts: 1)
            }
            let end = t0 == 0 ? t0 + length : t0 + length + 0.01
            tick(r, at: end, "the end after the first tick at \(t0)", writes: 1, width: rail, target: nil, running: false, starts: 1)
            XCTAssertEqual(r.probe.heard.count, 1, "the fold was told \(r.probe.heard.count) times through the travel from \(t0)")
        }
    }

    /// 56 to 200: the same arithmetic the other way, the width rising by `56 + 144 * progress`. Total failure
    /// prints: `check`'s lines at "<offset> s after the first tick at <t0>" with the widths 166.489, 192.235, 198.720 /
    /// "the end" / "the unfold was heard as <folds>".
    func testAnUnfoldFromTheRailTravelsByTheTable() {
        for t0 in firstTimestamps {
            let r = flipped(from: rail, to: open)
            tick(r, at: t0, "the first tick at \(t0)", writes: 0, width: rail, target: open, running: true)
            let table: [(CFTimeInterval, CGFloat)] = [(0.065, 166.489), (0.13, 192.235), (0.195, 198.720)]
            for (offset, width) in table {
                tick(r, at: t0 + offset, "\(offset) s after the first tick at \(t0)", writes: 1, width: width, accuracy: 0.01,
                     target: open, running: true, starts: 1)
            }
            let end = t0 == 0 ? t0 + length : t0 + length + 0.01
            tick(r, at: end, "the end after the first tick at \(t0)", writes: 1, width: open, target: nil, running: false, starts: 1)
            XCTAssertEqual(r.probe.heard, [Fold(from: rail, to: open, duration: length)],
                           "the unfold was heard as \(r.probe.heard)")
        }
    }

    /// The table's numbers are the curve's: the progress literals this family uses are the ones
    /// `HelmMotion.interfaceProgress(at:)` answers, so a width the table gives and a width the shell writes cannot
    /// part. Total failure prints: "at <fraction> the curve answered <p>, not <literal>".
    func testTheTablesProgressIsTheCurvesAnswer() {
        for (fraction, literal) in zip([0.25, 0.5, 0.75], progress) {
            let answered = HelmMotion.interfaceProgress(at: fraction)
            XCTAssertEqual(answered, literal, accuracy: 0.000_1, "at \(fraction) the curve answered \(answered), not \(literal)")
        }
    }

    // MARK: - the end

    /// An over-long gap between two ticks lands on the target with ONE write and ends the claim and the link.
    /// Total failure prints: `check`'s lines at "the gap of 10 s after the first tick at <t0>", with "<n> writes
    /// of the width, not 1" for a travel that wrote a middle width first.
    func testAnOverlongGapLandsOnTheTargetWithOneWrite() {
        for t0 in firstTimestamps + [5] {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", writes: 0, width: open, target: rail, running: true)
            tick(r, at: t0 + 10, "the gap of 10 s after the first tick at \(t0)", writes: 1, width: rail, target: nil, running: false, starts: 1)
        }
    }

    /// A landing writes the target itself, not the target as the arithmetic of the curve reaches it: from 200, the
    /// sum `from + (to - from)` is not `to` for some widths (`200 + (56.1 - 200)` is 56.099999999999994), and a
    /// travel that wrote that sum at its end would not be at its target, so it would not end and its link would
    /// run on. Total failure prints: "the instrument is dead: no width in the list is one the sum misses" /
    /// "the fold to <t> did not travel" / `check`'s lines at "the gap after the first tick at <t0> to <t>" with the
    /// width not <t> and the fold target still <t> for a landing that wrote the sum.
    func testALandingOnAWidthTheSumOfTheCurveMissesWritesTheTargetItself() {
        let widths = (1...40).map { rail + CGFloat($0) / 10 + 0.01 }.filter { open + ($0 - open) != $0 }
        XCTAssertFalse(widths.isEmpty, "the instrument is dead: no width in the list is one the sum misses")
        for target in widths.prefix(3) {
            for t0 in firstTimestamps {
                let r = rig()
                XCTAssertTrue(r.shell.fold(to: target, animated: true), "the fold to \(target) did not travel")
                tick(r, at: t0, "the first tick at \(t0) to \(target)", writes: 0, width: open, target: target, running: true)
                tick(r, at: t0 + 10, "the gap after the first tick at \(t0) to \(target)", writes: 1, width: target,
                     target: nil, running: false, starts: 1)
            }
        }
    }

    /// A tick after the end is a tick on its way when the link stopped: it writes nothing, starts nothing, leaves
    /// the width at the target. Total failure prints: "the first tick at <t0>" and "the landing" with
    /// `check`'s lines, and "the tick after the end at <late>: the instrument is dead: nothing ever started the link"
    /// (the link answered false) / `check`'s lines at "the tick after the end at <late>" with "<n> writes of the
    /// width, not 0" / "<n> starts, not 1".
    func testATickAfterTheEndWritesNothingAndStartsNothing() {
        for t0 in firstTimestamps {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(r, at: t0 + 10, "the landing", width: rail, target: nil, running: false)
            for late in [t0 + 10.5, t0 + 0.05, t0] {
                tick(r, at: late, "the tick after the end at \(late)", writes: 0, width: rail, target: nil, running: false, starts: 1)
            }
        }
    }

    // MARK: - timestamps nobody promised

    /// A timestamp below the last one lands on the target (the clock went back), whether it is below the first or
    /// below a later one. Total failure prints: `check`'s lines at "<case>" with the width not 56 for a tick that was
    /// taken as time, "<n> writes of the width, not 1" for a landing that wrote twice.
    func testATimestampBelowTheLastLandsOnTheTarget() {
        for t0 in firstTimestamps {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(r, at: t0 + 0.13, "a half", width: 63.765, accuracy: 0.01, target: rail, running: true)
            tick(r, at: t0 + 0.065, "a timestamp below the last", writes: 1, width: rail, target: nil, running: false, starts: 1)

            let q = flipped(from: open, to: rail)
            tick(q, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(q, at: t0 - 1, "a timestamp below the first", writes: 1, width: rail, target: nil, running: false, starts: 1)
        }
    }

    /// A timestamp equal to the last one is not a step back: the width stands where the clock put it and the
    /// travel goes on. How many times the same value is written is not asserted. Total failure prints: `check`'s
    /// lines at "a timestamp equal to the last" (the width is the one before, the fold target 56, the link running) /
    /// "a timestamp equal to the first".
    func testATimestampEqualToTheLastKeepsTheWidthAndTheTravel() {
        for t0 in firstTimestamps {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(r, at: t0, "a timestamp equal to the first", width: open, accuracy: 0.000_000_1, target: rail, running: true, starts: 1)
            tick(r, at: t0 + 0.13, "a half", width: 63.765, accuracy: 0.01, target: rail, running: true)
            let standing = r.shell.sidebarWidth
            tick(r, at: t0 + 0.13, "a timestamp equal to the last", width: standing, accuracy: 0.000_000_1, target: rail, running: true, starts: 1)
        }
    }

    /// A timestamp that is not finite, as the first tick or mid-way, lands on the target by one write: a travel
    /// that does not know where it is ends at its target. Total failure prints: `check`'s lines at "<name> as the first
    /// tick" / "<name> mid-way" with the width not 56 (a not-a-number written into the sidebar shows as
    /// "the width was nan").
    func testATimestampThatIsNotFiniteLandsOnTheTarget() {
        let notFinite: [(String, CFTimeInterval)] = [("not-a-number", .nan), ("+infinity", .infinity), ("-infinity", -.infinity)]
        for (name, bad) in notFinite {
            let first = flipped(from: open, to: rail)
            tick(first, at: bad, "\(name) as the first tick", writes: 1, width: rail, target: nil, running: false, starts: 1)

            for t0 in firstTimestamps {
                let mid = flipped(from: open, to: rail)
                tick(mid, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
                tick(mid, at: t0 + 0.13, "a half", width: 63.765, accuracy: 0.01, target: rail, running: true)
                tick(mid, at: bad, "\(name) mid-way", writes: 1, width: rail, target: nil, running: false, starts: 1)
            }

            let up = flipped(from: rail, to: open)
            tick(up, at: bad, "\(name) as the first tick of an unfold", writes: 1, width: open, target: nil, running: false, starts: 1)
        }
    }

    // MARK: - what interrupts a travel

    /// A cut in the middle of a travel (a fold from code, a flip under Reduce Motion) ends it where the cut put the
    /// width; the tick that comes late changes nothing. Total failure prints: `check`'s lines at "the cut" /
    /// "the late tick" (the width is the cut's, the fold target nil, the link stopped, no write).
    func testACutMidWayThenALateTickChangesNothing() {
        for t0 in firstTimestamps {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(r, at: t0 + 0.065, "a quarter", width: 89.511, accuracy: 0.01, target: rail, running: true)
            r.shell.fold(to: 120, animated: false)
            check(r, "the cut from code", width: 120, target: nil, running: false, starts: 1)
            tick(r, at: t0 + 0.13, "the late tick after the cut", writes: 0, width: 120, target: nil, running: false, starts: 1)

            let q = flipped(from: open, to: rail)
            tick(q, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(q, at: t0 + 0.065, "a quarter", width: 89.511, accuracy: 0.01, target: rail, running: true)
            q.probe.reduce = true
            q.c.flipSidebar()
            check(q, "the flip under Reduce Motion", width: open, target: nil, running: false, starts: 1)
            tick(q, at: t0 + 0.13, "the late tick after the flip under Reduce Motion", writes: 0, width: open, target: nil, running: false, starts: 1)
        }
    }

    /// The target written by hand in the middle of a travel ends it: the claim goes, the link stops, and a late tick
    /// writes nothing. Total failure prints: `check`'s lines at "the target written by hand" / "the late tick".
    func testTheTargetWrittenByHandMidWayEndsTheTravel() {
        let t0: CFTimeInterval = 4
        let r = flipped(from: open, to: rail)
        tick(r, at: t0, "the first tick", width: open, target: rail, running: true)
        tick(r, at: t0 + 0.065, "a quarter", width: 89.511, accuracy: 0.01, target: rail, running: true)
        r.shell.sidebarWidth = rail
        check(r, "the target written by hand", width: rail, target: nil, running: false, starts: 1)
        tick(r, at: t0 + 0.13, "the late tick", writes: 0, width: rail, target: nil, running: false, starts: 1)
    }

    /// A middle width written by hand stands until the next tick, which writes by the clock, not from the
    /// written width. Total failure prints: `check`'s lines at "the middle width written by hand" (the fold target
    /// 56, the link running) / "the next tick" (the width 63.765; a width of 130 moved on by a fraction would be
    /// read as "the width was ...").
    func testAMiddleWidthWrittenByHandIsFollowedByTheClock() {
        for t0 in firstTimestamps {
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick at \(t0)", width: open, target: rail, running: true)
            tick(r, at: t0 + 0.065, "a quarter", width: 89.511, accuracy: 0.01, target: rail, running: true)
            r.shell.sidebarWidth = 130
            check(r, "the middle width written by hand", width: 130, target: rail, running: true, starts: 1)
            tick(r, at: t0 + 0.13, "the next tick", writes: 1, width: 63.765, accuracy: 0.01, target: rail, running: true, starts: 1)
        }
    }

    /// A width that is not finite handed to `fold(to:animated:)` mid-way is refused whole: the travel goes on, no
    /// second start, nothing more heard. Total failure prints: "<name> was travelled to" / `check`'s lines at "<name>
    /// mid-way" with "<n> starts, not 1" / "<name> was heard as <folds>" / `check`'s lines at "the tick after <name>".
    func testAWidthThatIsNotFiniteHandedToFoldMidWayChangesNothing() {
        let notFinite: [(String, CGFloat)] = [("not-a-number", .nan), ("+infinity", .infinity), ("-infinity", -.infinity)]
        for (name, bad) in notFinite {
            let t0: CFTimeInterval = 2
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick", width: open, target: rail, running: true)
            tick(r, at: t0 + 0.065, "a quarter", width: 89.511, accuracy: 0.01, target: rail, running: true)
            let standing = r.shell.sidebarWidth
            let asked = r.shell.fold(to: bad, animated: true)
            XCTAssertFalse(asked, "\(name) was travelled to")
            XCTAssertEqual(r.probe.heard.count, 1, "\(name) was heard as \(r.probe.heard)")
            check(r, "\(name) mid-way", width: standing, target: rail, running: true, starts: 1)
            tick(r, at: t0 + 0.13, "the tick after \(name)", writes: 1, width: 63.765, accuracy: 0.01, target: rail, running: true, starts: 1)
        }
    }

    /// A second flip in flight folds from the width standing then: the fold is told as such, the link is started
    /// again, ITS first tick writes nothing (whatever the old travel's clock said, before or after its last tick),
    /// and the next tick gives `w + (200 - w) * 0.946079` at half of the length. Total failure prints: "the second
    /// flip was heard as <folds>" / `check`'s lines at "the second flip" / "the first tick of the second flip" (a write
    /// there reads "1 writes of the width, not 0") / "a half of the second flip".
    func testASecondFlipInFlightStartsAgainFromTheWidthStanding() {
        for t1Offset in [0.2, 0.05] as [CFTimeInterval] {
            let t0: CFTimeInterval = 50
            let r = flipped(from: open, to: rail)
            tick(r, at: t0, "the first tick", width: open, target: rail, running: true)
            tick(r, at: t0 + 0.13, "a half", width: 63.765, accuracy: 0.01, target: rail, running: true)
            let standing = r.shell.sidebarWidth

            r.c.flipSidebar()
            XCTAssertEqual(r.probe.heard.count, 2, "the second flip was heard as \(r.probe.heard)")
            if r.probe.heard.count == 2 {
                XCTAssertEqual(r.probe.heard[1], Fold(from: standing, to: open, duration: length),
                               "the second flip was heard as \(r.probe.heard[1])")
            }
            check(r, "the second flip", width: standing, target: open, running: true, starts: 2)
            let t1 = t0 + t1Offset
            tick(r, at: t1, "the first tick of the second flip at \(t1)", writes: 0, width: standing, target: open, running: true, starts: 2)
            let half = standing + (open - standing) * CGFloat(progress[1])
            tick(r, at: t1 + 0.13, "a half of the second flip", writes: 1, width: half, accuracy: 0.01, target: open, running: true, starts: 2)
            tick(r, at: t1 + 10, "the end of the second flip", writes: 1, width: open, target: nil, running: false, starts: 2)
        }
    }

    /// The view moved into another window, and then out of every window, in the middle of a travel: the width goes to
    /// the target, the claim and the link end, a late tick writes nothing. The window is made here and never
    /// ordered in. Total failure prints: "the window is on screen: the fixture is wrong" / "the view did not reach the
    /// window: the fixture is wrong" / "the view stayed in the window: the fixture is wrong" / `check`'s lines at
    /// "moved into a window" / "the late tick after the move into a window" / "the unfold in the window" / "moved out
    /// of every window" / "the late tick after the move out".
    func testAViewMovedToAnotherWindowOrToNoneMidWayLandsOnTheTarget() {
        let w = window()
        defer { w.close() }
        XCTAssertFalse(w.isVisible, "the window is on screen: the fixture is wrong")
        let t0: CFTimeInterval = 9
        let r = flipped(from: open, to: rail)
        tick(r, at: t0, "the first tick", width: open, target: rail, running: true)
        tick(r, at: t0 + 0.065, "a quarter", width: 89.511, accuracy: 0.01, target: rail, running: true)
        w.contentView = r.shell
        XCTAssertNotNil(r.shell.window, "the view did not reach the window: the fixture is wrong")
        check(r, "moved into a window", width: rail, target: nil, running: false, starts: 1)
        tick(r, at: t0 + 0.13, "the late tick after the move into a window", writes: 0, width: rail, target: nil, running: false, starts: 1)

        r.c.flipSidebar()
        check(r, "the unfold in the window", width: rail, target: open, running: true, starts: 2)
        tick(r, at: t0 + 1, "the first tick of the unfold", width: rail, target: open, running: true)
        tick(r, at: t0 + 1.065, "a quarter of the unfold", width: 166.489, accuracy: 0.01, target: open, running: true)
        w.contentView = NSView()
        XCTAssertNil(r.shell.window, "the view stayed in the window: the fixture is wrong")
        check(r, "moved out of every window", width: open, target: nil, running: false, starts: 2)
        tick(r, at: t0 + 1.13, "the late tick after the move out", writes: 0, width: open, target: nil, running: false, starts: 2)
    }

    /// A listener that ends the travel inside its own call of `onFold` (a cut from code, `fold(to:animated: false)`)
    /// leaves no link running: the shell starts the link before it tells `onFold`, so the cut ends the travel and
    /// stops the link it finds running. A link started after the listener would run with no travel to drive, the
    /// invariant `link.isRunning == (foldTarget != nil)` broken for good (no tick ever ends it). Beside it the same listener without the cut leaves the link running with its target, so a
    /// link nobody starts cannot pass. Total failure prints: `check`'s lines at "the flip with a listener that cuts"
    /// ("the link runs", "the link runs true while the fold target is nil") / "the late tick after the listener's
    /// cut" / "the instrument is dead: the listener was not told" / `check`'s lines at "the flip with a listener
    /// that does not cut" (the link not running, the fold target nil).
    func testAListenerThatCutsInsideOnFoldLeavesNoLinkRunning() {
        func listening(_ r: Rig, cuts: Bool) {
            r.shell.onFold = { [probe = r.probe, weak shell = r.shell] fold in
                probe.heard.append(fold)
                if cuts { shell?.fold(to: 120, animated: false) }
            }
        }

        let r = rig()
        listening(r, cuts: true)
        r.c.flipSidebar()
        XCTAssertEqual(r.probe.heard.count, 1, "the instrument is dead: the listener was not told, heard \(r.probe.heard)")
        check(r, "the flip with a listener that cuts", width: 120, target: nil, running: false)
        tick(r, at: 5, "the late tick after the listener's cut", writes: 0, width: 120, target: nil, running: false)

        let q = rig()
        listening(q, cuts: false)
        q.c.flipSidebar()
        XCTAssertEqual(q.probe.heard.count, 1, "the instrument is dead: the listener was not told, heard \(q.probe.heard)")
        check(q, "the flip with a listener that does not cut", width: open, target: rail, running: true, starts: 1, writes: 0)
    }

    // MARK: - what starts no link

    /// A flip under Reduce Motion is a cut and starts no link; the same controller with Reduce Motion off then starts
    /// one for its next flip, so a link nobody calls cannot pass. Total failure prints: `check`'s lines at "the flip
    /// under Reduce Motion" with "<n> starts, not 0" / "the flip under Reduce Motion was heard as <folds>" /
    /// "the flip with motion allowed" (the instrument is dead).
    func testAFlipUnderReduceMotionStartsNoLink() {
        let r = rig()
        r.probe.reduce = true
        r.c.flipSidebar()
        check(r, "the flip under Reduce Motion", width: rail, target: nil, running: false, starts: 0)
        XCTAssertEqual(r.probe.heard, [], "the flip under Reduce Motion was heard as \(r.probe.heard)")
        r.probe.reduce = false
        r.c.flipSidebar()
        check(r, "the flip with motion allowed", width: rail, target: open, running: true, starts: 1)
    }

    /// A fold set from code is a cut and starts no link, beside a flip that does. Total failure prints: `check`'s
    /// lines at "the fold from code" with "<n> starts, not 0" / "the flip after it" (the instrument is dead).
    func testAFoldSetFromCodeStartsNoLink() {
        let r = rig()
        r.c.sidebarCollapsed = true
        check(r, "the fold from code", width: rail, target: nil, running: false, starts: 0)
        r.c.flipSidebar()
        check(r, "the flip after it", width: rail, target: open, running: true, starts: 1)
    }

    /// A flip back to the width already standing is a cut: the link the first flip started is stopped and no
    /// second one starts; a third flip, which has a width to travel, starts one. Total failure prints: `check`'s
    /// lines at "the first flip" / "the flip to the standing width" with "<n> starts, not 1" / "the third flip".
    func testAFlipToTheStandingWidthStartsNoLink() {
        let r = rig()
        r.c.flipSidebar()
        check(r, "the first flip", width: open, target: rail, running: true, starts: 1)
        r.c.flipSidebar()
        check(r, "the flip to the standing width", width: open, target: nil, running: false, starts: 1)
        r.c.flipSidebar()
        check(r, "the third flip", width: open, target: rail, running: true, starts: 2)
    }

    /// A window that opens folded starts no link; its first flip starts one. Total failure prints: `check`'s lines at
    /// "the window opening folded" with "<n> starts, not 0" / "the window opening folded was heard as <folds>" /
    /// "the first flip" (the instrument is dead).
    func testAWindowOpeningFoldedStartsNoLink() {
        let r = rig(collapsed: true)
        check(r, "the window opening folded", width: rail, target: nil, running: false, starts: 0)
        XCTAssertEqual(r.probe.heard, [], "the window opening folded was heard as \(r.probe.heard)")
        r.c.flipSidebar()
        check(r, "the first flip", width: rail, target: open, running: true, starts: 1)
    }

    // MARK: - one write, then layout

    /// A tick is a plain write of the width and nothing else: it asks for a layout and moves no frame itself; the
    /// layout that follows places the card at the width, and the layout is the only writer of the card's frame.
    /// Total failure prints: "the fixture is wrong: a layout left needsLayout true" / "a tick left no layout asked:
    /// needsLayout was false" / "the tick moved the card to <x> before a layout" / "after the layout the card starts
    /// at <x>, the width is <w>" / "the layout left the card at <x>: the tick wrote nothing".
    func testATickAsksForTheLayoutThatPlacesTheCard() {
        let r = flipped(from: open, to: rail)
        tick(r, at: 3, "the first tick", width: open, target: rail, running: true)
        r.shell.layoutSubtreeIfNeeded()
        XCTAssertFalse(r.shell.needsLayout, "the fixture is wrong: a layout left needsLayout true")
        r.link.fire(at: 3.13)
        XCTAssertTrue(r.shell.needsLayout, "a tick left no layout asked: needsLayout was false")
        XCTAssertEqual(r.shell.card.frame.minX, open, accuracy: 0.000_001, "the tick moved the card to \(r.shell.card.frame.minX) before a layout")
        r.shell.layoutSubtreeIfNeeded()
        XCTAssertEqual(r.shell.card.frame.minX, r.shell.sidebarWidth, accuracy: 0.000_001,
                       "after the layout the card starts at \(r.shell.card.frame.minX), the width is \(r.shell.sidebarWidth)")
        XCTAssertLessThan(r.shell.card.frame.minX, open - 1, "the layout left the card at \(r.shell.card.frame.minX): the tick wrote nothing")
    }

    // MARK: - nothing keeps the view

    /// A link that still holds the tick closure does not keep the shell alive: the controller and its shell are
    /// released inside an `autoreleasepool` and the link's `weak var view` is nil. What would keep it alive is a
    /// closure that captures the view strongly, a link given the view strongly, or a view that retains itself
    /// through its own link. A controller that never flipped is released the same way first, so a shell that something
    /// else keeps cannot be blamed on the link. A tick that arrives after the release is taken as nothing. Total
    /// failure prints: "the instrument is dead: a shell that never folded outlived its controller" / "the instrument
    /// is dead: the link was not handed the view" / "the shell outlived its controller: the link or its closure keeps
    /// it" / "the link still holds the view" / "the late tick found no closure: the fixture is wrong".
    func testNothingKeepsTheViewAliveAfterItsControllerIsReleased() {
        weak var neverFolded: ShellContentView?
        autoreleasepool {
            let c = controller(Probe(), store: AppSettings.store.over(InMemoryKeyValueStore()), link: HandTickedFoldLink())
            neverFolded = c.shell
        }
        XCTAssertNil(neverFolded, "the instrument is dead: a shell that never folded outlived its controller")

        let link = HandTickedFoldLink()
        weak var folded: ShellContentView?
        autoreleasepool {
            let c = controller(Probe(), store: AppSettings.store.over(InMemoryKeyValueStore()), link: link)
            c.flipSidebar()
            link.fire(at: 1)
            link.fire(at: 1.1)
            XCTAssertNotNil(link.view, "the instrument is dead: the link was not handed the view")
            folded = c.shell
        }
        XCTAssertNil(folded, "the shell outlived its controller: the link or its closure keeps it")
        XCTAssertNil(link.view, "the link still holds the view")
        XCTAssertTrue(link.fire(at: 1.2), "the late tick found no closure: the fixture is wrong")
    }

    // MARK: - the real link

    /// The real link over a view in a window never ordered in. Never ticked and never waited on: whether it runs is
    /// the wrapper's own answer. Total failure prints: "the real link runs before a start" / "the real link does not
    /// run after a start" / "the real link runs after stop()" / "a second stop() brought the link back" / "stop() before
    /// a start left the real link running" / "the real link does not run after a start again".
    func testTheRealLinkRunsFromStartToStopAndStopTwiceIsSafe() {
        let w = window()
        defer { w.close() }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        w.contentView = view
        let link = DisplayFoldLink()
        XCTAssertFalse(link.isRunning, "the real link runs before a start")
        link.stop()
        XCTAssertFalse(link.isRunning, "stop() before a start left the real link running")
        link.start(on: view) { _ in }
        XCTAssertTrue(link.isRunning, "the real link does not run after a start")
        link.stop()
        XCTAssertFalse(link.isRunning, "the real link runs after stop()")
        link.stop()
        XCTAssertFalse(link.isRunning, "a second stop() brought the link back")
        link.start(on: view) { _ in }
        XCTAssertTrue(link.isRunning, "the real link does not run after a start again")
        link.stop()
    }

    /// A second `start` leaves ONE link running: the first is stopped by the second, and one `stop()` ends
    /// everything. The target of the first is let go. Total failure prints: "the real link does not run after
    /// the second start" / "the first start's target is still held after the second start" / "one stop() left the
    /// real link running" / "the instrument is dead: the link held no target".
    func testASecondStartLeavesOneLinkRunning() {
        let w = window()
        defer { w.close() }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        w.contentView = view
        let link = DisplayFoldLink()
        weak var first: AnyObject?
        autoreleasepool {
            link.start(on: view) { _ in }
            first = link.target
        }
        XCTAssertNotNil(first, "the instrument is dead: the link held no target")
        autoreleasepool { link.start(on: view) { _ in } }
        XCTAssertTrue(link.isRunning, "the real link does not run after the second start")
        XCTAssertNil(first, "the first start's target is still held after the second start")
        autoreleasepool { link.stop() }
        XCTAssertFalse(link.isRunning, "one stop() left the real link running")
    }

    /// The real link's target is gone after `stop()`: the row holds it weakly, and nothing the system's link kept
    /// is kept past the invalidation. This stands on an assumption about the system's link (that it lets go of its
    /// target when it is invalidated). Total failure prints: "the instrument is dead: the link held no target" /
    /// "the target is still held after stop()" / "the wrapper still names a target after stop()".
    func testTheRealLinksTargetIsGoneAfterStop() {
        let w = window()
        defer { w.close() }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        w.contentView = view
        let link = DisplayFoldLink()
        weak var held: AnyObject?
        autoreleasepool {
            link.start(on: view) { _ in }
            held = link.target
        }
        XCTAssertNotNil(held, "the instrument is dead: the link held no target")
        autoreleasepool { link.stop() }
        XCTAssertNil(held, "the target is still held after stop()")
        XCTAssertNil(link.target, "the wrapper still names a target after stop()")
    }

    /// The real link's target is gone after the wrapper itself is released without a `stop()`: its `deinit`
    /// invalidates the link. This stands on the same assumption about the system's link. Total failure prints:
    /// "the instrument is dead: the link held no target" / "the target outlived the wrapper that was released
    /// while running".
    func testTheRealLinksTargetIsGoneAfterTheWrapperIsReleased() {
        let w = window()
        defer { w.close() }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        w.contentView = view
        weak var held: AnyObject?
        autoreleasepool {
            let link = DisplayFoldLink()
            link.start(on: view) { _ in }
            held = link.target
            XCTAssertNotNil(held, "the instrument is dead: the link held no target")
        }
        XCTAssertNil(held, "the target outlived the wrapper that was released while running")
    }

    /// A shell released while its REAL link runs lets the link's target go: the controller, its shell and the window
    /// are released inside an `autoreleasepool` and the row's weak references to the shell and to the link's target
    /// are nil. The shell keeps the `DisplayFoldLink` it was built with, in a window made here and never ordered in;
    /// nothing is ticked and nothing is waited on. The control: while the shell lives and the link runs, the weak
    /// target is not nil. The row is a net over the whole chain and a guard of none of its links: it stays green
    /// with the wrapper's `deinit` emptied and with the closure holding the view strongly. Read from
    /// `viewDidMoveToWindow` and not shown: that the shell's move out of its window is what stops the link first.
    /// The wrapper's `deinit` and the closure's weak hold are held by
    /// `testTheRealLinksTargetIsGoneAfterTheWrapperIsReleased` and
    /// `testNothingKeepsTheViewAliveAfterItsControllerIsReleased`. This stands on an assumption about
    /// the system's link (that it lets go of its target when it is invalidated). Total failure prints: "the instrument is dead: the shell was not built with the real
    /// link" / "the instrument is dead: the real link does not run after the flip" / "the instrument is dead: the
    /// link held no target while the shell lives" / "the shell outlived its controller and its window" / "the
    /// target outlived the shell that was released while its link ran".
    func testAShellReleasedWhileItsRealLinkRunsLetsTheTargetGo() {
        weak var target: AnyObject?
        weak var shell: ShellContentView?
        autoreleasepool {
            let w = window()
            let c = controller(Probe(), store: AppSettings.store.over(InMemoryKeyValueStore()), link: nil)
            c.shell.reducesMotion = { false }
            w.contentView = c.shell
            c.flipSidebar()
            let real = c.shell.foldLink as? DisplayFoldLink
            XCTAssertNotNil(real, "the instrument is dead: the shell was not built with the real link")
            XCTAssertEqual(real?.isRunning, true, "the instrument is dead: the real link does not run after the flip")
            target = real?.target
            shell = c.shell
            XCTAssertNotNil(target, "the instrument is dead: the link held no target while the shell lives")
            w.close()
        }
        XCTAssertNil(shell, "the shell outlived its controller and its window")
        XCTAssertNil(target, "the target outlived the shell that was released while its link ran")
    }
}
