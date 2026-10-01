import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **What this page moves and what it cuts.**
///
/// The module animates the Refresh glyph while a query is out, the console's
/// scroll to the bottom, the console arriving and — below `HomebrewSplit`'s
/// threshold — a press on a row that swaps the whole pane for the package.
/// **Switching segment is a cut, and this file used to demand the opposite**: it
/// held a 220 ms crossfade between the two lists (the outgoing one mounted for
/// 26 turns) that drew every package name twice for a few frames, and the owner
/// decided on 2026-09-30 that tabs switch at once everywhere. The two segment
/// cases below were rewritten rather than deleted, and now assert the reverse —
/// the outgoing list is gone on the first turn — because a cut is a claim a
/// later edit can undo as quietly as a curve was once missing. The all-module
/// statement of it is `EveryTabSwitchIsACutTests` (`Tests/HelmAppTests`).
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
/// The layer's `opacity` is **not** the instrument, and that is a measurement
/// too: it read 1.0 on both lists through the whole crossfade, because whatever
/// SwiftUI fades is not the `NSScrollView`'s own layer. A sampler keyed on it
/// would have reported no animation on a page that was animating. The pixels
/// are the other instrument (`FrameRecorder`), and the one that sees a doubled
/// name, which geometry does not.
///
/// **And the assertions turn on Reduce Motion rather than ignoring it**, because
/// `HelmMotion` collapses every token to a 0.01 s cut when the setting is on —
/// which is the whole point of the tokens, and which would make a ramp test fail
/// on the Mac of the one person the setting exists for. With it on, the same
/// instrument is asked for the opposite answer. The cut cases need no such turn:
/// a cut is a cut under either setting.
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
    /// The first line `brew` prints puts a divider and the console's well under
    /// the page, and everything above it gives up the room. The well is ten
    /// lines plus the inset each side (`consoleHeight`, in `HomebrewSettingsPage`);
    /// this test reads the travel off the list it watches and asserts on that,
    /// so no figure is held here to go stale.
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

    // MARK: - The segment switch, and the swap

    /// **Switching segment cuts one list to the other in a frame.**
    ///
    /// The two lists are different views, so nothing about them interpolates —
    /// what an animated transaction bought here was that the outgoing one stayed
    /// mounted while it went, and that is what is read: on the first sampled turn
    /// only the incoming list is mounted.
    func testSwitchingSegmentCutsOneListAwayInAFrame() async throws {
        let (hb, _, mount) = await page(width: 984, segment: .updates)
        XCTAssertEqual(lists(mount).count, 1, "precondition: the Updates list is not mounted alone")
        let before = try XCTUnwrap(mount.pixels())

        let began = Date()
        hb.segment = .installed
        // One turn at a time, counting and photographing on the same turn: the
        // pictures start on the first turn after the switch, where a crossfade
        // is still on screen, and not after forty turns, where it is over.
        var counts: [Int] = []
        var shots: [FrameRecorder.Frame] = []
        for _ in 0..<45 {
            shots += try FrameRecorder.photograph(mount.host, turns: 1, since: began)
            counts.append(lists(mount).count)
        }

        XCTAssertEqual(counts.last, 1, """
            \(counts.last ?? -1) lists are mounted when the switch is over, so the incoming \
            list is not the only one left and this case is not measuring a switch
            """)
        let overlapping = counts.prefix { $0 > 1 }.count
        XCTAssertEqual(overlapping, 0, """
            the outgoing list was still mounted for \(overlapping) turns of the run loop after \
            the segment switch, so the switch is a crossfade. A cut removes it on the first
            """)
        try FrameRecorder.judge(shots, before: before, "light, Homebrew updates → installed")
    }

    /// **And a switch that also changes what is selected is the same cut.**
    /// `selected` is per segment, so leaving the segment a package is selected in
    /// for one where nothing is flips `hb.selected == nil` in the same update —
    /// the value the page's other curve is keyed on. The switch must not ride it.
    func testSwitchingSegmentWithASelectionIsStillACut() async throws {
        let (hb, _, mount) = await page(width: 984, segment: .installed)
        hb.select(Cellar.openssl.id)
        mount.settle(40)
        XCTAssertNotNil(hb.selected, "precondition: nothing is selected in Installed")
        XCTAssertNil(hb.selection[.updates], "precondition: Updates holds a selection of its own")
        let before = try XCTUnwrap(mount.pixels())

        let began = Date()
        hb.segment = .updates
        XCTAssertNil(hb.selected, "the switch did not change what is selected, so this is the plain case")
        let shots = try FrameRecorder.photograph(mount.host, since: began)

        try FrameRecorder.judge(shots, before: before, "light, Homebrew installed (selected) → updates")
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
