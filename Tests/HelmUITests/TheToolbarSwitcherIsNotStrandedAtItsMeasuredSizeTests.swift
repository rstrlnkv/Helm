import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The switcher's box is the size the control asked for — in a window that is
/// sized after its toolbar is published, which is every window Helm opens.**
///
/// # The reading this file was written against
///
/// Probed 2026-09-19. `HelmToolbarSwitcher.sizeThatFits` answers the control's
/// `fittingSize`, and it is asked while the control is still loose:
/// `controlSize` is `.regular` and the answer is 24 pt tall. AppKit promotes
/// the control when the toolbar inserts it in an `NSToolbarItemViewer` — to a
/// control size that reads back as raw 4, which is none of
/// `NSControl.ControlSize`'s named cases, and measures 36 pt tall — and nothing
/// in that promotion asks SwiftUI again. A
/// probe that built its window with `NSWindow(contentRect:styleMask:…)`, set a
/// content view controller and stopped there read the control out at
/// `frame = 351 × 24` while it asked for `370.5 × 36`, and the 12 pt shortfall
/// was reported as the cause of a misdraw on a first open.
///
/// **It is not, and the ablation is the one thing worth keeping from it.** Four
/// constructions were measured with one ingredient moved at a time: assigning
/// an `NSToolbar` by hand instead of letting the bridge make one changes
/// nothing, `.fullSizeContentView` changes nothing, passing the controller to
/// `NSWindow(contentViewController:)` rather than afterwards changes nothing.
/// One call does: `setContentSize(_:)`. A window resized at all after the
/// toolbar has published its items lays the toolbar out again, SwiftUI is asked
/// for a size again — and this time the control is promoted, so it answers
/// `370.5 × 36` and the frame follows. `SettingsWindow` calls `setContentSize`,
/// `contentMinSize` and `center()` before the window is ever shown, and the
/// person then resizes it at will. So the stranded state does not occur in
/// Helm: designer measured the capsule on the running app at 370.0 pt wide,
/// against this probe's 370.5, and no frame anywhere in three Dark and three
/// Light cycles read 351.
///
/// # Why both cases
///
/// The first case alone would pass on any machine where AppKit never promotes
/// anything — the equality would hold for free. The second builds the window
/// that does strand and asserts it strands, which is what makes the first a
/// reading of a real revision. If Apple makes the promotion re-ask by itself,
/// the second goes red and says so; that is the only notice there would be that
/// the difference between the two constructions has stopped existing.
@MainActor
final class TheToolbarSwitcherIsNotStrandedAtItsMeasuredSizeTests: XCTestCase {

    /// Four segments, as Homebrew's page declares them. The words are counted,
    /// never asserted, so no language is named: what is read here is geometry,
    /// and `AppLanguage` would change the numbers without changing the shape.
    private static let words = ["Installed", "Updates", "Search", "Health"]

    // MARK: - The invariant, in the app's own construction

    func testASwitcherInAWindowSizedAfterItsToolbarEndsUpTheSizeItAskedFor() throws {
        let mounted = try mount(.sizedAfterwards)
        defer { mounted.window.orderOut(nil) }
        let control = mounted.control

        XCTAssertEqual(control.frame.size.width, control.fittingSize.width, accuracy: 0.01, """
            the switcher's box is \(control.frame.size.width) pt wide and the control asks for \
            \(control.fittingSize.width). SwiftUI committed a width measured before the control \
            was inserted in the toolbar and nothing re-asked, so the segments draw in a box that \
            is not theirs.
            """)
        XCTAssertEqual(control.frame.size.height, control.fittingSize.height, accuracy: 0.01, """
            the switcher's box is \(control.frame.size.height) pt tall and the control asks for \
            \(control.fittingSize.height). AppKit promotes controlSize on insertion into the \
            toolbar; where the frame does not follow, the capsule draws short.
            """)
        XCTAssertGreaterThan(control.frame.size.height, mounted.firstFrame.height, """
            the switcher's box never grew: \(mounted.firstFrame.height) pt when SwiftUI first laid \
            it out, \(control.frame.size.height) pt now. Either AppKit no longer promotes \
            controlSize on insertion — in which case the equalities above hold for free and guard \
            nothing — or the control was never inserted at all.
            """)
    }

    // MARK: - The control that makes the invariant mean something

