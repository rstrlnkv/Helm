import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The real `SettingsWindow`, built and never ordered, with its fields read by `Mirror`.**
///
/// A test process window is never key nor visible, so nothing here waits for either. The window's saved
/// frame is removed before the build and put back in a teardown block, so a size a test sets does not
/// become the next launch's. `alwaysCollapseSearch`, which the build turns off, is put back by a block of its own. The two keys that
/// remember the sidebar's fold are cleared before the build and put back by a block each, so every window opens expanded.
@MainActor
struct SettingsWindowRig {
    let owner: SettingsWindow
    let window: NSWindow
    let model: SettingsModel
    let channel: HelmWindowToolbarChannel
    let shell: SettingsShellViewController

    /// nil when the window holds none of the parts; `failure` is the sentence that case prints. `make` builds
    /// the window after the protections below are in place; the default builds the `.pageBar` window, Helm's
    /// own page bar and no toolbar, on macOS 27's band, and a family that needs another builds it in the
    /// closure and keeps the same protections.
    static func build(in test: XCTestCase, failure: String,
                      make: @MainActor () -> SettingsWindow = { SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27), bar: .pageBar) },
                      file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let found = UserDefaults.standard.string(forKey: frameKey)
        UserDefaults.standard.removeObject(forKey: frameKey)
        test.addTeardownBlock {
            await MainActor.run {
                if let found { UserDefaults.standard.set(found, forKey: frameKey) }
                else { UserDefaults.standard.removeObject(forKey: frameKey) }
            }
        }
        // The fold the window family leaves in the process's defaults would open the next window in the rail.
        for key in ["module.app.sidebarCollapsed", "module.app.sidebarWidth"] {
            nonisolated(unsafe) let kept = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
            test.addTeardownBlock {
                await MainActor.run {
                    if let kept { UserDefaults.standard.set(kept, forKey: key) }
                    else { UserDefaults.standard.removeObject(forKey: key) }
                }
            }
        }
        let collapse = AppSettings.alwaysCollapseSearch
        test.addTeardownBlock { await MainActor.run { AppSettings.alwaysCollapseSearch = collapse } }
        AppSettings.alwaysCollapseSearch = false
        let owner = make()
        let fields = Mirror(reflecting: owner).children
        guard let window = fields.first(where: { $0.label == "window" })?.value as? NSWindow,
              let model = fields.first(where: { $0.label == "model" })?.value as? SettingsModel,
              let channel = fields.first(where: { $0.label == "toolbarChannel" })?.value as? HelmWindowToolbarChannel,
              let shell = window.contentViewController as? SettingsShellViewController else {
            XCTFail(failure, file: file, line: line)
            return nil
        }
        return SettingsWindowRig(owner: owner, window: window, model: model, channel: channel, shell: shell)
    }

    /// The window as the app builds it: the initialiser's own defaults, no bar named, on macOS 27's band like
    /// every other window of this rig.
    static func buildAsTheAppDoes(in test: XCTestCase, failure: String,
                                  file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        build(in: test, failure: failure,
              make: { SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27)) },
              file: file, line: line)
    }

    /// The bar the window holds, nil while it holds none.
    var pageBar: ShellPageBar? {
        Mirror(reflecting: owner).children.first { $0.label == "pageBar" }?.value as? ShellPageBar
    }

    static func pump(_ seconds: TimeInterval = 0.4) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// A page's toolbar content: two tabs, an action and, when asked, a search.
    static func content(search: Bool, selected: String = "installed") -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "installed", title: "Installed", symbol: "shippingbox"),
                   HelmToolbarTab(id: "updates", title: "Updates", symbol: "arrow.up.circle")],
            selectedTab: .constant(selected),
            actions: [HelmToolbarAction(id: "refresh", title: "Refresh list", symbol: "arrow.clockwise") {}],
            search: search ? HelmToolbarSearch(prompt: "Search packages", text: .constant("")) : nil)
    }

    /// Selects a page and declares its content on the window's channel.
    func open(_ id: String, search: Bool, selected: String = "installed") {
        model.selection = .module(id)
        channel.declare(Self.content(search: search, selected: selected), token: id,
                        generation: channel.nextGeneration())
    }
}
