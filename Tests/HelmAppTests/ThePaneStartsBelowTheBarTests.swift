import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **The page bar sits at the top of the card's clip and the pane starts below it: the pane's top safe area
/// is the bar's height.** The real window, never ordered.
@MainActor
final class ThePaneStartsBelowTheBarTests: XCTestCase {

    func testThePanesTopSafeAreaIsTheBarsHeightAtTwoWindowSizes() throws {
        guard let rig = SettingsWindowRig.buildThePageBarWindow(
            in: self, failure: "the window has no content view controller of the shell's type: no pane was read")
        else { return }
        let clip = rig.shell.shell.clip
        for size in [NSSize(width: 1060, height: 760), NSSize(width: 880, height: 620)] {
            rig.window.setContentSize(size)
            rig.window.contentView?.layoutSubtreeIfNeeded()
            SettingsWindowRig.pump(0.2)
            rig.window.contentView?.layoutSubtreeIfNeeded()

            let bars = clip.subviews.compactMap { $0 as? ShellPageBarView }
            let panes = clip.subviews.filter { !($0 is ShellPageBarView) }
            XCTAssertEqual(panes.count, 1, "the clip holds \(panes.count) panes at \(size)")
            guard let pane = panes.first else { continue }
            XCTAssertNotNil(pane.window, """
                the pane is in no window: its safe area read \(pane.safeAreaInsets.top) and so did the bar
                """)
            XCTAssertGreaterThan(clip.bounds.height, ShellBarLayout.height, "the clip is too small to hold the bar at \(size)")
            XCTAssertEqual(bars.count, 1, "the card's clip holds \(bars.count) page bars at \(size)")
            if let bar = bars.first {
                XCTAssertEqual(bar.frame.height, ShellBarLayout.height, accuracy: 0.01, "the bar's height at \(size)")
                XCTAssertEqual(bar.frame.maxY, clip.bounds.maxY, accuracy: 0.01,
                               "the bar is not at the top of the clip at \(size): \(bar.frame) in \(clip.bounds)")
                XCTAssertEqual(bar.frame.minX, clip.bounds.minX, accuracy: 0.01, "the bar's left edge at \(size)")
                XCTAssertEqual(bar.frame.width, clip.bounds.width, accuracy: 0.01, "the bar is not full width at \(size)")
            }
            XCTAssertEqual(pane.safeAreaInsets.top, ShellBarLayout.height, accuracy: 0.01,
                           "the pane's top safe area is not the bar's height at \(size)")
        }
    }

    /// What the reader read, in order.
    private final class Reads { var reads: [(size: CGSize, top: CGFloat)] = [] }

    /// What SwiftUI itself reads: a `GeometryReader` in the pane, in a toolbar-less full-size-content window
    /// built here and never ordered.
    func testSwiftUIReadsTheBarsHeightAsTheTopSafeAreaAtTwoSizes() {
        let reads = Reads()
        let pane = NSHostingView(rootView: GeometryReader { proxy in
            let _ = reads.reads.append((proxy.size, proxy.safeAreaInsets.top))
            Color.clear
        })
        let shell = ShellContentView(sidebar: NSView(), pane: pane, bar: ShellPageBarView())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = shell
        addTeardownBlock { await MainActor.run { window.contentView = nil } }
        XCTAssertNil(window.toolbar, "the test window wears a toolbar")
        for size in [NSSize(width: 1060, height: 760), NSSize(width: 880, height: 620)] {
            window.setContentSize(size)
            shell.layoutSubtreeIfNeeded()
            SettingsWindowRig.pump(0.2)
            shell.layoutSubtreeIfNeeded()
            XCTAssertNotNil(pane.window, "the pane is in no window at \(size)")
            // The reader's width is the pane's, which the card and the window decide (its height leaves the safe
            // area out): a read taken at this window size is one whose width is the pane's now.
            let atThisSize = reads.reads.filter { abs($0.size.width - pane.bounds.width) < 0.5 }
            XCTAssertFalse(atThisSize.isEmpty, "the reader never ran at \(size): it read only \(reads.reads.map(\.size))")
            XCTAssertEqual(pane.safeAreaInsets.top, ShellBarLayout.height, accuracy: 0.01, "AppKit's top safe area at \(size)")
            XCTAssertEqual(atThisSize.last?.top ?? -1, ShellBarLayout.height, accuracy: 0.01,
                           "SwiftUI read \(atThisSize.map(\.top)) as the top safe area at \(size), not the bar's height")
        }
    }

