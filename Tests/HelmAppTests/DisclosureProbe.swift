import XCTest
import SwiftUI
import AppKit
@testable import HelmApp
@testable import HelmUI

/// The panel's card grows over 0.3 s rather than in one frame.
///
/// Two guesses were spent on this before anything was measured, and both were
/// wrong. What settled it was sampling *pixels* over time: `fittingSize`
/// answers with the ideal size — where the animation is heading — so it reports
/// the end at the beginning and cannot see motion at all.
///
/// The fault was never the list. It animates its own height perfectly well; the
/// card around it did not, because `onGeometryChange` hands its measurement
/// over outside the running transaction. Measured against the real view,
/// `.animation(_, value:)` on the frame is indistinguishable from no animation
/// — only writing the measurement inside `withAnimation` ramps.
@MainActor
final class DisclosureProbe: XCTestCase {

    /// `heights` bootstraps the shared host to get real modules for the
    /// harness, and the engines that builds are real too. Let them go, or the
    /// rest of the process runs with a live keyboard tap in it.
    override func tearDown() {
        ModuleHost.shared.shutdown()
        super.tearDown()
    }

    private final class Box: ObservableObject { @Published var open = false }

    /// The panel's own sandwich: a pinned bar, a measured scroll view whose
    /// height is clamped, the section inside it, and another bar.
    private struct Harness: View {
        @ObservedObject var box: Box
        let modules: [ModuleHost.Live]
        let animateTheWrite: Bool
        @State private var gridHeight: CGFloat = 0

        var body: some View {
            VStack(spacing: 8) {
                Color.gray.frame(height: 20)
                ScrollView {
                    VStack(spacing: 8) {
                        UtilitiesSection(modules: modules, expanded: $box.open, editing: false,
                                         choosing: false, isOn: { _ in true }, toggle: { _ in })
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { h in
                        guard h > 0, gridHeight != h else { return }
                        if animateTheWrite {
                            withAnimation(HelmMotion.disclosure) { gridHeight = h }
                        } else {
                            gridHeight = h
                        }
                    }
                }
                .frame(height: gridHeight > 0 ? min(gridHeight, 500) : nil)
                Color.gray.frame(height: 20)
            }
            .frame(width: 276)
        }
    }

    /// Where the drawn content ends, in points. Pixels, because the layout
    /// system will happily tell you the answer before it gets there.
    private func inkBottom(_ host: NSHostingView<Harness>) -> Int {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        var last = 0
        for y in 0..<rep.pixelsHigh {
            for x in stride(from: 0, to: rep.pixelsWide, by: 6) {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.05,
                   c.brightnessComponent < 0.9 { last = y; break }
            }
        }
        return last / 2
    }

    private func heights(animateTheWrite: Bool) -> [Int] {
        ModuleHost.shared.bootstrap()
        let utilities = ModuleHost.shared.enabledModules.filter {
            $0.descriptor.menuBar($0.vm)?.isUtility == true
        }
        let box = Box()
        let host = NSHostingView(rootView: Harness(box: box, modules: utilities,
                                                   animateTheWrite: animateTheWrite))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        window.layoutIfNeeded()
        for _ in 0..<20 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }

        var series: [Int] = []
        withAnimation(HelmMotion.disclosure) { box.open = true }
        for _ in 0..<16 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            series.append(inkBottom(host))
        }
        return series
    }

    /// A ramp: several distinct heights on the way up, not one step.
    func testTheCardGrowsOverTime() throws {
        let series = heights(animateTheWrite: true)
        try XCTSkipIf(series.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        let steps = Set(series.filter { $0 > 0 }).count
        XCTAssertGreaterThanOrEqual(steps, 4,
                                    "the card reached its height in \(steps) step(s): \(series)")
    }

    /// The control, and the reason the fix is what it is: written outside a
    /// transaction, the same view arrives in one step. Without this the test
    /// above would pass on a machine that animates everything by default.
    func testWithoutTheTransactionItArrivesInOneStep() throws {
        let series = heights(animateTheWrite: false)
        try XCTSkipIf(series.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertLessThanOrEqual(Set(series.filter { $0 > 0 }).count, 2,
                                 "the unanimated write ramped too: \(series)")
    }
}
