import AppKit
import QuartzCore
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' tabs unfold across their fold point without a blink, on the toolbar the Settings window
/// wears.** Hosts' own declaration on its SSH tab (`HostsSettingsPage.toolbarContent`: the same two tabs,
/// the same two options with the same glyphs, `+` declared and hidden) is put on a real `SettingsToolbar`
/// and the detail pane is widened a point at a time through the tabs' fold point, in Russian and German,
/// in the words-only label style, under each look. The row finds the fold point itself and asserts what
/// happens on the way across it; no width in this file is a claim about today's bar, what the bar does is
/// what the row prints (`[hosts-unfold]`, one line per look and language whose precondition held).
///
/// **The bar.** A bare `SettingsToolbar(model:channel:)` on a split-view rig of its own, the default lead
/// `.sidebarSeparator`; not the app's window. The app builds `lead: .spacer` (`SettingsWindow.init`), whose
/// bar has a `helm.tabsLead` item and a capped search field this one has not, and the window's content is
/// never narrower than `SettingsWindow.minSize` (860 pt wide), so the rig's floor of 420 pt is not a
/// width a person can dial into that window; whether the fold point the row prints is above what the
/// window can reach is for that line to say. What the `.spacer` build does at its own fold is held in
/// `TheWindowWearsTheToolbarTests.testFoldedTabsUnfoldAtTheMarginAndNotBefore`.
///
/// **The look.** Read when a bar is built (`AppSettings.barAppearance`) and decides which cell draws the
/// tabs and the actions, so the fold point may move with the look; the sweep runs once per look on a
/// fresh rig per language, and each case says in its precondition which look the tabs item wears
/// (`ShellBarPlate` around the hosting view under Flat, the hosting view itself under Liquid Glass). The
/// rig of one case is let go of before the next look is written, because a look written reaches every
/// toolbar still alive (`.helmBarAppearanceChanged`).
///
/// **What the row asserts, from what it found.** The sweep goes up from the rig's floor, where the tabs
/// are folded (one segment), to the width the tabs have been whole at (two segments) for
/// `SettingsToolbar.unfoldMargin + 8` further points. Exactly one change of the segment count along the
/// way, 1 to 2; `gateRefusalsRecorded` where it started; and no item of the bar losing its `isVisible` at
/// or after the width the tabs unfolded at. Last in each case, a control: the window is made too narrow
/// for the whole tabs and the visibility watch must see an item lose its `isVisible`, because a watch
/// that cannot see one proves nothing about the sweep.
///
/// **What it cannot say.** `gateRefusalsRecorded` moves only when an eviction follows the toolbar's own
/// unfold within `SettingsToolbar.overflowAttributionWindow` (`checkOverflow()`), so "unchanged" alone
/// says nothing about an eviction that comes later or that no unfold of ours preceded; the visibility
/// watch stands beside it for that. An unfold, an eviction and a fold again inside one step leave the
/// segment count at one at the end of the step, so the width printed as folded can be one where an item
/// was lost; that list is printed (`evictions`), and the row asserts the refusal count and the losses
/// from the unfold on, not the losses before it. The sweep stops `unfoldMargin + 8` points after the
/// unfold, so a blink further up is not seen. And nothing here was seen in a window on a screen: the
/// window is never ordered in (a measurement rig that was ordered in put an empty window on the owner's
/// screen, see `AnUnfoldIsPredictedNeverTrialledTests.testTheMeasurementWindowNeverReachesTheScreen`), so
/// what AppKit does with a toolbar in a window that is shown is not what is read.
///
/// **Dated measurements of the bar they were taken on.** The row's first form was a repro (2026-09-25,
/// this Mac) written against the tree before `SettingsToolbar.segmentedReserveWidth(_:look:)` rounded a
/// `.segmented` entry's reserve up to a whole point: the reserve measured for Hosts' own Table /
/// Plain-text glyphs was 77.5 pt, so `helm.actions` was 117.5 pt wide on both of Hosts' tabs, a half
/// point. Widened from 420 pt in `.text` a point at a time, each width held 0.3 s, the fold prediction
/// unfolded the tabs at 430 pt (Russian) / 460 pt (German), AppKit evicted them and `gateRefusalsRecorded`
/// moved, the blink `AnUnfoldIsPredictedNeverTrialledTests` exists to rule out, and they unfolded for good
/// a point later. Measured then, 2 pt steps, same declaration, only the reserve overridden: 72.0, 78.0
/// and 80.0 (the reserve before that pass) unfold cleanly, at 426/456, 432/462 and 434/464; 77.5 blinks
/// every time, and a capsule of plain buttons at 112.0 pt unfolds cleanly too. So the blink followed the
/// half point. Not the rig's shared state: the same sweep with a re-declaration on every step (one extra
/// rig measurement each) recorded the same single refusal at the same pane. Seen red again (2026-09-26)
/// with the rounding taken out of the tree: one refusal each, at 430.0 pt (Russian) and 460.0 pt (German).
/// Swept wider on the rounded reserve (2026-09-26, `helm.actions` at 118.0 pt, a point at a time through
/// each unfold): in `.iconsAndText` Russian, English, French, Spanish and Portuguese from 420 pt, German
/// from 450 pt, no refusal anywhere; in `.text` only Russian and German were folded at the pane's 420 pt
/// minimum at all, which is why this file sweeps those two.
///
/// **Each step rests by the clock.** `settle(_:turns:)` alone returned in as little as 29 ms a step on
/// that bar (`run(mode:before:)` returns on the first source it serves), and the settle that runs the
/// prediction fires `SettingsToolbar.settleInterval` (0.1 s) after the last resize, so a step shorter
/// than that is cancelled by the next one and the prediction is never asked at that width: the same
/// sweep at 8 turns a step read no refusal at all. `restPerStep` says why it is 0.3 s.
@MainActor
final class HostsTabsUnfoldWithoutABlinkTests: XCTestCase {

