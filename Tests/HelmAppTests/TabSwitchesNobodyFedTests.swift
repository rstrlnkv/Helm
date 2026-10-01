import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Homebrew_Engine
@testable import Module_Homebrew_UI
import Module_Hosts_Engine
@testable import HelmApp

/// **The tab switches `EveryTabSwitchIsACutTests` does not reach, and the states
/// it does not feed the pages it does reach.** The owner's rule is the same one
/// that file holds — «вкладки везде переключаются резко», 2026-09-30 — and every
/// case here is judged by the same instrument (`FrameRecorder`: the drawing
/// before and after must differ, and no frame after one grace turn may differ
/// from the settled one), in a named appearance.
///
/// What the shared guard cannot see, and this file feeds:
///
/// - **The Log page**, which is not in `ModuleRegistry` and so is never mounted
///   there, though it declares All / Warnings / Errors into the same toolbar.
/// - **Homebrew with the console open, with outdated packages, with a selection
///   below `HomebrewSplit`'s threshold** — the three states in which the page's
///   two remaining curves (`showsConsole`, `hb.selected == nil`) could ride a
///   switch. The shared fixture has no outdated package, no console line, and is
///   drawn wide only.
/// - **Hosts with its SSH strip open** — the strip is a measured accordion on
///   `HelmMotion.disclosure` whose height is forgotten when the SSH tab is left.
/// - **Twice in a row**: a second switch landing one turn after the first, and
///   there-and-back inside one turn.
/// - **The menu-bar panel's own tabs**, which are not a page's toolbar tabs at
///   all and are switched by a press on the tab strip or by ⌘1…⌘9.
@MainActor
final class TabSwitchesNobodyFedTests: XCTestCase {

