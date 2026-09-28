import AppKit
import QuartzCore
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' tabs unfold across their fold point without a blink.** Guards the
/// whole-point rounding in `SettingsToolbar.segmentedReserveWidth(_:)`: a
/// `.segmented` entry's reserve is rounded up to the next whole point, so
/// `helm.actions` never stands half a point wide.
///
/// Written as a repro (tester, 2026-09-25) against the tree before that
/// rounding, in the default label style. The reserve measured for Hosts' own
/// Table / Plain-text glyphs was 77.5 pt, so `helm.actions` was 117.5 pt wide
/// on both of Hosts' tabs — a half point. Widened from 420 pt in `.text`
/// (the style nothing stored reads as) a point at a time, each width held
/// 0.3 s, the fold prediction unfolded the tabs at 430 pt (Russian) / 460 pt
/// (German), AppKit evicted them and `gateRefusalsRecorded` moved — the blink
/// `AnUnfoldIsPredictedNeverTrialledTests` exists to rule out — and they
/// unfolded for good a point later. Measured then on this Mac, 2 pt steps,
/// same declaration, only the reserve overridden: 72.0, 78.0 and 80.0 (the
/// reserve before that pass) unfold cleanly, at 426/456, 432/462 and
/// 434/464; 77.5 blinks every time, and a capsule of plain buttons at
/// 112.0 pt unfolds cleanly too. So the blink follows the half point. Not
/// the rig's shared state: the same sweep with a re-declaration on every
/// step (one extra rig measurement each) records the same single refusal at
/// the same pane. Seen red again (tester, 2026-09-26) with the rounding taken
/// out of the tree it guards: one refusal each, at 430.0 pt (Russian) and
/// 460.0 pt (German).
///
/// **Swept wider on the rounded reserve** (tester, 2026-09-26, this Mac,
/// `helm.actions` at 118.0 pt, a point at a time through each unfold): in
/// `.iconsAndText` — Russian, English, French, Spanish and Portuguese from
/// 420 pt, German from 450 pt — no refusal anywhere, Russian's and French's
/// full tabs included, which are a whole 198.0 and 180.0 pt rather than a
/// half; in `.text` only Russian and German are folded at the pane's 420 pt
/// minimum at all, which is why this file sweeps those two. A 0.5 pt step
/// does not sweep half points here: the window's own frame lands on the whole
/// point (644.5 asked, 645.0 read), so a point is the finest step this sweep
/// can take.
///
/// **Not a width the real window reaches today.** 420 pt is
/// `NSSplitViewItem.minimumThickness`'s own declared floor on the detail
/// pane, mirrored here in `mountSplit`'s own rig — `SettingsWindow.swift`
/// sets the window's own `contentMinSize` to 860 × 540 and the sidebar's own
/// maximum to 320 pt
/// (`command grep -n 'minSize = \|sidebarMaximum: \|detailItem.minimumThickness' Sources/HelmApp/SettingsWindow.swift`),
/// so the pane a person can actually narrow the real window to bottoms out at
/// 860 − 320 = 540 pt, above the whole 420–500 pt range this file sweeps. The
/// guard stays — `minimumThickness` is the pane's own declared floor, and
/// this file is what proves the tabs do not blink if that floor is ever
/// reached; how AppKit weighs it against the window's own limits on a resize
/// is not measured here — but nothing swept below should be read as a width
/// a person can dial into today's window.
///
/// **Each step rests by the clock.** `settle(_:turns:)` alone returned in as
/// little as 29 ms a step here — `run(mode:before:)` returns on the first
/// source it serves — and the settle that runs the prediction fires
/// `SettingsToolbar.settleInterval` (0.1 s) after the last resize, so a step
/// shorter than that is cancelled by the next one and the prediction is never
/// asked at that width: the same sweep at 8 turns a step read no refusal at
/// all. `restPerStep` says why it is 0.3 s: holding a width for that long is
/// what stands in for someone resting the window's edge there, or letting go
/// of it there, once the pane can actually reach it.
///
/// The declaration is Hosts' own on its SSH tab
/// (`HostsSettingsPage.toolbarContent`): the same two tabs, the same two
/// options with the same glyphs, `+` declared and hidden. The split-view
/// window is `AnUnfoldIsPredictedNeverTrialledTests.mountSplit`'s.
@MainActor
final class HostsTabsUnfoldWithoutABlinkTests: XCTestCase {

    private static let sidebarWidth: CGFloat = 214
    /// How long each width is held. Longer than `SettingsToolbar.settleInterval`
    /// is not enough: at 0.15 s a step, the tabs unfolded at 430 pt and the
    /// next step's resize arrived before AppKit's own eviction did, so the
    /// same tree read clean; at 0.3 s AppKit evicted at 430 pt every time. A
    /// width someone's cursor stops at, once the pane can reach it, is held
    /// for longer than either.
    private static let restPerStep: TimeInterval = 0.3

