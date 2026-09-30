import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The console is drawn at its full width from the first frame it is drawn
/// in.**
///
/// The owner's report: the first time the console appears it is a narrow strip
/// first, and then widens to the whole width of the window. The console
/// arriving is animated on purpose (`ThePageMovesRatherThanCutsTests` reads
/// the list above giving up its height as a curve); what must not be part of
/// that curve is the console's own width, which has nowhere to come from — the
/// pane was already as wide before the first line as after it.
///
/// **So the reading is every pass, not the settled one.** A page that ends at
/// the right width passes any check that reads it at rest, and the defect is
/// only ever on screen for a fraction of a second. The page is mounted with no
/// console, one line arrives on Установленные (or, in the `.running` cases, the
/// running state arrives first and the line after it), and from then on the
/// console's well (the rounded layer `HelmSurface.wellFill` paints) and the console's
/// own `NSScrollView` are read:
///
/// - at every Core Animation commit on the main run loop — a run-loop observer
///   ordered after the commit, so what it reads is what that commit handed to
///   the screen;
/// - after every turn of the run loop, before and after a forced layout of the
///   host, which is the pass the window would run before it displays.
///
/// Each reading carries its time from the line's arrival — in the `.running`
/// cases from the running state's arrival — so a failure says how long the
/// strip stood and through how many passes.
///
/// **The structure, not a figure**: every reading's width is compared with the
/// last one, and the last one with the pane's own width less the console's
/// padding (`HelmSpace.s5` each side) — so a console that never appeared, or
/// appeared and settled narrow, fails as surely as one that grew.
@MainActor
final class TheConsoleArrivesAtItsFullWidthTests: XCTestCase {

    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode(
                    [BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)])
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor: return try JSONEncoder().encode([DoctorIssue]())
            default: return Data()
            }
        }

        func state(_ op: OpState) {
            stream.continuation.yield(EngineEvent(name: HomebrewEvent.opState.rawValue,
                                                  payload: (try? JSONEncoder().encode(op)) ?? Data()))
        }

        func say(_ line: String) {
            stream.continuation.yield(
                EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data(line.utf8)))
        }
    }

    /// One reading of the console, `nil` where that part was not on the page.
    private struct Sample: CustomStringConvertible {
        let time: Double
        let pass: String
        let well: CGRect?
        let scroll: CGRect?

        var description: String {
            func show(_ r: CGRect?) -> String {
                r.map { "x\(Int($0.minX)) w\(String(format: "%.1f", $0.width)) h\(Int($0.height))" } ?? "-"
            }
            return String(format: "%6.1f ms", time * 1000) + " \(pass): well \(show(well)) scroll \(show(scroll))"
        }
    }

    /// Where the readings accumulate: the run-loop observer's block is not
    /// isolated, and a class is what it can capture and write.
    private final class Log {
        var samples: [Sample] = []
    }

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// The panes read: `ThePageMovesRatherThanCutsTests`' default, wide enough
    /// to draw the inspector beside the list, and one meant to sit below
    /// `HomebrewSplit.masterAndInspector` (560), where the list is the whole
    /// pane; what width the split's reader sees inside a 620 pane is not read
    /// here.
    private let widths: [CGFloat] = [984, 620]

    /// How the console is brought onto the page.
    enum Start: String {
        /// `brew`'s first line arrives while nothing was running.
        case line
        /// The operation's `running` state arrives first — what a press on
        /// Upgrade sends before the tool has printed anything — and the
        /// first line after it.
        case running
    }

    func testTheConsoleIsFullWidthFromItsFirstLineInLight() async throws {
        for width in widths { try await arrive(in: .aqua, width: width, start: .line) }
    }

    func testTheConsoleIsFullWidthFromItsFirstLineInDark() async throws {
        for width in widths { try await arrive(in: .darkAqua, width: width, start: .line) }
    }

    func testTheConsoleIsFullWidthFromTheOperationsStartInLight() async throws {
        for width in widths { try await arrive(in: .aqua, width: width, start: .running) }
    }

    func testTheConsoleIsFullWidthFromTheOperationsStartInDark() async throws {
        for width in widths { try await arrive(in: .darkAqua, width: width, start: .running) }
    }

    // MARK: - A console with nothing in it

    /// **A console that is on the page with no line in it is as wide as one
    /// with lines.** `showsConsole` keeps the console up for a failed
    /// operation whatever the console holds — a refusal before anything
    /// launched writes no line, and Clear empties the lines of a failed run
    /// while the failure stands — so an empty console is a resting state and
    /// not only a frame on the way to the first line.
    func testAnEmptyConsoleOnTheFailureIsFullWidthInLight() async throws {
        for width in widths { try await empty(in: .aqua, width: width) }
    }

    func testAnEmptyConsoleOnTheFailureIsFullWidthInDark() async throws {
        for width in widths { try await empty(in: .darkAqua, width: width) }
    }

    private func settledConsole(_ mount: MountedRender, layersBefore: Set<ObjectIdentifier>,
                                scrollsBefore: Set<ObjectIdentifier>) throws -> (well: CGRect?, scroll: CGRect?) {
        let host = mount.host
        let root = try XCTUnwrap(host.layer)
        let well = everyLayer(root).filter {
            !layersBefore.contains(ObjectIdentifier($0)) && $0.cornerRadius > 0.01 && $0.bounds.height > 60
        }.map { $0.convert($0.bounds, to: root) }.max { $0.height < $1.height }
        let scroll = host.everyView(ofType: NSScrollView.self)
            .filter { !scrollsBefore.contains(ObjectIdentifier($0)) }
            .map { $0.convert($0.bounds, to: host) }.max { $0.height < $1.height }
        return (well, scroll)
    }

    private func empty(in appearance: NSAppearance.Name, width: CGFloat) async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = .installed
        hb.clearConsole()
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: appearance)
        renders.append(mount)
        mount.settle(40)
        let root = try XCTUnwrap(mount.host.layer)
        let layersBefore = Set(everyLayer(root).map(ObjectIdentifier.init))
        let scrollsBefore = Set(mount.host.everyView(ofType: NSScrollView.self).map(ObjectIdentifier.init))
        let name = "\(appearance == .aqua ? "Light" : "Dark") \(Int(width)) pt"
        let full = width - 2 * HelmSpace.s5

        // A refusal: the operation failed before it printed anything.
        transport.state(OpState(phase: .failed, label: "upgrade wget", reason: .brewMissing))
        var yields = 0
        while hb.op.phase != .failed && yields < 50_000 { await Task.yield(); yields += 1 }
        XCTAssertEqual(hb.op.phase, .failed, "the failure never reached the model")
        XCTAssertTrue(hb.consoleLines.isEmpty, "precondition: the refusal wrote a line, so the console is not empty")
        mount.settle(40)
        let refused = try settledConsole(mount, layersBefore: layersBefore, scrollsBefore: scrollsBefore)
        print("[console-width] \(name), refused with no line: well \(refused.well.map { "\($0.width)" } ?? "-") scroll \(refused.scroll.map { "\($0.width)" } ?? "-")")
        let refusedScroll = try XCTUnwrap(refused.scroll, "\(name): the refusal drew no console at all")
        XCTAssertGreaterThanOrEqual(refusedScroll.width, full - 2 * HelmSpace.s5, """
            \(name): a refusal with no line keeps the console on the page at \(refusedScroll.width) pt \
            wide in a \(width) pt pane (the well \(refused.well.map { "\($0.width)" } ?? "not drawn") pt), \
            and nothing will arrive to widen it
            """)

        // Clear after a failed run: the lines go, the failure stays.
        transport.say("Error: wget: no bottle available")
        yields = 0
        while hb.consoleLines.isEmpty && yields < 50_000 { await Task.yield(); yields += 1 }
        mount.settle(40)
        let withLine = try settledConsole(mount, layersBefore: layersBefore, scrollsBefore: scrollsBefore)
        let lineScroll = try XCTUnwrap(withLine.scroll, "\(name): the failure's line drew no console")
        XCTAssertGreaterThanOrEqual(lineScroll.width, full - 2 * HelmSpace.s5,
                                    "\(name): the console with a line is \(lineScroll.width) pt, the control is broken")
        hb.clearConsole()
        mount.settle(40)
        let cleared = try settledConsole(mount, layersBefore: layersBefore, scrollsBefore: scrollsBefore)
        print("[console-width] \(name), cleared after failure: well \(cleared.well.map { "\($0.width)" } ?? "-") scroll \(cleared.scroll.map { "\($0.width)" } ?? "-") (with the line: \(lineScroll.width))")
        let clearedScroll = try XCTUnwrap(cleared.scroll, "\(name): Clear took the console off the page, so this case read nothing")
        XCTAssertGreaterThanOrEqual(clearedScroll.width, full - 2 * HelmSpace.s5, """
            \(name): Clear after a failure left the console \(clearedScroll.width) pt wide where it \
            was \(lineScroll.width) pt with its line
            """)
    }

    private func everyLayer(_ root: CALayer) -> [CALayer] {
        [root] + (root.sublayers ?? []).flatMap(everyLayer)
    }

    /// Turns of the run loop, each read twice: as the turn left the page, and
    /// after the layout the window would run before displaying it.
    /// Synchronous because `RunLoop.current` is unavailable from an
    /// asynchronous context, and a yield buys no wall-clock time.
    private func turns(_ count: Int, host: NSView, read: (String) -> Void) {
        for _ in 0..<count {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            read("turn")
            host.layoutSubtreeIfNeeded()
            read("layout")
        }
    }

    private func arrive(in appearance: NSAppearance.Name, width: CGFloat,
                        start how: Start) async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = .installed
        hb.clearConsole()
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: appearance)
        renders.append(mount)
        mount.settle(40)
        let host = mount.host
        let root = try XCTUnwrap(host.layer, "the host has no layer tree to read the well from")

        // **No console, and what was on the page without one.** Anything
        // present now is not the console, so the console is what is new.
        XCTAssertTrue(hb.consoleLines.isEmpty, "precondition: the console had lines before the case")
        let layersBefore = Set(everyLayer(root).map(ObjectIdentifier.init))
        let scrollsBefore = Set(host.everyView(ofType: NSScrollView.self).map(ObjectIdentifier.init))

        let log = Log()
        let start = CACurrentMediaTime()
        func read(_ pass: String) {
            let wells = everyLayer(root).filter {
                // Any rounded corner, not the card's alone: a well narrower
                // than twice `HelmRadius.card` has its corner clamped to half
                // its width, and that narrow well is the defect.
                !layersBefore.contains(ObjectIdentifier($0))
                    && $0.cornerRadius > 0.01 && $0.bounds.height > 60
            }.map { layer -> CGRect in
                let frame = layer.convert(layer.bounds, to: root)
                let top = root.isGeometryFlipped ? frame.minY : host.bounds.height - frame.maxY
                return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
            }
            let scrolls = host.everyView(ofType: NSScrollView.self)
                .filter { !scrollsBefore.contains(ObjectIdentifier($0)) }
                .map { $0.convert($0.bounds, to: host) }
            log.samples.append(Sample(time: CACurrentMediaTime() - start, pass: pass,
                                      well: wells.max { $0.height < $1.height },
                                      scroll: scrolls.max { $0.height < $1.height }))
        }

        // After Core Animation's own commit observer (order 2 000 000), so
        // the reading is of what that commit handed over.
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 2_100_000) { _, _ in
            MainActor.assumeIsolated { read("commit") }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }

        var yields = 0
        if how == .running {
            transport.state(OpState(phase: .running, label: "upgrade wget"))
            while !hb.running && yields < 50_000 {
                await Task.yield()
                yields += 1
            }
            XCTAssertTrue(hb.running, "the running state never reached the model in \(yields) yields")
            read("model")
            turns(30, host: host, read: read)
        }
        let had = hb.consoleLines.count
        transport.say("==> Pouring wget--1.25.0.arm64_tahoe.bottle.tar.gz")
        yields = 0
        while hb.consoleLines.count == had && yields < 50_000 {
            await Task.yield()
            yields += 1
        }
        XCTAssertGreaterThan(hb.consoleLines.count, had, "the line never reached the model in \(yields) yields")
        read("model")
        turns(60, host: host, read: read)

        let drawn = log.samples.filter { $0.well != nil || $0.scroll != nil }
        let trail = drawn.prefix(40).map(\.description).joined(separator: "\n")
        let name = "\(appearance == .aqua ? "Light" : "Dark") \(Int(width)) pt, \(how.rawValue) first"

        // **The subject first**: a console that never arrived has no width to
        // be wrong about, and would otherwise pass every comparison below.
        let finalWell = try XCTUnwrap(drawn.last?.well, """
            \(name): no console well was ever read after the line arrived — \(log.samples.count) \
            passes, none with a new card-cornered layer
            """)
        let finalScroll = try XCTUnwrap(drawn.last?.scroll, """
            \(name): the console's scroll view was never read after the line arrived
            """)
        XCTAssertEqual(finalWell.width, width - 2 * HelmSpace.s5, accuracy: 1, """
            \(name): the console settled \(finalWell.width) pt wide in a \(width) pt pane, which is \
            not the pane less the console's padding
            """)

        let firstWell = try XCTUnwrap(drawn.first(where: { $0.well != nil }))
        let firstScroll = try XCTUnwrap(drawn.first(where: { $0.scroll != nil }))
        let narrowWells = drawn.filter { ($0.well.map { abs($0.width - finalWell.width) > 1 }) ?? false }
        let narrowScrolls = drawn.filter {
            ($0.scroll.map { abs($0.width - finalScroll.width) > 1 }) ?? false
        }
        let untilFinal = drawn.lastIndex { sample in
            let wellOff = sample.well.map { abs($0.width - finalWell.width) > 1 } ?? false
            let scrollOff = sample.scroll.map { abs($0.width - finalScroll.width) > 1 } ?? false
            return wellOff || scrollOff
        }.map { $0 + 1 } ?? 0
        print("""
            [console-width] \(name): well first \(firstWell.well!.width) at \
            \(String(format: "%.1f", firstWell.time * 1000)) ms (\(firstWell.pass)), final \
            \(finalWell.width); scroll first \(firstScroll.scroll!.width), final \
            \(finalScroll.width); \(untilFinal) of \(drawn.count) passes before the final width
            \(trail)
            """)

        XCTAssertTrue(narrowWells.isEmpty, """
            \(name): the console's well was drawn at a width other than its final \
            \(finalWell.width) pt on \(narrowWells.count) of \(drawn.count) passes — first \
            \(firstWell.well!.width) pt at \(String(format: "%.1f", firstWell.time * 1000)) ms; \
            \(untilFinal) passes before it reached the final width:
            \(trail)
            """)
        XCTAssertTrue(narrowScrolls.isEmpty, """
            \(name): the console's scroll view was laid out at a width other than its final \
            \(finalScroll.width) pt on \(narrowScrolls.count) of \(drawn.count) passes — first \
            \(firstScroll.scroll!.width) pt:
            \(trail)
            """)
    }
}
