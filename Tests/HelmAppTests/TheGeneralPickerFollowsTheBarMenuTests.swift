import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import Vision
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The Appearance row's Page header picker, on screen, while the same
/// choice is made from the toolbar's own menu.**
///
/// `MenuBarSettingsView` reads `AppSettings.pageBarStyle` once, into a
/// `@State`, and nothing on the page listens for a change of it — a picker left
/// saying "With Icon" over a bar that has just gone to the plain title is two
/// answers to one question on one screen. What keeps it right is the pane's
/// own composition in `SettingsShellViewController` (a new identity for the
/// whole pane when the style changes), so the page is mounted exactly there,
/// through the real controller, and the choice is made through the menu
/// item's own action and target — nothing here re-composes either half.
///
/// The second case is the "Toolbar style" row, which listens for `.helmBarAppearanceChanged` itself
/// (`BarAppearanceRow`).
///
/// **Read off the rendering, because there is nothing else to read.** On
/// macOS 27.2 a menu-style `Picker` in a grouped `Form` is drawn by SwiftUI
/// itself: the page's view tree holds no `NSPopUpButton` and nothing named
/// like one (walked 2026-09-27 on this Mac, the whole 1449 pt form scrolled
/// through), and
/// an `NSHostingView`'s accessibility children are empty in a test process
/// (`KeyboardReachableControlsTests`' header). So the pane is rendered in
/// Aqua, in English, and the picker's words are read back with Vision's text
/// recogniser — the words a person would read on the row.
///
/// The General page reads a sealed setting when it appears; the seal key is
/// a probe here, so no keychain dialog stands on anybody's screen.
@MainActor
final class TheGeneralPickerFollowsTheBarMenuTests: XCTestCase {

    /// Raw, so a key the domain did not hold is removed again rather than
    /// written back as the typed getter's default.
    private var savedPageBar: Any?
    private var savedAppearance: Any?
    private var savedGuard: SettingGuard!

