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
///
/// General, Log and About are the three tabs of one page and carry one name,
/// Settings; a module page carries its own. What the check still tells apart is
/// a page that is titled from one that fell back to the window's own name, which
/// is why those two must be two strings in every language.
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
        XCTAssertNotEqual(expected, AppStr.settingsWindowTitle,
                          "\(label): the page's name and the window's own name are one string, so a fallback cannot be told from a title")
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
                try assertTitle(.about, is: AppStr.settingsPane, "\(language) About")
                try assertTitle(.log, is: AppStr.settingsPane, "\(language) Log")
                for descriptor in ModuleRegistry.all {
                    try assertTitle(.module(descriptor.idRaw), is: descriptor.moduleMetadata.name,
                                    "\(language) \(descriptor.idRaw)")
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    /// One turn of what a shown window does on its own: the content laid out, a pump of the run loop, the
    /// window displayed. An unordered window gets none of it by itself, and SwiftUI's update waits for it.
    private func drive(_ rig: SettingsWindowRig, _ seconds: TimeInterval = 0.3) {
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(seconds)
        rig.window.contentView?.layoutSubtreeIfNeeded()
        rig.window.displayIfNeeded()
    }

    /// **A selection that leaves the Log for a module page lands the module's page.** The title the pane
    /// reports is the page's own preference (`HelmPageTitleKey`, read by the window's `onPreferenceChange`);
    /// nothing else writes `model.pageTitle`, so a stale title is the pane still holding the old page, not
    /// only the bar being late. The mounted page is told by nothing but that title: the pages declare nothing
    /// into the bar and no view type is read. The bug it guards: the bar redrew inside `@Published`'s
    /// `willSet` of `selection` and the pane kept the log's page; `SettingsModel.selection`'s `didSet`
    /// announcement cures it (taken out, this row is red).
    ///
    /// **The window is ordered front here, on purpose.** Measured: in a window never ordered, the pane's page
    /// stops following the selection after the first change whatever the selection is (a General -> module
    /// -> module walk stalls too, with or without the `didSet`), so an unordered window cannot tell this
    /// defect from the harness. Ordered, the same walk titles every page. The rig is the unordered-window
    /// rig; the order is added here and taken back in a teardown block.
    func testASelectionFromTheLogStraightToAModulePageTitlesThePaneWithTheModule() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "the window has no shell: no selection was made")
        else { return }
        rig.window.orderFront(nil)
        addTeardownBlock { await MainActor.run { rig.window.orderOut(nil) } }
        let modules = ModuleRegistry.all.filter { $0.moduleMetadata.name != AppStr.settingsPane }
        XCTAssertFalse(modules.isEmpty, "no module page to select: nothing was measured")
        // Control: the same window titles a module page reached from General, and one reached from another
        // module; only the Log -> module step below is in question.
        if let first = modules.first, let second = modules.dropFirst().first {
            rig.model.selection = .module(first.idRaw)
            drive(rig)
            XCTAssertEqual(rig.model.pageTitle?.title, first.moduleMetadata.name, "control General -> \(first.idRaw): the harness never titled a module page")
            rig.model.selection = .module(second.idRaw)
            drive(rig)
            XCTAssertEqual(rig.model.pageTitle?.title, second.moduleMetadata.name, "control \(first.idRaw) -> \(second.idRaw): the harness never titled a module page")
        }
        for descriptor in modules {
            rig.model.selection = .log
            drive(rig)
            // Subject first: the Log's title was seen, and it is not the module's.
            XCTAssertEqual(rig.model.selection, .log, "the selection never reached the Log")
            XCTAssertEqual(rig.model.pageTitle?.title, AppStr.settingsPane,
                           "before \(descriptor.idRaw): the Log's title was never seen, so a stale one cannot be told")
            rig.model.selection = .module(descriptor.idRaw)
            drive(rig)
            XCTAssertEqual(rig.model.selection, .module(descriptor.idRaw), "the selection did not move to \(descriptor.idRaw)")
            XCTAssertEqual(rig.model.pageTitle?.title, descriptor.moduleMetadata.name,
                           "Log -> \(descriptor.idRaw) directly: the pane still reports the Log's page (\(rig.model.pageTitle?.title ?? "nil"))")
        }
    }
}
