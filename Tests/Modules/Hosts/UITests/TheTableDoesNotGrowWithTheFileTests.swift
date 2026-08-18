import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// The table costs the same whatever the file's size.
///
/// **Helm shows hosts files it refuses to write.** `HostsWrite.fits` stops the
/// privileged sentence at roughly 390 KB and the page says so on open rather
/// than at Apply, so an ad-blocking file of 1–4 MB is *displayed* on purpose —
/// and the table is handed every one of its rows.
///
/// Built eagerly that was not slow, it was fatal. Measured on this Mac,
/// 2026-08-18, offscreen at 810 pt: 2492 rows took **16.4 s to first frame,
/// 1.41 GB through the allocator and 32 408 views**, and 8587 rows **aborted the
/// process** in `AG::data::table::grow_region` — SwiftUI's attribute graph
/// running out of room, which is a ceiling rather than a slope. Lazily it reads
/// a couple of hundred views and about 1.3 s at every size from 1 KB to 4 MB.
///
/// **So the assertion is about growth, not about a number.** A ceiling on views
/// would be a figure somebody has to keep true; «the big file costs about what
/// the small one costs» is the property that matters and calibrates itself. It
/// fails loudly on the eager spelling — 32 408 against 752 — which is how it was
/// proved able to fail.
///
/// The large file is kept under the abort on purpose: a bundle that crashes
/// reports no failure at all, so a guard whose subject killed the runner would
/// have proved nothing.
@MainActor
final class TheTableDoesNotGrowWithTheFileTests: XCTestCase {

    /// The settings pane's own width, and a window tall enough that a lazy stack
    /// still has a viewport to fill — a zero-height one would build nothing and
    /// pass this by drawing nothing.
    private static let width: CGFloat = 810
    private static let height: CGFloat = 700

    /// Held for the test's life: the engine wires the transport with `[weak self]`,
    /// and the render holds the page that holds the model.
    private var wire: HostsUIWire?
    private var render: MountedRender?

    override func tearDown() async throws {
        await MainActor.run {
            self.render?.drop()
            self.render = nil
            self.wire = nil
        }
    }

    /// Mounts the real page against a fixed file and answers what it built.
    ///
    /// The appearance is named because `MountedRender` requires one, not because
    /// this reading depends on it: a count of views is the same on either screen.
    private func mount(over file: String) -> (built: Int, rows: Int) {
        let hosted = HostsUIWire.make(file: file, privileged: .declined)
        wire = hosted
        let model = HostsViewModel.shared(vm: hosted.vm)
        let mounted = MountedRender(HostsSettingsPage(vm: hosted.vm),
                                    width: Self.width, height: Self.height, appearance: .aqua)
        render = mounted
        mounted.settle()
        return (mounted.host.everyView.count, model.entries.count)
    }

    /// One mapping per line, so the row count tracks the file's size and nothing
    /// else — no comment, no blank line, nothing the parser would drop.
    private func hostsFile(kilobytes: Int) -> String {
        var out = "127.0.0.1\tlocalhost\n"
        var index = 0
        while out.utf8.count < kilobytes * 1024 {
            out += "0.0.0.0\tads-\(index).tracker-\(index).example.com\n"
            index += 1
        }
        return out
    }

    func testALargeFileBuildsAboutAsManyViewsAsASmallOne() throws {
        let small = mount(over: hostsFile(kilobytes: 1))
        render?.drop()
        let large = mount(over: hostsFile(kilobytes: 100))

        // The absence trap first: on a machine with no window server nothing
        // draws, every count is zero, and a ratio passes for ever while
        // measuring an empty bitmap.
        XCTAssertGreaterThan(small.built, 20,
                             "the page drew \(small.built) views, so nothing rendered at all "
                             + "and every count below is zero by default")
        XCTAssertGreaterThan(large.rows, 40 * small.rows,
                             "the large file parsed to \(large.rows) rows against "
                             + "\(small.rows) — the two files are not different enough for this "
                             + "to be measuring anything")

        XCTAssertLessThan(large.built, small.built * 2, """
            the table builds a view per row: \(large.rows) rows drew \(large.built) views \
            where \(small.rows) rows drew \(small.built). Helm shows hosts files far past the \
            size it can write, so this is a page that must not build what it cannot show — \
            eagerly it reached 16.4 s and 1.41 GB here, and aborted outright further up.
            """)
    }
}