    private func hostsOnSSH() -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "keys", title: HostsStr.keysTab, symbol: "key"),
                   HelmToolbarTab(id: "ssh", title: HostsStr.sshHostsTab, symbol: "server.rack")],
            selectedTab: .constant("ssh"),
            actions: [
                HelmToolbarAction(id: "viewMode", title: HostsStr.viewGroup, isVisible: true, options: [
                    HelmToolbarTab(id: "table", title: HostsStr.tableView, symbol: "tablecells"),
                    HelmToolbarTab(id: "text", title: HostsStr.textView, symbol: "text.alignleft"),
                ], selection: .constant("table")),
                HelmToolbarAction(id: "newKey", title: HostsStr.newKey, symbol: "plus", isVisible: false) {},
            ])
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let keepAlive: [AnyObject]
    }

    private func mountSplit(pane: CGFloat) -> Rig {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let detail = NSViewController()
        detail.view = NSView(frame: NSRect(x: 0, y: 0, width: pane, height: 700))
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420
        let sidebar = NSViewController()
        sidebar.view = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: 700))
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        sidebarItem.allowsFullHeightLayout = true
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
        window.orderBack(nil)
        window.layoutIfNeeded()
        split.splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
        window.layoutIfNeeded()
        toolbar.window = window
        model.selection = .module("test.hostsBlink")
        channel.declare(hostsOnSSH(), token: "test.hostsBlink", generation: channel.nextGeneration())
        window.layoutIfNeeded()
        return Rig(window: window, toolbar: toolbar, keepAlive: [model, channel, split])
    }

    private func settle(_ window: NSWindow, turns: Int) {
        for _ in 0..<turns {
            window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// Turns the run loop for `seconds` by the clock — see this file's header.
    private func rest(_ window: NSWindow, seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until { settle(window, turns: 1) }
    }

    private func segmentCount(_ toolbar: NSToolbar) -> Int? {
        toolbar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" }?.view?
            .everyView(ofType: NSSegmentedControl.self).first?.segmentCount
    }

    func testHostsTabsUnfoldAcrossTheirFoldPointWithoutABlink() {
        // Raw, so a key the domain did not hold is removed again rather than
        // written back as the typed getter's default. The page-bar style is
        // pinned as well: the fold point below is `moduleName`'s, and with
        // `windowTitle` left in the test tool's own domain the precondition
        // read two segments at 420 pt, not one (2026-09-28).
        let store = AppSettings.store
        let found = store.object(ToolbarSwitcherStyle.storageKey)
        let foundBar = store.object(PageBarStyle.storageKey)
        addTeardownBlock { @MainActor in
            store.set(found, for: ToolbarSwitcherStyle.storageKey)
            store.set(foundBar, for: PageBarStyle.storageKey)
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
            NotificationCenter.default.post(name: .helmPageBarStyleChanged, object: nil)
        }
        AppSettings.toolbarSwitcherStyle = .text
        AppSettings.pageBarStyle = .moduleName
        for language: AppLanguage in [.ru, .de] {
            AppLanguage.only(language) {
                let rig = mountSplit(pane: 420)
                defer { rig.window.orderOut(nil); rig.window.toolbar = nil }
                guard let bar = rig.window.toolbar else { return XCTFail("\(language): no toolbar attached") }
                settle(rig.window, turns: 30)
                XCTAssertEqual(segmentCount(bar), 1, """
                    \(language) precondition: Hosts' tabs are not folded at 420 pt, so a sweep upward from \
                    here crosses no fold point
                    """)
                let before = rig.toolbar.gateRefusalsRecorded
                var refusedAt: [CGFloat] = []
                var pane: CGFloat = 420
                while pane < 500 {
                    pane += 1
                    rig.window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
                    let refusals = rig.toolbar.gateRefusalsRecorded
                    rest(rig.window, seconds: Self.restPerStep)
                    if rig.toolbar.gateRefusalsRecorded != refusals { refusedAt.append(pane) }
                }
                XCTAssertEqual(segmentCount(bar), 2, """
                    \(language) precondition: Hosts' tabs never unfolded by 500 pt — the refusal count below \
                    cannot tell a clean unfold from none
                    """)
                XCTAssertEqual(rig.toolbar.gateRefusalsRecorded, before, """
                    \(language): widening Hosts' pane from 420 to 500 pt unfolded the tabs into an eviction at \
                    \(refusedAt) pt — the tabs blink open and shut before they stay
                    """)
                _ = rig.keepAlive
            }
        }
    }
}
