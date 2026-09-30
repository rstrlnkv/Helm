import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The console's text keeps `consoleInset` from its box on all four sides.**
///
/// The monospaced lines were drawn flush: the first glyph on the box's left edge,
/// the first line on its top, and a long line wrapped up to the right edge. Read
/// off the mounted page, as ink inside the well: a band from 2 pt in to one short
/// of `consoleInset`, along each edge and taken inside the rounded corners, must
/// hold nothing but the well's own fill. Three states are read, because the
/// layout has three ways to lose the inset:
///
/// - **at rest** (few lines, nothing scrolled): top, left and right. The right
///   edge is read on a long unbroken line, which wraps by character and so runs
///   out to whatever the width allows;
/// - **scrolled to the end** (more lines than the box holds, and one more
///   arriving, which is what scrolls it): bottom and left. The last line is
///   where `ConsoleScroll` leaves it (`position.scrollTo(edge: .bottom)`), and
///   a follow that stops short of the content's own end leaves the padding out
///   of view;
/// - **scrolled, top**: a line only partly scrolled off is clipped where the
///   scroll view's clip is. An inset inside the scrolled content scrolls away
///   with it, and the clip then sits on the box's edge, so the cut line's ink
///   ran up to a point or two from the edge. The clip has to sit at the inset.
///
/// Both appearances are read (`RenderedInk.bothAppearances`), each band is
/// preceded by an assertion that the text drew just inside it, so an empty
/// console cannot pass as a clear margin.
@MainActor
final class TheConsoleTextSitsInsideItsBoxTests: XCTestCase {

    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor: return try JSONEncoder().encode([DoctorIssue]())
            default: return Data()
            }
        }

        func say(_ line: String) {
            stream.continuation.yield(
                EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data(line.utf8)))
        }
    }

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// The page with `lines` already in its console.
    private func page(_ lines: [String], appearance: NSAppearance.Name)
        async -> (Cellar, HomebrewViewModel, MountedRender) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = .installed
        hb.clearConsole()
        for line in lines { transport.say(line) }
        await drain(hb, expecting: lines.count)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 984, height: 700, appearance: appearance)
        renders.append(mount)
        mount.settle(60)
        return (transport, hb, mount)
    }

    private func drain(_ hb: HomebrewViewModel, expecting count: Int) async {
        var yields = 0
        while hb.consoleLines.count < count && yields < 20_000 {
            await Task.yield()
            yields += 1
        }
        XCTAssertEqual(hb.consoleLines.count, count, "the lines never all reached the model")
    }

    /// The console's own box: the one rounded layer taller than a control.
    private func box(_ mount: MountedRender) throws -> CGRect {
        guard let root = mount.host.layer else { throw XCTSkip("no layer tree") }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > 100 {
                found.append(layer.convert(layer.bounds, to: root))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        XCTAssertEqual(found.count, 1, "\(found.count) block-sized wells drew, the console is one")
        let frame = try XCTUnwrap(found.first)
        // The layer tree is in the host's own space, flipped or not; the band
        // reader counts from the top of the bitmap.
        let top = root.isGeometryFlipped ? frame.minY : mount.host.bounds.height - frame.maxY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
    }

    private enum Edge { case top, left, bottom, right }

    /// Ink in a band along one edge of `box`, from `near` to `far` points in
    /// from that edge and kept a corner radius off both ends, so the rounded
    /// corner is not read.
    private func ink(_ mount: MountedRender, box: CGRect, edge: Edge,
                     from near: CGFloat, to far: CGFloat) throws -> Int {
        let corner = HelmRadius.card
        // Whole points, rounded inward: the band never touches an edge pixel.
        func up(_ v: CGFloat) -> Int { Int(v.rounded(.up)) }
        func down(_ v: CGFloat) -> Int { Int(v.rounded(.down)) }
        let rows: ClosedRange<Int>?
        let columns: ClosedRange<Int>?
        switch edge {
        case .top:
            rows = up(box.minY + near)...down(box.minY + far)
            columns = up(box.minX + corner)...down(box.maxX - corner)
        case .bottom:
            rows = up(box.maxY - far)...down(box.maxY - near)
            columns = up(box.minX + corner)...down(box.maxX - corner)
        case .left:
            rows = up(box.minY + corner)...down(box.maxY - corner)
            columns = up(box.minX + near)...down(box.minX + far)
        case .right:
            rows = up(box.minY + corner)...down(box.maxY - corner)
            columns = up(box.maxX - far)...down(box.maxX - near)
        }
        return try XCTUnwrap(RenderedInk.read(mount.host, points: rows, columns: columns),
                             "the \(edge) band could not be read")
    }

    /// Asserts the text drew just inside the margin, and nothing inside it.
    private func assertMargin(_ mount: MountedRender, box: CGRect, edge: Edge,
                              _ appearance: NSAppearance.Name, file: StaticString = #filePath,
                              line: UInt = #line) throws {
        let inset = HomebrewSettingsPage.consoleInset
        // The margin is read from 2 pt in to one short of the inset: the box's
        // own antialiased edge is not the claim. The text is read in the twelve
        // points that follow the margin.
        let drawn = try ink(mount, box: box, edge: edge, from: inset + 1, to: inset + 12)
        XCTAssertGreaterThan(drawn, 0, """
            \(RenderedInk.label(of: appearance)): nothing drew just inside the \(edge) margin, \
            so a clear margin would prove nothing
            """, file: file, line: line)
        let margin = try ink(mount, box: box, edge: edge, from: 2, to: inset - 1)
        XCTAssertEqual(margin, 0, """
            \(RenderedInk.label(of: appearance)): the console's text reaches into the \
            \(inset) pt at its \(edge) edge — ink \(margin) between 2 and \(inset - 1) pt \
            from the box
            """, file: file, line: line)
    }

    func testTheTextKeepsItsInsetFromTheTopTheLeftAndTheRightAtRest() async throws {
        let wide = String(repeating: "=", count: 400)
        for appearance in RenderedInk.bothAppearances {
            let (_, _, mount) = await page([
                "==> Would install 1 cask: something-long-named",
                wide,
                "==> Downloading https://example.invalid/a/b",
                "==> Pouring gwlpy",
            ], appearance: appearance)
            let box = try box(mount)
            for edge in [Edge.top, .left, .right] {
                try assertMargin(mount, box: box, edge: edge, appearance)
            }
        }
    }

    /// Several line counts, because where the top line is cut depends on the
    /// content's height modulo the line pitch, and one count can land on a gap.
    func testAPartlyScrolledLineIsClippedAtTheInsetAndNotAtTheEdge() async throws {
        for appearance in RenderedInk.bothAppearances {
            for count in [37, 38, 39, 40] {
                let lines = (0..<count).map { "==> Pouring formula-\($0) gwlpy" }
                let (transport, hb, mount) = await page(lines, appearance: appearance)
                transport.say("==> Summary: gwlpy done")
                await drain(hb, expecting: lines.count + 1)
                mount.settle(80)
                let box = try box(mount)
                try assertMargin(mount, box: box, edge: .top, appearance)
            }
        }
    }

    func testTheTextKeepsItsInsetFromTheBottomAndTheLeftWhenScrolledToTheEnd() async throws {
        for appearance in RenderedInk.bothAppearances {
            let lines = (0..<40).map { "==> Pouring formula-\($0) gwlpy" }
            let (transport, hb, mount) = await page(lines, appearance: appearance)
            // The count changing is what scrolls the console.
            transport.say("==> Summary: gwlpy done")
            await drain(hb, expecting: lines.count + 1)
            mount.settle(80)
            let box = try box(mount)
            for edge in [Edge.bottom, .left] {
                try assertMargin(mount, box: box, edge: edge, appearance)
            }
        }
    }
}