    /// A window built and left at the size its `contentRect` gave it. The item
    /// is published, the control is promoted, and no second layout ever asks
    /// SwiftUI for a size — so the frame stays at the pre-insertion
    /// measurement.
    ///
    /// This case asserts a defect rather than a virtue, deliberately: it is the
    /// negative control for the case above.
    func testASwitcherInAWindowNeverResizedAfterwardsIsStrandedAtItsPreInsertionSize() throws {
        let mounted = try mount(.neverResized)
        defer { mounted.window.orderOut(nil) }
        let control = mounted.control

        XCTAssertNotEqual(control.fittingSize.height, mounted.firstFrame.height, accuracy: 0.01, """
            the control asks for the same \(control.fittingSize.height) pt it was committed at, so \
            AppKit no longer re-measures it on insertion into the toolbar. The reason this file \
            exists is gone and both cases need re-measuring.
            """)
        XCTAssertEqual(control.frame.size.height, mounted.firstFrame.height, accuracy: 0.01, """
            a window that is never resized after publishing its toolbar now revises the switcher's \
            frame anyway — \(mounted.firstFrame.height) pt became \(control.frame.size.height). \
            It is no longer the negative control for the case above, and the case above no longer \
            distinguishes anything.
            """)
        XCTAssertNotEqual(control.frame.size.height, control.fittingSize.height, accuracy: 0.01, """
            the switcher is no longer stranded in a window nothing resizes — its box is \
            \(control.frame.size.height) pt and it asks for \(control.fittingSize.height). Good \
            news, and it retires this case; the case above is then the only one worth keeping.
            """)
    }

    // MARK: - Mounting

    private enum Construction {
        /// `SettingsWindow`'s: the window is given its content size after the
        /// hosting controller is in place, which is what lays the toolbar out
        /// a second time.
        case sizedAfterwards
        /// The same window, left at the size its `contentRect` gave it.
        case neverResized
    }

    private struct Mounted {
        let window: NSWindow
        let control: NSSegmentedControl
        /// The size the control was first laid out at — the first
        /// `frameDidChange`, which carries the size SwiftUI committed from
        /// `sizeThatFits` before the control was inserted.
        let firstFrame: CGSize
    }

    /// Builds the window, lets the toolbar settle, and finds the one control.
    ///
    /// The run loop is turned rather than yielded: the bridge publishes its
    /// items, and AppKit lays the toolbar out, on later turns of the main run
    /// loop, and a cooperative yield buys none of them.
    private func mount(_ construction: Construction,
                       file: StaticString = #filePath, line: UInt = #line) throws -> Mounted {
        _ = NSApplication.shared
        var frames: [CGSize] = []
        var caught: [NSSegmentedControl] = []
        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: nil, queue: nil) { note in
            guard let seen = note.object as? NSSegmentedControl else { return }
            let control = seen
            MainActor.assumeIsolated {
                frames.append(control.frame.size)
                if !caught.contains(where: { $0 === control }) { caught.append(control) }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let controller = NSHostingController(rootView: Page(words: Self.words))
        controller.sceneBridgingOptions = [.toolbars]
        controller.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        // The test holds this window; closing a window AppKit still believes
        // it owns releases it under ARC, which is a crash in teardown and not
        // a failure anybody can read.
        window.isReleasedWhenClosed = false
        if construction == .sizedAfterwards {
            window.setContentSize(NSSize(width: 1060, height: 700))
        }
        window.orderBack(nil)
        window.layoutIfNeeded()

        var control: NSSegmentedControl?
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, control == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            // The toolbar lives above the content view, so the walk starts at
            // the frame view. A control the walk cannot reach — the stranded
            // construction keeps its item viewer outside the window's own tree
            // — is taken off the frame observer instead.
            control = window.contentView?.superview?.everyView(ofType: NSSegmentedControl.self).first
                ?? caught.first
        }
        let found = try XCTUnwrap(control, """
            no NSSegmentedControl was mounted in the \(construction) window within two seconds, so \
            every reading below would be a reading of nothing.
            """, file: file, line: line)
        XCTAssertEqual(found.segmentCount, Self.words.count, """
            the mounted control holds \(found.segmentCount) segments, not \(Self.words.count): \
            production never filled it, so its frame is not a measurement of anything.
            """, file: file, line: line)
        let first = try XCTUnwrap(frames.first, """
            the control's frame was never set, so there is no pre-insertion size to compare \
            against and this check read nothing.
            """, file: file, line: line)
        return Mounted(window: window, control: found, firstFrame: first)
    }

    /// A page as Homebrew and Hosts declare theirs: the switcher as the
    /// principal toolbar item, under the same fixed navigation spacer
    /// `SettingsWindow` puts on the detail pane.
    private struct Page: View {
        let words: [String]
        @State private var selection = 0

        var body: some View {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HelmToolbarSwitcher("Probe", selection: $selection,
                                            segments: words.enumerated().map { index, word in
                                                HelmSwitcherSegment(index, word, symbol: "circle")
                                            })
                    }
                }
                .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }
    }
}
