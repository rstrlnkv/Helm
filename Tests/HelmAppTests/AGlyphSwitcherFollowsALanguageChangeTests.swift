import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **A language change while Hosts' SSH tab is up renames the view-mode
/// switcher's glyphs and the centre tabs' glyphs.** Seen red (tester,
/// 2026-09-25) before `HelmToolbarSwitcher.Coordinator.lastNames`: the
/// tooltip and the name VoiceOver reads stayed "Table" / "Plain text" while
/// the group name and the overflow menu moved to the new language, because
/// `HelmToolbarSwitcher.updateNSView` refilled only when the drawn words
/// differed, and a glyph-only switcher draws no words, so a changed name
/// never reached `fill` — where the tooltip and the glyph's accessibility
/// description are written. Red again, both cases, with the `namesChanged`
/// term taken out of that refill condition.
///
/// The page's re-declaration is played through the channel: in the app,
/// `SettingsWindow` re-identifies the page on `.helmLanguageChanged`
/// (`content.id(model.languageRevision)`), and the page declares again in the
/// new language onto the same page bar. The declared ids are the same, so the
/// actions zone keeps its host (`rebuilds` in `ShellBarActions.show`) and the
/// tabs zone re-roots the two hosts it already holds: neither builds a new
/// host for a language.
@MainActor
final class AGlyphSwitcherFollowsALanguageChangeTests: XCTestCase {

    private func content() -> HelmPageToolbarContent {
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

    /// The switcher the bar in the window holds in `zone`, found by a walk down from the window's frame
    /// view and held to be the mounted bar's own zone.
    private func segmented(_ zone: ShellPageBarView.Zone, _ mounted: MountedPageBar,
                           _ window: NSWindow) -> NSSegmentedControl? {
        let found = window.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        guard found === mounted.bar.view, let view = found?.view(for: zone) else { return nil }
        return view.everyView(ofType: NSSegmentedControl.self).first
    }

    private func names(_ control: NSSegmentedControl) -> (tips: [String?], spoken: [String?]) {
        ((0..<control.segmentCount).map { control.toolTip(forSegment: $0) },
         (control.cell?.accessibilityChildren() ?? []).map { ($0 as? NSAccessibilityProtocol)?.accessibilityLabel() })
    }

    /// `style` is the tabs' label style the bar is in while the language moves.
    private func run(style: ToolbarSwitcherStyle, zone: ShellPageBarView.Zone, expected: () -> [String]) {
        let store = AppSettings.store
        let saved = store.object(ToolbarSwitcherStyle.storageKey)
        let savedCollapse = store.object("alwaysCollapseSearch")
        let savedPageBar = store.object(PageBarStyle.storageKey)
        let savedBarAppearance = store.object(HelmBarAppearance.storageKey)
        defer {
            store.set(saved, for: ToolbarSwitcherStyle.storageKey)
            store.set(savedCollapse, for: "alwaysCollapseSearch")
            store.set(savedPageBar, for: PageBarStyle.storageKey)
            store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
        }
        AppLanguage.only(.en) {
            AppSettings.toolbarSwitcherStyle = style
            AppSettings.pageBarStyle = .windowTitle
            AppSettings.barAppearance = .flat
            AppSettings.alwaysCollapseSearch = false
            let model = SettingsModel(host: ModuleHost.shared)
            let channel = HelmWindowToolbarChannel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            let mounted = MountedPageBar(model: model, channel: channel, in: window)
            defer { mounted.remove() }
            model.selection = .module("test.language")
            var generation = channel.nextGeneration()
            channel.declare(content(), token: "test.language", generation: generation)
            mounted.layout()
            guard let control = segmented(zone, mounted, window) else { return XCTFail("no \(zone) switcher") }
            XCTAssertEqual(names(control).tips.map { $0 ?? "" }, expected(), "precondition: English names")

            AppLanguage.each { language in
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                channel.withdraw(token: "test.language", generation: generation)
                generation = channel.nextGeneration()
                channel.declare(content(), token: "test.language", generation: generation)
                for _ in 0..<10 {
                    mounted.layout()
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
                guard let now = segmented(zone, mounted, window) else { return XCTFail("\(language.rawValue): gone") }
                let read = names(now)
                XCTAssertEqual(read.tips, expected().map(Optional.some),
                               "\(style) \(zone) \(language.rawValue): tooltips stayed in another language")
                XCTAssertEqual(read.spoken, expected().map(Optional.some),
                               "\(style) \(zone) \(language.rawValue): VoiceOver names stayed in another language")
            }
        }
    }

    /// The view-mode switcher at the default label style (`.text`, what
    /// every Mac that never right-clicked a switcher reads) — drawn in glyphs
    /// all the same, so only a changed name can force the refill.
    func testTheViewModeGlyphsAreRenamedOnALanguageChange() {
        run(style: .text, zone: .actions) { [HostsStr.tableView, HostsStr.textView] }
    }

    /// The same defect in the family: the centre tabs, in `.icons` — older
    /// than the always-glyphs change, and red at the commit before it too.
    func testTheCentreTabsGlyphsAreRenamedOnALanguageChange() {
        run(style: .icons, zone: .tabs) { [HostsStr.keysTab, HostsStr.sshHostsTab] }
    }
}
