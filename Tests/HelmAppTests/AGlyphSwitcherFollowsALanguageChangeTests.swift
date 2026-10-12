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
/// new language onto the same `PageBar` — `ShapeSignature` carries no
/// language — so the same `NSSegmentedControl` receives the new titles.
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

    private func segmented(_ id: String, _ window: NSWindow) -> NSSegmentedControl? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == id }?.view?
            .everyView(ofType: NSSegmentedControl.self).first
    }

    private func names(_ control: NSSegmentedControl) -> (tips: [String?], spoken: [String?]) {
        ((0..<control.segmentCount).map { control.toolTip(forSegment: $0) },
         (control.cell?.accessibilityChildren() ?? []).map { ($0 as? NSAccessibilityProtocol)?.accessibilityLabel() })
    }

    /// `style` is the tabs' label style the bar is in while the language moves.
    private func run(style: ToolbarSwitcherStyle, item: String, expected: () -> [String]) {
        let store = AppSettings.store
        let saved = store.object(ToolbarSwitcherStyle.storageKey)
        defer {
            store.set(saved, for: ToolbarSwitcherStyle.storageKey)
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
        }
        AppLanguage.only(.en) {
            AppSettings.toolbarSwitcherStyle = style
            let model = SettingsModel(host: ModuleHost.shared)
            let channel = HelmWindowToolbarChannel()
            let toolbar = SettingsToolbar(model: model, channel: channel)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            toolbar.window = window
            model.selection = .module("test.language")
            var generation = channel.nextGeneration()
            channel.declare(content(), token: "test.language", generation: generation)
            window.layoutIfNeeded()
            guard let control = segmented(item, window) else { return XCTFail("no \(item) switcher") }
            XCTAssertEqual(names(control).tips.map { $0 ?? "" }, expected(), "precondition: English names")

            AppLanguage.each { language in
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                channel.withdraw(token: "test.language", generation: generation)
                generation = channel.nextGeneration()
                channel.declare(content(), token: "test.language", generation: generation)
                for _ in 0..<10 {
                    window.layoutIfNeeded()
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
                guard let now = segmented(item, window) else { return XCTFail("\(language.rawValue): gone") }
                let read = names(now)
                XCTAssertEqual(read.tips, expected().map(Optional.some),
                               "\(style) \(item) \(language.rawValue): tooltips stayed in another language")
                XCTAssertEqual(read.spoken, expected().map(Optional.some),
                               "\(style) \(item) \(language.rawValue): VoiceOver names stayed in another language")
            }
            _ = toolbar
        }
    }

    /// The view-mode switcher at the default label style (`.text`, what
    /// every Mac that never right-clicked a switcher reads) — drawn in glyphs
    /// all the same, so only a changed name can force the refill.
    func testTheViewModeGlyphsAreRenamedOnALanguageChange() {
        run(style: .text, item: "helm.actions") { [HostsStr.tableView, HostsStr.textView] }
    }

    /// The same defect in the family: the centre tabs, in `.icons` — older
    /// than the always-glyphs change, and red at the commit before it too.
    func testTheCentreTabsGlyphsAreRenamedOnALanguageChange() {
        run(style: .icons, item: "helm.tabs") { [HostsStr.keysTab, HostsStr.sshHostsTab] }
    }
}
