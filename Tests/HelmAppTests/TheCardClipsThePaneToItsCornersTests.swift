import AppKit
import XCTest
import HelmRuntime
@testable import HelmApp

/// **The shell's view lays its pieces out from `ShellGeometry`, cuts the card
/// from the corner `WindowCorner` read and clips the pane inside the card to the
/// same radius, so the page's band never runs square to the window's edge; it
/// tells whoever asked where the card went, and it writes a line about the
/// corner only while it is in a window.**
///
/// No window is ordered in, none is made key and the app is not
/// activated; the two tests that need windows (the lines in the log) use two
/// each, never shown, and say so at their end. The glass itself never composites
/// off screen, so nothing here judges what it draws, only that it is the bottom
/// subview and regular.
///
/// What is an input and what is arithmetic. The view of 1060x760 is the Settings
/// window's default size; the card frames (200, 4, 856, 752) and, at the rail,
/// (56, 4, 1000, 752) are `ShellGeometry`'s arithmetic on it. The radii 16 and
/// 26 are handed in to `apply` as two corners that are not the same: 16 gives 12
/// and 26 gives 22 because the card sits 4 pt inside the window; those cases do
/// not depend on the running macOS or on the guess table.
/// `testOutsideAWindowTheProbesZeroIsNotAReading` does, and skips where there is
/// no probe or no guess. What this file cannot prove:
/// that the probe on 27 reports, that a window's corner moves on 26 after the
/// toolbar's attach, and how the glass looks; only a window proves those.
@MainActor
final class TheCardClipsThePaneToItsCornersTests: XCTestCase {

    // MARK: - inputs

    private nonisolated static let size = CGSize(width: 1060, height: 760)

    /// The view with plain views for its two halves; the sidebar counts the
    /// times AppKit placed or sized it, which is how a layout that ran is told
    /// from one that did not.
    private struct Shell {
        let view: ShellContentView
        let sidebar: CountingView
        let pane: NSView
        let moved: MovedLog
    }

    private final class CountingView: NSView {
        private(set) var placements = 0
        override func setFrameSize(_ newSize: NSSize) {
            placements += 1
            super.setFrameSize(newSize)
        }
        override func setFrameOrigin(_ newOrigin: NSPoint) {
            placements += 1
            super.setFrameOrigin(newOrigin)
        }
    }

    private final class MovedLog {
        var frames: [CGRect] = []
    }

    private func makeShell(size: CGSize = TheCardClipsThePaneToItsCornersTests.size) -> Shell {
        let sidebar = CountingView()
        let pane = NSView()
        let moved = MovedLog()
        let view = ShellContentView(sidebar: sidebar, pane: pane, cardMoved: { moved.frames.append($0) })
        view.frame = CGRect(origin: .zero, size: size)
        return Shell(view: view, sidebar: sidebar, pane: pane, moved: moved)
    }

    /// A layout that is asked for, then run. Without a window AppKit runs none
    /// that was not requested, so a pass that is meant to happen says so.
    private func pass(_ view: NSView) {
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private func assertFrame(_ actual: CGRect, _ expected: CGRect, _ message: @autoclosure () -> String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.001, message(), file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.001, message(), file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.001, message(), file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.001, message(), file: file, line: line)
    }

    /// The log is off in a test process; a test that reads it turns it on, and
    /// puts it as it was found.
    private func withTheLogOn(_ body: @MainActor () throws -> Void) rethrows {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
        defer {
            HelmLog.shared.clearTail()
            HelmLog.shared.setEnabled(false)
        }
        try body()
    }

    /// A window that is never ordered in, made key or activated.
    private func unshownWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    private var windowLines: [LogEntry] {
        HelmLog.shared.recentEntries().filter { $0.category == WindowCorner.logCategory }
    }

    private func srgb(_ color: CGColor?) -> NSColor? {
        color.flatMap { NSColor(cgColor: $0) }?.usingColorSpace(.sRGB)
    }

