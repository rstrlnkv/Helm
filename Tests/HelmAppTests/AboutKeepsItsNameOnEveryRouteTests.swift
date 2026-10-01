import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_UI
@testable import HelmApp
@testable import HelmUI

/// **The routes into the About page that `EveryPageNamesTheWindowAfterItselfTests`
/// does not take.** That test opens the window under `PageBarStyle.windowTitle`
/// and walks the pages once, in order. The owner's defect («Если выбрана шапка
/// страницы без значка, то окно О Helm подписано как Настройки Helm») was a page
/// that published no title, and a page can publish a title and still lose it on
/// the way: the style switched while the page stays, the page left and come
/// back, the language switched while the page stays, the window ordered out and
/// back (which unmounts the pane, `helmIdlesOffScreen`), a subtitle left over
/// from a module whose status the window carried a moment before. Each case
/// reads the real `SettingsWindow`'s own `NSWindow`, never the preference.
///
/// Plus the two things the route list cannot see: a `SettingsSelection` case
/// added later (an exhaustive switch here, so a new page is a build error in
/// this file until it names its title), and About mounted with no window bar at
/// all, where the modifier must publish nothing.
@MainActor
final class AboutKeepsItsNameOnEveryRouteTests: XCTestCase {

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue

    private var owner: SettingsWindow?
    private var window: NSWindow?
    private var model: SettingsModel?
    private var savedStyle: PageBarStyle = .moduleName

    override func setUp() {
        super.setUp()
        savedStyle = AppSettings.pageBarStyle
        AppSettings.pageBarStyle = .windowTitle
    }

    override func tearDown() {
        window?.orderOut(nil)
        window?.toolbar = nil
        window = nil
        model = nil
        owner = nil
        NSWindow.removeFrame(usingName: "HelmSettingsWindow.v4")
        ModuleHost.shared.shutdown()
        UserDefaults.standard.removeObject(forKey: "module.\(Self.keepAwake).enabled")
        AppSettings.pageBarStyle = savedStyle
        super.tearDown()
    }

