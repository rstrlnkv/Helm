import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Where this page put its edges, against where the rest of the app puts
/// them.**
///
/// Four readings, each of a number that was chosen at the line rather than taken
/// from the house's vocabulary, and each read off the **mounted page** rather
/// than off the source — a padding token can be spelled correctly and land
/// somewhere else, and a radius survives into `CALayer.cornerRadius`, which is
/// the one ladder that can be measured where nobody typed it
/// (`RadiusLadderRatchetTests`' own reason).
///
/// Measured before this landed, 2026-09-16, at the 984 pt pane the app draws and
/// again at the widest single-column pane:
///
/// | reading | before | after |
/// |---|---|---|
/// | Upgrade all, from its column's trailing edge | 8 pt | 20 pt |
/// | the list's leading edge, in its pane | 12 pt | 0 pt |
/// | a row's content, from the pane | 28 pt | 16 pt |
/// | the console well | 160 pt tall | 148 pt, ten lines |
/// | the fix command's well | radius 10 | radius 6 |
///
/// The row figure is the one that says why the list inset mattered: 16 pt is
/// what `.listStyle(.inset)` insets a row by on its own, and it is what
/// Uninstaller, Orphans, Disk, Autopilot and Duplicates all draw. This page was
/// the only one at 28.
@MainActor
final class ThePageTakesItsStepsFromTheHouseTests: XCTestCase {

    /// One installed formula, one outdated one and one `brew doctor` finding that
    /// carries a fix — so both lists and the fix well are reachable from one
    /// fixture.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
        static let stale = OutdatedPackage(name: "wget", installed: "1.24.5", latest: "1.25.0",
                                           isCask: false, pinned: false)
        /// `fix: nil` on the wire, exactly as `DoctorParser` produces it — the
        /// view model is what judges the command, so a fixture that arrived with
        /// a judgement already on it would be testing a state the engine cannot
        /// send.
        static let finding = DoctorIssue(
            severity: .caution,
            title: "Some installed formulae are deprecated",
            body: "You should find replacements for the following formulae:\n  openssl@3")

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([Self.openssl])
            case .outdated: return try JSONEncoder().encode([Self.stale])
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor: return try JSONEncoder().encode([Self.finding])
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

