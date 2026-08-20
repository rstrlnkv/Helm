import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// The pools inside the scan's loops, measured against the allocator's books on a
/// tree this test builds — so the guard runs in the suite rather than behind
/// `HELM_BENCH=1`, and answers about a fixed number of files rather than about
/// whatever is in the home directory of whoever ran it.
///
/// `LeftoversScanFootprintTests` asks the same question against the real `~` and
/// reads `MemoryFootprint.current()`. It does fail on the defect — measured here,
/// three runs, 3657/3599/3599 bytes an item against its 2500 — but it is the
/// instrument CLAUDE.md warns off a per-item figure (`phys_footprint` answers
/// what the process costs the machine), it skips unless the Mac running it has
/// fifty items to find, and an ordinary `swift test` skips it altogether — so the
/// reading only exists when somebody remembers to ask for it.
/// This one reads `malloc_zone_statistics`' `size_in_use`, which is what malloc
/// has handed out and not been given back — the number an autoreleased `Data`
/// moves and a resident-page reading need not.
///
/// Measured on this tree — 200 settings files, 200 launch agents, 200 plug-in
/// bundles — three runs each, the three readings identical to the byte:
///
///     pools inside the loops:      1 124 928 bytes,  1820 an item
///     `autoreleasepool` removed:   6 303 648 bytes, 10200 an item
///
/// The threshold sits between the two readings, never above one of them — a
/// ceiling picked after a single measurement records the present and cannot fail
/// (ARCHITECTURE.md § A check that cannot fail is not a check). The mutation was
/// the three `autoreleasepool` calls in `LeftoversScanner` replaced by a closure
/// that only calls its body, read back in the file before the run and restored
/// from a copy after it.
///
/// The baseline is what the scan **found**: 618 rows of two strings each, and the
/// allocator's slack around them. What the defect adds is every plist read on the
/// way, which is why the two are a factor of five and a half apart rather than a
/// percentage.
///
/// **The home is resolved before the scanner is given it.** `$TMPDIR` is
/// `/var/folders/…`, `/var` is a symbolic link to `/private/var`, and
/// `LeftoversScanner.isItsOwnPlace` refuses a source that is not the directory it
/// names — so a scratch home handed over unresolved makes every source skipped
/// and the scan measures nothing while looking exactly like a scan.
final class AScanKeepsWhatItFoundTests: XCTestCase {

    /// Enough files that the per-item figure is about the loop rather than about
    /// the first allocation Foundation makes, and few enough to build in well
    /// under a second.
    private let count = 600

    /// All three of the scan's loops, because they do not cost the same thing: a
    /// settings file is weighed and never opened, a launch agent is *read* — and
    /// `NSDictionary(contentsOf:)` is where the autoreleased objects come from —
    /// and a plug-in is a bundle, read and then walked for its size. A tree of
    /// settings files alone measures the cheapest of the three and calls it the
    /// scan.
    private func home() throws -> URL {
        // Resolved: see the note above — an unresolved scratch home is a scan
        // that walks nothing.
        let root = scratchDirectory("leftovers-books").resolvingSymlinksInPath()
        for index in 0..<count / 3 {
            try write("Library/Preferences/com.vendor.app\(index).plist", in: root, bytes: 4_096)
            try plist(["Label": "com.vendor.agent\(index)",
                       "Program": "/Applications/Gone.app/Contents/MacOS/agent",
                       "RunAtLoad": true],
                      at: "Library/LaunchAgents/com.vendor.agent\(index).plist", in: root)
            try plist(["CFBundleIdentifier": "com.vendor.plugin\(index)",
                       "CFBundleName": "Vendor Plug-in \(index)"],
                      at: "Library/QuickLook/Vendor\(index).qlgenerator/Contents/Info.plist",
                      in: root)
            try write("Library/QuickLook/Vendor\(index).qlgenerator/Contents/MacOS/plugin",
                      in: root, bytes: 2_048)
        }
        return root
    }

    /// A real property list on disk, so the port under test reads a file rather
    /// than a fixture.
    private func plist(_ contents: [String: Any], at relative: String, in root: URL) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (contents as NSDictionary).write(to: url)
    }

    func testAScanCostsItsItemsAndNotWhatItRead() throws {
        let root = try home()
        let scanner = LeftoversScanner(home: root, files: FileSystemLeftovers(),
                                       apps: LeftoversFakeApps(ids: []),
                                       extensions: LeftoversFakeLoaded())

        // The first pass pays for whatever Foundation warms up once; the reading
        // that answers the question is a later one (ARCHITECTURE.md § Memory —
        // the allocator keeps its tools out, and the peak falls until it stops).
        for _ in 0..<2 { _ = autoreleasepool { scanner.scan() } }

        let before = AllocatorBooks.allocatedBytes()
        // Outside the reading, not inside it: this pool is the test's own, and
        // draining it after the reading would credit the scan with what the
        // *test* held. What is being measured is what the scan keeps while it
        // runs.
        let items = scanner.scan()
        let grew = AllocatorBooks.allocatedBytes() - before

        XCTAssertGreaterThanOrEqual(items.count, count, "precondition: the tree was walked")
        let perItem = Double(grew) / Double(items.count)
        XCTAssertLessThan(perItem, 4_000, """
            the scan kept \(grew) bytes for \(items.count) items \
            (\(Int(perItem)) an item) — it is holding what it read rather than \
            what it found. The `autoreleasepool` inside each of the scanner's \
            loops is what keeps a plist read from outliving the row built from \
            it (ARCHITECTURE.md § Memory: the pool goes inside the loop).
            """)
    }
}
