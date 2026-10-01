import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import HelmContract
import Module_Hosts_Engine
import Module_Uninstaller_Engine
@testable import HelmApp

/// **Switching a page's tab changes its content at once, on every module page
/// that has a tab.** The owner's decision, 2026-09-30: «вкладки везде
/// переключаются резко». The toolbar switcher's own selection slide is AppKit's
/// and is not content; what is held here is the page under it.
///
/// **The pages are found, not listed.** Every module in `ModuleRegistry.all` is
/// mounted with a `HelmWindowToolbarChannel`, and what it declares there —
/// `tabs` with their `selectedTab` binding, and any action that is a
/// `.segmented` choice (Hosts' Table / Plain text) — is what gets switched, by
/// writing the same binding the toolbar writes. A page that gains a tab arrives
/// here without anybody remembering it; `testEveryModuleThatDeclaresATabIsFound`
/// reads the sources to say that none is missed in the other direction, since a
/// channel that stays empty (a page that stopped declaring) and a page with no
/// tab read the same from the channel alone.
///
/// Each switch is photographed once per turn of the run loop by
/// `FrameRecorder` (`Tests/Support`), in a named appearance, and judged by the
/// bound stated there: the drawing before and after the switch must differ (or
/// the case proves nothing), and no frame after one grace turn may differ from
/// the settled one. Every `[frames]` line it prints is the account.
///
/// **What this cannot see**, so nobody reads it as more: it photographs the
/// hosting view, and a page's own toolbar lives in the window's `NSToolbar`;
/// it drives the binding and not a click on the segment; and the page is drawn
/// against `ModulePageFixtures`' wire, so a tab whose content the fixture does
/// not fill is judged on the state the fixture gives it.
@MainActor
final class EveryTabSwitchIsACutTests: XCTestCase {

    /// A window's height rather than the 3000 pt the ratchets read: a frame of
    /// that page is forty times the pixels, and forty-five frames of it a switch.
    private static let height: CGFloat = 700
    /// Wide enough for Homebrew's list-and-inspector split, the layout a person
    /// on a desktop has; the narrow one replaces the list with the package.
    private static let width: CGFloat = 984

    /// One thing a page lets a person switch.
    private struct Switcher {
        let name: String
        let ids: [String]
        let selection: Binding<String>
    }

    private static func switchers(of content: HelmPageToolbarContent) -> [Switcher] {
        var out: [Switcher] = []
        if content.tabs.count > 1, let selected = content.selectedTab {
            out.append(Switcher(name: "tabs", ids: content.tabs.map(\.id), selection: selected))
        }
        for action in content.actions {
            if case .segmented(let options, let selection) = action.kind, options.count > 1 {
                out.append(Switcher(name: action.id, ids: options.map(\.id), selection: selection))
            }
        }
        return out
    }

    /// Module folder names whose UI source builds a `HelmToolbarTab`, comments
    /// stripped so a doc comment naming the type is not a declaration.
    private static func modulesWithTabsInSource() throws -> Set<String> {
        var out: Set<String> = []
        for module in try UISources.moduleNames() {
            for file in try RepoSource.swiftFiles(under: "Sources/Modules/\(module)/UI") {
                let code = try RepoSource.lines(of: file).map(RepoSource.code).joined(separator: "\n")
                if code.contains("HelmToolbarTab(") { out.insert(module.lowercased()) }
            }
        }
        return out
    }

    /// What `ModulePageFixtures` answers, and two pages more: a tab whose content
    /// the fixture leaves empty is judged on its empty state, and an empty state
    /// on both sides of a switch is the easy case. Hosts gets keys, hosts and a
    /// readable `known_hosts`; Uninstaller gets a list of apps. Kept here, not in
    /// the shared fixture: the layer counts the other ratchets record would move.
    private static let wiring: ModulePageRender.Wiring = { id in
        var wire = ModulePageRender.answering(id)
        switch id {
        case HostsEngine.moduleID:
            wire.says(HostsEvent.state, HostsState(
                hostsText: "127.0.0.1 localhost\n::1 localhost\n",
                sshText: "Host alpha\n  HostName alpha.example\n  User one\n\nHost beta\n  HostName beta.example\n",
                keys: [KeyRow(name: "id_fixture", hasPublicHalf: true, described: nil, modified: nil,
                              permission: .ok, publicText: nil, inAgent: false),
                       KeyRow(name: "id_open", hasPublicHalf: false, described: nil, modified: nil,
                              permission: .tooOpen(fix: 0o600), publicText: nil, inAgent: false)],
                directoryPermission: .ok, agent: .empty,
                knownHostsText: "alpha.example ssh-ed25519 AAAAFIXTURE\n",
                home: "/nowhere"))
        case UninstallerEngine.moduleID:
            wire.answers(UninstallerCommand.listApps, with: [
                InstalledApp(name: "Fixture Alpha", bundleID: "fixture.alpha",
                             path: "/Applications/Fixture Alpha.app", sizeBytes: 1_000_000),
                InstalledApp(name: "Fixture Beta", bundleID: "fixture.beta",
                             path: "/Applications/Fixture Beta.app", sizeBytes: 2_000_000)])
        default:
            break
        }
        return wire
    }

