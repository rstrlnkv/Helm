import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The three biggest changes this page makes were all cuts.**
///
/// The module animated two things — the Refresh glyph while a query is out, and
/// the console's scroll to the bottom — and both are right. What it did not
/// animate is everything that changes *what is mounted*: switching segment
/// replaced one list with another in a frame, a press on a row below
/// `HomebrewSplit`'s threshold swapped the whole pane for the package in a frame,
/// and the console arriving took 199 pt off everything above it in a frame.
/// `UninstallerSettingsPage` carries `HelmMotion.interface` on exactly these
/// three kinds of change and says it is «the same one the other list screens
/// use»; this page was the list screen that did not.
///
/// **A test that asserts an animation exists passes over one that never runs**,
/// which is the trap this file was written to avoid. So nothing here reads the
/// source. Each case flips the value in a mounted page and samples the **frame
/// geometry of AppKit's own views**, turn of the run loop by turn of the run
/// loop — and the two things an animated transaction does to that geometry are
/// both visible without a single pixel:
///
/// - a **height that is interpolated** ramps through intermediate values instead
///   of arriving at its destination in one frame;
/// - a **subtree being replaced** stays mounted for the length of the animation
///   instead of being removed in the frame the value changed.
///
/// **Both were measured with the token deleted, which is the control.** Recorded
/// 2026-09-16 at a 984 pt pane, 10 ms a turn:
///
/// | change | with the token | with it deleted |
/// |---|---|---|
/// | console arrives (list height) | 552 → 353 over 19 turns, 20 distinct readings | 353 on turn 1, one reading |
/// | segment switch (outgoing list) | mounted for 26 turns | gone on turn 1 |
/// | narrow selection (outgoing list) | mounted for 26 turns | gone on turn 1 |
///
/// The layer's `opacity` is **not** the instrument, and that is a measurement
/// too: it read 1.0 on both lists through the whole crossfade, because whatever
/// SwiftUI fades is not the `NSScrollView`'s own layer. A sampler keyed on it
/// would have reported no animation on a page that was animating.
///
/// **And the assertions turn on Reduce Motion rather than ignoring it**, because
/// `HelmMotion` collapses every token to a 0.01 s cut when the setting is on —
/// which is the whole point of the tokens, and which would make a ramp test fail
/// on the Mac of the one person the setting exists for. With it on, the same
/// instrument is asked for the opposite answer.
@MainActor
final class ThePageMovesRatherThanCutsTests: XCTestCase {

    /// One installed formula and one outdated one, so the Updates segment has an
    /// Upgrade-all bar and both lists have a row.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
        static let stale = OutdatedPackage(name: "wget", installed: "1.24.5", latest: "1.25.0",
                                           isCask: false, pinned: false)

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([Self.openssl])
            case .outdated: return try JSONEncoder().encode([Self.stale])
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// How many turns of the run loop each sample is worth. Sampling is what
    /// costs the time here, so the turn is the resolution: at 10 ms a turn,
    /// `interface`'s 0.22 s is about twenty samples, which is enough to tell a
    /// ramp from a step and few enough that three cases cost a second.
    private static let turn = 0.01

