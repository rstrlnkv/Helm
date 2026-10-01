import AppKit
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Coming back to the SSH tab, a strip that is already due is simply there.**
///
/// The page's measured height for the strip outlives the tab's own subtree, and
/// the flag that says whether it is drawn is written by an `onChange` on the
/// page, which fires on Keys as well. Visit SSH with nothing to say (height 13),
/// go to Keys, let a snapshot say `known_hosts` is gone, come back: the flag is
/// already true and the stored height is the old one, so the tab's first frame
/// stood the box 12 pt lower than it then rested and the strip grew to its
/// real height over ~300 ms — the playing-in the seed in `init` exists to
/// prevent, and it protects the first build of the page only.
@MainActor
final class ReturningToTheSSHTabDoesNotReplayTheStripTests: XCTestCase {

    private var benches: [SSHStripBench] = []

    override func tearDown() async throws {
        await MainActor.run { benches.forEach { $0.drop() }; benches = [] }
    }

    func testReturningToTheTabDoesNotReplayTheStripFromAStaleHeight() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-return-stale"))
            benches.append(bench)
            XCTAssertEqual(try XCTUnwrap(bench.boxTop), HostsSettingsPage.textBoxMargin, accuracy: 0.5,
                           "\(what): precondition — the strip was open before it had something to say")
            try bench.select(tab: "keys")
            bench.mounted.settle(20)
            bench.known.text = nil
            await bench.hvm.load()
            bench.mounted.settle(40)
            XCTAssertFalse(bench.hvm.knownHostsReadable, "\(what): precondition — the snapshot still has known_hosts")
            try bench.select(tab: "ssh")
            let tops = bench.sample(seconds: 0.6, step: 0.005) { bench.boxTop ?? -1 }.filter { $0.value >= 0 }
            XCTAssertFalse(tops.isEmpty, "\(what): precondition — nothing drew on the SSH tab")
            let settled = try XCTUnwrap(tops.last?.value)
            XCTAssertGreaterThan(settled, HostsSettingsPage.textBoxMargin + 10,
                                 "\(what): precondition — the strip is not open on return")
            let off = tops.filter { abs($0.value - settled) > 0.5 }
            XCTAssertTrue(off.isEmpty,
                          "\(what): back on the SSH tab the box stood at \(off.prefix(5).map { "\($0.ms) ms: \($0.value)" }) before \(settled) — the strip replayed its reveal from the height it had before")
            bench.drop()
        }
    }
}
