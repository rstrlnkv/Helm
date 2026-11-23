import AppKit
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// An object that outlives its window is memory that grows with every open: the owner's `leaks` run found one window state with its icon
/// cache (a hundred icons and all their reps) kept per open, held by SwiftUI's hover and context-menu responders through the closures a tile
/// was given. After the window has closed and been let go, neither the state nor its icons may be alive. Runs the real panel off the screens (far
/// away; the first test at the full geometry size, so the tiles are laid out and their menus asked for, the second 40 points square) over the rig's
/// catalog, with the tiles drawn (a snapshot loaded) before it closes in the first.
@MainActor
final class AClosedLaunchpadWindowLeavesNothingOfItselfBehindTests: XCTestCase {
    override func setUp() async throws { _ = NSApplication.shared }

    private struct Gone { var state: Bool; var icons: Bool; var window: Bool }

    /// One open and close, then what is still alive; the strong references are all local, so they end with this call.
    private func session(_ rig: LaunchpadRig) async -> (weakState: WeakBox<LaunchpadScreenState>, weakIcons: WeakBox<LaunchpadIcons>, weakWindow: WeakBox<LaunchpadWindow>) {
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        let state0 = panel.state!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: state0.geometry.size.width, height: state0.geometry.size.height), display: false)
        let state = panel.state!
        let boxes = (WeakBox(state), WeakBox(state.icons), WeakBox(window))
        window.present()
        for _ in 0..<40 where state.pages.first?.isEmpty != false { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(state.pages.first?.isEmpty, false, "the control: the tiles were drawn from a snapshot before the window closed")
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        // The menus are asked for as the panel asks on a right click (the state's description, built as an `NSMenu`), without tracking one.
        var asked = 0
        for y in stride(from: 100.0, to: state.geometry.size.height - 100, by: 40) {
            for x in stride(from: 100.0, to: state.geometry.size.width - 100, by: 60) {
                if let menu = state.menu(at: CGPoint(x: x, y: y)) {
                    _ = LaunchpadNSMenu.make(menu) { [weak state] in state?.perform($0) }
                    asked += 1
                }
            }
        }
        XCTAssertGreaterThan(asked, 0, "the control: a tile has a menu to ask for")
        try? await Task.sleep(for: .milliseconds(300))
        window.close()
        try? await Task.sleep(for: .milliseconds(600))
        return boxes
    }

    func testTheWindowStateAndItsIconsAreGoneAfterEveryOpenAndClose() async {
        let rig = LaunchpadRig(self, label: "window-lifetime")
        var kept: [(WeakBox<LaunchpadScreenState>, WeakBox<LaunchpadIcons>, WeakBox<LaunchpadWindow>)] = []
        for _ in 0..<3 {
            let one = await session(rig)
            kept.append((one.weakState, one.weakIcons, one.weakWindow))
        }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(kept.filter { $0.2.value != nil }.count, 0, "the window is let go once it has closed")
        XCTAssertEqual(kept.filter { $0.0.value != nil }.count, 0, "a window state outlived its window: a closure SwiftUI keeps holds it")
        XCTAssertEqual(kept.filter { $0.1.value != nil }.count, 0, "an icon cache outlived its window")
    }

    func testTheIconsAWindowDrewAreDroppedWhenItsPictureIsTakenDown() async {
        let rig = LaunchpadRig(self, label: "window-icons")
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: 40, height: 40), display: false)
        let icons = panel.state!.icons
        window.present()
        // The icon is drawn off main and lands later: ask until it has.
        var drawn: NSImage?
        await waitUntil("the icon was drawn while the window is open") { drawn = icons.image(for: "/Applications/a.app", side: 64); return drawn != nil }
        XCTAssertTrue(drawn === icons.image(for: "/Applications/a.app", side: 64), "the control: the cache keeps an icon while the window is open")
        window.close()
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertNil(icons.image(for: "/Applications/a.app", side: 64), "the cache still held an icon after the window was taken down")
    }
}

private struct WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
