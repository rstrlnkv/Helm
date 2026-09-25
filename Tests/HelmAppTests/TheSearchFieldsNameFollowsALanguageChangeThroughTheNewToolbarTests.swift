import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Defect found while adding `HelmToolbarAction.Kind`, and fixed in this
/// pass**: `makeSearchItem` set the search field's accessibility label once,
/// at construction, and `patchSearch` — the method every later refresh calls,
/// a language change among them — never set it again. Nothing about the
/// field's shape moves on a language change, so nothing else would have
/// rebuilt it either. The deleted `ASearchFieldSaysWhatItIsTests` proved the
/// same shape of defect for the SwiftUI-bridge-era field (`ToolbarSearchName`,
/// also deleted); this is its twin for the field the app-owned toolbar now
/// builds directly, through
/// `SettingsToolbar` and the channel, the way
/// `TheAttachedToolbarNeverChurnsOnAPageSwitchTests`'s own header explains
/// going through them rather than mounting a page.
@MainActor
final class TheSearchFieldsNameFollowsALanguageChangeThroughTheNewToolbarTests: XCTestCase {

    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func makeToolbar() -> Fixture {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Fixture(toolbar: toolbar, model: model, channel: channel, window: window)
    }

    /// A name that is neither the app's own word for the field nor nil, so
    /// «nothing happened» and «it was re-read» are two different readings
    /// rather than one — the same device the deleted ancestor of this file
    /// (`ASearchFieldSaysWhatItIsTests`) planted before posting the notice.
    func testALanguageChangeReReadsTheSearchFieldsAccessibilityLabel() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.searchName")
        fixture.channel.declare(HelmPageToolbarContent(
            search: HelmToolbarSearch(prompt: "Search apps", text: .constant(""))
        ), token: "test.searchName", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let bar = try XCTUnwrap(fixture.window.toolbar, "page never got a toolbar")
        let field = try XCTUnwrap(
            bar.items.compactMap { $0 as? NSSearchToolbarItem }.first?.searchField,
            "no search field on the toolbar")

        field.setAccessibilityLabel("a name from the language before")
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        fixture.window.layoutIfNeeded()

        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the app changed language and the field kept \
            «\(field.accessibilityLabel() ?? "no name at all")» — patchSearch does not re-read \
            the field's own accessibility label on a language change
            """)
        _ = fixture.toolbar
    }

    /// **Every language answers**, not only the one this machine happens to
    /// be set to (CLAUDE.md's own rule on `AppLanguage.each`) — one
    /// `.helmLanguageChanged` notice per language, the same route the case
    /// above already proved wired to `patchSearch`, so this one only has to
    /// show the re-read is not a fluke of whichever language the notice
    /// above happened to land in.
    func testTheLabelIsInTodaysLanguageInEveryLanguage() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.searchNameLanguages")
        fixture.channel.declare(HelmPageToolbarContent(
            search: HelmToolbarSearch(prompt: "Search apps", text: .constant(""))
        ), token: "test.searchNameLanguages", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let bar = try XCTUnwrap(fixture.window.toolbar, "page never got a toolbar")
        let field = try XCTUnwrap(
            bar.items.compactMap { $0 as? NSSearchToolbarItem }.first?.searchField,
            "no search field on the toolbar")

        AppLanguage.each { language in
            NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
            fixture.window.layoutIfNeeded()
            XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField,
                           "\(language.rawValue): the field answers in another language")
        }
        _ = fixture.toolbar
    }

    /// **Ported from the deleted `ASearchFieldSaysWhatItIsTests
    /// .testTheNameIsAWordAndNotTheRole`**, which this pass's own removal of
    /// `ToolbarSearchName` left with no home: `HelmA11y.searchField` is not
    /// wired to `ToolbarSearchName` at all, so the case is pure string logic
    /// and needs no fixture. VoiceOver already announces the role — "search
    /// field" — so a label repeating it reads as "search field search
    /// field", which is exactly the mistake `HelmA11y.searchField`'s own doc
    /// comment says the word "Search" alone was chosen to avoid.
    func testTheNameIsAWordAndNotTheRole() {
        AppLanguage.each { language in
            let name = HelmA11y.searchField
            XCTAssertFalse(name.isEmpty, "\(language.rawValue): the search field's name is empty")
            XCTAssertFalse(name.lowercased().contains("field"), """
                \(language.rawValue): the name «\(name)» repeats the role VoiceOver already \
                announces
                """)
        }
    }
}