    private static func mount(_ descriptor: any ModuleDescriptor, _ appearance: NSAppearance.Name)
        -> (ModulePageRender.Page, HelmWindowToolbarChannel) {
        let channel = HelmWindowToolbarChannel()
        let page = ModulePageRender.page(for: descriptor, in: appearance, width: width,
                                         wiredBy: wiring, declaringTo: channel)
        page.host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        pump(page.host, turns: 40)
        return (page, channel)
    }

    private static func pump(_ view: NSView, turns: Int) {
        for _ in 0..<turns {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// One switch, photographed and judged.
    private func flip(_ switcher: Switcher, to target: String, on page: ModulePageRender.Page,
                      _ label: String, named: String) throws {
        let before = try XCTUnwrap(RenderedInk.bytes(page.host))
        // The wire is held for the length of the photograph: what a page asks its
        // engine for when a tab is shown answers a turn or two later, and that is
        // content arriving, not the switch (`FixtureTransport.hold()`).
        page.transport.hold()
        defer {
            page.transport.release()
            Self.pump(page.host, turns: 40)
        }
        let began = Date()
        switcher.selection.wrappedValue = target
        XCTAssertEqual(switcher.selection.wrappedValue, target,
                       "\(label): the switch did not reach the binding")
        let shots = try FrameRecorder.photograph(page.host, since: began)
        FrameRecorder.write(shots, of: page.host, named: named)
        try FrameRecorder.judge(shots, before: before, label)
    }

    /// Out to every other option and back to where it began, so each direction is
    /// held and the page ends as it began.
    private func cycle(_ switcher: Switcher, on page: ModulePageRender.Page,
                       _ label: String, named: String) throws {
        let start = switcher.selection.wrappedValue
        for target in switcher.ids.filter({ $0 != start }) + [start]
        where switcher.selection.wrappedValue != target {
            try flip(switcher, to: target, on: page, "\(label) → \(target)",
                     named: "\(named)-\(target)")
        }
    }

    /// Every page with a switcher, every other option of it, both ways round, in
    /// both appearances. The tabs first; then, on each tab in turn, the
    /// segmented choices that tab offers — Hosts' Table / Plain text is an action
    /// of the SSH tab alone, so it is reached by standing on that tab.
    func testEveryTabSwitchIsACut() throws {
        var covered: Set<String> = []
        for descriptor in ModuleRegistry.all {
            let id = type(of: descriptor).id.rawValue
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let (page, channel) = Self.mount(descriptor, appearance)
                defer { page.host.window?.contentView = nil }
                let screen = RenderedInk.label(of: appearance)
                let content = channel.content(for: id) ?? HelmPageToolbarContent()
                let tabs = Self.switchers(of: content).filter { $0.name == "tabs" }
                // **Each tab is visited once before anything is photographed.**
                // Some pages ask their engine for a tab's data the moment it is
                // shown (Homebrew's `refresh(segment)`), and the answer lands a
                // few turns after the cut — that is content arriving, a fact
                // about the wire, and it is the page's state on a second visit
                // rather than the first. What is judged is the switch.
                for tabs in tabs {
                    let start = tabs.selection.wrappedValue
                    for target in tabs.ids.filter({ $0 != start }) + [start] {
                        tabs.selection.wrappedValue = target
                        Self.pump(page.host, turns: 40)
                    }
                }
                if !Self.switchers(of: content).isEmpty { covered.insert(id) }
                for tabs in tabs {
                    try cycle(tabs, on: page, "\(screen), \(id) tabs",
                              named: "tab-\(id)-\(appearance.rawValue)")
                }
                // The segmented choices of each tab. Standing on a tab is itself
                // a switch, made unphotographed; what is photographed is the choice.
                let standing = tabs.first?.selection.wrappedValue
                for tab in tabs.first?.ids ?? [standing ?? ""] {
                    if let tabs = tabs.first, tabs.selection.wrappedValue != tab {
                        tabs.selection.wrappedValue = tab
                        Self.pump(page.host, turns: 40)
                    }
                    let here = channel.content(for: id) ?? HelmPageToolbarContent()
                    for action in here.actions where action.isVisible {
                        guard case .segmented(let options, let selection) = action.kind,
                              options.count > 1 else { continue }
                        let choice = Switcher(name: action.id, ids: options.map(\.id), selection: selection)
                        try cycle(choice, on: page, "\(screen), \(id) \(tab) \(action.id)",
                                  named: "choice-\(id)-\(tab)-\(action.id)-\(appearance.rawValue)")
                    }
                }
            }
        }
        XCTAssertFalse(covered.isEmpty, "no module page declared a tab, so nothing was switched")
    }

    /// The other half of finding the pages: a module whose source builds tabs
    /// must have been found declaring them, or its switch was never tried.
    func testEveryModuleThatDeclaresATabIsFound() throws {
        let inSource = try Self.modulesWithTabsInSource()
        XCTAssertFalse(inSource.isEmpty, "the source scan found no module with a tab")
        var declared: Set<String> = []
        for descriptor in ModuleRegistry.all {
            let id = type(of: descriptor).id.rawValue
            let (page, channel) = Self.mount(descriptor, .aqua)
            defer { page.host.window?.contentView = nil }
            if let content = channel.content(for: id), !Self.switchers(of: content).isEmpty {
                declared.insert(id.replacingOccurrences(of: "-", with: ""))
            }
        }
        XCTAssertEqual(declared, inSource,
                       "the modules whose sources build a tab and the modules whose mounted page declares one differ")
    }
}