    // MARK: - The window's buttons

    /// **What the bar is handed is the window buttons' owner's obstacle for AppKit's home of the buttons.**
    /// Expanded, the union of the three real buttons as they stand; in the rail, the closed capsule of the
    /// placement for a bare window's home, converted from the shell to the bar as `ShellContentView.layout()`
    /// converts it, and the name does not start under it.
    func testTheBarIsHandedTheWindowButtonsObstacleAndTheNameClearsItOnTheRail() throws {
        guard let rig = SettingsWindowRig.buildThePageBarWindow(
            in: self, failure: "the window has no content view controller of the shell's type: no buttons were read")
        else { return }
        guard let bar = rig.pageBar?.view else {
            XCTFail("SettingsWindow holds no page bar: no place was read")
            return
        }
        func settle() {
            rig.window.contentView?.layoutSubtreeIfNeeded()
            SettingsWindowRig.pump(0.2)
            rig.window.contentView?.layoutSubtreeIfNeeded()
        }
        settle()
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { rig.window.standardWindowButton($0) }
        XCTAssertEqual(buttons.count, 3, "the window has \(buttons.count) standard buttons")
        XCTAssertTrue(buttons.allSatisfy { $0.window === rig.window && !$0.isHidden }, "a standard button is hidden or foreign")
        let expected = buttons.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: bar)) }
        XCTAssertFalse(expected.isNull || expected.isEmpty, "the buttons' union is empty: nothing to compare with")

        let given = bar.place.buttons
        XCTAssertFalse(given.isNull, "the bar was handed no buttons (null)")
        XCTAssertFalse(given.isEmpty, "the bar was handed an empty buttons rect \(given)")
        for (got, want, what) in [(given.minX, expected.minX, "minX"), (given.maxX, expected.maxX, "maxX"),
                                  (given.minY, expected.minY, "minY"), (given.maxY, expected.maxY, "maxY")] {
            XCTAssertEqual(got, want, accuracy: 0.5, "the buttons' \(what) the bar was handed is not the union of the three")
        }

        // AppKit's own home, read off a bare window of the same style mask and size, never shown; the shell is
        // flipped and fills the window, so a rect's y from the window's top is its y in the shell.
        let reference = NSWindow(contentRect: rig.window.contentView?.bounds ?? .zero,
                                 styleMask: rig.window.styleMask, backing: .buffered, defer: true)
        reference.isReleasedWhenClosed = false
        let homeButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { reference.standardWindowButton($0) }
        XCTAssertEqual(homeButtons.count, 3, "the reference window has \(homeButtons.count) standard buttons")
        let inWindow = homeButtons.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: nil)) }
        XCTAssertFalse(inWindow.isNull || inWindow.isEmpty, "the reference's buttons are \(inWindow): no home to compare with")
        let shell = rig.shell.shell
        XCTAssertEqual(shell.bounds.height, reference.frame.height, accuracy: 0.5,
                       "the shell is not as tall as the reference window: its y is not the window's from the top")
        let home = CGRect(x: inWindow.minX, y: reference.frame.height - inWindow.maxY,
                          width: inWindow.width, height: inWindow.height)

        rig.shell.sidebarCollapsed = true
        XCTAssertTrue(rig.shell.sidebarCollapsed, "the sidebar did not fold")
        settle()
        let obstacle = ShellWindowButtons.obstacle(ShellWindowButtons.placement(home: home, rail: true))
        XCTAssertFalse(obstacle.isNull || obstacle.isEmpty, "the owner's obstacle for \(home) is \(obstacle): nothing to compare with")
        let want = shell.convert(obstacle, to: bar)
        let folded = bar.place.buttons
        XCTAssertFalse(folded.isNull, "the folded bar was handed no obstacle")
        for (got, wanted, what) in [(folded.minX, want.minX, "minX"), (folded.maxX, want.maxX, "maxX"),
                                    (folded.minY, want.minY, "minY"), (folded.maxY, want.maxY, "maxY")] {
            XCTAssertEqual(got, wanted, accuracy: 0.5, "the folded bar's \(what) is not the owner's obstacle \(want): it holds \(folded)")
        }
        guard let name = bar.view(for: .name) else {
            XCTFail("the bar has no name view")
            return
        }
        XCTAssertGreaterThanOrEqual(name.frame.minX, folded.maxX + ShellBarLayout.obstacleClearance - 0.5,
                                    "the name \(name.frame) starts under the obstacle ending at \(folded.maxX)")
    }
}
