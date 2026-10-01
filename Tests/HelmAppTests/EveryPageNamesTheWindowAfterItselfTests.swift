import AppKit
import HelmContract
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The owner, 2026-09-30: «Если выбрана шапка страницы без значка, то окно
/// О Helm подписано как Настройки Helm».** Under `PageBarStyle.windowTitle`
/// the window's title is whatever the page on screen reports through
/// `HelmPageTitleKey`, and a page that reports nothing leaves
/// `SettingsWindow.applyTitle(_:)` on its fallback, the window's own name.
/// About reported nothing.
///
/// The real `SettingsWindow`, on screen, read through `Mirror` for its own
/// `window` and `model`, one page at a time; the title asserted is the one the
/// window itself carries, not the preference. Every language, since the title
/// is a lookup.
@MainActor
final class EveryPageNamesTheWindowAfterItselfTests: XCTestCase {

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
        AppSettings.pageBarStyle = savedStyle
        super.tearDown()
    }

    private func open() throws {
        let settings = SettingsWindow(host: ModuleHost.shared)
        owner = settings
        let fields = Mirror(reflecting: settings).children
        window = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                               "SettingsWindow no longer holds `window` as an NSWindow")
        model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                              "SettingsWindow no longer holds `model` as a SettingsModel")
        window?.orderFront(nil)
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

    private func assertTitle(_ page: SettingsSelection, is expected: String, _ label: String) throws {
        let model = try XCTUnwrap(self.model)
        model.selection = page
        settle()
        XCTAssertEqual(window?.title, expected,
                       "\(label) under .windowTitle: the window is titled by another page's name")
        XCTAssertNotEqual(window?.title, AppStr.settingsWindowTitle,
                          "\(label) under .windowTitle: the window fell back to its own name")
    }

    func testEveryPageTitlesTheWindowWithItsOwnNameUnderWindowTitle() throws {
        try open()
        AppLanguage.each { language in
            do {
                try assertTitle(.general, is: AppStr.settingsPane, "\(language) General")
                try assertTitle(.about, is: AppStr.aboutHelm, "\(language) About")
                try assertTitle(.log, is: AppStr.logPane, "\(language) Log")
                for descriptor in ModuleRegistry.all {
                    try assertTitle(.module(descriptor.idRaw), is: descriptor.moduleMetadata.name,
                                    "\(language) \(descriptor.idRaw)")
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }
}