    /// A reading per turn of the run loop, taken after the layout it caused.
    ///
    /// Synchronous on purpose: `RunLoop.current` is unavailable from an
    /// asynchronous context, and a `Task.yield()` buys a turn on the pool and no
    /// wall-clock time at all — so a sampler written with yields measures nothing
    /// about a curve.
    private func samples<T>(_ turns: Int, of mount: MountedRender,
                            reading: () -> T) -> [T] {
        var out: [T] = []
        for _ in 0..<turns {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(Self.turn))
            mount.host.layoutSubtreeIfNeeded()
            out.append(reading())
        }
        return out
    }

    /// Every list mounted right now, by height. `ListCoreScrollView` is the class
    /// AppKit gives a SwiftUI `List`, which is the one view on this page whose
    /// frame says how much room the page has left for it.
    private func lists(_ mount: MountedRender) -> [Int] {
        mount.host.everyView(named: "ListCoreScrollView").map { Int($0.frame.height) }
    }

    private func page(width: CGFloat, segment: HomebrewViewModel.Segment)
        async -> (HomebrewViewModel, Cellar, MountedRender) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.segment = segment
        await hb.refreshOutdated()
        hb.select(nil)
        // Light, named: an unnamed appearance is a reading of whatever hour this
        // Mac is in (`RenderedInk`'s reason).
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        renders.append(mount)
        mount.settle(40)
        return (hb, transport, mount)
    }

    // MARK: - The console arriving

    /// **The one change that is a height rather than a swap, so it can be read as
    /// a curve.**
    ///
    /// The first line `brew` prints puts a divider and a 148 pt well under the
    /// page, and everything above it gives up the room. Measured at 199 pt of
    /// travel, which is the figure the defect was described by.
    func testTheConsoleArrivingRampsInsteadOfSnapping() async throws {
        let (hb, transport, mount) = await page(width: 984, segment: .updates)
        let before = try XCTUnwrap(lists(mount).first)
        XCTAssertTrue(hb.consoleLines.isEmpty, "precondition: the console is already on the page")

        transport.stream.continuation.yield(
            EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data("==> Pouring wget".utf8)))
        // Yields, not turns of the run loop: the model consumes the event on a
        // task of its own and this costs no wall-clock time, so the curve has not
        // started when the sampling below does.
        var yields = 0
        while hb.consoleLines.isEmpty && yields < 5_000 {
            await Task.yield()
            yields += 1
        }
        XCTAssertFalse(hb.consoleLines.isEmpty, "the line never reached the model in \(yields) yields")

        let heights = samples(40, of: mount) { lists(mount).first ?? -1 }
        let after = try XCTUnwrap(heights.last)

        // **The subject before anything about how it got there.** A page where
        // the console did not arrive at all has one reading throughout, which is
        // also what a cut looks like — so the travel is asserted first.
        XCTAssertGreaterThan(before - after, 100, """
            the list went from \(before) pt to \(after) pt, so the console did not take the \
            room this case is about and every reading below is of a page that did not change
            """)

        if HelmMotion.reduceMotion {
            XCTAssertEqual(Set(heights).count, 1, """
                Reduce Motion is on and the page still drew \(Set(heights).count) intermediate \
                heights — `HelmMotion.interface` is meant to collapse to a cut, which is the \
                whole reason the curve is a token
                """)
            return
        }
        XCTAssertGreaterThan(Set(heights).count, 5, """
            the list's height took \(Set(heights).count) distinct values between \(before) pt \
            and \(after) pt, so the console arrived in a frame and shoved \(before - after) pt \
            of page out from under the reader. With the token the same sampler reads twenty; \
            with it deleted, one
            """)
        let first = try XCTUnwrap(heights.first)
        XCTAssertEqual(first, before, accuracy: 20, """
            the first sampled height is \(first) where the page was at \(before) — the curve had \
            already finished before the sampling began, so its shape is not what was measured
            """)
    }

    // MARK: - The two swaps

    /// **Switching segment must not cut one list to another.**
    ///
    /// The two lists are different views, so nothing about them interpolates —
    /// what an animated transaction buys here is that the outgoing one stays
    /// mounted while it goes, and that is what is read.
    func testSwitchingSegmentDoesNotCutOneListAwayInAFrame() async {
        let (hb, _, mount) = await page(width: 984, segment: .updates)
        XCTAssertEqual(lists(mount).count, 1, "precondition: the Updates list is not mounted alone")

        hb.segment = .installed
        let counts = samples(40, of: mount) { lists(mount).count }

        XCTAssertEqual(counts.last, 1, """
            \(counts.last ?? -1) lists are still mounted when the animation is over, so the \
            outgoing one was never removed — which is a leak with a scrollbar rather than a \
            transition
            """)
        let overlapping = counts.prefix { $0 > 1 }.count
        if HelmMotion.reduceMotion {
            XCTAssertEqual(overlapping, 0,
                           "Reduce Motion is on and the outgoing list still lingered "
                           + "\(overlapping) turns")
            return
        }
        XCTAssertGreaterThan(overlapping, 5, """
            the outgoing list was gone after \(overlapping) turns of the run loop, so the \
            segment switch is a cut. With the token the same sampler reads 26 turns; with it \
            deleted, zero
            """)
    }

    /// **And neither must a press on a row at a width with no room for two
    /// columns**, where the list is not narrowed but *replaced* by the package.
    func testSelectingARowBelowTheThresholdDoesNotCutTheListAway() async {
        let width = threshold - 1
        let (hb, _, mount) = await page(width: width, segment: .installed)
        XCTAssertEqual(lists(mount).count, 1,
                       "precondition: no list is mounted at \(width) pt with nothing selected")
        XCTAssertFalse(HomebrewSplit(availableWidth: width).showsInspector,
                       "precondition: \(width) pt draws the inspector, so nothing is replaced here")

        hb.select(Cellar.openssl.id)
        let counts = samples(60, of: mount) { lists(mount).count }

        XCTAssertEqual(counts.last, 0, """
            the list is still mounted after the package replaced it, so this case is not \
            measuring a swap at all
            """)
        let surviving = counts.prefix { $0 > 0 }.count
        if HelmMotion.reduceMotion {
            XCTAssertEqual(surviving, 0,
                           "Reduce Motion is on and the list still lingered \(surviving) turns")
            return
        }
        XCTAssertGreaterThan(surviving, 5, """
            the list was gone after \(surviving) turns of the run loop, so the pane swaps in a \
            frame. With the token the same sampler reads 26 turns; with it deleted, zero
            """)
    }

    /// The narrowest width `HomebrewSplit` answers `true` for, asked of the type
    /// rather than read off its private constant, the way the inspector's own
    /// column test asks it and for the same reason.
    private var threshold: CGFloat {
        for width in stride(from: CGFloat(200), through: 1400, by: 1)
        where HomebrewSplit(availableWidth: width).showsInspector { return width }
        return 0
    }
}