    private func page(width: CGFloat, segment: HomebrewViewModel.Segment)
        async -> (HomebrewViewModel, MountedRender) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = segment
        switch segment {
        case .updates: await hb.refreshOutdated()
        case .health: await hb.refreshDoctor()
        default: break
        }
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        renders.append(mount)
        mount.settle(40)
        return (hb, mount)
    }

    /// The `List` AppKit drew, in the host's own points.
    private func list(_ mount: MountedRender) -> CGRect? {
        mount.host.everyView(named: "ListCoreScrollView")
            .map { $0.convert($0.bounds, to: mount.host) }.first
    }

    /// Every rounded layer under the host, as (radius, frame in host points).
    private func wells(_ mount: MountedRender) -> [(radius: CGFloat, frame: CGRect)] {
        guard let root = mount.host.layer else { return [] }
        var out: [(CGFloat, CGRect)] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01 {
                out.append((layer.cornerRadius, layer.convert(layer.bounds, to: root)))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return out
    }

    // MARK: - The Upgrade-all bar, retired
    //
    // This file held `testTheUpgradeBarEndsWhereTheBarAboveItEnds`: «Обновить
    // всё» sat in a strip of its own under the header, and at `.padding(8)` it
    // missed Refresh one hairline above it by 12 pt. The strip is gone —
    // the button is in the header's own row beside Refresh (`upgradeAll`), one
    // `HStack` and one inset — so two bars that end in different places are no
    // longer something this page can draw, and the case measured a control
    // that no longer exists. What that move put at risk instead is the width
    // the header asks for, and `TheBarAsksForOneWidthInEverySegmentTests` is
    // what holds it.

    // MARK: - The lists

    /// **The lists had an inset of their own and nothing else in the app does.**
    ///
    /// `.listStyle(.inset)` already insets a row; a further
    /// `.padding(.horizontal, HelmSpace.s5)` put this page's rows 12 pt further
    /// in than every other list screen's — which is half of what `helmListRow`
    /// exists to undo.
    func testTheListsAreInsetLikeEveryOtherListInTheApp() async throws {
        for segment in [HomebrewViewModel.Segment.installed, .updates, .health] {
            let (_, mount) = await page(width: 984, segment: segment)
            let list = try XCTUnwrap(list(mount), "no list drew for \(segment)")
            XCTAssertEqual(list.minX, 0, accuracy: 0.5, """
                the \(segment) list starts \(list.minX) pt inside its pane, where \
                `.listStyle(.inset)` is where Uninstaller, Orphans, Disk, Autopilot and \
                Duplicates all stop
                """)

            // And the row inside it, which is the number a reader actually sees:
            // 16 is what the inset style gives a row on its own.
            let cell = try XCTUnwrap(mount.host.everyView(named: "ListTableCellView")
                .map { $0.convert($0.bounds, to: mount.host) }.first,
                                     "no row drew for \(segment)")
            XCTAssertEqual(cell.minX, 16, accuracy: 0.5, """
                a \(segment) row's content starts \(cell.minX) pt from the pane, where the \
                inset list style's own figure is 16
                """)
        }
    }

    // MARK: - The console

    /// **Ten lines, and the number is derived rather than typed.**
    ///
    /// It was a bare `160`, which is on no ladder and carried no reason anywhere.
    /// The arithmetic is recomputed here from `NSFont` rather than copied, so a
    /// macOS release that lays SF Mono out differently moves both together
    /// instead of leaving this test asserting yesterday's constant.
    func testTheConsoleIsTenLinesOfWhatBrewPrinted() async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = .installed
        transport.stream.continuation.yield(
            EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data("==> Pouring".utf8)))
        var yields = 0
        while hb.consoleLines.isEmpty && yields < 5_000 {
            await Task.yield()
            yields += 1
        }
        XCTAssertFalse(hb.consoleLines.isEmpty, "the line never reached the model")

        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 984, height: 700, appearance: .aqua)
        renders.append(mount)
        mount.settle(60)

        let face = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
        let line = (face.ascender - face.descender + face.leading).rounded(.up)
        let lines = CGFloat(HomebrewSettingsPage.consoleLinesShown)
        let expected = line * lines + HelmSpace.s1 * (lines - 1)

        // The one well on the page taller than a control: the console's.
        let blocks = wells(mount).filter { $0.frame.height > 100 }
        XCTAssertEqual(blocks.count, 1, """
            \(blocks.count) block-sized wells drew where the console is exactly one, so this \
            is measuring whichever of them the walk found first
            """)
        let console = try XCTUnwrap(blocks.first)
        XCTAssertEqual(console.frame.height, expected, accuracy: 1, """
            the console is \(console.frame.height) pt where ten lines of the face it draws in \
            is \(expected) — a height that is neither derived from what it shows nor on a step
            """)
        XCTAssertEqual(console.radius, HelmRadius.card, accuracy: 0.01, """
            the console is drawn at radius \(console.radius); a block-sized well takes the \
            card's corner
            """)
    }

    // MARK: - The fix command's well

    /// **A one-line field well takes the control corner, not the card's.**
    ///
    /// The fix command drew at `HelmRadius.card`, which made the smallest box in
    /// the inspector the roundest one — rounder than the fact tiles, the quiet
    /// notes and the multi-line caveats block beside it, all of which are
    /// `HelmRadius.ctl`, and as round as the 148 pt console.
    func testTheFixCommandsWellIsAControlAndNotACard() async throws {
        let (hb, mount) = await page(width: 984, segment: .health)
        let issue = try XCTUnwrap(hb.issues.first, "the fixture's finding never reached the page")
        XCTAssertNotNil(issue.fix, """
            the finding carries no judged fix, so no command well is drawn and this case \
            measures nothing — `DoctorFix.judge` did not admit `uninstall openssl@3`
            """)
        hb.select(issue.id)
        mount.settle(40)

        // The command sits in the inspector's scrolled pane, which is the one
        // container on this page that is not the list.
        let pane = try XCTUnwrap(mount.host.everyView(named: "HostingScrollView")
            .map { $0.convert($0.bounds, to: mount.host) }
            .max(by: { $0.width < $1.width }), "the inspector never mounted")
        let inside = wells(mount).filter {
            $0.frame.midX >= pane.minX && $0.frame.midX <= pane.maxX
                && $0.frame.midY >= pane.minY && $0.frame.midY <= pane.maxY
                && $0.frame.width > 100
        }
        XCTAssertFalse(inside.isEmpty, """
            no well wider than 100 pt drew inside the inspector, so the fix block is not on \
            screen and there is no radius here to judge
            """)
        for well in inside {
            XCTAssertEqual(well.radius, HelmRadius.ctl, accuracy: 0.01, """
                a \(Int(well.frame.width))×\(Int(well.frame.height)) pt well in the inspector \
                is drawn at radius \(well.radius) where this page's field wells are \
                \(HelmRadius.ctl)
                """)
        }
    }
}
