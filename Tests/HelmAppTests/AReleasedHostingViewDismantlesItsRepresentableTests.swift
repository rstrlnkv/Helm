import AppKit
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **What SwiftUI does with a representable when its `NSHostingView` is
/// released** — whether `dismantleNSView` is called, whether the coordinator
/// is deallocated, and when.
///
/// `HelmToolbarSwitcher` stops its coordinator's local mouse monitor only in
/// `dismantleNSView`, and the coordinator has no `deinit`; the page bar keeps
/// hosts of it mounted. Whether that monitor outlives a released host depends
/// on this, and it is a fact about SwiftUI on this macOS, so it is measured
/// here rather than read: a probe representable leaves a mark from
/// `makeNSView`, from `dismantleNSView` and from its coordinator's `deinit`,
/// and each probe row releases a host in one of the forms the bar can meet and
/// reads the marks at two moments: at once, and after the run loop turned. The
/// row on the real switcher reads whether its coordinator and its host are gone
/// at the same two moments.
///
/// The rows assert what was measured, so a change in SwiftUI turns one red
/// and names the moment. **Subject first:** every row asserts that
/// `makeNSView` ran before the release (a detached host has no control until
/// its first layout), so a probe that never mounts fails there and not as a
/// quiet "never dismantled".
///
/// What is not measured: a host in a shown, key window; and that the real
/// switcher's monitor is removed. Its coordinator is seen to die with the host
/// and the probe's `dismantleNSView` is seen to run, so `stop()` running for the
/// real switcher is inferred from the two, not read.
@MainActor
final class AReleasedHostingViewDismantlesItsRepresentableTests: XCTestCase {

    // MARK: - The probe

    final class Marks: @unchecked Sendable {
        var made = 0
        var dismantled = 0
        var coordinatorsGone = 0
    }

    struct Probe: NSViewRepresentable {
        let marks: Marks

        final class Coordinator {
            let marks: Marks
            init(_ marks: Marks) { self.marks = marks }
            deinit { marks.coordinatorsGone += 1 }
        }