    /// The rig's sidebar width, as `AnUnfoldIsPredictedNeverTrialledTests` has it. The app's own default is
    /// `ShellGeometry.defaultSidebarWidth` (200); the app's window is not this rig, and the pane widths
    /// this file prints are this rig's detail pane.
    private static let sidebarWidth: CGFloat = 214
    /// The narrowest pane the rig can be laid out at: the detail item's `minimumThickness` in `mountSplit`.
    /// The sweep starts there so that the tabs are folded at its first width (asserted per case, out
    /// loud, not assumed).
    private static let floor: CGFloat = 420
    /// The widest pane the sweep goes to, folded or whole. The window's content is never narrower than
    /// `SettingsWindow.minSize` (860 pt), which beside this rig's sidebar leaves a pane of 646 pt; 720 is
    /// that plus the `unfoldMargin + 8` points kept after an unfold and 50 more. Tabs still folded or not
    /// yet stable there fail the case with their own sentence: a fold point that high is a finding, and a
    /// point costs `restPerStep`, so every point further out is 0.3 s more in each case that fails.
    private static let ceiling: CGFloat = 720
    /// How long each width is held. Longer than `SettingsToolbar.settleInterval` is not enough: at 0.15 s a
    /// step, the tabs unfolded at 430 pt and the next step's resize arrived before AppKit's own eviction
    /// did, so the same tree read clean; at 0.3 s AppKit evicted at 430 pt every time (on the bar the
    /// header's dated measurements were taken on). A width someone's cursor stops at is held for longer
    /// than either.
    private static let restPerStep: TimeInterval = 0.3
    /// A point at a time: the window's own frame lands on the whole point (644.5 asked, 645.0 read,
    /// 2026-09-26), so a point is the finest step this sweep can take.
    private static let step: CGFloat = 1
    /// Points the tabs must stay whole for after the unfold before the sweep ends, past the margin
    /// `settle(_:)` requires of the room before it unfolds at all.
    private static let wholePoints = Int(SettingsToolbar.unfoldMargin) + 8
    /// The languages whose tabs were folded at the pane's floor in the words-only label style, by the
    /// header's dated measurement (2026-09-26, on the bar of that day). The other languages were not read
    /// on today's bar under either look, so whether their tabs are whole at the floor is not claimed;
    /// where they are, the precondition fails for them. On 2026-10-13 the bar folded the tabs up to a
    /// wider pane under Flat than under Liquid Glass (Russian 466 against 425 pt, German 496 against
    /// 455 pt: the "folded up to" widths of the `[hosts-unfold]` lines of a run of this file on this
    /// Mac), so the header's measurement does not carry over to that bar.
    private static let languages: [AppLanguage] = [.ru, .de]

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

