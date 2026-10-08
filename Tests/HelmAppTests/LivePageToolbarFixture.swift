import XCTest
import AppKit
import SwiftUI
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// **A page mounted in a window that holds the Settings window's real page bar** — the fixture the
/// Homebrew integration tests and the bar's readings share.
///
/// `MountedRender`'s window holds the page and nothing else: it has no bar, so a page's
/// `helmWindowToolbar` declaration reaches nobody. This adds a `MountedPageBar` to that window, listening
/// on the same `channel` the page was mounted with, so the page's tabs, actions and search arrive in the
/// bar's zones as they do in the real window. `HelmTestSupport` may not reach `HelmApp` (`Package.swift`'s
/// own "support may reach the shared plumbing, nothing may reach support"), which is why the fixture lives
/// in `HelmAppTests`, per `CLAUDE.md`'s "app-layer checks in `Tests/HelmAppTests`".
///
/// `selection` is set before the bar is constructed: the bar refreshes from `model.selection` in its
/// initialiser, so its first refresh already reads the page this fixture was built for. No `settle()` has
/// run by then; what the page declares later reaches the bar through the channel.
///
/// The bar reads four settings when it is built and its tabs zone reads a fifth,
/// `AppSettings.toolbarSwitcherStyle` (`MountedPageBar`'s own doc); a family that depends on one
/// pins it before building the fixture. Each bar's search zone holds an event monitor until it is
/// released, so a fixture is dropped in `tearDown`.
@MainActor
struct LivePageToolbarFixture {
    let mount: MountedRender
    let pageBar: MountedPageBar
    let model: SettingsModel
    let channel: HelmWindowToolbarChannel

    var bar: ShellPageBar { pageBar.bar }

    init<V: View>(_ view: V, selection: SettingsSelection, width: CGFloat, height: CGFloat,
                 appearance: NSAppearance.Name = .aqua, titlebarIsTransparent: Bool = true) {
        let channel = HelmWindowToolbarChannel()
        let model = SettingsModel(host: ModuleHost.shared)
        model.selection = selection
        let mount = MountedRender(view, width: width, height: height,
                                  appearance: appearance, channel: channel)
        self.mount = mount
        self.pageBar = MountedPageBar(model: model, channel: channel, in: mount.window,
                                      titlebarIsTransparent: titlebarIsTransparent)
        self.model = model
        self.channel = channel
    }

    /// Settles the page and lays the bar out after every turn, so a reading of the bar's frames sees the
    /// zones where the page's latest declaration put them.
    func settle(_ turns: Int = 25) {
        for _ in 0..<turns {
            pageBar.layout()
            mount.settle(1)
        }
        pageBar.layout()
    }

    func drop() {
        pageBar.remove()
        mount.drop()
    }
}

/// **The fixture's own check: the bar it builds is in a window, laid out, drawing, and hearing the page.**
/// A bar that is built and never added to a window still carries a name view (its first refresh draws the
/// page's identity), so a check that asks the bar itself finds something and cannot fail. The first
/// assertion walks down from the frame view of the mount's window and never asks the fixture for its bar;
/// the rest hold that what it found is the fixture's bar, that it has a size, that its
/// name draws, and that a page declared on the fixture's channel arrives in it.
@MainActor
final class LivePageToolbarFixtureTests: XCTestCase {
    private static let width: CGFloat = 600

    private func page() -> some View {
        Color.clear.frame(width: Self.width, height: 100)
            .helmWindowToolbar(
                HelmPageToolbarContent(
                    actions: [HelmToolbarAction(id: "refresh", title: "Refresh list",
                                                symbol: "arrow.clockwise") {}]),
                token: "general")
    }

    func testTheFixturesBarIsInTheWindow() {
        let fx = LivePageToolbarFixture(page(), selection: .general, width: Self.width, height: 400)
        defer { fx.drop() }
        fx.settle()

        // 1. Found from the window, not from the fixture.
        guard let root = fx.mount.window?.contentView?.superview else {
            XCTFail("the fixture's mount has no window")
            return
        }
        guard let found = root.everyView(ofType: ShellPageBarView.self).first else {
            XCTFail("the fixture's bar is in no window: every test built on it read an empty bar")
            return
        }

        // 2. It is the fixture's bar, at the window's width and the bar's height.
        XCTAssertTrue(found === fx.bar.view, "the bar in the window is not the fixture's bar")
        XCTAssertTrue(found.window === fx.mount.window, "the bar's window is not the fixture's window")
        XCTAssertEqual(found.frame.width, Self.width, "the bar is not as wide as the window")
        XCTAssertEqual(found.frame.height, ShellBarLayout.height, "the bar is not the bar's height")

        // 3. It has been laid out, and its name has room.
        XCTAssertNotNil(found.frames, "the bar was never laid out")
        XCTAssertTrue(found.reachableZones.contains(.name), "the bar holds no name")
        let name = found.view(for: .name)
        XCTAssertGreaterThan(name?.frame.width ?? 0, 0, "the name zone has no width")

        // 4. The name draws.
        if let name, let rep = name.bitmapImageRepForCachingDisplay(in: name.bounds) {
            name.cacheDisplay(in: name.bounds, to: rep)
            var inked = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                    inked += 1
                }
            }
            XCTAssertGreaterThan(inked, 0, "the name zone drew nothing")
        } else {
            XCTFail("the name zone cannot be photographed")
        }

        // 5. A page declared on the fixture's channel arrives.
        XCTAssertEqual(fx.bar.presentation, .page(key: "general", isLive: true, isDimmed: false),
                       "the page's declaration did not reach the fixture's bar")
        XCTAssertNotNil(found.view(for: .actions), "the page's action did not reach the bar")
    }
}