        func makeCoordinator() -> Coordinator { Coordinator(marks) }
        func makeNSView(context: Context) -> NSView {
            marks.made += 1
            return NSView()
        }
        func updateNSView(_ view: NSView, context: Context) {}
        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            coordinator.marks.dismantled += 1
        }
    }

    // MARK: - The release forms

    enum Form: CustomStringConvertible {
        case neverInAWindow
        case droppedWithItsSuperviewInAnUnshownWindow
        case removedFromItsSuperviewThenDropped
        var description: String {
            switch self {
            case .neverInAWindow: return "never in a window"
            case .droppedWithItsSuperviewInAnUnshownWindow: return "in an unshown window, dropped with its superview"
            case .removedFromItsSuperviewThenDropped: return "removed from its superview, then dropped"
            }
        }
    }

    struct SwitcherReading: Equatable, CustomStringConvertible {
        var coordinatorGone: Bool
        var hostGone: Bool
        var description: String { "coordinator gone \(coordinatorGone), host gone \(hostGone)" }
    }

    private final class Held { var host: NSView?; var container: NSView?; var window: NSWindow? }

    /// Mounts `root` in a host (the bar's form or a bare one); unless the form is `neverInAWindow` the host
    /// sits in a container that is the content view of an unshown window. Laid out once, so the control exists.
    private func mount<V: View>(_ root: V, _ form: Form, inBar: Bool) -> Held {
        let held = Held()
        let host: NSView = inBar ? NSHostingView.inBar(rootView: root) : NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        held.host = host
        if form != .neverInAWindow {
            let container = NSView(frame: host.frame)
            container.addSubview(host)
            let window = NSWindow(contentRect: container.frame, styleMask: [.titled],
                                  backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = container
            held.container = container
            held.window = window
        }
        host.layoutSubtreeIfNeeded()
        host.superview?.layoutSubtreeIfNeeded()
        return held
    }

    /// Lets go of the host in `form`; `afterRemoval` runs between removing it from its superview and dropping it.
    private func release(_ held: Held, _ form: Form, afterRemoval: () -> Void = {}) {
        autoreleasepool {
            switch form {
            case .neverInAWindow: held.host = nil
            case .droppedWithItsSuperviewInAnUnshownWindow: held.host = nil; held.container = nil; held.window = nil
            case .removedFromItsSuperviewThenDropped:
                held.host?.removeFromSuperview()
                afterRemoval()
                held.host = nil
            }
        }
    }

    /// Mounts the real switcher in a host, finds its segmented control and the
    /// coordinator that is the control's target, releases the host in `form`, and
    /// reads whether the coordinator and the host are gone at the two moments.
    private func releaseSwitcher(_ form: Form, inBar: Bool)
        -> (controlFound: Bool, atOnce: SwitcherReading, turned: SwitcherReading) {
        var held: Held!
        weak var weakHost: NSView?
        weak var weakCoordinator: AnyObject?
        var found = false
        autoreleasepool {
            let segments = [HelmSwitcherSegment(0, "One", symbol: "1.circle"), HelmSwitcherSegment(1, "Two", symbol: "2.circle")]
            held = mount(HelmToolbarSwitcher("Probe", selection: .constant(0), segments: segments), form, inBar: inBar)
            if let control = held.host?.everyView(ofType: NSSegmentedControl.self).first {
                found = true
                weakCoordinator = control.target
            }
            weakHost = held.host
        }
        func read() -> SwitcherReading {
            SwitcherReading(coordinatorGone: weakCoordinator == nil, hostGone: weakHost == nil)
        }
        release(held, form)
        let atOnce = read()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let turned = read()
        held.container = nil; held.window = nil
        return (found, atOnce, turned)
    }

    /// The probe's coordinator cannot be held weakly from outside (SwiftUI makes it),
    /// so its life is the counter its `deinit` bumps.
    private func assertProbe(_ form: Form, inBar: Bool,
                             dismantledAtOnce: Int, coordinatorsGoneAtOnce: Int,
                             dismantledAfterTurn: Int, coordinatorsGoneAfterTurn: Int,
                             hostGone: Bool,
                             file: StaticString = #filePath, line: UInt = #line) {
        let marks = Marks()
        var atOnce: (Int, Int, Bool)?
        var turned: (Int, Int, Bool)?
        var made = 0
        var afterRemovalOnly: Int?
        weak var weakHost: NSView?
        var held: Held!
        autoreleasepool {
            held = mount(Probe(marks: marks), form, inBar: inBar)
            made = marks.made
            weakHost = held.host
        }
        XCTAssertEqual(made, 1, "subject first: makeNSView must have run once before the release (\(form))",
                       file: file, line: line)
        XCTAssertEqual(marks.dismantled, 0, "nothing dismantled before the release (\(form))", file: file, line: line)
        release(held, form) { afterRemovalOnly = marks.dismantled }
        atOnce = (marks.dismantled, marks.coordinatorsGone, weakHost == nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        turned = (marks.dismantled, marks.coordinatorsGone, weakHost == nil)
        held.container = nil; held.window = nil
        if form == .removedFromItsSuperviewThenDropped {
            XCTAssertEqual(afterRemovalOnly, 0,
                           "removing the host from its superview dismantles nothing while the host is still held",
                           file: file, line: line)
        }
        XCTAssertEqual(atOnce?.0, dismantledAtOnce, "dismantle count at once (\(form))", file: file, line: line)
        XCTAssertEqual(atOnce?.1, coordinatorsGoneAtOnce, "coordinators gone at once (\(form))", file: file, line: line)
        XCTAssertEqual(turned?.0, dismantledAfterTurn, "dismantle count after the run loop turned (\(form))", file: file, line: line)
        XCTAssertEqual(turned?.1, coordinatorsGoneAfterTurn, "coordinators gone after the run loop turned (\(form))", file: file, line: line)
        XCTAssertEqual(turned?.2, hostGone, "host gone after the run loop turned (\(form))", file: file, line: line)
    }

    // MARK: - Rows

    /// The control for the rows below: a host that is still held is never dismantled.
    func testAHeldHostIsNeverDismantled() {
        let marks = Marks()
        let host = NSHostingView.inBar(rootView: Probe(marks: marks))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(marks.made, 1, "subject first: makeNSView ran")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(marks.dismantled, 0)
        XCTAssertEqual(marks.coordinatorsGone, 0)
        withExtendedLifetime(host) {}
    }

    func testProbeBareNeverInAWindow() {
        assertProbe(.neverInAWindow, inBar: false, dismantledAtOnce: 1, coordinatorsGoneAtOnce: 1,
                    dismantledAfterTurn: 1, coordinatorsGoneAfterTurn: 1, hostGone: true)
    }
    func testProbeBareInAnUnshownWindow() {
        assertProbe(.droppedWithItsSuperviewInAnUnshownWindow, inBar: false, dismantledAtOnce: 1, coordinatorsGoneAtOnce: 1,
                    dismantledAfterTurn: 1, coordinatorsGoneAfterTurn: 1, hostGone: true)
    }
    func testProbeBareRemovedThenDropped() {
        assertProbe(.removedFromItsSuperviewThenDropped, inBar: false, dismantledAtOnce: 1, coordinatorsGoneAtOnce: 1,
                    dismantledAfterTurn: 1, coordinatorsGoneAfterTurn: 1, hostGone: true)
    }
    func testProbeInBarNeverInAWindow() {
        assertProbe(.neverInAWindow, inBar: true, dismantledAtOnce: 1, coordinatorsGoneAtOnce: 1,
                    dismantledAfterTurn: 1, coordinatorsGoneAfterTurn: 1, hostGone: true)
    }
    func testProbeInBarInAnUnshownWindow() {
        assertProbe(.droppedWithItsSuperviewInAnUnshownWindow, inBar: true, dismantledAtOnce: 1, coordinatorsGoneAtOnce: 1,
                    dismantledAfterTurn: 1, coordinatorsGoneAfterTurn: 1, hostGone: true)
    }
    func testProbeInBarRemovedThenDropped() {
        assertProbe(.removedFromItsSuperviewThenDropped, inBar: true, dismantledAtOnce: 1, coordinatorsGoneAtOnce: 1,
                    dismantledAfterTurn: 1, coordinatorsGoneAfterTurn: 1, hostGone: true)
    }

    func testTheRealSwitcherCoordinatorIsGoneWithItsHost() {
        for inBar in [true, false] {
            for form in [Form.neverInAWindow, .droppedWithItsSuperviewInAnUnshownWindow, .removedFromItsSuperviewThenDropped] {
                let r = releaseSwitcher(form, inBar: inBar)
                XCTAssertTrue(r.controlFound, "subject first: the switcher's control was mounted (\(form))")
                XCTAssertEqual(r.atOnce, SwitcherReading(coordinatorGone: true, hostGone: true), "\(form)")
                XCTAssertEqual(r.turned, SwitcherReading(coordinatorGone: true, hostGone: true), "\(form)")
            }
        }
    }
}