    // MARK: - the clip and the card

    func testTheClipMasksAtTheCardsRadius() throws {
        let shell = makeShell()
        let view = shell.view

        // Before any radius is set: AppKit turns a layer's masksToBounds on by itself
        // once a radius above 0 is set on it (measured on 27.2 for the clip, not for the card,
        // which carries a shadow), so only a view that has no radius yet shows whether
        // the clip's own line is there.
        XCTAssertEqual(view.clip.layer?.cornerRadius, 0, "the clip has a radius before any layout: the case below proves nothing")
        XCTAssertEqual(view.clip.layer?.masksToBounds, true,
                       "the clip does not mask by itself: it masks only because AppKit does so once a radius above 0 is set")
        XCTAssertEqual(view.card.layer?.masksToBounds, false, "the card masks before any layout: its shadow is cut off")
        pass(view)

        XCTAssertNil(view.window, "the view is in a window: the case proves nothing about a view in none")
        XCTAssertTrue(shell.pane.superview === view.clip,
                      "the pane is not inside the clip: nothing was assembled")
        XCTAssertTrue(view.clip.superview === view.card,
                      "the clip is not inside the card: nothing was assembled")

        assertFrame(view.card.frame, CGRect(x: 200, y: 4, width: 856, height: 752),
                    "the card is at \(view.card.frame), not (200, 4, 856, 752): the shell does not lay out from ShellGeometry")
        assertFrame(view.clip.frame, view.card.bounds, "the clip does not cover the card: \(view.clip.frame)")
        assertFrame(shell.pane.frame, view.clip.bounds, "the pane does not fill the clip: \(shell.pane.frame)")

        XCTAssertEqual(view.clip.layer?.masksToBounds, true,
                       "the clip does not mask: the pane's band runs square to the window's edge")
        XCTAssertEqual(view.card.layer?.masksToBounds, false,
                       "the card masks its own layer: its shadow is cut off")
        XCTAssertNotNil(view.card.shadow, "the card has no shadow")

        for (window, card) in [(16, 12), (26, 22), (16, 12)] as [(CGFloat, CGFloat)] {
            view.apply(WindowCorner(radius: window, rung: .publicAPI))
            XCTAssertEqual(view.clip.layer?.cornerRadius, card,
                           "the clip kept \(view.clip.layer?.cornerRadius ?? -1) when the corner became \(window): the radius is read once")
            XCTAssertEqual(view.card.layer?.cornerRadius, card,
                           "the card kept \(view.card.layer?.cornerRadius ?? -1) when the corner became \(window): the radius is read once")
        }
        XCTAssertEqual(view.clip.layer?.cornerCurve, CALayerCornerCurve.continuous, "the clip's corner is a circle, not the system's curve")
        XCTAssertEqual(view.card.layer?.cornerCurve, CALayerCornerCurve.continuous, "the card's corner is a circle, not the system's curve")

        let fill = try XCTUnwrap(srgb(view.card.layer?.backgroundColor), "the card has no fill")
        XCTAssertEqual(fill.alphaComponent, 1, accuracy: 0.001, "the card's fill lets the window through: \(fill)")

        let glass = try XCTUnwrap(view.subviews.first as? NSGlassEffectView,
                                  "the glass is not the bottom subview: \(String(describing: view.subviews.first))")
        XCTAssertEqual(glass.style, NSGlassEffectView.Style.regular, "the glass is not the regular style")
    }

    func testACornerSmallerThanTheGapLeavesASquareCardNotANegativeOne() {
        let shell = makeShell()
        shell.view.apply(WindowCorner(radius: 26, rung: .publicAPI))
        shell.view.apply(WindowCorner(radius: 2, rung: .guess))
        XCTAssertEqual(shell.view.card.layer?.cornerRadius, 0, "a window corner of 2 gave the card a radius of \(shell.view.card.layer?.cornerRadius ?? -1)")
        XCTAssertEqual(shell.view.clip.layer?.cornerRadius, 0, "a window corner of 2 gave the clip a radius of \(shell.view.clip.layer?.cornerRadius ?? -1)")
        shell.view.apply(WindowCorner(radius: 0, rung: .none))
        XCTAssertEqual(shell.view.clip.layer?.cornerRadius, 0, "a corner nobody read left the clip rounded")
    }