    private func open(liveKeepAwake: Bool = false) throws {
        if liveKeepAwake {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        }
        let settings = SettingsWindow(host: ModuleHost.shared)
        owner = settings
        let fields = Mirror(reflecting: settings).children
        window = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                               "SettingsWindow no longer holds `window` as an NSWindow")
        model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                              "SettingsWindow no longer holds `model` as a SettingsModel")
        window?.orderFront(nil)
        settle()
    }

    private func settle(_ seconds: TimeInterval = 0.3) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            autoreleasepool {
                window?.layoutIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }
    }

    private func select(_ page: SettingsSelection) throws {
        try XCTUnwrap(model).selection = page
        settle()
    }

    /// The window as the owner reads it under `.windowTitle`: the page's own
    /// name, drawn, with no subtitle left from anywhere.
    private func assertAboutUnderWindowTitle(_ label: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(window?.title, AppStr.aboutHelm,
                       "\(label): the window is not titled with About's own name", file: file, line: line)
        XCTAssertEqual(window?.titleVisibility, .visible,
                       "\(label): under .windowTitle the title must be drawn", file: file, line: line)
        XCTAssertEqual(window?.subtitle, "",
                       "\(label): About has no status, so no subtitle", file: file, line: line)
    }

    // MARK: - The style switched while About stays

    func testSwitchingTheStyleBothWaysWhileAboutIsOpenKeepsItsName() throws {
        try open()
        try select(.about)
        assertAboutUnderWindowTitle("opened under .windowTitle")

        AppSettings.pageBarStyle = .moduleName
        settle()
        // Under `.moduleName` the title is not drawn, but it is still what the
        // Window menu and Mission Control call the window.
        XCTAssertEqual(window?.titleVisibility, .hidden, "moduleName: the title bar must not draw the title")
        XCTAssertEqual(window?.title, AppStr.aboutHelm, "moduleName: the window's own name for About")

        AppSettings.pageBarStyle = .windowTitle
        settle()
        assertAboutUnderWindowTitle("switched back to .windowTitle while About stayed")

        // Twice in a row, same value: the notification fires with nothing moved.
        AppSettings.pageBarStyle = .windowTitle
        settle()
        assertAboutUnderWindowTitle("the same style chosen a second time")
    }

    /// Opened on About under `.moduleName`, then switched — the direction in
    /// which the page never published under `.windowTitle` before the switch.
    func testAboutOpenedUnderModuleNameThenSwitchedToWindowTitle() throws {
        AppSettings.pageBarStyle = .moduleName
        try open()
        try select(.about)
        AppSettings.pageBarStyle = .windowTitle
        settle()
        assertAboutUnderWindowTitle("opened under .moduleName, switched on About")
    }

    // MARK: - Leaving and coming back

    func testAboutGeneralAboutAndAboutTwiceKeepTheName() throws {
        try open()
        try select(.about)
        assertAboutUnderWindowTitle("first visit")
        try select(.general)
        XCTAssertEqual(window?.title, AppStr.settingsPane, "General between two visits to About")
        try select(.about)
        assertAboutUnderWindowTitle("About after General")
        try select(.about)
        assertAboutUnderWindowTitle("About selected twice in a row")
        try select(.log)
        try select(.about)
        assertAboutUnderWindowTitle("About after Log")
    }

    /// A module with a status puts it in the subtitle under `.windowTitle`;
    /// About has none, so arriving from that module must clear it rather than
    /// carry «Not running» under «About Helm».
    func testArrivingFromAModuleWithAStatusLeavesNoSubtitleOnAbout() throws {
        try open(liveKeepAwake: true)
        try select(.module(Self.keepAwake))
        // The subject first: without a subtitle here the case below proves nothing.
        XCTAssertEqual(window?.subtitle, AppStr.moduleIdle,
                       "Keep Awake's status did not reach the subtitle; the case below would prove nothing")
        try select(.about)
        assertAboutUnderWindowTitle("About after Keep Awake")
        try select(.module(Self.keepAwake))
        try select(.general)
        XCTAssertEqual(window?.subtitle, "", "General after Keep Awake carries its status")
        try select(.module(Self.keepAwake))
        try select(.log)
        XCTAssertEqual(window?.subtitle, "", "Log after Keep Awake carries its status")
    }

    // MARK: - The language switched while About stays

    func testChangingTheLanguageWhileAboutIsOpenRetitlesTheWindow() throws {
        try open()
        try select(.about)
        for language in AppLanguage.allCases {
            AppLanguage.only(language) {
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                settle()
                assertAboutUnderWindowTitle("\(language), switched while About stayed")
            }
        }
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        settle()
    }

    // MARK: - The window ordered out and back, and minimised

    /// Ordered out and back on About. **What this does not prove**: that the
    /// pane was unmounted in between. `helmIdlesOffScreen` unmounts on an
    /// occlusion change, and a test process is sent none, so this posts the one
    /// AppKit posts — and measured, the window's title and `model.pageTitle`
    /// stayed «О Helm» while hidden, so either the unmount did not happen here
    /// or it withdrew nothing. What it does prove is the person's reading: the
    /// window reopened on About carries About's name.
    func testClosingAndReopeningTheWindowOnAboutKeepsItsName() throws {
        try open()
        try select(.about)
        let window = try XCTUnwrap(self.window)
        window.orderOut(nil)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        settle()
        window.orderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        settle()
        assertAboutUnderWindowTitle("About after the window was closed and reopened")
    }

    /// A minimised window is named by its title in the Dock and in the Window
    /// menu, and it is not visible, which is the state `helmIdlesOffScreen`
    /// reads — so the name must survive the page being off screen.
    func testAMinimisedWindowOnAboutIsStillNamedAbout() throws {
        try open()
        try select(.about)
        let window = try XCTUnwrap(self.window)
        window.miniaturize(nil)
        settle(1.5)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        settle()
        // The subject: the window really is minimised and not visible.
        XCTAssertTrue(window.isMiniaturized, "the window did not minimise; the case proves nothing")
        XCTAssertFalse(window.isVisible, "a minimised window read as visible; the case proves nothing")
        XCTAssertEqual(window.title, AppStr.aboutHelm, "the minimised window lost About's name")
        window.deminiaturize(nil)
        settle(1.5)
        assertAboutUnderWindowTitle("About after the window came back from the Dock")
    }

    // MARK: - A page nobody has written a title for yet

    /// Every page the window can show, by an exhaustive switch: a new
    /// `SettingsSelection` case does not compile here until somebody says what
    /// it is called.
    private func expectedTitle(_ page: SettingsSelection) -> String {
        switch page {
        case .general: return AppStr.settingsPane
        case .about: return AppStr.aboutHelm
        case .log: return AppStr.logPane
        case .module(let id):
            // An id no descriptor answers falls back to General's page
            // (`SettingsDetail`), and so to General's name.
            return ModuleRegistry.all.first { $0.idRaw == id }?.moduleMetadata.name ?? AppStr.settingsPane
        }
    }

    func testAnUnknownModuleIdIsTitledByThePageActuallyDrawn() throws {
        try open()
        try select(.about)
        let stale = SettingsSelection.module("helm.no-such-module")
        try select(stale)
        XCTAssertEqual(window?.title, expectedTitle(stale),
                       "a selection that outlived its module: titled by a page that is not on screen")
        XCTAssertNotEqual(window?.title, AppStr.aboutHelm, "the previous page's name stayed on the window")
    }

    // MARK: - About with no window bar

    /// A sheet, or the page mounted on its own: `helmPageBar` is nil, and the
    /// page must publish nothing, the way every other page does there.
    func testAboutMountedWithoutABarPublishesNoTitle() throws {
        let probe = TitleProbe()
        let host = NSHostingView(rootView: AboutHelmView()
            .onPreferenceChange(HelmPageTitleKey.self) { probe.seen.append($0) })
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        XCTAssertFalse(probe.seen.contains { $0 != nil },
                       "About with no bar published a title: \(probe.seen)")

        // The subject exists: the same mount with a bar does publish.
        let barred = TitleProbe()
        let host2 = NSHostingView(rootView: AboutHelmView()
            .onPreferenceChange(HelmPageTitleKey.self) { barred.seen.append($0) }
            .environment(\.helmPageBar, .windowTitle))
        host2.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        host2.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        XCTAssertEqual(barred.seen.last ?? nil, HelmPageTitle(title: AppStr.aboutHelm, subtitle: nil),
                       "About under a bar did not publish its name; the case above proves nothing")
    }
}

@MainActor
private final class TitleProbe {
    var seen: [HelmPageTitle?] = []
}