    override func setUp() async throws {
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        savedGuard = AppSettings.scanGuard
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(SealKeyProbe()))
        AppSettings.pageBarStyle = .moduleName
        AppSettings.barAppearance = .flat
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedAppearance, for: HelmBarAppearance.storageKey)
        AppSettings.scanGuard = savedGuard
    }

    private func pump(_ window: NSWindow, turns: Int = 10) {
        for _ in 0..<turns {
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// The form's own scroll view — the pane's, not the sidebar's list.
    private func form(_ window: NSWindow) -> NSScrollView? {
        window.contentView?.everyView(ofType: NSScrollView.self).first { $0.appKitClassName == "HostingScrollView" }
    }

    /// Every line of text Vision reads in what `view` draws right now.
    private func words(in view: NSView) -> [String] {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let image = rep.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// **The words on screen with the Page header row in view** — the form
    /// scrolled a third of a screen at a time until the row's own title is
    /// read. `nil` when no scroll position shows it.
    private func pickerRow(_ window: NSWindow) -> [String]? {
        guard let form = form(window), let document = form.documentView else { return nil }
        // Where the row was found last, first — the pane is rebuilt on every
        // change and its height does not move, so the row is where it was.
        let offsets = (rowOffset.map { [$0] } ?? [])
            + stride(from: 0, through: document.bounds.height, by: form.contentView.bounds.height / 3)
        for y in offsets {
            form.contentView.scroll(to: NSPoint(x: 0, y: y))
            form.reflectScrolledClipView(form.contentView)
            pump(window, turns: 3)
            let lines = words(in: form)
            if lines.contains(where: { $0.contains("Page header") }) {
                rowOffset = y
                return lines
            }
        }
        return nil
    }

    private var rowOffset: CGFloat?

    /// Which of the two answers is on screen — exactly one of them, matched
    /// on whole words so `Without Icon` is never also read as `With Icon`.
    private func shown(_ lines: [String]) -> PageBarStyle? {
        let text = lines.joined(separator: " | ")
        let without = text.range(of: #"\bWithout Icon\b"#, options: .regularExpression) != nil
        let with = text.range(of: #"\bWith Icon\b"#, options: .regularExpression) != nil
        switch (with, without) {
        case (true, false): return .moduleName
        case (false, true): return .windowTitle
        default: return nil
        }
    }

    private func choose(_ title: String) {
        let items = ShellBarMenu.items(pageBarStyle: AppSettings.pageBarStyle, tabLabels: nil,
                                       appearance: AppSettings.barAppearance, alwaysCollapseSearch: nil)
        guard let item = items.first(where: { $0.title == title && !$0.isSectionHeader }),
              let action = item.action else {
            return XCTFail("the bar's menu offers no «\(title)»")
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item), "«\(title)» reached nobody")
    }

    func testThePickerOnScreenFollowsAChoiceMadeInTheBarsMenu() {
        AppLanguage.only(.en) {
            let model = SettingsModel(host: ModuleHost.shared)
            model.selection = .general
            let channel = HelmWindowToolbarChannel()
            let split = SettingsShellViewController(model: model, toolbarChannel: channel, band: .onMacOS(27))
            let window = NSWindow(contentViewController: split)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.appearance = NSAppearance(named: .aqua)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1060, height: 800))
            window.orderBack(nil)
            let toolbar = SettingsToolbar(model: model, channel: channel)
            toolbar.window = window
            defer {
                window.toolbar = nil
                window.close()
            }
            pump(window, turns: 30)

            guard let first = pickerRow(window) else {
                return XCTFail("no Page header row read anywhere on the General page — nothing below is read")
            }
            XCTAssertEqual(shown(first), .moduleName, "precondition: the row does not start on With Icon: \(first)")

            for (step, (title, style)) in [("Without Icon", PageBarStyle.windowTitle),
                                           ("With Icon", .moduleName),
                                           ("Without Icon", .windowTitle)].enumerated() {
                choose(title)
                XCTAssertEqual(AppSettings.pageBarStyle, style, "step \(step): «\(title)» did not store \(style)")
                pump(window, turns: 20)
                let lines = pickerRow(window)
                XCTAssertEqual(lines.flatMap(shown), style, """
                    step \(step): «\(title)» chosen in the bar's menu, and General's own picker on \
                    screen reads \(lines ?? ["nothing"])
                    """)
            }
        }
    }

    /// **The Toolbar style row, on screen, while Liquid Glass is chosen from the bar's menu.** Vision reads
    /// every line of the form with the row in view, before the choice and after it, and the case asserts only
    /// that the two readings differ. The row's words are the same whichever segment is picked, so any line in
    /// view read differently passes it, and nothing here measures that a picked segment is read differently.
    func testTheToolbarStyleRowOnScreenFollowsAChoiceMadeInTheBarsMenu() {
        AppLanguage.only(.en) {
            let model = SettingsModel(host: ModuleHost.shared)
            model.selection = .general
            let channel = HelmWindowToolbarChannel()
            let split = SettingsShellViewController(model: model, toolbarChannel: channel, band: .onMacOS(27))
            let window = NSWindow(contentViewController: split)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.appearance = NSAppearance(named: .aqua)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1060, height: 800))
            window.orderBack(nil)
            defer { window.close() }
            pump(window, turns: 30)

            guard let form = form(window), let document = form.documentView else {
                return XCTFail("no form on the General page — nothing below is read")
            }
            @MainActor func row() -> [String]? {
                for y in stride(from: 0, through: document.bounds.height, by: form.contentView.bounds.height / 3) {
                    form.contentView.scroll(to: NSPoint(x: 0, y: y))
                    form.reflectScrolledClipView(form.contentView)
                    pump(window, turns: 3)
                    let lines = words(in: form)
                    if lines.contains(where: { $0.contains("Toolbar style") }) { return lines }
                }
                return nil
            }
            guard let before = row() else {
                return XCTFail("no Toolbar style row read anywhere on the General page — nothing below is read")
            }
            choose("Liquid Glass")
            XCTAssertEqual(AppSettings.barAppearance, .liquidGlass, "the menu did not store Liquid Glass")
            pump(window, turns: 20)
            guard let after = row() else {
                return XCTFail("the Toolbar style row vanished after the choice: \(before)")
            }
            XCTAssertNotEqual(after, before, """
                Liquid Glass chosen in the bar's menu, and General's Toolbar style row reads the same as \
                before: \(after)
                """)
        }
    }
}