    func testTheFillFollowsTheAppearance() throws {
        let shell = makeShell()
        let view = shell.view

        view.appearance = NSAppearance(named: .aqua)
        let light = try XCTUnwrap(srgb(view.card.layer?.backgroundColor), "the card has no fill under the light appearance")
        view.appearance = NSAppearance(named: .darkAqua)
        let dark = try XCTUnwrap(srgb(view.card.layer?.backgroundColor), "the card has no fill under the dark appearance")

        XCTAssertEqual(light.alphaComponent, 1, accuracy: 0.001, "the light fill lets the window through")
        XCTAssertEqual(dark.alphaComponent, 1, accuracy: 0.001, "the dark fill lets the window through")
        XCTAssertGreaterThan(light.brightnessComponent - dark.brightnessComponent, 0.2,
                             "the card kept its light fill under a dark appearance: the fill is resolved once (light \(light), dark \(dark))")

        view.appearance = NSAppearance(named: .aqua)
        let again = try XCTUnwrap(srgb(view.card.layer?.backgroundColor))
        XCTAssertEqual(again.brightnessComponent, light.brightnessComponent, accuracy: 0.001,
                       "the card stayed dark when the appearance went back to light")
    }

    // MARK: - the corner outside a window

    func testALayoutWithoutAWindowWritesNoLine() {
        withTheLogOn {
            let shell = makeShell()
            pass(shell.view)
            pass(shell.view)
            shell.view.apply(WindowCorner(radius: 26, rung: .publicAPI))
            let lines = windowLines
            XCTAssertEqual(lines.count, 0,
                           "a view in no window wrote \(lines.count) line(s) under [window]: a corner nobody drew was reported: \(lines.map(\.message))")

            // The control: a log that is off, or a category nobody reads, reads as silence too.
            HelmLog.shared.info(WindowCorner.logCategory, "control")
            XCTAssertEqual(windowLines.map(\.message), ["control"],
                           "the log did not show a line written under [window]: the silence above proves nothing")
        }
    }

    func testOutsideAWindowTheProbesZeroIsNotAReading() throws {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard major >= 27 else {
            throw XCTSkip("macOS \(major): there is no probe below 27, so there is no zero to mistake for a reading")
        }
        let chrome = WindowCorner.Chrome(hasToolbar: false, systemMajor: major)
        let read = WindowCorner.read(publicReading: nil, from: nil, chrome: chrome)
        guard WindowCorner.guess(for: chrome) != nil else {
            throw XCTSkip("macOS \(major) has no guess in the table: outside a window the card would be square by the ladder itself")
        }
        let expected = ShellGeometry.cardRadius(windowRadius: read.radius)
        XCTAssertGreaterThan(expected, 0, "the expectation is square: the case cannot tell a guess from a zero")

        let shell = makeShell()
        pass(shell.view)
        XCTAssertEqual(shell.view.clip.layer?.cornerRadius, expected,
                       "outside a window the card was cut square: the probe's 0 was taken as the window's corner")
        XCTAssertEqual(shell.view.card.layer?.cornerRadius, expected,
                       "outside a window the card was cut square: the probe's 0 was taken as the window's corner")
    }

    // MARK: - the card's frame is told, once per move

