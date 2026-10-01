import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import ObjectiveC
import XCTest
@testable import Module_Hosts_UI

/// **Under Reduce Motion the SSH strip opens and closes as a cut.**
///
/// `HelmMotion.disclosure` collapses to a 10 ms linear step when the setting
/// is on, and the strip is revealed through it; an inline curve at this site,
/// or a transaction carrying something other than the token, would play the
/// full 300 ms slide to somebody who asked the system not to.
/// `TheSSHHeaderRevealsAndTheBannerAlignsTests` skips itself with the setting
/// on, so without this the setting-on half is checked on no Mac whose owner
/// leaves it off — which is this one.
///
/// The setting is the workspace's own reading, answered here for the length of
/// the test by replacing that getter; the teardown puts AppKit's back.
@MainActor
final class TheSSHStripCutsUnderReduceMotionTests: XCTestCase {

    private var benches: [SSHStripBench] = []

    override func tearDown() async throws {
        await MainActor.run { benches.forEach { $0.drop() }; benches = [] }
    }

    private func reduceMotion() throws {
        let selector = #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion)
        let method = try XCTUnwrap(class_getInstanceMethod(NSWorkspace.self, selector),
                                   "AppKit no longer answers the Reduce Motion reading by this getter")
        let original = method_getImplementation(method)
        let answering: @convention(block) (AnyObject) -> Bool = { _ in true }
        method_setImplementation(method, imp_implementationWithBlock(answering))
        addTeardownBlock { method_setImplementation(method, original) }
        XCTAssertTrue(HelmMotion.reduceMotion, "precondition — the token does not read the replaced getter")
    }

    func testTheStripArrivesAndLeavesWithinAFrame() async throws {
        try reduceMotion()
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-strip-cut"))
            benches.append(bench)
            let rest = try XCTUnwrap(bench.boxTop)
            let tv = try XCTUnwrap(bench.textView)
            bench.mounted.window?.makeFirstResponder(tv)

            tv.insertText("X", replacementRange: NSRange(location: 0, length: 0))
            let down = bench.sample(seconds: 0.4, step: 0.002) { bench.boxTop ?? -1 }
            let open = try XCTUnwrap(down.last?.value)
            XCTAssertGreaterThan(open, rest + 20, "\(what): precondition — the strip never opened")
            // The last sample still short of the far end, in ms after the
            // keystroke. The bound is 80, loose for a loaded machine and well
            // under the 300 ms curve; what each run measured is printed below
            // rather than written here.
            let lastBetweenDown = down.last { $0.value < open - 0.5 }?.ms ?? 0
            print("reduce-motion strip, \(what): opened in \(lastBetweenDown) ms")
            XCTAssertLessThanOrEqual(lastBetweenDown, 80,
                                     "\(what): with Reduce Motion on the box was still travelling \(lastBetweenDown) ms after the keystroke")

            bench.hvm.revertSSH()
            let up = bench.sample(seconds: 0.4, step: 0.002) { bench.boxTop ?? -1 }
            XCTAssertEqual(try XCTUnwrap(up.last?.value), rest, accuracy: 0.5, "\(what): precondition — the strip did not close")
            let lastBetweenUp = up.last { $0.value > rest + 0.5 }?.ms ?? 0
            print("reduce-motion strip, \(what): closed in \(lastBetweenUp) ms")
            XCTAssertLessThanOrEqual(lastBetweenUp, 80,
                                     "\(what): with Reduce Motion on the box was still travelling \(lastBetweenUp) ms after Revert")
            bench.drop()
        }
    }
}
