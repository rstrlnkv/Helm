import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A package with an update waiting must not be the one name in the list
/// that does not line up.**
///
/// The installed list marks an outdated package with an arrow ahead of its
/// name. The mark was drawn only on that row, so its name began a mark's
/// width to the right of every other name in the column — rendered
/// 2026-09-16 with `node` outdated among five others. A column of names is
/// read down its left edge, and the one that broke the edge was the one that
/// wanted attention. The repair keeps the slot on every row of a list that
/// marks updates at all, the way Mail keeps the column for its unread dot.
///
/// **Read from the pixels, because nothing else can see it.** `NSHostingView`
/// builds no accessibility tree until a client connects (measured in
/// `TheNarrowPaneCanStillActOnAPackageTests`), and a SwiftUI `Text` is not an
/// `NSView`, so there is no frame to ask for. What there is, is ink: a
/// package name is drawn in the primary label colour, which is near black in
/// the light appearance, while the mark is `HelmSignal.warning` and the
/// version beside the name is `HelmText.quiet` — neither of them near black.
/// So the leftmost near-black pixel of each line of text in the list is where
/// that row's name begins.
///
/// Light, named: an unnamed appearance is a reading of whatever this Mac is
/// set to at this hour, and «near black» means nothing in the dark one.
@MainActor
final class EveryNameInTheListStartsInOneColumnTests: XCTestCase {

    /// Six installed packages, one of them outdated and not first — a marked
    /// row at the top would put the only misaligned name where a reader might
    /// take it for a heading.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([
                    BrewPackage(name: "ada-url", version: "4.0.0", isCask: false),
                    BrewPackage(name: "aria2", version: "1.37.0_2", isCask: false),
                    BrewPackage(name: "node", version: "26.8.2", isCask: false),
                    BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false),
                    BrewPackage(name: "periphery", version: "3.8.0", isCask: false),
                    BrewPackage(name: "wget", version: "1.25.0", isCask: false)])
            case .outdated:
                return try JSONEncoder().encode([
                    OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                    isCask: false, pinned: false)])
            default:
                return Data("[]".utf8)
            }
        }
    }

    /// Where each line of near-black text in `area` begins, in pixels, top to
    /// bottom. A line is a run of pixel rows that each hold at least one
    /// near-black pixel; the run's leftmost such pixel is where it starts.
    private func lineStarts(in rep: NSBitmapImageRep, area: CGRect, scale: CGFloat) -> [Int] {
        guard let data = rep.bitmapData, rep.samplesPerPixel >= 3, rep.bitsPerSample == 8 else {
            return []
        }
        let x0 = max(0, Int(area.minX * scale)), x1 = min(rep.pixelsWide, Int(area.maxX * scale))
        let y0 = max(0, Int(area.minY * scale)), y1 = min(rep.pixelsHigh, Int(area.maxY * scale))
        let stride = rep.bytesPerRow / rep.pixelsWide
        var starts: [Int] = []
        var runStart: Int?
        for y in y0..<y1 {
            var leftmost: Int?
            for x in x0..<x1 {
                let i = y * rep.bytesPerRow + x * stride
                // Near black and opaque: label ink, not the warning orange and
                // not the quiet grey of the version beside it.
                if data[i] < 70, data[i + 1] < 70, data[i + 2] < 70,
                   stride < 4 || data[i + 3] > 200 {
                    leftmost = x
                    break
                }
            }
            if let leftmost {
                runStart = min(runStart ?? leftmost, leftmost)
            } else if let started = runStart {
                starts.append(started)
                runStart = nil
            }
        }
        if let started = runStart { starts.append(started) }
        return starts
    }

    func testTheOutdatedPackagesNameLinesUpWithEveryOther() async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        await hb.refreshOutdated()
        hb.segment = .installed
        hb.select(nil)

        // The subject first: a list in which nothing is outdated draws no
        // mark, and every name then lines up for a reason that proves nothing.
        XCTAssertTrue(hb.outdated.contains { $0.name == "node" },
                      "the fixture's outdated package never reached the page, so no row is marked")

        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 834, height: 700, appearance: .aqua)
        mount.settle(40)
        defer { mount.drop() }

        let list = try XCTUnwrap(mount.host.everyView(named: "ListCoreScrollView")
            .map { $0.convert($0.bounds, to: mount.host) }.first, "no list drew")
        let view = mount.host
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds),
                                "the host gave no bitmap to read")
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width

        // The bitmap's rows run top-down and so does a flipped host; an
        // unflipped one has to be turned over before its y means the list's.
        let area = view.isFlipped ? list
            : CGRect(x: list.minX, y: view.bounds.height - list.maxY,
                     width: list.width, height: list.height)
        let starts = lineStarts(in: rep, area: area, scale: scale)

        XCTAssertEqual(starts.count, 6, """
            \(starts.count) lines of near-black text in the list where six names drew — this \
            is not a reading of those six rows, so nothing below measures their alignment
            """)
        guard let first = starts.min(), let last = starts.max() else { return }
        XCTAssertLessThanOrEqual(CGFloat(last - first) / scale, 1, """
            the names in the installed list begin at \(starts.map { CGFloat($0) / scale }) pt — \
            one of them starts \(CGFloat(last - first) / scale) pt to the right of the others, \
            and the row it belongs to is the one carrying the update mark
            """)
        withExtendedLifetime(transport) {}
    }
}