    func testCardMovedIsToldTheCardsFrameWhenItMovesAndNotOtherwise() {
        let shell = makeShell()
        let view = shell.view
        pass(view)
        XCTAssertEqual(shell.moved.frames.count, 1, "the first layout told \(shell.moved.frames.count) times where the card is")
        assertFrame(shell.moved.frames.first ?? .zero, CGRect(x: 200, y: 4, width: 856, height: 752),
                    "the first layout told \(String(describing: shell.moved.frames.first))")

        let before = shell.sidebar.placements
        pass(view)
        XCTAssertGreaterThan(shell.sidebar.placements, before,
                             "the repeat pass ran no layout: the count below proves nothing")
        XCTAssertEqual(shell.moved.frames.count, 1,
                       "cardMoved was called \(shell.moved.frames.count) times for a layout that moved nothing")

        view.sidebarWidth = ShellGeometry.railWidth
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(shell.moved.frames.count, 2,
                       "the sidebar's width changed and nobody was told where the card went")
        assertFrame(shell.moved.frames.last ?? .zero, CGRect(x: 56, y: 4, width: 1000, height: 752),
                    "the card was reported at \(String(describing: shell.moved.frames.last)) at the rail")
        XCTAssertEqual(shell.sidebar.frame.width, 56, accuracy: 0.001, "the sidebar is not at the rail's width")

        view.setFrameSize(NSSize(width: 900, height: 600))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(shell.moved.frames.count, 3, "the window was resized and nobody was told where the card went")
        assertFrame(shell.moved.frames.last ?? .zero, CGRect(x: 56, y: 4, width: 840, height: 592),
                    "the card was reported at \(String(describing: shell.moved.frames.last)) after a resize")
    }

    func testAWidthThatIsNotANumberLeavesFiniteFrames() {
        for width: CGFloat in [.nan, .infinity, -.infinity, -200, 5000] {
            let shell = makeShell()
            let view = shell.view
            pass(view)
            view.sidebarWidth = width
            view.layoutSubtreeIfNeeded()

            let expected = ShellGeometry.cardFrame(in: view.bounds.size, sidebarWidth: width)
            assertFrame(view.card.frame, expected, "a sidebar of \(width) put the card at \(view.card.frame), not \(expected)")
            let frame = shell.sidebar.frame
            XCTAssertTrue([frame.origin.x, frame.origin.y, frame.size.width, frame.size.height].allSatisfy(\.isFinite),
                          "a sidebar of \(width) left the sidebar's frame at \(frame)")
            XCTAssertGreaterThanOrEqual(frame.width, 0, "a sidebar of \(width) was given a negative width: \(frame)")
            XCTAssertEqual(frame.width, max(view.card.frame.minX, 0), accuracy: 0.001,
                           "the sidebar is \(frame.width) wide and the card starts at \(view.card.frame.minX): two places")
            XCTAssertEqual(frame.height, view.bounds.height, accuracy: 0.001, "the sidebar does not run the window's height")
            XCTAssertTrue(shell.moved.frames.allSatisfy { [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) },
                          "a sidebar of \(width) told the closure a frame that is not finite: \(shell.moved.frames)")
        }
    }

    func testAViewWithNoRoomLeavesNoNegativeFrames() {
        for size in [CGSize(width: 0, height: 0), CGSize(width: 100, height: 10), CGSize(width: 1060, height: 3)] {
            let shell = makeShell(size: size)
            let view = shell.view
            pass(view)
            let expected = ShellGeometry.cardFrame(in: size, sidebarWidth: view.sidebarWidth)
            assertFrame(view.card.frame, expected, "a view of \(size) put the card at \(view.card.frame), not \(expected)")
            XCTAssertGreaterThanOrEqual(view.card.frame.width, 0, "a view of \(size) gave the card a negative width")
            XCTAssertGreaterThanOrEqual(view.card.frame.height, 0, "a view of \(size) gave the card a negative height")
            assertFrame(view.clip.frame, view.card.bounds, "a view of \(size) left the clip at \(view.clip.frame)")
            assertFrame(shell.pane.frame, view.clip.bounds, "a view of \(size) left the pane at \(shell.pane.frame)")
            XCTAssertGreaterThanOrEqual(shell.sidebar.frame.width, 0, "a view of \(size) gave the sidebar a negative width")
        }
    }

