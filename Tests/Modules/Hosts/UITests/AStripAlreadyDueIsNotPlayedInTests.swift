import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_UI

/// **A strip that has something to say when the SSH tab first draws is simply
/// there — it does not grow in.**
///
/// The drawn flag is seeded from the model when the page is built and the
/// first measurement of the strip's height is written without a transaction
/// (`helmMeasuredHeight`), so the first frame of the tab already stands the box
/// under an open strip. Seeded `false`, the flag would never change and the
/// strip would never open at all; measured with a transaction, the tab would
/// open with the strip sliding down over its first 300 ms.
///
/// Sampled from the turn the tab is first asked for, on both ways in: the page
/// built already on the text box, and the toolbar's tab onto the table.
@MainActor
final class AStripAlreadyDueIsNotPlayedInTests: XCTestCase {

    private var benches: [SSHStripBench] = []

    override func tearDown() async throws {
        await MainActor.run { benches.forEach { $0.drop() }; benches = [] }
    }

    private func check(seam: Bool, mode: String) async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = "\(RenderedInk.label(of: appearance)), \(seam ? "built on the text box" : "toolbar to the \(mode)")"
            var first: [(ms: Int, value: CGFloat)] = []
            // `known_hosts` missing: the strip says so from the start.
            let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-strip-due"),
                                                known: nil, mode: mode, seam: seam) { mounted in
                var readings: [(ms: Int, value: CGFloat)] = []
                let start = Date()
                for _ in 0..<60 {
                    mounted.host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
                    let top = Self.surfaceTop(mounted)
                    readings.append((Int(Date().timeIntervalSince(start) * 1000), top))
                }
                first = readings
            }
            benches.append(bench)
            XCTAssertFalse(bench.hvm.knownHostsReadable, "\(what): precondition — known_hosts was readable")
            bench.mounted.settle(20)
            let settled = try XCTUnwrap(bench.firstSurfaceTop, "\(what): nothing drawn")
            let bare = HostsSettingsPage.textBoxMargin
            XCTAssertGreaterThan(settled, bare + 10, "\(what): the strip is not open over the tab at all")
            let drawn = first.filter { $0.value >= 0 }
            XCTAssertFalse(drawn.isEmpty, "\(what): precondition — nothing drew in the first 300 ms")
            let off = drawn.filter { abs($0.value - settled) > 0.5 }
            XCTAssertTrue(off.isEmpty,
                          "\(what): the tab's first frames stood the content at \(off.prefix(6).map { "\($0.ms) ms: \($0.value)" }) before \(settled) — the strip was played in")
            bench.drop()
        }
    }

    /// Rounded surfaces 300 pt wide or more, highest first: the box in the
    /// text view, the first card in the table. -1 when there is none yet.
    private static func surfaceTop(_ mounted: MountedRender) -> CGFloat {
        guard let root = mounted.host.layer else { return -1 }
        var tops: [CGFloat] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.width >= 300 {
                let frame = layer.convert(layer.bounds, to: root)
                tops.append(root.isGeometryFlipped ? frame.minY : mounted.host.bounds.height - frame.maxY)
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return tops.min() ?? -1
    }

    func testBuiltOnTheTextBox() async throws {
        try await check(seam: true, mode: "text")
    }

    func testReachedThroughTheToolbarOntoTheTable() async throws {
        try await check(seam: false, mode: "table")
    }
}
