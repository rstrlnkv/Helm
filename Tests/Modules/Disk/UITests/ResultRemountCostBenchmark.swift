import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Disk_Engine
@testable import Module_Disk_UI

/// What one *remount* of the Disk result screen costs while it holds a big
/// restored tree.
///
/// `helmIdlesOffScreen()` unmounts a page's subtree while its window is not
/// visible and rebuilds it on the next occlusion change — by design, and the
/// rebuild was costed in *time* (32.5 ms cold, 7–9 ms warm, ARCHITECTURE.md
/// § A hidden window is unmounted, not billed). Its memory bill was never
/// measured, and occlusion changes are not rare events: they arrive whenever
/// the person's other windows pass over Helm's. Every such rebuild re-creates
/// the result screen over whatever tree the view model holds — 45 081 nodes in
/// the owner's saved scan, 1.5 M files after a whole-volume scan.
///
/// The tree here is the same 46 021-node fixture `SavedScanRestoreCostBenchmark`
/// decodes, restored through the real `ScanStore` + `DiskViewModel` path, so
/// the two files price the two halves of one launch: reading the scan back,
/// and drawing it again.
///
/// Costs are read against the allocator's books; six cycles, because two
/// cannot tell a leak from a cache still filling. The deterministic assertion
/// is the *kept* bytes per cycle: a remount is a rebuild of the same screen,
/// and one that keeps its predecessor's tree ratchets by ~15 MB a pass —
/// the hidden-page defect in a new coat.
///
/// `HELM_BENCH=1 swift test --filter ResultRemountCostBenchmark`
@MainActor
final class ResultRemountCostBenchmark: XCTestCase {

    private static func fixture(rootPath: String) -> ScanResult {
        var counter = 0
        func node(_ depth: Int, _ path: String) -> DiskEntry {
            counter += 1
            let children: [DiskEntry]
            if depth > 0 && counter < 46_000 {
                children = (0..<15).map {
                    node(depth - 1, path + "/bench-folder-\(counter)-\($0)")
                }
            } else {
                children = []
            }
            return DiskEntry(name: (path as NSString).lastPathComponent,
                             path: path,
                             bytes: 4096 * counter,
                             isDirectory: !children.isEmpty,
                             noAccess: false,
                             children: children)
        }
        let root = node(4, rootPath)
        return ScanResult(root: root, freeBytes: 1 << 36,
                          filesScanned: counter, seconds: 61.5)
    }

    func testRemountingTheResultScreen() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let storeDirectory = scratchDirectory("remount-store")
        // The root must exist: `restoreLastScan` clears a scan whose folder has
        // gone, and a cleared store restores nothing — the page would then be
        // measured empty and every figure below would be about a blank screen.
        let root = scratchDirectory("remount-root")
        let store = ScanStore(directory: storeDirectory)
        store.save(Self.fixture(rootPath: root.path))

        let model = DiskViewModel(vm: ModuleViewModel(transport: LocalTransport()),
                                  store: store)
        // The restore decodes ~11 MB on a detached task — yields alone give it
        // no wall time, so this waits for real, up to five seconds.
        for _ in 0..<500 where model.phase != .result {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.phase, .result,
                       "the fixture never restored; the cycles below would mount an empty page")

        func mountOnce() -> Int {
            let view = NSHostingView(rootView: AnyView(
                DiskResultView(dvm: model, hovered: .constant(nil))
                    .frame(width: 810, height: 640)))
            view.frame = NSRect(x: 0, y: 0, width: 810, height: 640)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            view.appearance = NSAppearance(named: .aqua)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let layers = view.layer?.sublayers?.count ?? 0
            window.contentView = nil
            // AppKit and SwiftUI both tear down on the run loop, not on the
            // assignment above — without these turns every cycle's graph is
            // still alive when the books are read, and a deferred release
            // reads as a keep.
            for _ in 0..<20 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            }
            return layers
        }

        // Warm-up: fonts, glyph caches, the first attribute graph.
        var layers = mountOnce()
        XCTAssertGreaterThan(layers, 0, "the result screen drew nothing; nothing below measures a render")

        var cycles: [(kept: Int, peak: Int)] = []
        for _ in 0..<6 {
            let before = AllocatorBooks.allocatedBytes()
            let (drawn, peak) = AllocatorPeak.during { autoreleasepool { mountOnce() } }
            layers = drawn
            cycles.append((AllocatorBooks.allocatedBytes() - before, peak))
        }
        print("disk result remount, 46021-node tree: "
              + cycles.map { String(format: "kept %+d KB, peak %d KB",
                                    $0.kept / 1024, $0.peak / 1024) }
                  .joined(separator: "; "))

        // Kept: the last three cycles must not ratchet. The bound is set the
        // way the hidden-page one was — a screen that keeps its predecessor's
        // copy of the tree reads ~15 MB a cycle (the tree's own weight,
        // SavedScanRestoreCostBenchmark), and a healthy remount frees what the
        // unmount released.
        let lastThree = cycles.suffix(3).map(\.kept).reduce(0, +)
        XCTAssertLessThan(lastThree / 3, 4 * 1024 * 1024,
            "a remount of the result screen keeps \(lastThree / 3 / 1024) KB per cycle, "
            + "sustained — every occlusion change of a hidden window pays it")
    }
}