    private static let width: CGFloat = 984
    private static let height: CGFloat = 700
    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]
    /// The menu-bar panel from 44 pt down to the bottom of its 520 pt window:
    /// under the strip, whose plate slides, with margin for the plate's shadow.
    private static let belowThePanelsStrip = 44...520

    private static func pump(_ view: NSView, turns: Int) {
        for _ in 0..<turns {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// Wall-clock pumping, for the Log page, which reads its source on a
    /// one-second tick.
    private static func pump(_ view: NSView, seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// One change, photographed from the moment before `act` and judged.
    private func photographed(_ host: NSView, _ label: String, named: String,
                              holding transport: FixtureTransport? = nil,
                              band: ClosedRange<Int>? = nil,
                              act: () -> Void) throws {
        let before = try XCTUnwrap(RenderedInk.bytes(host, points: band), "\(label): the view drew nothing")
        transport?.hold()
        defer {
            transport?.release()
            Self.pump(host, turns: 40)
        }
        let began = Date()
        act()
        let shots = try FrameRecorder.photograph(host, band: band, since: began)
        FrameRecorder.write(shots, of: host, named: named)
        try FrameRecorder.judge(shots, before: before, label)
    }

    // MARK: - The Log page

    /// A log with all three levels, so each of the three tabs has lines of its
    /// own and a switch between any two of them changes the list.
    private static func threeLevelLog() -> [LogEntry] {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return (0..<300).map { index in
            let level: LogLevel = index % 5 == 4 ? .error : (index % 2 == 1 ? .warn : .info)
            return LogEntry(date: start.addingTimeInterval(Double(index)), level: level,
                            category: "app", message: "line \(index)")
        }
    }

    private static func mountLog(_ lines: [LogEntry], _ appearance: NSAppearance.Name)
        -> (MountedRender, HelmWindowToolbarChannel) {
        let channel = HelmWindowToolbarChannel()
        let mount = MountedRender(LogView(source: { lines }, storedLog: { false }),
                                  width: 810, height: height, appearance: appearance,
                                  channel: channel)
        pump(mount.host, seconds: 1.5)
        return (mount, channel)
    }

    /// **All, Warnings, Errors: every switch between them, both ways, in both
    /// appearances** — and a second log where Errors is empty, so one direction
    /// of the switch unmounts the list for the empty state.
    func testTheLogsLevelTabsCut() throws {
        let withErrors = Self.threeLevelLog()
        let withoutErrors = withErrors.filter { $0.level != .error }
        for (name, lines) in [("errors", withErrors), ("noerrors", withoutErrors)] {
            for appearance in Self.appearances {
                let (mount, channel) = Self.mountLog(lines, appearance)
                let screen = RenderedInk.label(of: appearance)
                let content = try XCTUnwrap(channel.content(for: "log"),
                                            "\(screen): the Log page declared nothing")
                let tabs = try XCTUnwrap(content.selectedTab, "\(screen): the Log page declared no tabs")
                XCTAssertEqual(content.tabs.map(\.id), ["all", "warn", "error"])
                for (from, to) in [("all", "warn"), ("warn", "error"), ("error", "all"),
                                   ("all", "error"), ("error", "warn"), ("warn", "all")] {
                    XCTAssertEqual(tabs.wrappedValue, from, "\(screen) \(name): the walk lost its place")
                    try photographed(mount.host, "\(screen), log(\(name)) \(from) → \(to)",
                                     named: "log-\(name)-\(from)-\(to)-\(appearance.rawValue)") {
                        tabs.wrappedValue = to
                    }
                    Self.pump(mount.host, seconds: 0.3)
                }
            }
        }
    }

    /// **Twice in a row on the Log**: Warnings, and one turn later Errors — the
    /// second switch lands while the first could still be on its way.
    func testTheLogSwitchedTwiceInARowSettlesAtOnce() throws {
        for appearance in Self.appearances {
            let (mount, channel) = Self.mountLog(Self.threeLevelLog(), appearance)
            let screen = RenderedInk.label(of: appearance)
            let tabs = try XCTUnwrap(channel.content(for: "log")?.selectedTab)
            try photographed(mount.host, "\(screen), log all → warn → error, a turn apart",
                             named: "log-twice-\(appearance.rawValue)") {
                tabs.wrappedValue = "warn"
                Self.pump(mount.host, turns: 1)
                tabs.wrappedValue = "error"
            }
        }
    }

    // MARK: - There and back inside one turn

    /// **A switch undone before the page drew it draws nothing.** Not judged by
    /// `FrameRecorder.judge`, whose first assertion is that the drawing changed:
    /// here the subject is that it did *not*, so the case asserts first that the
    /// same switch taken alone does change the page.
    func testThereAndBackInOneTurnDrawsNothing() throws {
        for appearance in Self.appearances {
            let (mount, channel) = Self.mountLog(Self.threeLevelLog(), appearance)
            let screen = RenderedInk.label(of: appearance)
            let tabs = try XCTUnwrap(channel.content(for: "log")?.selectedTab)
            let before = try XCTUnwrap(RenderedInk.bytes(mount.host))
            // The subject: Warnings alone is a different drawing.
            tabs.wrappedValue = "warn"
            Self.pump(mount.host, seconds: 0.5)
            XCTAssertNotEqual(try XCTUnwrap(RenderedInk.bytes(mount.host)), before,
                              "\(screen): Warnings drew the same page as All, so the round trip proves nothing")
            tabs.wrappedValue = "all"
            Self.pump(mount.host, seconds: 0.5)
            let rested = try XCTUnwrap(RenderedInk.bytes(mount.host))

            let began = Date()
            tabs.wrappedValue = "warn"
            tabs.wrappedValue = "all"
            let shots = try FrameRecorder.photograph(mount.host, since: began)
            FrameRecorder.write(shots, of: mount.host, named: "log-roundtrip-\(appearance.rawValue)")
            let off = shots.enumerated().filter { $0.element.pixels != rested }
                .map { "#\($0.offset)@\(Int($0.element.at * 1000))ms" }
            print("[frames] \(screen), log all → warn → all in one turn: \(off.count)/\(shots.count) off the rest \(off)")
            XCTAssertEqual(off.count, 0, "\(screen): a switch undone in the same turn drew \(off.count) frames")
        }
    }

    // MARK: - Homebrew under the states the shared fixture does not reach

    private static let stale = OutdatedPackage(name: "fixture-formula", installed: "1.2.3",
                                               latest: "1.3.0", isCask: false, pinned: false)

    /// The shared fixture, plus outdated packages and one console line.
    private static let brewWiring: ModulePageRender.Wiring = { id in
        var wire = ModulePageRender.answering(id)
        if id == HomebrewDescriptor.id.rawValue {
            wire.answers(HomebrewCommand.outdated, with: [stale])
            wire.says(HomebrewEvent.opLog, "==> Pouring fixture-formula")
        }
        return wire
    }

    private static func mountBrew(_ appearance: NSAppearance.Name, width: CGFloat)
        throws -> (ModulePageRender.Page, HomebrewViewModel, Binding<String>) {
        let descriptor = try XCTUnwrap(ModuleRegistry.all.first { $0.idRaw == HomebrewDescriptor.id.rawValue })
        let channel = HelmWindowToolbarChannel()
        let page = ModulePageRender.page(for: descriptor, in: appearance, width: width,
                                         wiredBy: brewWiring, declaringTo: channel)
        page.host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        pump(page.host, turns: 40)
        let hb = HomebrewViewModel.shared(vm: page.viewModel)
        let tabs = try XCTUnwrap(channel.content(for: HomebrewDescriptor.id.rawValue)?.selectedTab,
                                 "Homebrew declared no segment switcher")
        // Every segment once, unphotographed: a segment's data is asked for when
        // it is shown and answers a few turns later (the shared guard's reason).
        for segment in ["updates", "health", "installed"] {
            tabs.wrappedValue = segment
            pump(page.host, turns: 40)
        }
        return (page, hb, tabs)
    }

    /// **The console open, an outdated package in Updates, every segment both
    /// ways.** `showsConsole` must not change on a switch, or the console curve
    /// rides it; this asserts that it is open throughout, then judges frames.
    func testHomebrewSegmentsCutWithTheConsoleOpenAndUpdatesPending() throws {
        for appearance in Self.appearances {
            let (page, hb, tabs) = try Self.mountBrew(appearance, width: Self.width)
            let screen = RenderedInk.label(of: appearance)
            XCTAssertFalse(hb.consoleLines.isEmpty, "\(screen): precondition: the console is not open")
            XCTAssertFalse(hb.outdated.isEmpty, "\(screen): precondition: Updates has no outdated package")
            for (from, to) in [("installed", "updates"), ("updates", "health"), ("health", "installed"),
                               ("installed", "health"), ("health", "updates"), ("updates", "installed")] {
                XCTAssertEqual(tabs.wrappedValue, from)
                try photographed(page.host, "\(screen), homebrew (console, outdated) \(from) → \(to)",
                                 named: "brew-console-\(from)-\(to)-\(appearance.rawValue)",
                                 holding: page.transport) { tabs.wrappedValue = to }
                XCTAssertFalse(hb.consoleLines.isEmpty, "\(screen): the console closed on \(from) → \(to)")
            }
        }
    }

    /// **Below the split, a selection swaps the whole pane** — and a segment
    /// switch from a segment with a selection to one without flips the pane from
    /// the package to the list. The shared fixture and the page's own case are
    /// drawn wide, where the same flip only changes the inspector.
    func testHomebrewSegmentsCutBelowTheSplitWithASelection() throws {
        var threshold: CGFloat = 0
        for width in stride(from: CGFloat(200), through: 1400, by: 1)
        where HomebrewSplit(availableWidth: width).showsInspector { threshold = width; break }
        XCTAssertGreaterThan(threshold, 0, "HomebrewSplit never shows the inspector")
        let narrow = threshold - 1
        for appearance in Self.appearances {
            let (page, hb, tabs) = try Self.mountBrew(appearance, width: narrow)
            let screen = RenderedInk.label(of: appearance)
            hb.select(try XCTUnwrap(hb.installed.first?.id, "no installed package to select"))
            Self.pump(page.host, turns: 40)
            XCTAssertNotNil(hb.selected, "precondition: nothing selected on Installed")
            try photographed(page.host, "\(screen), homebrew narrow installed (selected) → updates",
                             named: "brew-narrow-sel-installed-updates-\(appearance.rawValue)",
                             holding: page.transport) { tabs.wrappedValue = "updates" }
            XCTAssertNil(hb.selected, "\(screen): Updates carried a selection, so the pane did not swap")
            try photographed(page.host, "\(screen), homebrew narrow updates → installed (selected)",
                             named: "brew-narrow-sel-updates-installed-\(appearance.rawValue)",
                             holding: page.transport) { tabs.wrappedValue = "installed" }
            XCTAssertNotNil(hb.selected, "\(screen): the selection on Installed was lost")
            try photographed(page.host, "\(screen), homebrew narrow installed (selected) → health",
                             named: "brew-narrow-sel-installed-health-\(appearance.rawValue)",
                             holding: page.transport) { tabs.wrappedValue = "health" }
        }
    }

    /// **Twice in a row on Homebrew**, the second switch a turn after the first,
    /// with the console open.
    func testHomebrewSwitchedTwiceInARowSettlesAtOnce() throws {
        for appearance in Self.appearances {
            let (page, _, tabs) = try Self.mountBrew(appearance, width: Self.width)
            let screen = RenderedInk.label(of: appearance)
            try photographed(page.host, "\(screen), homebrew installed → updates → health, a turn apart",
                             named: "brew-twice-\(appearance.rawValue)", holding: page.transport) {
                tabs.wrappedValue = "updates"
                Self.pump(page.host, turns: 1)
                tabs.wrappedValue = "health"
            }
        }
    }

    // MARK: - Hosts with its SSH strip open

    /// `known_hosts` unreadable: the SSH tab's strip has a sentence and is open,
    /// and its measured height is forgotten each time the tab is left.
    private static let hostsWiring: ModulePageRender.Wiring = { id in
        var wire = ModulePageRender.answering(id)
        if id == HostsEngine.moduleID {
            wire.says(HostsEvent.state, HostsState(
                hostsText: "127.0.0.1 localhost\n",
                sshText: "Host alpha\n  HostName alpha.example\n",
                keys: [KeyRow(name: "id_fixture", hasPublicHalf: true, described: nil, modified: nil,
                              permission: .ok, publicText: nil, inAgent: false)],
                directoryPermission: .ok, agent: .empty,
                knownHostsText: "", knownHostsReadable: false,
                home: "/nowhere"))
        }
        return wire
    }

    func testHostsTabsCutWithTheSSHStripOpen() throws {
        for appearance in Self.appearances {
            let descriptor = try XCTUnwrap(ModuleRegistry.all.first { $0.idRaw == HostsEngine.moduleID })
            let channel = HelmWindowToolbarChannel()
            let page = ModulePageRender.page(for: descriptor, in: appearance, width: Self.width,
                                             wiredBy: Self.hostsWiring, declaringTo: channel)
            page.host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
            Self.pump(page.host, turns: 40)
            let screen = RenderedInk.label(of: appearance)
            let tabs = try XCTUnwrap(channel.content(for: HostsEngine.moduleID)?.selectedTab)
            let start = tabs.wrappedValue
            let other = start == "ssh" ? "keys" : "ssh"
            // Each tab once, unphotographed.
            tabs.wrappedValue = other; Self.pump(page.host, turns: 40)
            tabs.wrappedValue = start; Self.pump(page.host, turns: 40)
            for target in [other, start, other, start] {
                try photographed(page.host, "\(screen), hosts (strip open) → \(target)",
                                 named: "hosts-strip-\(target)-\(appearance.rawValue)",
                                 holding: page.transport) { tabs.wrappedValue = target }
            }
        }
    }

    // MARK: - The menu-bar panel's tabs

    /// **The panel's tab strip.** Two tabs, the utilities drawer on the first and
    /// nothing on the second, written into the app's store for the length of the
    /// case and put back as it was; the switch is ⌘2 and ⌘1, the shortcut the
    /// strip answers, delivered to the window the panel is drawn in.
    func testThePanelsTabsCut() throws {
        // The panel's own selection plate is allowed to slide — the owner kept
        // the toolbar switcher's the same way — and the content under it is not.
        // So the frame is the panel below the strip (26 pt capsule in a 12 pt
        // inset, 38 pt down), and it holds to the same zero: the card's height,
        // the footer and the grid are in it.
        let key = PanelLayoutStore.key
        let saved = AppSettings.store.object(key)
        // A teardown block, so the store is put back whether or not the case
        // reached its end.
        addTeardownBlock { @MainActor in AppSettings.store.set(saved, for: key) }
        let layout = PanelLayout(tabs: [
            PanelLayout.Tab(id: "tab.1", name: "One",
                            widgets: [PanelLayout.Slot(widget: HelmPanelContent.utilitiesWidget, size: .tall)],
                            glyph: "star"),
            PanelLayout.Tab(id: "tab.2", name: "Two", widgets: [], glyph: "circle"),
        ])
        AppSettings.store.set(try JSONEncoder().encode(layout), for: key)

        for appearance in Self.appearances {
            let mount = MountedRender(HelmPanelContent(host: ModuleHost.shared),
                                      width: helmPanelWidth, height: 520, appearance: appearance)
            let window = try XCTUnwrap(mount.window)
            NotificationCenter.default.post(name: .helmPanelDidShow, object: nil)
            Self.pump(mount.host, turns: 60)
            let screen = RenderedInk.label(of: appearance)
            for (digit, code, to) in [("2", UInt16(19), "tab.2"), ("1", UInt16(18), "tab.1"),
                                      ("2", UInt16(19), "tab.2"), ("1", UInt16(18), "tab.1")] {
                let press = try XCTUnwrap(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: digit,
                    charactersIgnoringModifiers: digit, isARepeat: false, keyCode: code))
                try photographed(mount.host, "\(screen), panel ⌘\(digit) → \(to)",
                                 named: "panel-\(to)-\(appearance.rawValue)",
                                 band: Self.belowThePanelsStrip) {
                    _ = window.performKeyEquivalent(with: press)
                }
            }
        }
    }

    /// **The same two tabs, switched by a click on the strip** rather than by
    /// ⌘1 and ⌘2: the press goes through the tab's own button and not through
    /// the shortcut's hidden one, so a curve left on either path is seen.
    /// Tab centres are read off the strip's drawing: «One» about 32 pt and
    /// «Two» about 76 pt from the left, the strip's middle 25 pt from the top.
    func testThePanelsTabsCutOnAClickToo() throws {
        let key = PanelLayoutStore.key
        let saved = AppSettings.store.object(key)
        addTeardownBlock { @MainActor in AppSettings.store.set(saved, for: key) }
        let layout = PanelLayout(tabs: [
            PanelLayout.Tab(id: "tab.1", name: "One",
                            widgets: [PanelLayout.Slot(widget: HelmPanelContent.utilitiesWidget, size: .tall)],
                            glyph: "star"),
            PanelLayout.Tab(id: "tab.2", name: "Two", widgets: [], glyph: "circle"),
        ])
        AppSettings.store.set(try JSONEncoder().encode(layout), for: key)

        for appearance in Self.appearances {
            let mount = MountedRender(HelmPanelContent(host: ModuleHost.shared),
                                      width: helmPanelWidth, height: 520, appearance: appearance)
            let window = try XCTUnwrap(mount.window)
            NotificationCenter.default.post(name: .helmPanelDidShow, object: nil)
            Self.pump(mount.host, turns: 60)
            let screen = RenderedInk.label(of: appearance)
            for (x, to) in [(76.0, "tab.2"), (32.0, "tab.1"), (76.0, "tab.2"), (32.0, "tab.1")] {
                let point = NSPoint(x: x, y: window.contentView!.bounds.height - 25)
                func click(_ type: NSEvent.EventType) throws -> NSEvent {
                    try XCTUnwrap(NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1))
                }
                let down = try click(.leftMouseDown), up = try click(.leftMouseUp)
                window.makeKeyAndOrderFront(nil)
                // The press lands a turn before the release, as a hand does; the
                // switch is the release, which is what is photographed.
                window.sendEvent(down)
                Self.pump(mount.host, turns: 3)
                try photographed(mount.host, "\(screen), panel click → \(to)",
                                 named: "panel-click-\(to)-\(appearance.rawValue)",
                                 band: Self.belowThePanelsStrip) {
                    window.sendEvent(up)
                }
            }
        }
    }
}