    /// A split-view rig, so `offeredRoom()` reads a detail pane and the fold is the rig's. Never ordered on
    /// screen (see the header).
    private func mountSplit(pane: CGFloat) -> Rig {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let detail = NSViewController()
        detail.view = NSView(frame: NSRect(x: 0, y: 0, width: pane, height: 700))
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = Self.floor
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

    /// What the tabs item's view says of the look the bar was built under: a `ShellBarPlate` under Flat, the
    /// hosting view under Liquid Glass. Nil when the bar has no tabs item. Folded or whole alike, the item's
    /// view is the same one (`SettingsToolbar.makeTabsItem`).
    private func lookDrawn(_ window: NSWindow) -> HelmBarAppearance? {
        guard let view = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "helm.tabs" })?.view
        else { return nil }
        return view is ShellBarPlate ? .flat : .liquidGlass
    }

    /// Every `isVisible` going false on the items of the bar attached when the watch started, with the pane
    /// the sweep had asked for when it did (`pane`, which the sweep sets before each step and the control
    /// sets to zero).
    @MainActor private final class VisibilityWatch {
        var pane: CGFloat = 0
        private(set) var lost: [(pane: CGFloat, item: String)] = []
        private var kvo: [NSKeyValueObservation] = []

        init(_ toolbar: NSToolbar) {
            for item in toolbar.items {
                let name = item.itemIdentifier.rawValue
                kvo.append(item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                    guard change.newValue == false else { return }
                    MainActor.assumeIsolated { if let self { self.lost.append((self.pane, name)) } }
                })
            }
        }

        func stop() { kvo = [] }
    }

    private struct Reading {
        let pane: CGFloat
        let segments: Int
        let refusals: Int
    }

    /// **One look and one language.** The precondition, the sweep, the `[hosts-unfold]` line, the three
    /// assertions and the control, in that order; a case whose precondition or sweep fails says so and does
    /// not go on to assert about a sweep that did not happen.
    private func sweepHosts(look: HelmBarAppearance, language: AppLanguage) {
        let label = "\(look.rawValue) \(language.rawValue)"
        let rig = mountSplit(pane: Self.floor)
        defer { rig.window.toolbar = nil }
        guard let bar = rig.window.toolbar else { return XCTFail("\(label): no toolbar attached") }
        settle(rig.window, turns: 30)
        XCTAssertEqual(lookDrawn(rig.window), look, """
            \(label) precondition: the tabs item wears \
            \(lookDrawn(rig.window).map { String(describing: $0) } ?? "no view at all"), not the look the bar \
            was built under — the fold point below would be read under the wrong cell
            """)
        guard segmentCount(bar) == 1 else {
            return XCTFail("""
                \(label) precondition: Hosts' tabs read \(segmentCount(bar).map(String.init) ?? "no segments") \
                at \(Self.floor) pt, not one, so a sweep upward from here crosses no fold point
                """)
        }
        let before = rig.toolbar.gateRefusalsRecorded
        let watch = VisibilityWatch(bar)
        defer { watch.stop() }
        var readings = [Reading(pane: Self.floor, segments: 1, refusals: before)]
        var refusedAt: [CGFloat] = []
        var pane = Self.floor
        var wholeRun = 0
        while pane < Self.ceiling && wholeRun <= Self.wholePoints {
            pane += Self.step
            watch.pane = pane
            rig.window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
            rest(rig.window, seconds: Self.restPerStep)
            let reading = Reading(pane: pane, segments: segmentCount(bar) ?? 0,
                                  refusals: rig.toolbar.gateRefusalsRecorded)
            if reading.refusals != readings[readings.count - 1].refusals { refusedAt.append(pane) }
            readings.append(reading)
            wholeRun = reading.segments == 2 ? wholeRun + 1 : 0
        }

        let unfoldedAt = wholeRun > 0 ? readings[readings.count - wholeRun].pane : nil
        let foldedUpTo = readings.last { $0.segments == 1 && $0.pane < (unfoldedAt ?? .infinity) }?.pane
        let evictions = watch.lost.map { "\(Int($0.pane)):\($0.item)" }
        let cell: (CGFloat?) -> String = { $0.map { String(Int($0)) } ?? "never" }
        print("[hosts-unfold] look=\(look.rawValue) language=\(language.rawValue) "
              + "folded up to \(cell(foldedUpTo)) unfolded from \(cell(unfoldedAt)) "
              + "refusals \(rig.toolbar.gateRefusalsRecorded - before) "
              + "evictions \(evictions.isEmpty ? "none" : evictions.joined(separator: ","))")

        guard wholeRun > Self.wholePoints, let unfoldedAt else {
            let spoken = readings.contains { $0.segments == 2 }
                ? "unfolded but did not stay whole for \(Self.wholePoints) points"
                : "never unfolded"
            return XCTFail("""
                \(label): Hosts' tabs \(spoken) up to \(pane) pt (ceiling \(Self.ceiling), floor \(Self.floor)) \
                — the refusal and eviction readings below are about no unfold
                """)
        }

        let changes = zip(readings, readings.dropFirst()).filter { $0.segments != $1.segments }
            .map { "\($0.segments) to \($1.segments) at \(Int($1.pane))" }
        XCTAssertEqual(changes.count, 1, """
            \(label): the segment count changed \(changes.count) times along the sweep from \(Self.floor) pt: \
            \(changes) — the tabs did not fold once and stay whole
            """)
        XCTAssertEqual(rig.toolbar.gateRefusalsRecorded, before, """
            \(label): widening Hosts' pane from \(Self.floor) pt unfolded the tabs into an eviction at \
            \(refusedAt) pt — the tabs blink open and shut before they stay
            """)
        let after = watch.lost.filter { $0.pane >= unfoldedAt }
        XCTAssertTrue(after.isEmpty, """
            \(label): an item of the bar lost its visibility at or after \(Int(unfoldedAt)) pt, where the tabs \
            unfolded for good: \(after.map { "\(Int($0.pane)):\($0.item)" })
            """)

        // The control, last because it leaves the bar changed: the whole tabs in a window made too narrow
        // for them. The watch must see an item lose its visibility, or the absences above are about a deaf
        // watch. The pane is zero in the list, which is how it is told from the sweep.
        let lostBefore = watch.lost.count
        watch.pane = 0
        rig.window.setContentSize(NSSize(width: 120, height: 700))
        rest(rig.window, seconds: 2 * Self.restPerStep)
        XCTAssertGreaterThan(watch.lost.count, lostBefore, """
            \(label): the watch saw no item lose its visibility when the window was made 120 pt wide with the \
            tabs whole — the absences above are about a deaf watch
            """)
        _ = rig.keepAlive
    }

    func testHostsTabsUnfoldAcrossTheirFoldPointWithoutABlink() {
        PinnedBarSettings.pin(in: self)
        for look in HelmBarAppearance.allCases {
            AppSettings.barAppearance = look
            for language in Self.languages {
                AppLanguage.only(language) { sweepHosts(look: look, language: language) }
            }
        }
    }
}