    func testBarWasAttachedAsksForALayout() {
        let shell = makeShell()
        pass(shell.view)
        XCTAssertFalse(shell.view.needsLayout, "a layout was run and the view still wants one: the control does not hold")
        shell.view.barWasAttached()
        XCTAssertTrue(shell.view.needsLayout,
                      "barWasAttached asked for nothing: where there is no probe the corner is never read again")
    }

    // MARK: - in a window

    func testInAWindowOneLineIsWrittenAndTheSameCornerWritesNoSecond() {
        withTheLogOn {
            let first = unshownWindow()
            let second = unshownWindow()
            let shell = makeShell()
            let view = shell.view

            first.contentView = view
            XCTAssertTrue(view.window === first, "the view is not in the window: the case proves nothing")
            pass(view)
            pass(view)
            pass(view)
            view.barWasAttached()
            view.layoutSubtreeIfNeeded()

            let lines = windowLines
            XCTAssertGreaterThan(lines.count, 0, "a view in a window wrote no line: a machine nobody measured reports nothing")
            XCTAssertEqual(lines.count, 1,
                           "four layouts of one corner wrote \(lines.count) lines: \(lines.map(\.message))")
            if let line = lines.first {
                XCTAssertEqual(line.level == .warn, line.message.hasPrefix("corner not read"),
                               "the level is \(line.level) for \"\(line.message)\": a guess and a square are warnings, a reading is not")
            }

            first.contentView = nil
            pass(view)
            XCTAssertEqual(windowLines.count, 1, "a view taken out of its window wrote \(windowLines.count - 1) more line(s)")

            second.contentView = view
            XCTAssertTrue(view.window === second, "the view did not move to the second window")
            pass(view)
            pass(view)
            XCTAssertEqual(windowLines.count, 2,
                           "the view moved to a second window and \(windowLines.count) line(s) in all were written, not 2: that window's corner went unreported or was reported twice: \(windowLines.map(\.message))")

            second.contentView = nil
            XCTAssertFalse(first.isVisible, "the first window was shown: a test must not draw on the owner's screen")
            XCTAssertFalse(second.isVisible, "the second window was shown: a test must not draw on the owner's screen")
        }
    }

    func testAViewPutBackIntoTheSameWindowWritesNoSecondLine() {
        withTheLogOn {
            let first = unshownWindow()
            let second = unshownWindow()
            let shell = makeShell()
            let view = shell.view

            first.contentView = view
            XCTAssertTrue(view.window === first, "the view is not in the window: the case proves nothing")
            pass(view)
            XCTAssertEqual(windowLines.count, 1, "the first attachment wrote \(windowLines.count) line(s): \(windowLines.map(\.message))")

            for round in 1...3 {
                first.contentView = nil
                XCTAssertNil(view.window, "round \(round): the view was still in a window: it was never taken out")
                pass(view)
                first.contentView = view
                XCTAssertTrue(view.window === first, "round \(round): the view did not return to the same window")
                pass(view)
            }
            XCTAssertEqual(windowLines.count, 1,
                           "a view put back into the window it left wrote \(windowLines.count - 1) line(s) more: the journal is kept per attachment, not per window: \(windowLines.map(\.message))")

            first.contentView = nil
            XCTAssertNil(view.window, "the view was still in a window: it was never taken out")
            second.contentView = view
            XCTAssertTrue(view.window === second, "the view did not move to the second window")
            pass(view)
            XCTAssertEqual(windowLines.count, 2,
                           "another window did not start the journal again: \(windowLines.count) line(s) in all: \(windowLines.map(\.message))")

            second.contentView = nil
            XCTAssertFalse(first.isVisible, "the first window was shown: a test must not draw on the owner's screen")
            XCTAssertFalse(second.isVisible, "the second window was shown: a test must not draw on the owner's screen")
        }
    }
}
